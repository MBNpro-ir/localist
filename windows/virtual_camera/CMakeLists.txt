cmake_minimum_required(VERSION 3.18)
project(localist_virtual_camera LANGUAGES C CXX)
if(TARGET flutter_webrtc_plugin)
  if(LOCALIST_CAPTURE_QA_RUNNER)
    target_compile_definitions(flutter_webrtc_plugin PRIVATE LOCALIST_CAMERA_TEST_IDENTITY=1)
  endif()
  set(LOCALIST_CAMERA_VERSION "${FLUTTER_VERSION_MAJOR}.${FLUTTER_VERSION_MINOR}.${FLUTTER_VERSION_PATCH}.${FLUTTER_VERSION_BUILD}")
endif()
set(VC_SUFFIX "")
if(LOCALIST_CAMERA_VERSION)
  set(VC_SUFFIX "-${LOCALIST_CAMERA_VERSION}")
endif()
set(VC_SOURCE "${CMAKE_CURRENT_SOURCE_DIR}/../../third_party/virtual_camera/upstream")
set(VC_MODULE "${VC_SOURCE}/plugins/win-dshow/virtualcam-module")
set(VC_DSHOW "${VC_SOURCE}/deps/libdshowcapture/src")
set(VC_SCALE "${VC_SOURCE}/shared/obs-tiny-nv12-scale")
set(VC_QUEUE "${VC_SOURCE}/shared/obs-shared-memory-queue")

# Keep reference sources byte-for-byte pinned; adaptations live in the build.
file(READ "${VC_MODULE}/virtualcam-module.cpp" module)
string(REPLACE "OBS Virtual Camera" "Localist Camera" module "${module}")
string(PREPEND module "#include \"capture_controls.h\"\n")
string(REPLACE "CreateInstance(LPUNKNOWN parent, REFIID, void **p_ptr)" "CreateInstance(LPUNKNOWN parent, REFIID iid, void **p_ptr)" module "${module}")
string(REPLACE "*p_ptr = (void *)new VCamFilter();\n\t\treturn S_OK;" "auto* filter = new VCamFilter();\n\t\tconst auto hr = filter->QueryInterface(iid, p_ptr);\n\t\tfilter->Release();\n\t\treturn hr;" module "${module}")
string(REPLACE "if (IsEqualCLSID(cls, CLSID_OBS_VirtualVideo)) {" "if (IsEqualCLSID(cls, CLSID_LocalistControls)) return CreateLocalistControlsPage(iid, p_ptr);\n\tif (IsEqualCLSID(cls, CLSID_OBS_VirtualVideo)) {" module "${module}")
string(REPLACE "return RegServer(CLSID_OBS_VirtualVideo, L\"Localist Camera\", file);" "return RegServer(CLSID_OBS_VirtualVideo, L\"Localist Camera\", file) && RegServer(CLSID_LocalistControls, L\"Localist Camera Controls\", file);" module "${module}")
string(REPLACE "return UnregServer(CLSID_OBS_VirtualVideo);" "UnregServer(CLSID_LocalistControls); return UnregServer(CLSID_OBS_VirtualVideo);" module "${module}")
string(REPLACE "if (!IsEqualCLSID(cls, CLSID_OBS_VirtualVideo)) {" "if (!IsEqualCLSID(cls, CLSID_OBS_VirtualVideo) && !IsEqualCLSID(cls, CLSID_LocalistControls)) {" module "${module}")
string(REPLACE "L\"Localist Camera\"" "LOCALIST_CAMERA_NAME" module "${module}")
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/virtualcam-module.cpp" "${module}")
file(READ "${VC_MODULE}/virtualcam-filter.hpp" header)
string(PREPEND header "#include <ocidl.h>\n")
string(REPLACE "class VCamFilter : public DShow::OutputFilter {" "class VCamFilter : public DShow::OutputFilter, public IAMCameraControl, public ISpecifyPropertyPages {" header "${header}")
string(REPLACE "\tVCamFilter();" "\tSTDMETHODIMP QueryInterface(REFIID, void**) override;\n\tSTDMETHODIMP_(ULONG) AddRef() override { return OutputFilter::AddRef(); }\n\tSTDMETHODIMP_(ULONG) Release() override { return OutputFilter::Release(); }\n\tSTDMETHODIMP GetPages(CAUUID*) override;\n\tSTDMETHODIMP GetRange(long,long*,long*,long*,long*,long*) override;\n\tSTDMETHODIMP Get(long,long*,long*) override;\n\tSTDMETHODIMP Set(long,long,long) override;\n\tVCamFilter();" header "${header}")
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/virtualcam-filter.hpp" "${header}")
file(READ "${VC_MODULE}/virtualcam-filter.cpp" filter)
# Stable idle capabilities without writing any user-wide OBS/configuration file.
string(REPLACE "uint32_t new_obs_cx = obs_cx;" "uint32_t new_obs_cx = obs_cx ? obs_cx : 640;" filter "${filter}")
string(REPLACE "uint32_t new_obs_cy = obs_cy;" "uint32_t new_obs_cy = obs_cy ? obs_cy : 480;" filter "${filter}")
string(REPLACE "uint64_t new_obs_interval = obs_interval;" "uint64_t new_obs_interval = obs_interval ? obs_interval : 333333;" filter "${filter}")
string(FIND "${filter}" "\t} else {\n\t\twchar_t res_file" config_start)
string(FIND "${filter}" "\n\tif (new_obs_cx != obs_cx" config_end)
if(config_start LESS 0 OR config_end LESS 0)
  message(FATAL_ERROR "Pinned camera filter config block changed")
