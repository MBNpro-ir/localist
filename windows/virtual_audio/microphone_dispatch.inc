  if (method_call.method_name().compare("localistVirtualMicrophone") == 0) {
    if (!method_call.arguments()) { result->Error("BAD_MICROPHONE_ARGUMENTS","Missing microphone arguments");return; }
    const auto params=GetValue<EncodableMap>(*method_call.arguments());
    const int slot=static_cast<int>(findLongInt(params,"slot"));
    const auto track_id=findString(params,"trackId");
    if (slot<0||slot>=4) { result->Error("BAD_MICROPHONE_SLOT","Slot must be between zero and three");return; }
    libwebrtc::scoped_refptr<libwebrtc::RTCAudioTrack> audio;
    if (!track_id.empty()) {
      auto* observer=PeerConnectionObserversForId(findString(params,"ownerTag"));
      auto track=observer ? observer->MediaTrackForId(track_id) : nullptr;
      if (!track || track->kind().std_string()!="audio") { result->Error("MICROPHONE_TRACK_MISSING","The received audio track is unavailable");return; }
      audio=libwebrtc::scoped_refptr<libwebrtc::RTCAudioTrack>(static_cast<libwebrtc::RTCAudioTrack*>(track.get()));
    }
    LocalistAudioRenderOptions output;
    if(params.count(EncodableValue("audioMinBuffer")))output.minimum_ms=static_cast<int>(findLongInt(params,"audioMinBuffer"));
    if(params.count(EncodableValue("audioMaxBuffer")))output.maximum_ms=static_cast<int>(findLongInt(params,"audioMaxBuffer"));
    output.gain_db=maybeFindDouble(params,"audioGainDb").value_or(0);
    output.playback=findString(params,"audioOutputMode")=="playback";
    output.pcm=findBoolean(params,"audioUncompressed");
    if(params.count(EncodableValue("audioEventSync")))output.event_sync=findBoolean(params,"audioEventSync");
    if(output.minimum_ms<0||output.maximum_ms<10||output.maximum_ms>1000||output.minimum_ms>output.maximum_ms||
        !(output.gain_db>=-30&&output.gain_db<=40)){
      result->Error("BAD_AUDIO_SETTINGS","Invalid audio buffer/gain");return;
    }
    if (!LocalistMicrophoneSetTrack(slot,audio,findString(params,"endpointId"),output)) {
      result->Error("LOCALIST_MICROPHONE_UNAVAILABLE","No unused VB-CABLE is available. Install independent A/B/C/D cables for additional microphones, or disable audio on another receiver.",EncodableValue(static_cast<int32_t>(LocalistMicrophoneError(slot))));return;
    }
    result->Success(EncodableValue(true));return;
  }
  if (method_call.method_name().compare("localistVirtualMicrophoneStatus") == 0) {
    if (!method_call.arguments()) { result->Error("BAD_MICROPHONE_ARGUMENTS","Missing microphone arguments");return; }
    const auto params=GetValue<EncodableMap>(*method_call.arguments());
    const int slot=static_cast<int>(findLongInt(params,"slot"));
    if (slot<0||slot>=4) { result->Error("BAD_MICROPHONE_SLOT","Slot must be between zero and three");return; }
    const auto queue=LocalistMicrophoneQueue(slot);
    result->Success(EncodableValue(EncodableMap{
      {EncodableValue("frames"),EncodableValue(static_cast<int64_t>(LocalistMicrophoneFrames(slot)))},
      {EncodableValue("microphone"),EncodableValue(LocalistMicrophoneName(slot))},
      {EncodableValue("silentPlayoutEndpoint"),EncodableValue(LocalistCapturePlayoutEndpoint())},
      {EncodableValue("bufferedFrames"),EncodableValue(static_cast<int64_t>(queue.buffered))},
      {EncodableValue("droppedFrames"),EncodableValue(static_cast<int64_t>(queue.dropped))},
      {EncodableValue("underruns"),EncodableValue(static_cast<int64_t>(queue.underruns))},
      {EncodableValue("clippedFrames"),EncodableValue(static_cast<int64_t>(queue.clipped))},
      {EncodableValue("error"),EncodableValue(static_cast<int32_t>(LocalistMicrophoneError(slot)))}
    }));return;
  }
  if (method_call.method_name().compare("localistCaptureAudioSettings") == 0) {
    EnsureWebRTCInitialized();
    const auto params=GetValue<EncodableMap>(*method_call.arguments());
    const auto gain=maybeFindDouble(params,"audioGainDb").value_or(0);
    if(!(gain>=-30&&gain<=40)){result->Error("BAD_AUDIO_GAIN","Gain is outside -30..40 dB");return;}
    LocalistConfigureCaptureAudio(gain,findBoolean(params,"audioUncompressed"));
    result->Success(EncodableValue(true));return;
  }
  if (method_call.method_name().compare("localistVirtualMicrophonePcm") == 0) {
    const auto params=GetValue<EncodableMap>(*method_call.arguments());
    const auto found=params.find(EncodableValue("data"));
    if(found==params.end()||!TypeIs<std::vector<uint8_t>>(found->second)){
      result->Error("BAD_PCM","PCM bytes missing");return;
    }
    result->Success(EncodableValue(LocalistMicrophonePcm(static_cast<int>(findLongInt(params,"slot")),GetValue<std::vector<uint8_t>>(found->second))));return;
  }
  if (method_call.method_name().compare("localistStopSystemAudio") == 0) {
    FlutterScreenCapture::OnStop(nullptr);
    result->Success(EncodableValue(true));return;
  }
