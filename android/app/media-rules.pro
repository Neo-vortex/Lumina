# libVLC's native side (libvlcjni.so) finds these classes, fields and methods
# by name in JNI_OnLoad. R8 renamed them, so loading failed and opening a
# video crashed the release build.
-keep class org.videolan.libvlc.** { *; }
-dontwarn org.videolan.libvlc.**