endif()
string(SUBSTRING "${filter}" 0 ${config_start} filter_before)
string(SUBSTRING "${filter}" ${config_end} -1 filter_after)
set(filter "${filter_before}\t}\n${filter_after}")
# Consumer output modes are independent of the phone's current capture mode.
string(REPLACE "\t/* ---------------------------------------- */\n\n\tth = std::thread" "\tfor (auto size : {std::pair<int,int>{320,240},{640,480},{1280,720},{1920,1080},{480,640},{720,1280},{1080,1920}})\n\t\tfor (int fps : {10,15,24,30,60})\n\t\t\tfor (auto fmt : {VideoFormat::NV12,VideoFormat::I420,VideoFormat::YUY2})\n\t\t\t\tAddVideoFormat(fmt,size.first,size.second,10000000LL/fps);\n\t/* ---------------------------------------- */\n\n\tth = std::thread" filter "${filter}")
string(REPLACE "in_obs = !!wcsstr(file, obs_process);" "in_obs = false; // Localist always respects the consumer-selected output mode." filter "${filter}")
string(REPLACE "sleepto_100ns(cur_time += obs_interval);\n\t\tfilter_time += obs_interval;" "const uint64_t output_interval = static_cast<uint64_t>(GetInterval());\n\t\tsleepto_100ns(cur_time += output_interval);\n\t\tfilter_time += output_interval;" filter "${filter}")
string(REPLACE "UnlockSampleData(ts, ts + obs_interval);" "UnlockSampleData(ts, ts + GetInterval());" filter "${filter}")
string(REPLACE "if (!video_queue_read(vq, &scaler, ptr, &temp)) {"
  "if (!video_queue_read(vq, &scaler, ptr, &temp)) {\n\t\tShowDefaultFrame(ptr);" filter "${filter}")
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/virtualcam-filter.cpp" "${filter}")
file(READ "${VC_DSHOW}/source/output-filter.cpp" pin)
string(REPLACE "if (pmt == nullptr)\n\t\treturn VFW_E_INVALIDMEDIATYPE;" "if (!pmt || pmt->majortype != MEDIATYPE_Video || pmt->formattype != FORMAT_VideoInfo || !pmt->pbFormat || pmt->cbFormat < sizeof(VIDEOINFOHEADER)) return VFW_E_INVALIDMEDIATYPE;\n\tconst auto* requested = reinterpret_cast<const VIDEOINFOHEADER*>(pmt->pbFormat);\n\tif (requested->bmiHeader.biWidth < 2 || requested->bmiHeader.biWidth > 4096 || requested->bmiHeader.biHeight < 2 || requested->bmiHeader.biHeight > 4096 || (requested->bmiHeader.biWidth & 1) || (requested->bmiHeader.biHeight & 1) || requested->AvgTimePerFrame < 166666 || requested->AvgTimePerFrame > 1000000 || (pmt->subtype != MEDIASUBTYPE_NV12 && pmt->subtype != MEDIASUBTYPE_I420 && pmt->subtype != MEDIASUBTYPE_YUY2)) return VFW_E_INVALIDMEDIATYPE;\n\tif (connectedPin) return VFW_E_ALREADY_CONNECTED;" pin "${pin}")
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/output-filter.cpp" "${pin}")
file(READ "${VC_QUEUE}/shared-memory-queue.c" queue)
string(REPLACE "#define VIDEO_NAME L\"OBSVirtualCamVideo\"" "#define LOCALIST_QUEUE_IMPLEMENTATION\n#include \"camera_namespace.h\"" queue "${queue}")
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/shared-memory-queue.c" "${queue}")

