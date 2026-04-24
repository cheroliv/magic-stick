plugins {
    alias(libs.plugins.bakery)
    kotlin("jvm") version "2.1.20"
}

repositories {
    mavenCentral()
}

bakery { configPath = file("site.yml").absolutePath }

kotlin {
    jvmToolchain(17)
}

dependencies {
    testImplementation(libs.playwright)
    testImplementation("org.junit.jupiter:junit-jupiter:5.12.2")
    testRuntimeOnly("org.junit.platform:junit-platform-launcher")
}

tasks {
    named("test", Test::class) {
        useJUnitPlatform()
        environment("BAKE_DIR", file("build/bake").absolutePath)
    }
}

tasks.register("a11yAudit") {
    group = "verification"
    description = "Run accessibility audit on the baked site using Playwright + axe-core"
    dependsOn("bake")
    finalizedBy("test")
}