// Engine-only build. Lets CI (or any machine without the Android SDK) compile and test
// the domain layer with:
//     gradle -c settings-core.gradle.kts :core:test
pluginManagement {
    repositories {
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories { mavenCentral() }
}

rootProject.name = "FactWarehouse"
include(":core")