set(VC_COMMON "${CMAKE_CURRENT_BINARY_DIR}/shared-memory-queue.c" "${VC_SCALE}/tiny-nv12-scale.c")
set(VC_INCLUDES "${CMAKE_CURRENT_BINARY_DIR}" "${CMAKE_CURRENT_SOURCE_DIR}" "${VC_MODULE}" "${VC_DSHOW}" "${VC_DSHOW}/source" "${VC_SCALE}" "${VC_QUEUE}" "${VC_SOURCE}/libobs")
foreach(VC_SLOT RANGE 0 3)
  set(VC_TARGET "LocalistVirtualCamera")
  set(VC_SLOT_SUFFIX "")
  if(VC_SLOT GREATER 0)
    math(EXPR VC_NUMBER "${VC_SLOT} + 1")
    set(VC_SLOT_SUFFIX "-${VC_NUMBER}")
    set(VC_TARGET "LocalistVirtualCamera${VC_NUMBER}")
  endif()
add_library(${VC_TARGET} SHARED
  "${CMAKE_CURRENT_BINARY_DIR}/virtualcam-module.cpp"
  "${CMAKE_CURRENT_BINARY_DIR}/virtualcam-filter.cpp"
  "${VC_MODULE}/sleepto.c" placeholder.cpp dshow_errors.cpp camera.def capture_controls.cpp capture_controls_bus.cpp
  "${CMAKE_CURRENT_BINARY_DIR}/output-filter.cpp"
  "${VC_DSHOW}/source/dshow-formats.cpp"
  "${VC_DSHOW}/source/dshow-media-type.cpp"
  "${VC_DSHOW}/source/log.cpp"
  ${VC_COMMON})
