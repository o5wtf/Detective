#!/usr/bin/env python3
"""Download the pinned sherpa-onnx Android AAR, keep arm64, build the Godot plugin.

The .so files are not committed. CI runs this before the Android export.
"""

import argparse
import hashlib
import io
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VERSION = "2.0.3"
AAR_URL = (
    "https://github.com/k2-fsa/sherpa-onnx/releases/download/"
    f"v{VERSION}/sherpa-onnx-{VERSION}.aar"
)
AAR_SHA256 = "4c766e2e74c9d33d595338c21fe3b305c73ba45d47e96a235675c33142a2ec50"
GRADLE_URL = "https://services.gradle.org/distributions/gradle-8.10.2-bin.zip"
GRADLE_SHA256 = "31c55713e40233a8303827ceb42ca48a47267a0ad4bab9177123121e71524c26"
KEEP_LIBS = (
    "jni/arm64-v8a/libonnxruntime.so",
    "jni/arm64-v8a/libsherpa-onnx-jni.so",
)
BIN = ROOT / "addons" / "sherpa_onnx" / "bin"
PLUGIN = ROOT / "addons" / "sherpa_onnx" / "android"
JNI_SYMBOL = "Java_com_k2fsa_sherpa_onnx_OfflineRecognizer_newFromFile"


def fail(message: str) -> None:
    print(f"sherpa: {message}", file=sys.stderr)
    raise SystemExit(1)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def download(url: str, dest: Path, expected: str) -> None:
    if dest.is_file() and sha256(dest) == expected:
        print(f"sherpa: уже есть {dest.name}")
        return
    dest.parent.mkdir(parents=True, exist_ok=True)
    print(f"sherpa: качаю {url}")
    with urllib.request.urlopen(url) as response, dest.open("wb") as handle:
        shutil.copyfileobj(response, handle)
    actual = sha256(dest)
    if actual != expected:
        dest.unlink(missing_ok=True)
        fail(f"SHA-256 {dest.name}: {actual}, ожидалось {expected}")


def arm64_aar(source: Path, dest: Path) -> None:
    with zipfile.ZipFile(source) as incoming, zipfile.ZipFile(dest, "w") as outgoing:
        names = set(incoming.namelist())
        for required in ("classes.jar", "AndroidManifest.xml", *KEEP_LIBS):
            if required not in names:
                fail(f"в официальном AAR нет {required}")
        for info in incoming.infolist():
            if info.filename.startswith("jni/") and info.filename not in KEEP_LIBS:
                continue
            if info.filename.endswith("/"):
                continue
            outgoing.writestr(info.filename, incoming.read(info.filename))
    with zipfile.ZipFile(dest) as check:
        native = [name for name in check.namelist() if name.startswith("jni/") and not name.endswith("/")]
        if sorted(native) != sorted(KEEP_LIBS):
            fail(f"arm64 AAR содержит лишние библиотеки: {native}")


def require_symbol(aar: Path) -> None:
    readelf = shutil.which("readelf")
    if readelf is None:
        fail("нет readelf, символ JNI не проверить")
    with zipfile.ZipFile(aar) as archive, tempfile.TemporaryDirectory() as temp:
        blob = Path(temp) / "libsherpa-onnx-jni.so"
        blob.write_bytes(archive.read("jni/arm64-v8a/libsherpa-onnx-jni.so"))
        header = blob.read_bytes()[:20]
        if header[:4] != b"\x7fELF" or header[4] != 2 or header[18] != 183:
            fail("libsherpa-onnx-jni.so не ELF arm64")
        result = subprocess.run(
            [readelf, "-sW", str(blob)],
            check=False,
            capture_output=True,
            text=True,
        )
        if result.returncode != 0 or JNI_SYMBOL not in result.stdout:
            fail(f"в JNI нет {JNI_SYMBOL}")
    print(f"sherpa: {JNI_SYMBOL} есть, ABI arm64-v8a")


def gradle_home(cache: Path) -> Path:
    archive = cache / "gradle-8.10.2-bin.zip"
    download(GRADLE_URL, archive, GRADLE_SHA256)
    home = cache / "gradle-8.10.2"
    binary = home / "bin" / "gradle"
    if binary.is_file():
        return home
    with zipfile.ZipFile(archive) as bundle:
        bundle.extractall(cache)
    binary.chmod(binary.stat().st_mode | stat.S_IEXEC)
    return home


def build_plugin() -> None:
    sdk = os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT")
    if not sdk:
        fail("ANDROID_HOME не задан, плагин Godot не собрать")
    classes = BIN / "sherpa-classes.jar"
    with zipfile.ZipFile(BIN / f"sherpa-onnx-{VERSION}-arm64.aar") as archive:
        classes.write_bytes(archive.read("classes.jar"))
    properties = PLUGIN / "local.properties"
    properties.write_text(f"sdk.dir={sdk}\n", encoding="utf-8")
    cache = Path(os.environ.get("SHERPA_CACHE", ROOT / "addons" / "sherpa_onnx" / ".cache"))
    gradle = gradle_home(cache) / "bin" / "gradle"
    subprocess.run(
        [str(gradle), "-p", str(PLUGIN), "assembleRelease", "--no-daemon"],
        check=True,
    )
    built = PLUGIN / "build" / "outputs" / "aar" / "android-release.aar"
    if not built.is_file():
        found = list((PLUGIN / "build" / "outputs" / "aar").glob("*.aar"))
        if not found:
            fail("Gradle не положил AAR плагина")
        built = found[0]
    target = BIN / "sherpa_godot-release.aar"
    shutil.copyfile(built, target)
    print(f"sherpa: плагин {target} ({target.stat().st_size} байт)")


def self_test() -> None:
    payload = {
        "classes.jar": b"jar",
        "AndroidManifest.xml": b"<manifest/>",
        "jni/arm64-v8a/libonnxruntime.so": b"ort",
        "jni/arm64-v8a/libsherpa-onnx-jni.so": b"jni",
        "jni/arm64-v8a/libsherpa-onnx-c-api.so": b"extra",
        "jni/x86_64/libsherpa-onnx-jni.so": b"desktop",
        "proguard.txt": b"",
    }
    source = io.BytesIO()
    with zipfile.ZipFile(source, "w") as archive:
        for name, body in payload.items():
            archive.writestr(name, body)
    with tempfile.TemporaryDirectory() as temp:
        raw = Path(temp) / "full.aar"
        raw.write_bytes(source.getvalue())
        stripped = Path(temp) / "arm64.aar"
        arm64_aar(raw, stripped)
        with zipfile.ZipFile(stripped) as archive:
            names = sorted(name for name in archive.namelist() if not name.endswith("/"))
        expected = sorted(
            [
                "classes.jar",
                "AndroidManifest.xml",
                "proguard.txt",
                *KEEP_LIBS,
            ]
        )
        if names != expected:
            fail(f"self-test: {names}")
    print("sherpa: self-test ок")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--libs-only", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    cache = Path(os.environ.get("SHERPA_CACHE", ROOT / "addons" / "sherpa_onnx" / ".cache"))
    official = cache / f"sherpa-onnx-{VERSION}.aar"
    download(AAR_URL, official, AAR_SHA256)
    BIN.mkdir(parents=True, exist_ok=True)
    arm64 = BIN / f"sherpa-onnx-{VERSION}-arm64.aar"
    arm64_aar(official, arm64)
    require_symbol(arm64)
    size = arm64.stat().st_size
    print(f"sherpa: arm64 AAR {size} байт (без x86 и без c-api)")
    if args.libs_only:
        return
    build_plugin()


if __name__ == "__main__":
    main()
