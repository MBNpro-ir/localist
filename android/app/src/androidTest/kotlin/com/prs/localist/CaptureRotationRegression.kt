package com.prs.localist

import org.webrtc.JavaI420Buffer
import org.webrtc.VideoFrame

/** Uses asymmetric pixels, not only dimensions, to catch sideways/stretched output. */
object CaptureRotationRegression {
    private fun pixels(frame: VideoFrame): List<Int> {
        val data = checkNotNull(frame.buffer.toI420())
        return try { (0 until data.height).flatMap { y ->
            (0 until data.width).map { x -> data.dataY.get(y * data.strideY + x).toInt() and 255 }
        } } finally { data.release() }
    }
    fun verify() {
        System.loadLibrary("jingle_peerconnection_so")
        val buffer = JavaI420Buffer.allocate(4, 2)
        for (y in 0..1) for (x in 0..3) buffer.dataY.put(y * buffer.strideY + x, (1 + y * 4 + x).toByte())
        for (x in 0..1) {
            buffer.dataU.put(x, (40 + x).toByte())
            buffer.dataV.put(x, (80 + x).toByte())
        }
        val frame = VideoFrame(buffer, 90, 123L)
        try {
            val expected = mapOf(
                0 to listOf(1, 2, 3, 4, 5, 6, 7, 8),
                90 to listOf(5, 1, 6, 2, 7, 3, 8, 4),
                180 to listOf(8, 7, 6, 5, 4, 3, 2, 1),
                270 to listOf(4, 8, 3, 7, 2, 6, 1, 5),
            )
            for ((rotation, pixels) in expected) {
                val output = CaptureOrientation.rotatePixels(frame, rotation)
                try {
                    check(output.rotation == 0 && output.timestampNs == 123L)
                    val data = checkNotNull(output.buffer.toI420())
                    try {
                        val actual = (0 until data.height).flatMap { y ->
                            (0 until data.width).map { x -> data.dataY.get(y * data.strideY + x).toInt() and 255 }
                        }
                        check(actual == pixels) { "Pixels were not rotated correctly at $rotation: $actual" }
                        val chroma = (0 until (data.height + 1) / 2).flatMap { y ->
                            (0 until (data.width + 1) / 2).map { x -> data.dataU.get(y * data.strideU + x).toInt() and 255 }
                        }
                        check(chroma == if (rotation < 180) listOf(40, 41) else listOf(41, 40))
                    } finally { data.release() }
                } finally { if (output !== frame) output.release() }
            }
            // A landscape frame must keep its shape and handedness as the
            // Android display changes pose, including with auto-rotate disabled.
            for (front in listOf(false, true)) {
                val native = if (front) 270 else 90
                var display = 0
                val landscape = CaptureOrientation.FrameRotation(front, 0, { display })
                for ((pose, expectedRotation) in listOf(0 to 0, 90 to 180, 180 to 180, 270 to 0)) {
                    landscape.update(pose)
                    for (screen in listOf(0, pose)) {
                        display = screen
                        val sourceRotation = (native + (if (front) -display else display) + 360) % 360
                        val source = VideoFrame(buffer.also { it.retain() }, sourceRotation, 456L)
                        val output = landscape.onFrame(source)
                        try {
                            check(output.rotation == 0 && output.buffer.width > output.buffer.height)
                            check(pixels(output) == expected.getValue(expectedRotation)) {
                                "Wrong landscape landmarks: front=$front pose=$pose display=$screen"
                            }
                        } finally { if (output !== source) output.release(); source.release() }
                    }
                }
            }
            check(buffer.dataY.get(0).toInt() == 1)
            var failures = 0
            val damaged = object : VideoFrame.Buffer {
                override fun getWidth() = 8
                override fun getHeight() = 4
                override fun toI420(): VideoFrame.I420Buffer { throw OutOfMemoryError("QA allocation failure") }
                override fun cropAndScale(x: Int, y: Int, w: Int, h: Int, ow: Int, oh: Int): VideoFrame.Buffer = this
                override fun retain() {}
                override fun release() {}
            }
            val unsafe = VideoFrame(damaged, 90, 0)
            val guarded = CaptureOrientation.FrameRotation(false, 90) { failures++ }
            check(guarded.onFrame(unsafe) === unsafe)
            check(guarded.onFrame(unsafe) === unsafe && failures == 1) { "Frame errors must stop capture once, without crashing" }
            unsafe.release()
        } finally { frame.release() }
    }
}
