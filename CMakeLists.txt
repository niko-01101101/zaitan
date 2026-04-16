cmake_minimum_required(VERSION 3.20)
project(WindowManager)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_OSX_ARCHITECTURES "x86_64;arm64")

# Enable Objective-C++
enable_language(OBJCXX)

# Source files
set(SOURCES
    App/main.mm
    App/AppDelegate.mm

    Platform/WindowController.mm

    Input/Hotkeys.mm
)

# Create macOS app bundle
add_executable(WindowManager MACOSX_BUNDLE ${SOURCES})

# Link required macOS frameworks
target_link_libraries(WindowManager
    "-framework AppKit"
    "-framework ApplicationServices"
    "-framework Carbon"
)
