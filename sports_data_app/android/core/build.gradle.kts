import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    alias(libs.plugins.kotlin.jvm)
    application
}

application {
    // Headless smoke check for the engine: gradle -c settings-core.gradle.kts :core:run
    mainClass.set("com.factwarehouse.core.DemoKt")
}

java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}

kotlin {
    compilerOptions {
        // Targets 17 bytecode for the Android module without pinning the JDK that
        // builds it, so CI can verify the engine on whatever JDK 17+ it happens to have.
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

dependencies {
    testImplementation(libs.junit)
}

tasks.withType<Test>().configureEach {
    testLogging {
        events("passed", "failed", "skipped")
    }
}
