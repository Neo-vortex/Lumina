# liblumina_calls.so: tgcalls + WebRTC as Telegram-Android builds them, with
# Lumina's JNI glue. tool/fetch_calls_engine.sh copies this file into the
# root of Telegram's jni/ tree (its voip/CMakeLists.txt uses paths relative
# to that root); tool/build_calls_engine.sh configures and builds it.
# Adapted from TMessagesProj/jni/CMakeLists.txt (GPL v2 or later); Lumina is
# GPL-3.0-or-later (docs/DECISIONS.md D14).
cmake_minimum_required(VERSION 3.16)
project(lumina_calls C CXX ASM)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

set(CMAKE_CXX_FLAGS "-DANDROID -g")
set(CMAKE_C_FLAGS "-w -std=c11 -DANDROID -D_LARGEFILE_SOURCE=1 -g -Wno-error=implicit-function-declaration")
set(CMAKE_ASM_FLAGS "${CFLAGS} -x assembler-with-cpp")
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -ffunction-sections -fdata-sections -fvisibility=hidden")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -ffunction-sections -fdata-sections -fvisibility=hidden -fvisibility-inlines-hidden")
set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -Wl,--gc-sections -Wl,--icf=safe -Wl,-Bsymbolic")

set(CAN_COMPILE_SME FALSE CACHE INTERNAL "Disable libyuv SME" FORCE)
add_subdirectory(third_party/libyuv ${CMAKE_CURRENT_BINARY_DIR}/libyuv EXCLUDE_FROM_ALL)

set(ABSL_PROPAGATE_CXX_STD ON)
set(ABSL_BUILD_TESTING OFF)
set(ABSL_ENABLE_INSTALL OFF)
add_subdirectory(third_party/absl ${CMAKE_CURRENT_BINARY_DIR}/absl EXCLUDE_FROM_ALL)
add_library(webrtc_absl INTERFACE)
target_link_libraries(webrtc_absl INTERFACE
        absl::base absl::strings absl::str_format absl::cord absl::synchronization absl::time
        absl::status absl::statusor absl::hash absl::flat_hash_map absl::flat_hash_set absl::flags
        absl::flags_parse absl::random_random absl::random_distributions absl::crc32c absl::log
        absl::check)

# Telegram's prebuilt static libraries for this ABI.
foreach(lib avutil avformat avcodec swresample swscale crypto ssl vpx dav1d opus)
    add_library(prebuilt_${lib} STATIC IMPORTED)
    set_target_properties(prebuilt_${lib} PROPERTIES
            IMPORTED_LOCATION ${CMAKE_CURRENT_SOURCE_DIR}/prebuild/lib/${ANDROID_ABI}/lib${lib}.a)
endforeach()

# Defines rnnoise, openh264, wasm, tgcalls_tp, tgcalls and voipandroid.
include(${CMAKE_CURRENT_SOURCE_DIR}/voip/CMakeLists.txt)

# Telegram's JNI glue needs its app (tgnet, group calls, tde2e); ours
# replaces it.
get_target_property(VOIP_SOURCES voipandroid SOURCES)
list(FILTER VOIP_SOURCES EXCLUDE REGEX "org_telegram_messenger_voip_Instance\\.cpp$")
set_property(TARGET voipandroid PROPERTY SOURCES ${VOIP_SOURCES})

add_library(lumina_calls SHARED lumina/lumina_calls_jni.cpp)
target_compile_options(lumina_calls PRIVATE -Wall -fexceptions)
target_link_options(lumina_calls PRIVATE
        "-Wl,-z,max-page-size=16384"
        "-Wl,-z,common-page-size=16384"
        "-Wl,--version-script=${CMAKE_CURRENT_SOURCE_DIR}/lumina/exports.map")
target_link_libraries(lumina_calls
        # Whole archives: tgcalls registers protocol versions and WebRTC its
        # JNI entry points through static initialisers.
        -Wl,--whole-archive rnnoise openh264 voipandroid -Wl,--no-whole-archive
        webrtc_absl
        tgcalls
        wasm
        tgcalls_tp
        prebuilt_swscale
        prebuilt_avformat
        prebuilt_avcodec
        prebuilt_swresample
        prebuilt_vpx
        prebuilt_dav1d
        prebuilt_opus
        yuv
        prebuilt_avutil
        prebuilt_ssl
        prebuilt_crypto
        log
        z
        GLESv2
        EGL
        android
        OpenSLES
        cpufeatures)

include(AndroidNdkModules)
android_ndk_import_module_cpufeatures()
