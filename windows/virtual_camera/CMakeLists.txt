cmake_minimum_required(VERSION 3.18)
project(localist_virtual_camera LANGUAGES C CXX)
if(TARGET flutter_webrtc_plugin)
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
string(REPLACE "#define VIDEO_NAME L\"OBSVirtualCamVideo\"" "#include \"camera_namespace.h\"" queue "${queue}")
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/shared-memory-queue.c" "${queue}")

set(VC_COMMON "${CMAKE_CURRENT_BINARY_DIR}/shared-memory-queue.c" "${VC_SCALE}/tiny-nv12-scale.c")
set(VC_INCLUDES "${CMAKE_CURRENT_BINARY_DIR}" "${CMAKE_CURRENT_SOURCE_DIR}" "${VC_MODULE}" "${VC_DSHOW}" "${VC_DSHOW}/source" "${VC_SCALE}" "${VC_QUEUE}" "${VC_SOURCE}/libobs")
add_library(LocalistVirtualCamera SHARED
  "${CMAKE_CURRENT_BINARY_DIR}/virtualcam-module.cpp"
  "${CMAKE_CURRENT_BINARY_DIR}/virtualcam-filter.cpp"
  "${VC_MODULE}/sleepto.c" placeholder.cpp dshow_errors.cpp camera.def capture_controls.cpp capture_controls_bus.cpp
  "${CMAKE_CURRENT_BINARY_DIR}/output-filter.cpp"
  "${VC_DSHOW}/source/dshow-formats.cpp"
  "${VC_DSHOW}/source/dshow-media-type.cpp"
  "${VC_DSHOW}/source/log.cpp"
  ${VC_COMMON})
target_include_directories(LocalistVirtualCamera PRIVATE ${VC_INCLUDES})
target_compile_features(LocalistVirtualCamera PRIVATE cxx_std_17)
target_compile_definitions(LocalistVirtualCamera PRIVATE UNICODE _UNICODE _CRT_SECURE_NO_WARNINGS NOMINMAX)
target_compile_options(LocalistVirtualCamera PRIVATE /wd4005 /wd4018)
set_property(TARGET LocalistVirtualCamera PROPERTY MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
target_link_libraries(LocalistVirtualCamera PRIVATE strmiids ole32 oleaut32 advapi32 shell32 winmm)
if(CMAKE_SIZEOF_VOID_P EQUAL 8)
  set_target_properties(LocalistVirtualCamera PROPERTIES OUTPUT_NAME "LocalistCamera64${VC_SUFFIX}")
else()
  set_target_properties(LocalistVirtualCamera PROPERTIES OUTPUT_NAME "LocalistCamera32${VC_SUFFIX}")
endif()

option(LOCALIST_CAMERA_QA "Build the isolated camera probe" OFF)
if(LOCALIST_CAMERA_QA)
  add_executable(localist_camera_probe camera_probe.cpp webrtc_virtual_camera.cpp capture_controls_bus.cpp ${VC_COMMON})
  target_include_directories(localist_camera_probe PRIVATE ${VC_INCLUDES} "${LOCALIST_WEBRTC_DIR}/include")
  target_compile_features(localist_camera_probe PRIVATE cxx_std_17)
  target_compile_definitions(localist_camera_probe PRIVATE UNICODE _UNICODE NOMINMAX LIB_WEBRTC_API_DLL)
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
    BUILD_COMMAND "${CMAKE_COMMAND}" --build <BINARY_DIR> --config Release --target LocalistVirtualCamera
    INSTALL_COMMAND ""
    BUILD_ALWAYS TRUE)
  add_dependencies(${BINARY_NAME} localist_camera_x86)
  install(FILES "${CMAKE_BINARY_DIR}/camera-x86/Release/LocalistCamera32${VC_SUFFIX}.dll"
    DESTINATION "${CMAKE_INSTALL_PREFIX}" COMPONENT Runtime)
  get_target_property(plugin_sources flutter_webrtc_plugin SOURCES)
  set(renderer_found FALSE)
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
    endif()
  endforeach()
  if(NOT renderer_found)
    message(FATAL_ERROR "WebRTC renderer source missing")
  endif()
  set_property(TARGET flutter_webrtc_plugin PROPERTY SOURCES "${plugin_sources}")
  target_sources(flutter_webrtc_plugin PRIVATE "${CMAKE_CURRENT_BINARY_DIR}/flutter_video_renderer.cc" webrtc_virtual_camera.cpp ${VC_COMMON})
  set_source_files_properties(${VC_COMMON} PROPERTIES COMPILE_OPTIONS /W0)
  target_include_directories(flutter_webrtc_plugin PRIVATE ${VC_INCLUDES})
  add_dependencies(${BINARY_NAME} LocalistVirtualCamera)
  install(TARGETS LocalistVirtualCamera RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}" COMPONENT Runtime)
  install(DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/../../third_party/virtual_camera/"
    DESTINATION "${CMAKE_INSTALL_PREFIX}/data/licenses/LocalistCamera/reference-source" COMPONENT Runtime)
  install(DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/"
    DESTINATION "${CMAKE_INSTALL_PREFIX}/data/licenses/LocalistCamera/localist-source" COMPONENT Runtime)
endif()
