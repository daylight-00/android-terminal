cmake_minimum_required(VERSION 3.22.1)
project(shellbridge LANGUAGES C)

if(NOT ANDROID_ABI STREQUAL "arm64-v8a")
    message(FATAL_ERROR "Only arm64-v8a is supported")
endif()

add_library(shellbridge SHARED shell_bridge.c)

target_compile_features(shellbridge PRIVATE c_std_11)
target_compile_definitions(shellbridge PRIVATE _FILE_OFFSET_BITS=64)
target_compile_options(shellbridge PRIVATE
    -Wall
    -Wextra
    -Werror
    -Wconversion
    -Wformat=2
    -Wshadow
    -Wstrict-prototypes
    -Wno-unused-parameter
    -fvisibility=hidden
    -fstack-protector-strong
    -ffunction-sections
    -fdata-sections
)
target_link_options(shellbridge PRIVATE
    -Wl,--gc-sections
    -Wl,-z,relro
    -Wl,-z,now
    -Wl,--no-undefined
)
