# ClipSync ProGuard / R8 Rules for Release Builds

# Flutter Framework & Native Wrappers
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.**  { *; }

# SQLite3 & Native Database Libraries
-keep class org.sqlite.** { *; }
-keep class com.simonhmartin.sqlite3_flutter_libs.** { *; }

# Drift Database Framework
-keep class * extends androidx.room.RoomDatabase
-dontwarn androidx.room.paging.**

# Flutter Foreground Task Service
-keep class com.pravera.flutter_foreground_task.** { *; }
-keep class com.pravera.flutter_foreground_task.service.** { *; }

# Receive Sharing Intent Plugin
-keep class com.kasem.receive_sharing_intent.** { *; }

# Local Notifications Plugin
-keep class com.dexterous.flutterlocalnotifications.** { *; }

# Mobile Scanner (Camera / MLKit)
-keep class com.google.mlkit.** { *; }
-keep class androidx.camera.** { *; }

# Kotlin Reflection & Coroutines
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod
-dontwarn kotlin.**
-dontwarn kotlinx.coroutines.**
