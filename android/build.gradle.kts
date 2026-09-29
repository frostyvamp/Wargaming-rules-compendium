allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Force plugin subprojects to compileSdk 36 (fixes checkDebugAarMetadata)
val minCompileSdk = 36
subprojects {
    afterEvaluate {
        val androidExt = extensions.findByName("android")
            as? com.android.build.gradle.BaseExtension ?: return@afterEvaluate
        val current = androidExt.compileSdkVersion?.replace("android-", "")?.toIntOrNull() ?: 0
        if (current < minCompileSdk) { androidExt.compileSdkVersion(minCompileSdk) }
    }
}
val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)


subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
