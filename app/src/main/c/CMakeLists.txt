cmake_minimum_required(VERSION 3.22)
project(android_terminal_shellbridge LANGUAGES C)

add_library(shellbridge SHARED
    shell_bridge.c
    session_environment.c
)
set_target_properties(shellbridge PROPERTIES
    C_STANDARD 11
    C_STANDARD_REQUIRED YES
    C_EXTENSIONS NO
    C_VISIBILITY_PRESET hidden
    VISIBILITY_INLINES_HIDDEN YES
    OUTPUT_NAME shellbridge
)

target_compile_options(shellbridge PRIVATE
    -Wall
    -Wextra
    -Werror
    -Wconversion
    -Wformat=2
    -Wshadow
    -Wstrict-prototypes
    -Wno-unused-parameter
    -fstack-protector-strong
    -ffunction-sections
    -fdata-sections
)

target_link_options(shellbridge PRIVATE
    -Wl,--gc-sections
    -Wl,-z,relro
    -Wl,-z,now
    -Wl,--no-undefined
    -Wl,-soname,libshellbridge.so
)
