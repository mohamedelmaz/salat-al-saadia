allprojects {
    repositories {
        google()
        mavenCentral()
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

// NOTE: an earlier revision of this file ended with a `subprojects { afterEvaluate {
// hasProperty("android") -> android { compileSdk = 34 } } }` block, added to force
// every plugin to compileSdk 34. It was removed because:
//
//  1. It does not compile. `hasProperty(...)` and the `android { }` accessor are
//     Groovy DSL; in Kotlin DSL neither is available on a `Project`, so the whole
//     build script fails to compile with "Unresolved reference 'android'" /
//     "'compileSdk'" before any task runs.
//  2. It was not needed. The app uses `compileSdk = flutter.compileSdkVersion`
//     (36 on this toolchain), and the two locally patched plugins
//     (../flutter_qiblah_local, ../flutter_compass_v2_local) already declare
//     `compileSdk 36` in their own build files — see BUILD_NOTES.md.
//  3. Forcing 34 would have been actively harmful: androidx AAR metadata written
//     for compileSdk 35+ refuses to link against a 34 compileSdk, so the build
//     would have failed again with a less obvious error.
//
// If a future plugin ever does need a different compileSdk, change it in that
// plugin's own build file (that is what the local patched copies are for)
// rather than reaching for a global `afterEvaluate` override here.
