package com.prs.localist

import android.annotation.SuppressLint
import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.MediaRecorder.AudioSource
import android.os.Build
import com.cloudwebrtc.webrtc.FlutterWebRTCPlugin
import com.cloudwebrtc.webrtc.LocalistAudioInput
import com.cloudwebrtc.webrtc.audio.AudioUtils
import org.webrtc.audio.JavaAudioDeviceModule

/** Supplies explicitly selected Android recording presets to the WebRTC audio worker. */
object CaptureMicrophone {
    private const val RATE = 48000
    private const val MONO = AudioFormat.CHANNEL_IN_MONO
    private const val PCM = AudioFormat.ENCODING_PCM_16BIT
    private var recorder: AudioRecord? = null
    private var callback: JavaAudioDeviceModule.AudioBufferCallback? = null
    @Volatile private var muted = false

    private fun sources(manager: AudioManager): Map<String, Int> = buildMap {
        put("default", AudioSource.DEFAULT)
        put("mic", AudioSource.MIC)
        if (manager.getProperty(AudioManager.PROPERTY_SUPPORT_AUDIO_SOURCE_UNPROCESSED) == "true") {
            put("raw", AudioSource.UNPROCESSED)
        }
        put("communication", AudioSource.VOICE_COMMUNICATION)
        if (Build.VERSION.SDK_INT >= 29) put("performance", AudioSource.VOICE_PERFORMANCE)
        put("recognition", AudioSource.VOICE_RECOGNITION)
        put("camcorder", AudioSource.CAMCORDER)
    }

    fun modes(context: Context): List<String> = sources(context.getSystemService(AudioManager::class.java)).keys.toList()

    private fun routes(manager: AudioManager): Map<String, AudioDeviceInfo> {
        val inputs = manager.getDevices(AudioManager.GET_DEVICES_INPUTS).filter { device ->
            device.type in setOf(AudioDeviceInfo.TYPE_BUILTIN_MIC, AudioDeviceInfo.TYPE_WIRED_HEADSET,
                AudioDeviceInfo.TYPE_USB_HEADSET, AudioDeviceInfo.TYPE_USB_DEVICE, AudioDeviceInfo.TYPE_USB_ACCESSORY,
                AudioDeviceInfo.TYPE_BLUETOOTH_SCO, AudioDeviceInfo.TYPE_BLE_HEADSET)
        }
        val aliases = inputs.groupingBy(AudioUtils::getAudioDeviceId).eachCount()
        return inputs.associateBy { device ->
            val alias = AudioUtils.getAudioDeviceId(device)
            if (aliases[alias] == 1) alias else "android:${device.id}"
        }
    }

    fun inputs(context: Context): List<Map<String, String>> {
        val inputs = routes(context.getSystemService(AudioManager::class.java))
        val names = inputs.values.groupingBy { it.productName.toString() }.eachCount()
        return inputs.map { (id, input) ->
            val name = input.productName.toString()
            mapOf("deviceId" to id, "label" to if (names[name] == 1) name else "$name (${input.id})")
        }
    }

    @SuppressLint("MissingPermission") // Called after the microphone permission and capture-start checks.
    @Synchronized fun configure(context: Context, mode: String, deviceId: String?, startMuted: Boolean) {
        val manager = context.getSystemService(AudioManager::class.java)
        val source = sources(manager)[mode] ?: error("This microphone mode is not available on this device")
        val module = FlutterWebRTCPlugin.sharedSingleton?.audioDeviceModule ?: error("Audio engine is not ready")
        val device = deviceId?.let { selected ->
            routes(manager)[selected] ?: manager.getDevices(AudioManager.GET_DEVICES_INPUTS)
                .firstOrNull { AudioUtils.getAudioDeviceId(it) == selected }
                ?: error("The selected microphone has disconnected")
        }
        val minimum = AudioRecord.getMinBufferSize(RATE, MONO, PCM)
        check(minimum > 0) { "The microphone does not support this audio format" }
        val format = AudioFormat.Builder().setEncoding(PCM).setSampleRate(RATE).setChannelMask(MONO).build()
        val next = AudioRecord.Builder().setAudioSource(source).setAudioFormat(format)
            .setBufferSizeInBytes(maxOf(minimum, 3840)).build()
        try {
            check(next.state == AudioRecord.STATE_INITIALIZED) { "The microphone could not be initialized" }
            check(device == null || next.setPreferredDevice(device)) { "The microphone does not support this input route" }
            next.startRecording()
            check(next.recordingState == AudioRecord.RECORDSTATE_RECORDING) { "The microphone could not start" }
        } catch (error: RuntimeException) {
            next.release()
            throw error
        }

        val previous = recorder
        val input = JavaAudioDeviceModule.AudioBufferCallback { buffer, encoding, channels, rate, _, timestamp ->
            // WebRTC reports zero bytes from its recorder when external input is active.
            val requested = buffer.capacity()
            val target = buffer.duplicate().apply { clear() }
            val count = if (encoding == PCM && channels == 1 && rate == RATE) {
                runCatching { next.read(target, requested, AudioRecord.READ_BLOCKING) }.getOrDefault(0)
            } else 0
            val silentFrom = if (muted) 0 else count.coerceAtLeast(0)
            for (index in silentFrom until requested) buffer.put(index, 0.toByte())
            timestamp
        }
        recorder = next
        callback = input
        muted = startMuted
        LocalistAudioInput.callback = input
        module.setAudioRecordEnabled(false)
        close(previous)
        MainActivity.broadcastNativeLog(context, "CaptureMicrophone",
            "Recording preset=$mode selectedType=${device?.type} routedType=${next.routedDevice?.type}")
    }

    fun setMuted(value: Boolean) { muted = value }

    @Synchronized fun stop() {
        muted = false
        val previous = recorder ?: return
        if (LocalistAudioInput.callback === callback) {
            LocalistAudioInput.callback = null
            FlutterWebRTCPlugin.sharedSingleton?.audioDeviceModule?.setAudioRecordEnabled(true)
        }
        recorder = null
        callback = null
        close(previous)
    }

    private fun close(record: AudioRecord?) {
        if (record == null) return
        runCatching { record.stop() }
        record.release()
    }
}
