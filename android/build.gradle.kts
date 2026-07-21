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

// 统一所有子项目（Flutter 插件）的 JVM 字节码版本为 17，
// 解决 Kotlin 2.1.0 默认 jvmTarget=21 与 app compileOptions = 17 冲突，
// 以及老插件（如 app_settings/audioplayers_android/home_widget）默认 Java 1.8 冲突。
// 触发原因：photo_manager 3.10.0 等新插件在 Kotlin 2.1.0 下默认产出 JVM 21 字节码，
// 老插件反过来默认 1.8，统一锁 17 才能与 host 项目（JavaVersion.VERSION_17）保持一致。
// 跳过 :app（自身已正确配置 17）；插件项目用 afterEvaluate 在 Android 插件配置完成后覆盖。
subprojects {
    if (project.name != "app") {
        afterEvaluate {
            plugins.withId("com.android.library") {
                extensions.findByType(com.android.build.gradle.LibraryExtension::class.java)?.apply {
                    compileOptions {
                        sourceCompatibility = JavaVersion.VERSION_17
                        targetCompatibility = JavaVersion.VERSION_17
                    }
                }
            }
            plugins.withId("org.jetbrains.kotlin.android") {
                tasks.withType(org.jetbrains.kotlin.gradle.tasks.KotlinCompile::class.java).configureEach {
                    compilerOptions {
                        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
                    }
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
