package com.prs.localist

/** Mono 48k native queue, used only when the user selects OpenSL ES. */
object OpenSlAudioOutput {
    init { System.loadLibrary("localist_audio") }
    external fun create(effects: Boolean): Long
    external fun write(handle: Long, pcm: ShortArray): Boolean
    external fun stop(handle: Long)
    external fun release(handle: Long)
}
