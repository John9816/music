#!/usr/bin/env python3
"""Cache SHA-256 pinned Kotlin compilers from Maven Central before Gradle runs."""

import hashlib
import os
from pathlib import Path
import re
import urllib.request


# Flutter's included Gradle build and this app use separate Kotlin versions.
# Digests are from complete official Maven Central JARs; 2.2.20 also matches
# JetBrains' GitHub release asset digest.
COMPILERS = {
    "2.2.20": "1c6c3f810bfe6a41abcbc34b3a2ef639f1e3f4aeed3a953a4b0974eea4f41889",
    "2.3.20": "976f989d0b5f5d80e8e8a8ad4b73da0bfc27fdd965b9fa38362b2be79ecc1337",
}
REPOSITORIES = (
    "https://repo.maven.apache.org/maven2/",
    "https://maven-central.storage-download.googleapis.com/maven2/",
)


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def cache_compiler(version, expected, gradle_home, opener=urllib.request.urlopen):
    if not re.fullmatch(r"\d+\.\d+\.\d+", version) or not re.fullmatch(r"[a-f0-9]{64}", expected):
        raise ValueError("Expected a pinned Kotlin version and SHA-256")
    name = "kotlin-compiler-embeddable-" + version + ".jar"
    directory = gradle_home / "caches/modules-2/files-2.1/org.jetbrains.kotlin/kotlin-compiler-embeddable" / version
    for candidate in directory.glob("*/" + name):
        if sha256(candidate) == expected:
            print("Kotlin " + version + " compiler cache verified")
            return candidate
    directory.mkdir(parents=True, exist_ok=True)
    temporary = directory / (name + ".download")
    path = "org/jetbrains/kotlin/kotlin-compiler-embeddable/" + version + "/" + name
    try:
        for index, repository in enumerate(REPOSITORIES):
            try:
                request = urllib.request.Request(repository + path, headers={"User-Agent": "DuckMusic-release"})
                digest = hashlib.sha256()
                address = hashlib.sha1()
                with opener(request, timeout=120) as response, temporary.open("wb") as output:
                    for chunk in iter(lambda: response.read(1024 * 1024), b""):
                        digest.update(chunk)
                        address.update(chunk)
                        output.write(chunk)
                if digest.hexdigest() != expected:
                    raise ValueError("Kotlin compiler failed SHA-256 verification")
                # Gradle renders the SHA-1 as an unpadded hexadecimal integer.
                target = directory / (address.hexdigest().lstrip("0") or "0") / name
                target.parent.mkdir(parents=True, exist_ok=True)
                temporary.replace(target)
                print("Kotlin " + version + " compiler downloaded and SHA-256 verified")
                return target
            except OSError:
                if index == len(REPOSITORIES) - 1:
                    raise
    finally:
        temporary.unlink(missing_ok=True)


if __name__ == "__main__":
    gradle_home = Path(os.environ.get("GRADLE_USER_HOME", Path.home() / ".gradle"))
    for version, expected in COMPILERS.items():
        cache_compiler(version, expected, gradle_home)
