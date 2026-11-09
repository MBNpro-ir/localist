package com.prs.localist

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioFocusRequest
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack as PlatformAudioTrack
import android.os.Handler
import android.os.Looper
import android.os.Process
import com.cloudwebrtc.webrtc.FlutterWebRTCPlugin
import com.cloudwebrtc.webrtc.audio.AudioProcessingAdapter
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import org.webrtc.AudioTrack
import org.webrtc.AudioTrackSink
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.pow

/** Private PCM processing/output. Never changes Android stream/system volume. */
object CaptureAudioEngine {
    @Volatile var systemRecorder: android.media.AudioRecord? = null
    private val handler = Handler(Looper.getMainLooper())
    private var events: EventChannel.EventSink? = null
    private var adapter: AudioProcessingAdapter? = null
    private val outputs = arrayOfNulls<Output>(4)
    @Volatile private var sourceGain = 1.0
    @Volatile private var sourcePcm = false
    private var sourceCount = 0
    private var sourceSequence = 0
    private val sourceSamples = ShortArray(960)
    private val sourceProcessor = object : AudioProcessingAdapter.ExternalAudioFrameProcessing {
        override fun initialize(sampleRateHz: Int, numChannels: Int) { sourceCount = 0 }
        override fun reset(newRate: Int) { sourceCount = 0 }
        override fun process(numBands: Int, numFrames: Int, buffer: ByteBuffer) {
            val rate = numFrames * 100
            if (rate !in 8000..48000) return
            val floats = buffer.duplicate().order(ByteOrder.nativeOrder()).asFloatBuffer()
            val count = minOf(numFrames, floats.capacity())
            for (i in 0 until count) {
                val input = floats.get(i).toDouble() * sourceGain
                val sample = if (input.isFinite()) input.coerceIn(-32768.0, 32767.0) else 0.0
                floats.put(i, sample.toFloat())
                if (!sourcePcm) continue
                sourceSamples[sourceCount++] = sample.toInt().toShort()
                if (sourceCount >= rate / 50) {
                    val packet = ByteBuffer.allocate(20 + sourceCount * 2).order(ByteOrder.LITTLE_ENDIAN)
                    packet.putInt(0x4143504c).putShort(1).putShort(1).putInt(rate).putInt(sourceCount).putInt(sourceSequence++)
                    for (j in 0 until sourceCount) packet.putShort(sourceSamples[j])
                    val data = packet.array()
                    handler.post { if (sourcePcm) events?.success(data) }
                    sourceCount = 0
                }
            }
        }
    }

