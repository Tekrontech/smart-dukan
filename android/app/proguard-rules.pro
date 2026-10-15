# Flutter and plugins ship their own consumer rules; keep the app's channel code.
-keep class pk.smartdukan.smart_dukan.** { *; }
# ML Kit (mobile_scanner) optional classes
-dontwarn com.google.mlkit.**
-dontwarn com.google.android.gms.**
