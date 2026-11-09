package com.prs.localist

import android.app.Activity
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioPlaybackCaptureConfiguration
import android.media.AudioRecord
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.annotation.RequiresApi
import com.carriez.flutter_hbb.LocalistNotifications
import io.flutter.plugin.common.MethodChannel
import com.cloudwebrtc.webrtc.LocalistAudioInput
import com.cloudwebrtc.webrtc.FlutterWebRTCPlugin

/** Android 10+ playback capture, started only after MediaProjection consent. */
@RequiresApi(29)
class SystemAudioCaptureService : Service() {
    private var intentionalStop=false
    private var projection: MediaProjection? = null
    private var recorder: AudioRecord? = null
    override fun onBind(intent: Intent?): IBinder? = null
    override fun onStartCommand(intent: Intent?, flags: Int, id: Int): Int {
        try {
            LocalistNotifications.start(this,"Localist",LocalistText.choose(this,"انتقال صدای برنامه‌ها","Sharing app audio"),emptyList(),ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
            @Suppress("DEPRECATION")
            val data=intent?.getParcelableExtra<Intent>("consent") ?: error("Audio capture consent is missing")
            val manager=getSystemService(MediaProjectionManager::class.java)
            val media=manager.getMediaProjection(Activity.RESULT_OK,data) ?: error("Screen/audio capture consent expired")
            projection=media
            media.registerCallback(object:MediaProjection.Callback(){
                override fun onStop(){ if(!intentionalStop)CaptureForegroundService.channel?.invokeMethod("captureError","System audio capture permission was revoked");stopSelf() }
            },Handler(Looper.getMainLooper()))
            val config=AudioPlaybackCaptureConfiguration.Builder(media)
                .addMatchingUsage(AudioAttributes.USAGE_MEDIA).addMatchingUsage(AudioAttributes.USAGE_GAME).addMatchingUsage(AudioAttributes.USAGE_UNKNOWN).build()
            val format=AudioFormat.Builder().setEncoding(AudioFormat.ENCODING_PCM_16BIT).setSampleRate(48000).setChannelMask(AudioFormat.CHANNEL_IN_MONO).build()
            @Suppress("MissingPermission")
            val record=AudioRecord.Builder().setAudioFormat(format).setBufferSizeInBytes(maxOf(9600,AudioRecord.getMinBufferSize(48000,AudioFormat.CHANNEL_IN_MONO,AudioFormat.ENCODING_PCM_16BIT)))
                .setAudioPlaybackCaptureConfig(config).build()
            check(record.state==AudioRecord.STATE_INITIALIZED) { "System audio recorder is unavailable" }
            recorder=record;record.startRecording();CaptureAudioEngine.systemRecorder=record
            LocalistAudioInput.callback=org.webrtc.audio.JavaAudioDeviceModule.AudioBufferCallback { buffer,format,channels,rate,_,time ->
                val size=buffer.capacity()
                for(i in 0 until size)buffer.put(i,0.toByte())
                if(format==AudioFormat.ENCODING_PCM_16BIT && channels==1 && rate==48000){
                    val target=buffer.duplicate();target.clear()
                    runCatching { record.read(target,size,AudioRecord.READ_BLOCKING) }
                }
                time
            }
            FlutterWebRTCPlugin.sharedSingleton?.audioDeviceModule?.setAudioRecordEnabled(false)
            complete(null)
        }catch(error:Throwable){complete(error);stopSelf()}
        return START_NOT_STICKY
    }
    override fun onDestroy(){
        intentionalStop=true
        CaptureAudioEngine.systemRecorder=null
        LocalistAudioInput.callback=null
        FlutterWebRTCPlugin.sharedSingleton?.audioDeviceModule?.setAudioRecordEnabled(true)
        runCatching{recorder?.stop()};recorder?.release();recorder=null
        val media=projection;projection=null;runCatching { media?.stop() }
        LocalistNotifications.stop(this);super.onDestroy()
    }
    companion object {
        var pending:MethodChannel.Result?=null
        fun begin(context:Context,data:Intent,result:MethodChannel.Result){
            if(pending!=null){result.error("SYSTEM_AUDIO_BUSY","Audio capture is starting",null);return}
            pending=result
            try {
                context.startForegroundService(Intent(context,SystemAudioCaptureService::class.java).putExtra("consent",data))
                Handler(Looper.getMainLooper()).postDelayed({
                    if(pending===result){complete(IllegalStateException("System audio capture timed out"));context.stopService(Intent(context,SystemAudioCaptureService::class.java))}
                },15000)
            }catch(error:Exception){complete(error)}
        }
        private fun complete(error:Throwable?){val result=pending;pending=null
            if(error==null)result?.success(true) else result?.error("SYSTEM_AUDIO_CAPTURE",error.message,null)}
    }
}
