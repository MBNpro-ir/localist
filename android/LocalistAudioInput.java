package com.cloudwebrtc.webrtc;

import org.webrtc.audio.JavaAudioDeviceModule;

/** Public, narrow injection point compiled into the generated plugin sources. */
public final class LocalistAudioInput {
    private LocalistAudioInput() {}
    public static volatile JavaAudioDeviceModule.AudioBufferCallback callback;
    public static final JavaAudioDeviceModule.AudioBufferCallback bridge =
        (buffer, format, channels, rate, bytes, timestamp) -> {
            JavaAudioDeviceModule.AudioBufferCallback current = callback;
            return current == null ? timestamp : current.onBuffer(buffer, format, channels, rate, bytes, timestamp);
        };
}
