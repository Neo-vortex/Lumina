# The calls engine (liblumina_calls.so) finds these classes, fields and
# methods by name through JNI.
-keep class dev.lumina.calls.NativeCall { *; }
-keep class dev.lumina.calls.NativeCall$* { *; }
-keep class org.webrtc.** { *; }
-keep class org.telegram.messenger.voip.VideoCapturerDevice { *; }
-dontwarn org.webrtc.**
