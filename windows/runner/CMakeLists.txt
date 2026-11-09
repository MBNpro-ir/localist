cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)
option(LOCALIST_CAPTURE_QA_RUNNER "Build a hidden isolated receive acceptance host" OFF)
set(LOCALIST_EXECUTION_LEVEL "requireAdministrator")
if(LOCALIST_CAPTURE_QA_RUNNER)
  set(LOCALIST_EXECUTION_LEVEL "asInvoker")
endif()

configure_file(
  "${CMAKE_CURRENT_SOURCE_DIR}/runner.exe.manifest.in"
  "${CMAKE_CURRENT_BINARY_DIR}/runner.exe.manifest"
  @ONLY
)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "main.cpp"
  "embedded_remote.cpp"
  "remote_host_process.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "windows_native_bridge.cpp"
  "elevated_startup.cpp"
  "virtual_devices.cpp"
  "virtual_audio_driver.cpp"
  "../virtual_audio/cable_output.cpp"
  "capture_capabilities.cpp"
  "../virtual_camera/capture_controls_bus.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "${CMAKE_CURRENT_BINARY_DIR}/runner.exe.manifest"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# The logon task starts the admin manifest without prompting at every sign-in.
set_target_properties(${BINARY_NAME} PROPERTIES
  VS_GLOBAL_UACExecutionLevel "${LOCALIST_EXECUTION_LEVEL}"
  VS_GLOBAL_UACUIAccess "false"
)
target_link_options(${BINARY_NAME} PRIVATE
  "/MANIFESTUAC:level='${LOCALIST_EXECUTION_LEVEL}' uiAccess='false'"
)
if(LOCALIST_CAPTURE_QA_RUNNER)
  target_compile_definitions(${BINARY_NAME} PRIVATE LOCALIST_CAPTURE_QA_RUNNER=1 LOCALIST_CAMERA_TEST_IDENTITY=1)
endif()

# Add preprocessor definitions for the build version.
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")
target_compile_definitions(${BINARY_NAME} PRIVATE "LOCALIST_CAMERA_VERSION=L\"${FLUTTER_VERSION_MAJOR}.${FLUTTER_VERSION_MINOR}.${FLUTTER_VERSION_PATCH}.${FLUTTER_VERSION_BUILD}\"")

# Disable Windows macros that collide with C++ standard library functions.
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

# Add dependency libraries and include directories. Add any application-specific
# dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib" "winmm.lib")
target_link_libraries(${BINARY_NAME} PRIVATE "wlanapi.lib")
target_link_libraries(${BINARY_NAME} PRIVATE "taskschd.lib" "comsuppw.lib")
target_link_libraries(${BINARY_NAME} PRIVATE "wintrust.lib" "bcrypt.lib")
target_link_libraries(${BINARY_NAME} PRIVATE setupapi newdev crypt32)
target_link_libraries(${BINARY_NAME} PRIVATE avrt)
target_link_libraries(${BINARY_NAME} PRIVATE strmiids oleaut32)
target_link_libraries(${BINARY_NAME} PRIVATE "windowscodecs.lib")
target_link_libraries(${BINARY_NAME} PRIVATE "comdlg32.lib" "wininet.lib" "mf.lib" "mfplat.lib" "mfuuid.lib")
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)
add_executable(localist_resource_tool "remove_remote_icon.cpp")
apply_standard_settings(localist_resource_tool)
target_compile_definitions(localist_resource_tool PRIVATE "NOMINMAX")
set_target_properties(localist_resource_tool PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/build-tools")
add_dependencies(${BINARY_NAME} localist_resource_tool)
add_executable(localist_windows_integration_probe EXCLUDE_FROM_ALL
  "${CMAKE_CURRENT_SOURCE_DIR}/../../tools/windows_integration_probe.cpp" "elevated_startup.cpp")
apply_standard_settings(localist_windows_integration_probe)
target_include_directories(localist_windows_integration_probe PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}")
target_compile_definitions(localist_windows_integration_probe PRIVATE NOMINMAX)
target_link_libraries(localist_windows_integration_probe PRIVATE taskschd comsuppw advapi32 ole32 oleaut32)
set_target_properties(localist_windows_integration_probe PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/integration-qa")
add_custom_command(TARGET ${BINARY_NAME} POST_BUILD
  COMMAND "${CMAKE_COMMAND}"
    "-DOUTPUT=$<TARGET_FILE_DIR:${BINARY_NAME}>"
    "-DREMOTE_RUNTIME=${CMAKE_SOURCE_DIR}/../third_party/localist_remote/windows/runtime"
    "-DREMOTE_PACKAGE=${CMAKE_SOURCE_DIR}/../third_party/localist_remote"
    "-DAPP_EXE=$<TARGET_FILE:${BINARY_NAME}>"
    "-DRESOURCE_TOOL=$<TARGET_FILE:localist_resource_tool>"
    -P "${CMAKE_CURRENT_SOURCE_DIR}/copy_debug_remote.cmake"
  VERBATIM
)
add_custom_command(TARGET ${BINARY_NAME} POST_BUILD
  COMMAND "${CMAKE_COMMAND}" -E copy_if_different
    "$<TARGET_FILE:${LOCALIST_UPDATER_BINARY_NAME}>"
    "$<TARGET_FILE_DIR:${BINARY_NAME}>/$<TARGET_FILE_NAME:${LOCALIST_UPDATER_BINARY_NAME}>"
  VERBATIM
)
