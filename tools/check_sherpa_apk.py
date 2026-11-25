#!/usr/bin/env python3
"""Проверяет, что release APK содержит sherpa-onnx только для arm64-v8a."""

import sys
import zipfile
from pathlib import Path

REQUIRED = (
    "lib/arm64-v8a/libsherpa-onnx-jni.so",
    "lib/arm64-v8a/libonnxruntime.so",
)
FORBIDDEN_PREFIXES = (
    "lib/armeabi-v7a/libsherpa-onnx",
    "lib/armeabi-v7a/libonnxruntime.so",
    "lib/x86/libsherpa-onnx",
    "lib/x86/libonnxruntime.so",
    "lib/x86_64/libsherpa-onnx",
    "lib/x86_64/libonnxruntime.so",
    "lib/arm64-v8a/libsherpa-onnx-c-api.so",
    "lib/arm64-v8a/libsherpa-onnx-cxx-api.so",
)


def fail(message: str) -> None:
    print(f"ПРОВЕРКА SHERPA: {message}", file=sys.stderr)
    raise SystemExit(1)


def main() -> None:
    if len(sys.argv) != 2:
        fail("укажите apk")
    path = Path(sys.argv[1])
    if not path.is_file():
        fail(f"нет файла {path}")
    with zipfile.ZipFile(path) as archive:
        names = set(archive.namelist())
        for required in REQUIRED:
            if required not in names:
                fail(f"в APK нет {required}")
        for name in sorted(names):
            if name.startswith(FORBIDDEN_PREFIXES):
                fail(f"в APK лишняя библиотека {name}")
        native = 0
        compressed = 0
        print(f"APK {path.stat().st_size} байт")
        for name in REQUIRED:
            info = archive.getinfo(name)
            native += info.file_size
            compressed += info.compress_size
            print(f"{name}: {info.file_size} байт, в архиве {info.compress_size}")
        print(f"sherpa arm64 несжатые {native} байт, в APK {compressed}")


if __name__ == "__main__":
    main()
