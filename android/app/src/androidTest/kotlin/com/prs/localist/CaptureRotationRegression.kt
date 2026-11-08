package com.prs.localist

import org.webrtc.JavaI420Buffer
import org.webrtc.VideoFrame

/** Uses asymmetric pixels, not only dimensions, to catch sideways/stretched output. */
object CaptureRotationRegression {
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
            for (front in listOf(false, true)) {
                val sensor = if (front) 270 else 90
                val transform = CaptureOrientation.FrameRotation("auto", sensor, front, 0)
                for (physical in listOf(0, 90, 180, 270, 0)) {
                    transform.update(physical)
                    val output = transform.onFrame(frame)
                    val rotation = (sensor + (if (front) -physical else physical) + 360) % 360
                    val reference = CaptureOrientation.rotatePixels(frame, rotation)
                    try {
                        check(output.rotation == 0)
                        check(output.buffer.width == reference.buffer.width && output.buffer.height == reference.buffer.height)
                        val a = checkNotNull(output.buffer.toI420()); val b = checkNotNull(reference.buffer.toI420())
                        try { check(a.dataY.get(0) == b.dataY.get(0)) { "Front/back sensor direction incorrect" } }
                        finally { a.release(); b.release() }
                    } finally { if (output !== frame) output.release(); if (reference !== frame) reference.release() }
                }
            }
            for (mode in listOf("portrait", "landscape")) {
                val transform = CaptureOrientation.FrameRotation(mode, 90, false, 0)
                for (physical in listOf(0, 90, 180, 270)) {
                    transform.update(physical)
                    val output = transform.onFrame(frame)
                    try { check((output.buffer.height > output.buffer.width) == (mode == "portrait")) }
                    finally { if (output !== frame) output.release() }
                }
            }
            // The source must still be valid after every replacement releases its reference.
            check(buffer.dataY.get(0).toInt() == 1)
        } finally { frame.release() }
    }
}
