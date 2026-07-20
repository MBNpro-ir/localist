set(LOCALIST_UPDATER_BINARY_NAME "LocalistUpdater")

add_executable(${LOCALIST_UPDATER_BINARY_NAME} WIN32
  "main.cpp"
)

apply_standard_settings(${LOCALIST_UPDATER_BINARY_NAME})
target_compile_definitions(${LOCALIST_UPDATER_BINARY_NAME} PRIVATE "NOMINMAX")
target_link_libraries(${LOCALIST_UPDATER_BINARY_NAME} PRIVATE "shell32.lib")
