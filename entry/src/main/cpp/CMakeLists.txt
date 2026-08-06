cmake_minimum_required(VERSION 3.5.0)
project(wplayerbackground)

set(RENDERER_ROOT ${CMAKE_CURRENT_SOURCE_DIR})

if(DEFINED PACKAGE_FIND_FILE)
    include(${PACKAGE_FIND_FILE})
endif()

set(WEBP_BUILD_ANIM_UTILS OFF CACHE BOOL "" FORCE)
set(WEBP_BUILD_CWEBP OFF CACHE BOOL "" FORCE)
set(WEBP_BUILD_DWEBP OFF CACHE BOOL "" FORCE)
set(WEBP_BUILD_GIF2WEBP OFF CACHE BOOL "" FORCE)
set(WEBP_BUILD_IMG2WEBP OFF CACHE BOOL "" FORCE)
set(WEBP_BUILD_VWEBP OFF CACHE BOOL "" FORCE)
set(WEBP_BUILD_WEBPINFO OFF CACHE BOOL "" FORCE)
set(WEBP_BUILD_LIBWEBPMUX OFF CACHE BOOL "" FORCE)
set(WEBP_BUILD_WEBPMUX OFF CACHE BOOL "" FORCE)
set(WEBP_BUILD_EXTRAS OFF CACHE BOOL "" FORCE)
set(WEBP_USE_THREAD OFF CACHE BOOL "" FORCE)
add_subdirectory(third_party/libwebp EXCLUDE_FROM_ALL)

add_library(wplayerbackground SHARED
    apple_music_renderer.cpp
    plugin_manager.cpp
    napi_init.cpp
)

add_library(wplayermedia SHARED
    artwork_webp_encoder.cpp
    media_parser.cpp
    media_napi.cpp
)

target_include_directories(wplayerbackground PUBLIC ${RENDERER_ROOT})
target_compile_features(wplayerbackground PUBLIC cxx_std_17)
target_compile_features(wplayermedia PUBLIC cxx_std_17)
target_compile_options(wplayermedia PRIVATE -Wall -Wextra)

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

target_link_libraries(wplayermedia PRIVATE
    ${NAPI_LIB}
    webp
)
