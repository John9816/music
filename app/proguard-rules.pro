# Add project specific ProGuard rules here.
# Keep data models and auth / music-library payloads that Gson reflects on.
# Release minify renames fields unless kept — broken JSON breaks favorites, playlists, login.
-keep class com.music.player.data.model.** { *; }
-keep class com.music.player.data.auth.** { *; }
-keepclassmembers class com.music.player.data.auth.** { <fields>; }

# Retrofit
-keepattributes Signature, InnerClasses, EnclosingMethod
-keepattributes RuntimeVisibleAnnotations, RuntimeVisibleParameterAnnotations
-keepattributes AnnotationDefault
-keepattributes Exceptions
-dontwarn retrofit2.**
-keep class retrofit2.** { *; }
-keepclasseswithmembers class * {
    @retrofit2.http.* <methods>;
}
-keepclassmembers,allowshrinking,allowobfuscation interface * {
    @retrofit2.http.* <methods>;
}
-if interface * { @retrofit2.http.* <methods>; }
-keep,allowobfuscation interface <1>
-if interface * { @retrofit2.http.* <methods>; }
-keep,allowobfuscation interface * extends <1>
-keep,allowoptimization,allowshrinking,allowobfuscation class kotlin.coroutines.Continuation
-if interface * { @retrofit2.http.* public *** *(...); }
-keep,allowoptimization,allowshrinking,allowobfuscation class <3>
-keep,allowoptimization,allowshrinking,allowobfuscation class retrofit2.Response

# OkHttp
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn javax.annotation.**
-keepnames class okhttp3.internal.publicsuffix.PublicSuffixDatabase

# Gson
-keepattributes EnclosingMethod
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer
-keepclassmembers,allowobfuscation class * {
  @com.google.gson.annotations.SerializedName <fields>;
}

# Playback session snapshot (Gson reflected fields — must survive R8)
-keep class com.music.player.playback.PlaybackStateStore { *; }
-keep class com.music.player.playback.PlaybackStateStore$* { *; }

# Library disk cache (favorites / history / playlists)
-keep class com.music.player.data.repository.LibraryDiskCache { *; }
-keep class com.music.player.data.repository.LibraryDiskCache$* { *; }

# Glide
-keep public class * implements com.bumptech.glide.module.GlideModule
-keep class * extends com.bumptech.glide.module.AppGlideModule {
 <init>(...);
}
-keep public enum com.bumptech.glide.load.ImageHeaderParser$** {
  **[] $VALUES;
  public *;
}
-keep class com.bumptech.glide.load.data.ParcelFileDescriptorRewinder$InternalRewinder {
  *** rewind();
}

# Coroutines
-keepnames class kotlinx.coroutines.internal.MainDispatcherFactory {}
-keepnames class kotlinx.coroutines.CoroutineExceptionHandler {}
-keepclassmembernames class kotlinx.** {
    volatile <fields>;
}

# ExoPlayer / Media3
-dontwarn androidx.media3.**

# Keep R8 from stripping interface annotations used by ViewBinding

# Keep enum classes
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}
