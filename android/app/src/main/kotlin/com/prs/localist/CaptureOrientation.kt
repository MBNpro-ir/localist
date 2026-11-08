package com.prs.localist

import com.cloudwebrtc.webrtc.FlutterWebRTCPlugin
import com.cloudwebrtc.webrtc.video.LocalVideoTrack
import org.webrtc.VideoFrame

/** Changes outgoing frame rotation, not just the local preview widget. */
object CaptureOrientation {
    private var track: LocalVideoTrack? = null
    private var processor: LocalVideoTrack.ExternalVideoFrameProcessing? = null

    @Synchronized fun set(trackId: String?, mode: String) {
        require(mode in listOf("auto", "portrait", "landscape"))
        processor?.let { track?.removeProcessor(it) }
        track = null
        processor = null
        if (trackId == null || mode == "auto") return
        val local = FlutterWebRTCPlugin.sharedSingleton?.getLocalTrack(trackId) as? LocalVideoTrack
            ?: throw IllegalStateException("The active camera track is unavailable")
        val transform = object : LocalVideoTrack.ExternalVideoFrameProcessing {
            private var rotation: Int? = null
            override fun onFrame(frame: VideoFrame): VideoFrame {
                if (rotation == null) {
                    val portrait = frame.rotatedHeight > frame.rotatedWidth
                    rotation = if (portrait == (mode == "portrait")) frame.rotation
                        else (frame.rotation + 90) % 360
                }
                if (rotation == frame.rotation) return frame
                // LocalVideoTrack owns/release the replacement; retain the
                // original shared buffer exactly once for that new frame.
                frame.buffer.retain()
                return VideoFrame(frame.buffer, rotation!!, frame.timestampNs)
            }
        }
        local.addProcessor(transform)
        track = local
        processor = transform
    }
}
