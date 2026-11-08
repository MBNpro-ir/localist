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
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/virtualcam-module.cpp" "${module}")
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
string(REPLACE "if (!video_queue_read(vq, &scaler, ptr, &temp)) {"
  "if (!video_queue_read(vq, &scaler, ptr, &temp)) {\n\t\tShowDefaultFrame(ptr);" filter "${filter}")
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/virtualcam-filter.cpp" "${filter}")
file(READ "${VC_QUEUE}/shared-memory-queue.c" queue)
string(REPLACE "#define VIDEO_NAME L\"OBSVirtualCamVideo\"" "#include \"camera_namespace.h\"" queue "${queue}")
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/shared-memory-queue.c" "${queue}")

set(VC_COMMON "${CMAKE_CURRENT_BINARY_DIR}/shared-memory-queue.c" "${VC_SCALE}/tiny-nv12-scale.c")
set(VC_INCLUDES "${CMAKE_CURRENT_SOURCE_DIR}" "${VC_MODULE}" "${VC_DSHOW}" "${VC_SCALE}" "${VC_QUEUE}" "${VC_SOURCE}/libobs")
add_library(LocalistVirtualCamera SHARED
  "${CMAKE_CURRENT_BINARY_DIR}/virtualcam-module.cpp"
  "${CMAKE_CURRENT_BINARY_DIR}/virtualcam-filter.cpp"
  "${VC_MODULE}/sleepto.c" placeholder.cpp dshow_errors.cpp camera.def
  "${VC_DSHOW}/source/output-filter.cpp"
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
  add_executable(localist_camera_probe camera_probe.cpp webrtc_virtual_camera.cpp ${VC_COMMON})
  target_include_directories(localist_camera_probe PRIVATE ${VC_INCLUDES} "${LOCALIST_WEBRTC_DIR}/include")
  target_compile_features(localist_camera_probe PRIVATE cxx_std_17)
  target_compile_definitions(localist_camera_probe PRIVATE UNICODE _UNICODE NOMINMAX LIB_WEBRTC_API_DLL)
  target_link_libraries(localist_camera_probe PRIVATE "${LOCALIST_WEBRTC_DIR}/lib/libwebrtc.dll.lib" advapi32 ole32)
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
