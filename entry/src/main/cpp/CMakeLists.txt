cmake_minimum_required(VERSION 3.5.0)
project(wplayerbackground)

set(RENDERER_ROOT ${CMAKE_CURRENT_SOURCE_DIR})

if(DEFINED PACKAGE_FIND_FILE)
    include(${PACKAGE_FIND_FILE})
endif()

add_library(wplayerbackground SHARED
    apple_music_renderer.cpp
    plugin_manager.cpp
    napi_init.cpp
)

target_include_directories(wplayerbackground PUBLIC ${RENDERER_ROOT})
target_compile_features(wplayerbackground PUBLIC cxx_std_17)

find_library(EGL_LIB EGL)
find_library(GLES_LIB GLESv3)
find_library(HILOG_LIB hilog_ndk.z)
find_library(ACE_LIB ace_ndk.z)
find_library(NAPI_LIB ace_napi.z)

target_link_libraries(wplayerbackground PUBLIC
    ${EGL_LIB}
    ${GLES_LIB}
    ${HILOG_LIB}
    ${ACE_LIB}
    ${NAPI_LIB}
    libnative_window.so
)
