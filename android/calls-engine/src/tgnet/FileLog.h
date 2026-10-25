// Lumina stand-in for Telegram-Android's tgnet/FileLog.h: a few vendored
// WebRTC files log through these macros. They go to logcat (tag
// "LuminaCalls"); REF/DELREF are JNI reference tracing, dropped.
// GPL-3.0-or-later, see docs/DECISIONS.md D14.
#ifndef LUMINA_TGNET_FILELOG_H
#define LUMINA_TGNET_FILELOG_H

#include <android/log.h>

#define DEBUG_FATAL(...) __android_log_print(ANDROID_LOG_FATAL, "LuminaCalls", __VA_ARGS__)
#define DEBUG_E(...) __android_log_print(ANDROID_LOG_ERROR, "LuminaCalls", __VA_ARGS__)
#define DEBUG_W(...) __android_log_print(ANDROID_LOG_WARN, "LuminaCalls", __VA_ARGS__)
#define DEBUG_D(...) __android_log_print(ANDROID_LOG_DEBUG, "LuminaCalls", __VA_ARGS__)
#define DEBUG_REF(...) ((void) 0)
#define DEBUG_DELREF(...) ((void) 0)

#endif