target_include_directories(${VC_TARGET} PRIVATE ${VC_INCLUDES})
target_compile_features(${VC_TARGET} PRIVATE cxx_std_17)
target_compile_definitions(${VC_TARGET} PRIVATE UNICODE _UNICODE _CRT_SECURE_NO_WARNINGS NOMINMAX LOCALIST_CAMERA_SLOT=${VC_SLOT})
target_compile_options(${VC_TARGET} PRIVATE /wd4005 /wd4018)
set_property(TARGET ${VC_TARGET} PROPERTY MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
target_link_libraries(${VC_TARGET} PRIVATE strmiids ole32 oleaut32 advapi32 shell32 winmm)
if(CMAKE_SIZEOF_VOID_P EQUAL 8)
  set_target_properties(${VC_TARGET} PROPERTIES OUTPUT_NAME "LocalistCamera64${VC_SLOT_SUFFIX}${VC_SUFFIX}")
else()
  set_target_properties(${VC_TARGET} PROPERTIES OUTPUT_NAME "LocalistCamera32${VC_SLOT_SUFFIX}${VC_SUFFIX}")
endif()

endforeach()

option(LOCALIST_CAMERA_QA "Build the isolated camera probe" OFF)
if(LOCALIST_CAMERA_QA)
  if(NOT LOCALIST_WEBRTC_DIR AND DEFINED FLUTTER_MANAGED_DIR)
    set(LOCALIST_WEBRTC_DIR "${FLUTTER_MANAGED_DIR}/ephemeral/.plugin_symlinks/flutter_webrtc/third_party/libwebrtc")
  endif()
  foreach(VC_TARGET LocalistVirtualCamera LocalistVirtualCamera2 LocalistVirtualCamera3 LocalistVirtualCamera4)
    target_compile_definitions(${VC_TARGET} PRIVATE LOCALIST_CAMERA_TEST_IDENTITY=1)
  endforeach()
  add_executable(localist_camera_probe camera_probe.cpp webrtc_virtual_camera.cpp capture_controls_bus.cpp ${VC_COMMON})
  target_include_directories(localist_camera_probe PRIVATE ${VC_INCLUDES} "${LOCALIST_WEBRTC_DIR}/include")
  target_compile_features(localist_camera_probe PRIVATE cxx_std_17)
  target_compile_definitions(localist_camera_probe PRIVATE UNICODE _UNICODE NOMINMAX LIB_WEBRTC_API_DLL LOCALIST_CAMERA_TEST_IDENTITY=1)
  target_link_libraries(localist_camera_probe PRIVATE "${LOCALIST_WEBRTC_DIR}/lib/libwebrtc.dll.lib" advapi32 ole32 oleaut32 strmiids)
  add_custom_command(TARGET localist_camera_probe POST_BUILD COMMAND "${CMAKE_COMMAND}" -E copy_if_different
    "${LOCALIST_WEBRTC_DIR}/lib/libwebrtc.dll" "$<TARGET_FILE_DIR:localist_camera_probe>")
endif()

if(TARGET flutter_webrtc_plugin)
  include(ExternalProject)
  ExternalProject_Add(localist_camera_x86
    SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}"
    BINARY_DIR "${CMAKE_BINARY_DIR}/camera-x86"
    CMAKE_GENERATOR "${CMAKE_GENERATOR}"
    CMAKE_GENERATOR_PLATFORM Win32
    CMAKE_ARGS "-DLOCALIST_CAMERA_VERSION=${LOCALIST_CAMERA_VERSION}"
    BUILD_COMMAND "${CMAKE_COMMAND}" --build <BINARY_DIR> --config Release --target LocalistVirtualCamera LocalistVirtualCamera2 LocalistVirtualCamera3 LocalistVirtualCamera4
    INSTALL_COMMAND ""
    BUILD_ALWAYS TRUE)
  add_dependencies(${BINARY_NAME} localist_camera_x86)
  foreach(VC_CAMERA_SUFFIX "" "-2" "-3" "-4")
    install(FILES "${CMAKE_BINARY_DIR}/camera-x86/Release/LocalistCamera32${VC_CAMERA_SUFFIX}${VC_SUFFIX}.dll"
      DESTINATION "${CMAKE_INSTALL_PREFIX}" COMPONENT Runtime)
  endforeach()
  get_target_property(plugin_sources flutter_webrtc_plugin SOURCES)
  set(renderer_found FALSE)
  set(peer_found FALSE)
  foreach(source IN LISTS plugin_sources)
    if(source MATCHES "flutter_video_renderer.cc$")
      # CMake plugin SOURCES can be relative to its own source directory.
      get_target_property(plugin_dir flutter_webrtc_plugin SOURCE_DIR)
      get_filename_component(renderer_path "${source}" ABSOLUTE BASE_DIR "${plugin_dir}")
      file(SHA256 "${renderer_path}" renderer_digest)
      if(NOT renderer_digest STREQUAL "c4edbd4ec7c692ceb4f5a0b02f2dc2fe253d8a3a3a91fa79a3d8184026712ab6")
        message(FATAL_ERROR "WebRTC renderer changed; review Localist virtual camera integration before building")
      endif()
      file(READ "${renderer_path}" renderer)
      string(PREPEND renderer "#include \"webrtc_virtual_camera.h\"\n")
      string(REPLACE "void FlutterVideoRenderer::OnFrame(scoped_refptr<RTCVideoFrame> frame) {"
        "void FlutterVideoRenderer::OnFrame(scoped_refptr<RTCVideoFrame> frame) {\n  LocalistVirtualCameraFrame(texture_id_, frame);" renderer "${renderer}")
      string(REPLACE "void FlutterVideoRenderer::Dispose() {"
        "void FlutterVideoRenderer::Dispose() {\n  LocalistVirtualCameraRelease(texture_id_);" renderer "${renderer}")
      file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/flutter_video_renderer.cc" "${renderer}")
      list(REMOVE_ITEM plugin_sources "${source}")
      set(renderer_found TRUE)
    elseif(source MATCHES "flutter_peerconnection.cc$")
      get_target_property(plugin_dir flutter_webrtc_plugin SOURCE_DIR)
      get_filename_component(peer_path "${source}" ABSOLUTE BASE_DIR "${plugin_dir}")
      file(SHA256 "${peer_path}" peer_digest)
      if(NOT peer_digest STREQUAL "f83b9a2b91bbb7041f8bd63fc726bc6ca33e0d4665e3dc24ccdbf7484f40ff33")
        message(FATAL_ERROR "WebRTC peer observer changed; review unified-plan stream registration")
      endif()
      file(READ "${peer_path}" peer)
      # Unified Plan can emit OnTrack without the legacy OnAddStream callback.
      # Register its streams before notifying Dart or native renderer lookup
      # silently fails while RTP continues decoding successfully.
      string(REPLACE
        "for (scoped_refptr<RTCMediaStream> item : streams.std_vector()) {\n    streams_info.push_back"
        "for (scoped_refptr<RTCMediaStream> item : streams.std_vector()) {\n    remote_streams_[item->id().std_string()] = item;\n    streams_info.push_back"
        patched_peer "${peer}")
      if(patched_peer STREQUAL peer)
        message(FATAL_ERROR "WebRTC unified-plan stream patch did not apply")
      endif()
      file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/flutter_peerconnection.cc" "${patched_peer}")
      list(REMOVE_ITEM plugin_sources "${source}")
      set(peer_found TRUE)
    endif()
  endforeach()
  if(NOT renderer_found OR NOT peer_found)
    message(FATAL_ERROR "WebRTC renderer or peer observer source missing")
  endif()
  set_property(TARGET flutter_webrtc_plugin PROPERTY SOURCES "${plugin_sources}")
  target_sources(flutter_webrtc_plugin PRIVATE "${CMAKE_CURRENT_BINARY_DIR}/flutter_video_renderer.cc" "${CMAKE_CURRENT_BINARY_DIR}/flutter_peerconnection.cc" webrtc_virtual_camera.cpp ${VC_COMMON})
  set_source_files_properties(${VC_COMMON} PROPERTIES COMPILE_OPTIONS /W0)
  target_include_directories(flutter_webrtc_plugin PRIVATE ${VC_INCLUDES})
  add_dependencies(${BINARY_NAME} LocalistVirtualCamera LocalistVirtualCamera2 LocalistVirtualCamera3 LocalistVirtualCamera4)
  install(TARGETS LocalistVirtualCamera LocalistVirtualCamera2 LocalistVirtualCamera3 LocalistVirtualCamera4 RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}" COMPONENT Runtime)
  install(DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/../../third_party/virtual_camera/"
    DESTINATION "${CMAKE_INSTALL_PREFIX}/data/licenses/LocalistCamera/reference-source" COMPONENT Runtime)
  install(DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/"
    DESTINATION "${CMAKE_INSTALL_PREFIX}/data/licenses/LocalistCamera/localist-source" COMPONENT Runtime)
endif()
