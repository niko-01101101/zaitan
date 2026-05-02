cmake_minimum_required(VERSION 3.20)
project(Zaitan)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_OSX_ARCHITECTURES "x86_64;arm64")

enable_language(OBJCXX)

set(SOURCES
    app/main.mm
    app/AppDelegate.mm
    platform/WindowController.mm
    platform/DebugOverlay.mm
    input/Hotkeys.mm
    src/Desktop.cpp
)

add_executable(Zaitan MACOSX_BUNDLE ${SOURCES})

set_target_properties(Zaitan PROPERTIES
    MACOSX_BUNDLE_INFO_PLIST ${CMAKE_SOURCE_DIR}/app/Info.plist
)

target_include_directories(Zaitan PRIVATE src)

if(CMAKE_BUILD_TYPE STREQUAL "Debug")
  target_compile_definitions(Zaitan PRIVATE DEBUG)
endif()

target_link_libraries(Zaitan
    "-framework AppKit"
    "-framework ApplicationServices"
    "-framework Carbon"
)

# Strip extended attributes then ad-hoc sign
add_custom_command(TARGET Zaitan POST_BUILD
    COMMAND xattr -cr $<TARGET_BUNDLE_DIR:Zaitan>
    COMMAND codesign --force --deep --sign - $<TARGET_BUNDLE_DIR:Zaitan>
)
