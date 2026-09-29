allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Force plugin subprojects to compileSdk 36 (fixes checkDebugAarMetadata)
val minCompileSdk = 36
plugins.withId("com.android.library") {
    extensions.findByName("android")
        ?.let { it as? com.android.build.gradle.LibraryExtension }
        ?.let { ext ->
            val current = ext.compileSdk?.toIntOrNull() ?: 0
            if (current < minCompileSdk) {
                ext.compileSdk = minCompileSdk
            }
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
