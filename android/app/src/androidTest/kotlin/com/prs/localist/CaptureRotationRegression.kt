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
            // Independent landmark expectations for actual capturer metadata.
            // A front camera's raw SENSOR_ORIENTATION is deliberately not used.
            for (front in listOf(false, true)) {
                val native = if (front) 270 else 90
                val source = VideoFrame(buffer.also { it.retain() }, native, 456L)
                try {
                    val auto = CaptureOrientation.FrameRotation("auto", front, 0)
                    val rotations = if (front) listOf(270,180,90,0) else listOf(90,180,270,0)
                    for ((index, physical) in listOf(0,90,180,270).withIndex()) {
                        auto.update(physical)
                        val output = auto.onFrame(source)
                        try { check(pixels(output) == expected.getValue(rotations[index])) { "Upright landmarks wrong: front=$front physical=$physical" } }
                        finally { if (output !== source) output.release() }
                    }
                    for (mode in listOf("portrait", "landscape")) {
                        var displayPhysical = 0
                        val locked = CaptureOrientation.FrameRotation(mode, front, 0, { displayPhysical })
                        locked.update(0)
                        val reference = if (mode == "landscape") expected.getValue(0) else expected.getValue(native)
                        for (physical in listOf(0,90,180,270)) {
                            locked.update(physical)
                            displayPhysical = physical
                            val displayNative = (native + (if (front) -physical else physical) + 360) % 360
                            val current = VideoFrame(buffer.also { it.retain() }, displayNative, 789L)
                            val output = locked.onFrame(current)
                            try {
                                check(output.rotation == 0)
                                check((output.buffer.width > output.buffer.height) == (mode == "landscape"))
                                check(pixels(output) == reference) { "Locked image moved, flipped or acquired padding: $mode front=$front pose=$physical" }
                            } finally { if (output !== current) output.release(); current.release() }
                        }
                    }
                } finally { source.release() }
            }
            // Metadata from a pre-transformed/vendor camera may be 90 even when
            // Camera2 reports a 270 sensor. Preserve the actual capturer result.
            val metadata = CaptureOrientation.FrameRotation("auto", true, 0).onFrame(frame)
            try { check(pixels(metadata) == expected.getValue(90)) { "Metadata was replaced by sensor rotation (upside-down regression)" } }
            finally { if (metadata !== frame) metadata.release() }
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
            val guarded = CaptureOrientation.FrameRotation("auto", false, 0) { failures++ }
            check(guarded.onFrame(unsafe) === unsafe)
            check(guarded.onFrame(unsafe) === unsafe && failures == 1) { "Frame errors must stop capture once, without crashing" }
            unsafe.release()
        } finally { frame.release() }
    }
}
