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
    if (!LocalistMicrophoneSetTrack(slot,audio)) {
      result->Error("LOCALIST_MICROPHONE_UNAVAILABLE","Localist Microphone is unavailable. Repair the signed driver with Localist Setup.",EncodableValue(static_cast<int32_t>(LocalistMicrophoneError(slot))));return;
    }
    result->Success(EncodableValue(true));return;
  }
  if (method_call.method_name().compare("localistVirtualMicrophoneStatus") == 0) {
    if (!method_call.arguments()) { result->Error("BAD_MICROPHONE_ARGUMENTS","Missing microphone arguments");return; }
    const auto params=GetValue<EncodableMap>(*method_call.arguments());
    const int slot=static_cast<int>(findLongInt(params,"slot"));
    if (slot<0||slot>=4) { result->Error("BAD_MICROPHONE_SLOT","Slot must be between zero and three");return; }
    result->Success(EncodableValue(EncodableMap{
      {EncodableValue("frames"),EncodableValue(static_cast<int64_t>(LocalistMicrophoneFrames(slot)))},
      {EncodableValue("error"),EncodableValue(static_cast<int32_t>(LocalistMicrophoneError(slot)))}
    }));return;
  }