    fun register(context: Context, messenger: BinaryMessenger) {
        EventChannel(messenger, "localist/audioFrames").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, sink: EventChannel.EventSink) { events = sink }
            override fun onCancel(arguments: Any?) { events = null }
        })
        EventChannel(messenger, "localist/audioDevices").setStreamHandler(object : EventChannel.StreamHandler {
            private var callback: android.media.AudioDeviceCallback? = null
            private val manager = context.getSystemService(AudioManager::class.java)
            override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
                callback?.let { manager.unregisterAudioDeviceCallback(it) }
                callback = object : android.media.AudioDeviceCallback() {
                    override fun onAudioDevicesAdded(devices: Array<out AudioDeviceInfo>) { sink.success(true) }
                    override fun onAudioDevicesRemoved(devices: Array<out AudioDeviceInfo>) { sink.success(true) }
                }.also { manager.registerAudioDeviceCallback(it, handler) }
            }
            override fun onCancel(arguments: Any?) {
                callback?.let { manager.unregisterAudioDeviceCallback(it) }; callback = null
            }
        })
    }
    fun configureSource(settings: Map<*, *>) {
        val gain = (settings["audioGainDb"] as? Number)?.toDouble() ?: 0.0
        require(gain.isFinite() && gain in -30.0..40.0)
        val current = FlutterWebRTCPlugin.sharedSingleton?.audioProcessingController?.capturePostProcessing
            ?: error("Audio processing is not initialized")
        if (adapter !== current) {
            adapter?.removeProcessor(sourceProcessor)
            current.addProcessor(sourceProcessor)
            adapter = current
        }
        sourceGain = 10.0.pow(gain / 20.0)
        sourcePcm = settings["audioUncompressed"] == true
    }
    fun devices(context: Context): Map<String, Any> {
        val manager = context.getSystemService(AudioManager::class.java)
        return mapOf("available" to true, "backend" to "AudioTrack", "endpoints" to emptyList<Any>(),
            "playbackEndpoints" to manager.getDevices(AudioManager.GET_DEVICES_OUTPUTS).map {
                mapOf("id" to it.id.toString(), "name" to it.productName.toString())
            })
    }
    @Synchronized fun bind(context: Context, settings: Map<*, *>): Boolean {
        val slot = (settings["slot"] as? Number)?.toInt() ?: -1
        require(slot in 0..3)
        outputs[slot]?.stop(); outputs[slot] = null
        val trackId = settings["trackId"] as? String ?: ""
        if (trackId.isEmpty()) { if (outputs.all { it == null }) AudioPlaybackForegroundService.stop(context); return true }
        require(settings["audioOutputMode"] != "mic") { "Android supports playback output; virtual microphone output requires Windows" }
        val track = FlutterWebRTCPlugin.sharedSingleton?.getTrackForId(trackId, settings["ownerTag"] as? String ?: "") as? AudioTrack
            ?: error("The received audio track is unavailable")
        val output = Output(context.applicationContext, track, settings)
        try {
            AudioPlaybackForegroundService.start(context)
            output.start()
            outputs[slot] = output
            return true
        } catch (error: Throwable) {
            output.stop()
            if (outputs.all { it == null }) AudioPlaybackForegroundService.stop(context)
            throw error
        }
    }
    @Synchronized fun status(slot: Int): Map<String, Any> = outputs.getOrNull(slot)?.status()
        ?: mapOf("error" to 0, "frames" to 0L, "microphone" to "")
    @Synchronized fun pcm(slot: Int, data: ByteArray): Boolean = outputs.getOrNull(slot)?.pcm(data) ?: false

    private class Output(val context: Context, val track: AudioTrack, val settings: Map<*, *>) : AudioTrackSink {
        private val maximum = ((settings["audioMaxBuffer"] as? Number)?.toInt() ?: 100).also { require(it in 10..1000) } * 48
        private val minimum = ((settings["audioMinBuffer"] as? Number)?.toInt() ?: 0).also { require(it in 0..maximum / 48) } * 48
        private val gain = 10.0.pow(((settings["audioGainDb"] as? Number)?.toDouble() ?: 0.0).also { require(it.isFinite() && it in -30.0..40.0) } / 20.0)
        private val queue = ShortArray(maximum)
        private val lock = Any()
        private var read = 0; private var count = 0; private var waiting = minimum > 0
        @Volatile private var running = false
        @Volatile private var frames = 0L; @Volatile private var underruns = 0L
        @Volatile private var dropped = 0L; @Volatile private var clipped = 0L
        @Volatile private var error = 0
        @Volatile private var focusPaused = false
        private val usePcm = settings["audioUncompressed"] == true
        private val openSl = settings["audioOutputBackend"] == "opensl"
        private var nativeOutput=0L
        private var equalizer:android.media.audiofx.Equalizer?=null
        private var sequence: Int? = null
        private var previous = 0.0; private var phase = 0; private var oldRate = 0
        private val manager = context.getSystemService(AudioManager::class.java)
        private val attributes = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build()
        private val focus = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
            .setAudioAttributes(attributes).setOnAudioFocusChangeListener { focusPaused = it < 0 }.build()
        private val playerDelegate = lazy { PlatformAudioTrack.Builder().setAudioAttributes(attributes)
            .setAudioFormat(AudioFormat.Builder().setEncoding(AudioFormat.ENCODING_PCM_16BIT).setSampleRate(48000).setChannelMask(AudioFormat.CHANNEL_OUT_MONO).build())
            .setTransferMode(PlatformAudioTrack.MODE_STREAM)
            .setBufferSizeInBytes(maxOf(PlatformAudioTrack.getMinBufferSize(48000,AudioFormat.CHANNEL_OUT_MONO,AudioFormat.ENCODING_PCM_16BIT),1920))
            .setPerformanceMode(if(settings["audioLowLatency"] != false && settings["audioOutputEffects"] != true) PlatformAudioTrack.PERFORMANCE_MODE_LOW_LATENCY else PlatformAudioTrack.PERFORMANCE_MODE_NONE).build() }
        private val player by playerDelegate
        private var worker: Thread? = null
        private var name = "AudioTrack"
        fun start() {
            if(openSl){nativeOutput=OpenSlAudioOutput.create(settings["audioOutputEffects"]==true);check(nativeOutput!=0L){"OpenSL ES output is unavailable"};name="OpenSL ES"}
            else check(player.state == PlatformAudioTrack.STATE_INITIALIZED)
            val requested = (settings["endpointId"] as? String)?.toIntOrNull()
            if (requested != null) {
                val device = manager.getDevices(AudioManager.GET_DEVICES_OUTPUTS).firstOrNull { it.id == requested } ?: error("Output device disconnected")
                check(!openSl) { "Selecting a specific device requires AudioTrack output" }
                check(player.setPreferredDevice(device)) { "Output device selection failed" }
                name = device.productName.toString()
            }
            if (settings["audioFocus"] == "exclusive") check(manager.requestAudioFocus(focus) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED) { "Audio focus is unavailable" }
            running = true
            if(!openSl){
                if(settings["audioOutputEffects"]==true)equalizer=android.media.audiofx.Equalizer(0,player.audioSessionId).apply{enabled=true}
                player.play()
            }
            worker = Thread({
                Process.setThreadPriority(Process.THREAD_PRIORITY_AUDIO)
                val chunk = ShortArray(480)
                try {
                    while (running) {
                        synchronized(lock) {
                            java.util.Arrays.fill(chunk,0.toShort())
                            if (!focusPaused && (!waiting || count >= minimum)) {
                                waiting = false
                                val available = minOf(count,chunk.size)
                                for(i in 0 until available) chunk[i] = queue[(read+i)%maximum]
                                read = (read+available)%maximum; count -= available
                                if(available < chunk.size) { underruns++; waiting = minimum > 0 }
                            }
                        }
                        val written = if(openSl)if(OpenSlAudioOutput.write(nativeOutput,chunk))chunk.size else -1 else player.write(chunk,0,chunk.size,PlatformAudioTrack.WRITE_BLOCKING)
                        if (written < 0) { error = written; break }
                    }
                } catch (_: RuntimeException) { if(running) error = -1 }
            },"Localist Audio Player").apply { start() }
            track.addSink(this)
        }
        private fun push(data: ShortArray, rate: Int, channels: Int, samples: Int) = synchronized(lock) {
            if (!running || rate !in 8000..48000 || channels !in 1..8 || samples > rate/5) return@synchronized
            if(oldRate != rate) { oldRate = rate; phase = 0; previous = 0.0 }
            for(i in 0 until samples) {
                var sum = 0.0
                for(c in 0 until channels) sum += data[i*channels+c]
                val mono = sum/channels
                phase += 48000
                while(phase >= rate) {
                    val interpolated = previous + (mono-previous)*(48000-(phase-rate))/48000
                    val value = interpolated * gain
                    if(value > 32767 || value < -32768) clipped++
                    if(count == maximum) { read=(read+1)%maximum;count--;dropped++ }
                    queue[(read+count)%maximum] = value.coerceIn(-32768.0,32767.0).toInt().toShort()
                    count++;frames++;phase-=rate
                }
                previous=mono
            }
        }
        override fun onData(buffer: ByteBuffer, bits: Int, rate: Int, channels: Int, samples: Int, timestamp: Long) {
            if(usePcm || bits != 16 || channels !in 1..8 || samples <= 0 || samples > rate/5 || samples*channels*2 > buffer.remaining()) return
            val shorts = ShortArray(samples*channels)
            buffer.duplicate().order(ByteOrder.nativeOrder()).asShortBuffer().get(shorts)
            push(shorts,rate,channels,samples)
        }
        fun pcm(data: ByteArray): Boolean {
            if(!usePcm || data.size !in 22..3860) return false
            val buffer = ByteBuffer.wrap(data).order(ByteOrder.LITTLE_ENDIAN)
            if(buffer.int != 0x4143504c || buffer.short.toInt() != 1 || buffer.short.toInt() != 1) return false
            val rate=buffer.int; val size=buffer.int; val seq=buffer.int
            if(rate !in 8000..48000 || size !in 1..rate/25 || data.size != 20+size*2) return false
            if(sequence != null && seq-sequence!! <= 0) return true
            sequence=seq
            val shorts=ShortArray(size); buffer.asShortBuffer().get(shorts)
            push(shorts,rate,1,size);return true
        }
        fun status(): Map<String,Any> = synchronized(lock) { mapOf("error" to error,"frames" to frames,"microphone" to name,
            "bufferedFrames" to count,"droppedFrames" to dropped,"underruns" to underruns,"clippedFrames" to clipped) }
        fun stop() {
            running=false
            track.removeSink(this)
            if(openSl)OpenSlAudioOutput.stop(nativeOutput) else if(playerDelegate.isInitialized()) runCatching { player.pause();player.flush();player.stop() }
            worker?.join(2000)
            equalizer?.release()
            if(openSl){OpenSlAudioOutput.release(nativeOutput);nativeOutput=0L} else if(playerDelegate.isInitialized())player.release()
            if(settings["audioFocus"] == "exclusive")manager.abandonAudioFocusRequest(focus)
        }
    }
}
