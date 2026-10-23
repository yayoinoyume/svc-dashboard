#!/usr/bin/env python3
"""把 CI 注入的签名材料写进 Flutter 宿主工程的 Gradle 配置。

用法: python3 configure-signing.py <flutter_host_dir>

依赖环境变量（由 1Password action 导出）：
  KEYSTORE_PASSWORD / KEY_ALIAS / KEY_PASSWORD
密钥文件由调用方解码到 /tmp/magpie-release.p12。
"""

import os
import sys
from pathlib import Path

KEYSTORE_PATH = "/tmp/magpie-release.p12"


def write_props(android: Path) -> None:
    props = android / "key.properties"
    props.write_text(
        f"storeFile={KEYSTORE_PATH}\n"
        f"storePassword={os.environ['KEYSTORE_PASSWORD']}\n"
        f"keyAlias={os.environ['KEY_ALIAS']}\n"
        f"keyPassword={os.environ['KEY_PASSWORD']}\n"
    )


KTS_BLOCK = """android {
    signingConfigs {
        create("release") {
            val props = Properties()
            val f = rootProject.file("key.properties")
            if (f.exists()) f.inputStream().use { props.load(it) }
            storeFile = file(props.getProperty("storeFile"))
            storePassword = props.getProperty("storePassword")
            keyAlias = props.getProperty("keyAlias")
            keyPassword = props.getProperty("keyPassword")
        }
    }
"""

GROOVY_BLOCK = """android {
    signingConfigs {
        release {
            def props = new Properties()
            def f = rootProject.file("key.properties")
            if (f.exists()) f.withInputStream { props.load(it) }
            storeFile file(props["storeFile"])
            storePassword props["storePassword"]
            keyAlias props["keyAlias"]
            keyPassword props["keyPassword"]
        }
    }
"""


def patch_kts(path: Path) -> None:
    text = path.read_text()
    if "import java.util.Properties" not in text:
        text = "import java.util.Properties\n\n" + text
    head = text.split("buildTypes")[0]
    if "signingConfigs" not in head:
        text = text.replace("android {", KTS_BLOCK, 1)
    text = text.replace(
        'signingConfigs.getByName("debug")',
        'signingConfigs.getByName("release")',
    )
    path.write_text(text)


def patch_groovy(path: Path) -> None:
    text = path.read_text()
    head = text.split("buildTypes")[0]
    if "signingConfigs" not in head:
        text = text.replace("android {", GROOVY_BLOCK, 1)
    text = text.replace(
        "signingConfig signingConfigs.debug",
        "signingConfig signingConfigs.release",
    )
    path.write_text(text)


def main() -> int:
    if len(sys.argv) < 2:
        print("缺少宿主工程目录", file=sys.stderr)
        return 2

    host = Path(sys.argv[1])
    android = host / "android"
    if not android.is_dir():
        print(f"找不到 android 目录: {android}", file=sys.stderr)
        return 2

    write_props(android)

    kts = android / "app" / "build.gradle.kts"
    groovy = android / "app" / "build.gradle"
    if kts.exists():
        patch_kts(kts)
        print("已配置 Kotlin DSL 签名")
    elif groovy.exists():
        patch_groovy(groovy)
        print("已配置 Groovy 签名")
    else:
        print("找不到 build.gradle(.kts)", file=sys.stderr)
        return 2

    # 确认替换生效，避免静默用回 debug 签名
    build_file = kts if kts.exists() else groovy
    body = build_file.read_text()
    if "release" not in body.split("buildTypes")[-1]:
        print("签名字段未生效", file=sys.stderr)
        return 3
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
