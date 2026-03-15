# Flutter wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Google Play Core (for deferred components)
-dontwarn io.flutter.embedding.engine.deferredcomponents.**
-keep class io.flutter.embedding.engine.deferredcomponents.** { *; }
-dontwarn com.google.android.play.**
-keep class com.google.android.play.** { *; }

# Speech to Text
-keep class com.csdn.plugin.speech.** { *; }
-keep class io.flutter.plugins.speechtotext.** { *; }
-dontwarn io.flutter.plugins.speechtotext.**

# Permission Handler
-keep class com.baseflow.permissionhandler.** { *; }
-dontwarn com.baseflow.permissionhandler.**

# Image Picker
-keep class io.flutter.plugins.imagepicker.** { *; }
-dontwarn io.flutter.plugins.imagepicker.**

# File Picker
-keep class com.flutter.plugins.filepicker.** { *; }
-dontwarn com.flutter.plugins.filepicker.**

# Emoji Picker
-keep class flutter.emoji_picker.** { *; }
-dontwarn flutter.emoji_picker.**

# Provider
-keep class provider.** { *; }
-dontwarn provider.**

# Gson (for JSON serialization)
-keepattributes Signature
-keepattributes *Annotation*
-dontwarn sun.misc.**
-keep class * implements com.google.gson.TypeAdapter
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer

# Keep native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Keep enumerations
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# Prevent R8 from leaving Data object members always null
-keepclassmembers,allowobfuscation class * {
  @com.google.gson.annotations.SerializedName <fields>;
  <fields>;
}

# Keep serialized name
-keepattributes *Annotation*
-keepclassmembers class * {
  @com.google.gson.annotations.SerializedName <fields>;
}

# Don't obfuscate JSON model classes
-keep class com.example.** { *; }
-keep class **_Json { *; }
