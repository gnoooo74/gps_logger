"""
`flutter create .` 실행 후 자동 생성된 android/app/build.gradle(.kts)에
core library desugaring 설정을 주입하는 스크립트.

flutter_local_notifications(및 다른 일부 플러그인)는 Java 8+ API를 쓰기 때문에
Android Gradle Plugin이 "core library desugaring"을 켜달라고 요구한다.

Flutter 3.29부터 `flutter create`가 기본으로 build.gradle.kts(Kotlin DSL)를
생성하므로(그 이전엔 build.gradle/Groovy), 두 형식 모두 처리한다.
android/ 폴더가 매 빌드마다 새로 생성되므로, 이 설정도 매번 자동으로 넣어줘야 한다.
GitHub Actions 워크플로우에서 자동으로 실행된다.
"""
import re
import sys

KTS_PATH = "android/app/build.gradle.kts"
GROOVY_PATH = "android/app/build.gradle"

DESUGAR_LIB_VERSION = "2.1.4"


def patch_kts(path):
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()

    if "CoreLibraryDesugaringEnabled" in content:
        print(f"{path}: 이미 패치되어 있음, 건너뜀")
        return

    if re.search(r"compileOptions\s*\{", content):
        content = re.sub(
            r"(compileOptions\s*\{)",
            r"\1\n        isCoreLibraryDesugaringEnabled = true",
            content,
            count=1,
        )
    else:
        content = re.sub(
            r"(android\s*\{)",
            r"\1\n    compileOptions {\n"
            r"        isCoreLibraryDesugaringEnabled = true\n"
            r"        sourceCompatibility = JavaVersion.VERSION_1_8\n"
            r"        targetCompatibility = JavaVersion.VERSION_1_8\n"
            r"    }\n",
            content,
            count=1,
        )

    desugar_dep = f'    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:{DESUGAR_LIB_VERSION}")\n'

    if re.search(r"\ndependencies\s*\{", content):
        content = re.sub(
            r"(\ndependencies\s*\{)",
            r"\1\n" + desugar_dep.rstrip("\n"),
            content,
            count=1,
        )
    else:
        content += f"\ndependencies {{\n{desugar_dep}}}\n"

    with open(path, "w", encoding="utf-8") as f:
        f.write(content)

    print(f"{path}: 패치 완료 (core library desugaring 활성화, Kotlin DSL)")


def patch_groovy(path):
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()

    if "coreLibraryDesugaringEnabled" in content:
        print(f"{path}: 이미 패치되어 있음, 건너뜀")
        return

    if re.search(r"compileOptions\s*\{", content):
        content = re.sub(
            r"(compileOptions\s*\{)",
            r"\1\n        coreLibraryDesugaringEnabled true",
            content,
            count=1,
        )
    else:
        content = re.sub(
            r"(android\s*\{)",
            r"\1\n    compileOptions {\n"
            r"        coreLibraryDesugaringEnabled true\n"
            r"        sourceCompatibility JavaVersion.VERSION_1_8\n"
            r"        targetCompatibility JavaVersion.VERSION_1_8\n"
            r"    }\n",
            content,
            count=1,
        )

    desugar_dep = f'    coreLibraryDesugaring "com.android.tools:desugar_jdk_libs:{DESUGAR_LIB_VERSION}"\n'

    if re.search(r"\ndependencies\s*\{", content):
        content = re.sub(
            r"(\ndependencies\s*\{)",
            r"\1\n" + desugar_dep.rstrip("\n"),
            content,
            count=1,
        )
    else:
        content += f"\ndependencies {{\n{desugar_dep}}}\n"

    with open(path, "w", encoding="utf-8") as f:
        f.write(content)

    print(f"{path}: 패치 완료 (core library desugaring 활성화, Groovy)")


def main():
    import os

    if os.path.exists(KTS_PATH):
        patch_kts(KTS_PATH)
    elif os.path.exists(GROOVY_PATH):
        patch_groovy(GROOVY_PATH)
    else:
        print(f"오류: {KTS_PATH} 도 {GROOVY_PATH} 도 없음")
        sys.exit(1)


if __name__ == "__main__":
    sys.exit(main())
