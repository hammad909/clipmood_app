############################################
# ClipMood release optimization rules
############################################

# WorkManager's Room implementation is instantiated through reflection.
-keep class androidx.work.impl.WorkDatabase_Impl {
    <init>();
}

# ML Kit component registrars are instantiated through reflection.
-keep class com.google.mlkit.vision.face.internal.FaceRegistrar {
    <init>();
}

-keep class com.google.mlkit.common.internal.CommonComponentRegistrar {
    <init>();
}

-keep class com.google.mlkit.vision.common.internal.VisionCommonRegistrar {
    <init>();
}

# Preserve constructors for future ML Kit/Firebase component registrars.
-keep class * implements com.google.firebase.components.ComponentRegistrar {
    <init>();
}