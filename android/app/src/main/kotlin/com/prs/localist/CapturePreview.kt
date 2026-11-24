package com.prs.localist

import com.cloudwebrtc.webrtc.FlutterWebRTCPlugin
import com.cloudwebrtc.webrtc.utils.EglUtils
import io.flutter.view.TextureRegistry
import org.webrtc.EglBase
import org.webrtc.EglRenderer
import org.webrtc.GlRectDrawer
import org.webrtc.VideoTrack
import java.util.concurrent.CountDownLatch

/** A small, frame-limited texture attached only to the local preview sink. */
internal class CapturePreview(private val textures: TextureRegistry) : AutoCloseable {
    private var track: VideoTrack? = null
    private var producer: TextureRegistry.SurfaceProducer? = null
    private var renderer: EglRenderer? = null

    fun bind(trackId: String?, width: Int, height: Int): Long? {
        close()
        if (trackId == null) return null
        val source = FlutterWebRTCPlugin.sharedSingleton?.getLocalTrack(trackId)?.track as? VideoTrack
            ?: error("The preview track is unavailable")
        val wide = maxOf(width, height).coerceAtLeast(2)
        val tall = minOf(width, height).coerceAtLeast(2)
        val previewWidth = minOf(480, wide)
        val previewHeight = (previewWidth * tall / wide).coerceAtLeast(2)
        val surface = textures.createSurfaceProducer()
        producer = surface
        val output = EglRenderer("Localist preview")
        try {
            surface.setSize(previewWidth, previewHeight)
            output.init(EglUtils.getRootEglBaseContext(), EglBase.CONFIG_PLAIN, GlRectDrawer())
            renderer = output
            output.setFpsReduction(12f)
            output.setLayoutAspectRatio(previewWidth.toFloat() / previewHeight)
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
            source.addSink(output)
            track = source
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
        if (output != null && source != null) {
            // A live configuration change can dispose the old track first.
            runCatching { source.removeSink(output) }
        }
        try {
            output?.release()
        } finally {
            surface?.setCallback(null)
            surface?.release()
        }
    }
}
