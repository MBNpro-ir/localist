package com.prs.localist

import com.cloudwebrtc.webrtc.FlutterWebRTCPlugin
import com.cloudwebrtc.webrtc.utils.EglUtils
import io.flutter.view.TextureRegistry
import org.webrtc.EglBase
import org.webrtc.EglRenderer
import org.webrtc.GlRectDrawer
import org.webrtc.VideoFrame
import org.webrtc.VideoSink
import org.webrtc.VideoTrack
import java.util.concurrent.CountDownLatch

/** A small, frame-limited texture attached only to the local preview sink. */
internal class CapturePreview(private val textures: TextureRegistry) : AutoCloseable {
    private var track: VideoTrack? = null
    private var sink: VideoSink? = null
    private var producer: TextureRegistry.SurfaceProducer? = null
    private var renderer: EglRenderer? = null

    fun bind(trackId: String?): Long? {
        close()
        if (trackId == null) return null
        val source = FlutterWebRTCPlugin.sharedSingleton?.getLocalTrack(trackId)?.track as? VideoTrack
            ?: error("The preview track is unavailable")
        val surface = textures.createSurfaceProducer()
        producer = surface
        val output = EglRenderer("Localist preview")
        try {
            // Only the local preview is locked to portrait.
            surface.setSize(270, 480)
            output.init(EglUtils.getRootEglBaseContext(), EglBase.CONFIG_PLAIN, GlRectDrawer())
            renderer = output
            output.setFpsReduction(12f)
            surface.setCallback(object : TextureRegistry.SurfaceProducer.Callback {
                override fun onSurfaceAvailable() {
                    if (producer === surface) output.createEglSurface(surface.surface)
                }

                override fun onSurfaceCleanup() {
                    if (producer !== surface) return
                    val released = CountDownLatch(1)
                    output.releaseEglSurface { released.countDown() }
                    org.webrtc.ThreadUtils.awaitUninterruptibly(released)
                }
            })
            output.createEglSurface(surface.surface)
            val previewSink = VideoSink { frame ->
                val rotation = CaptureOrientation.previewRotation(frame)
                if (rotation == frame.rotation) {
                    output.onFrame(frame)
                } else {
                    frame.buffer.retain()
                    val local = VideoFrame(frame.buffer, rotation, frame.timestampNs)
                    try {
                        output.onFrame(local)
                    } finally {
                        local.release()
                    }
                }
            }
            track = source
            sink = previewSink
            source.addSink(previewSink)
            return surface.id()
        } catch (error: Exception) {
            close()
            throw error
        }
    }

    override fun close() {
        val output = renderer
        renderer = null
        val surface = producer
        producer = null
        val source = track
        track = null
        val previewSink = sink
        sink = null
        if (previewSink != null && source != null) {
            // A live configuration change can dispose the old track first.
            runCatching { source.removeSink(previewSink) }
        }
        try {
            output?.release()
        } finally {
            surface?.setCallback(null)
            surface?.release()
        }
    }
}
