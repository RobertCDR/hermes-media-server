# Keep Hermes entrypoints and Flutter plugin JNI/reflection targets intact under R8.
-keep class dev.hermes.hermes_client.** { *; }

-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugins.** { *; }

# audio_service / AndroidX Media session and notification components
-keep class com.ryanheise.audioservice.** { *; }
-keep class androidx.media.** { *; }
-keep class androidx.media3.** { *; }

# media_kit native JNI / libmpv bindings
-keep class com.alexmercerind.media_kit** { *; }
-keep class com.alexmercerind.mediakit** { *; }
-keepclassmembers class com.alexmercerind.** { *; }

# Flutter Play Store deferred-components optional references when Play Core isn't bundled
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**
