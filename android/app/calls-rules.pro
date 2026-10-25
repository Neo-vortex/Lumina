# The calls engine (liblumina_calls.so) finds these classes, fields and
# methods by name through JNI.
-keep class dev.lumina.calls.NativeCall { *; }
-keep class dev.lumina.calls.NativeCall$* { *; }
-keep class org.webrtc.** { *; }
-keep class org.telegram.messenger.voip.VideoCapturerDevice { *; }
-dontwarn org.webrtc.**

# WorkManager (battery-saver sync) creates its Room database and the
# workers by reflection; R8 in AGP 9 full mode stripped the constructors
# (crash at startup: NoSuchMethodException WorkDatabase_Impl.<init>).
-keep class * extends androidx.room.RoomDatabase { <init>(); }
-keep class androidx.work.impl.WorkDatabase_Impl { *; }
-keep class * extends androidx.work.ListenableWorker {
    public <init>(android.content.Context, androidx.work.WorkerParameters);
}
