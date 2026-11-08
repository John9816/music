#!/usr/bin/env python3
"""Download the pinned official Gradle asset without the release-page redirect."""

import hashlib
import json
import os
from pathlib import Path
import re
import time
import urllib.request


def wrapper_target(properties, gradle_home):
    values = dict(line.split("=", 1) for line in properties.splitlines()
                  if "=" in line and not line.startswith("#"))
    url = values["distributionUrl"].replace(r"\:", ":")
    match = re.fullmatch(r"https://services\.gradle\.org/distributions/(gradle-([\d.]+)-(?:all|bin))\.zip", url)
    if not match:
        raise ValueError("Expected an official Gradle wrapper distribution URL")
    checksum = values.get("distributionSha256Sum", "")
    if not re.fullmatch(r"[a-f0-9]{64}", checksum):
        raise ValueError("Pin distributionSha256Sum before downloading Gradle")
    # Gradle's PathAssembler hashes the original distribution URL in base 36.
    number = int.from_bytes(hashlib.md5(url.encode()).digest(), "big")
    encoded = ""
    while number:
        number, remainder = divmod(number, 36)
        encoded = "0123456789abcdefghijklmnopqrstuvwxyz"[remainder] + encoded
    name, version = match.groups()
    target = gradle_home / "wrapper/dists" / name / (encoded or "0") / (name + ".zip")
    return target, version, checksum


def digest(path):
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(chunk)
    return result.hexdigest()


def cache_distribution(properties, gradle_home, opener=urllib.request.urlopen):
    target, version, expected = wrapper_target(properties, gradle_home)
    if target.exists() and digest(target) == expected:
        print("Gradle distribution cache verified")
        return target
    headers = {"Accept": "application/vnd.github+json", "User-Agent": "DuckMusic-release"}
    if os.environ.get("GITHUB_TOKEN"):
        headers["Authorization"] = "Bearer " + os.environ["GITHUB_TOKEN"]
    request = urllib.request.Request(
        "https://api.github.com/repos/gradle/gradle-distributions/releases/tags/v" + version,
        headers=headers)
    with opener(request, timeout=30) as response:
        release = json.load(response)
    asset = next(item for item in release["assets"] if item["name"] == target.name)
    if asset.get("digest") != "sha256:" + expected:
        raise ValueError("Official Gradle asset does not match pinned checksum")
    asset_url = asset["url"]
    if not re.fullmatch(r"https://api\.github\.com/repos/gradle/gradle-distributions/releases/assets/\d+", asset_url):
        raise ValueError("Unexpected Gradle asset URL")
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = target.with_suffix(".download")
    try:
        request = urllib.request.Request(asset_url, headers={
            "Accept": "application/octet-stream", "User-Agent": "DuckMusic-release"})
        with opener(request, timeout=120) as response, temporary.open("wb") as output:
            for chunk in iter(lambda: response.read(1024 * 1024), b""):
                output.write(chunk)
        if digest(temporary) != expected:
            raise ValueError("Downloaded Gradle distribution failed SHA-256 verification")
        temporary.replace(target)
    finally:
        temporary.unlink(missing_ok=True)
    print("Official Gradle distribution downloaded and SHA-256 verified")
    return target


if __name__ == "__main__":
    properties = Path("android/gradle/wrapper/gradle-wrapper.properties").read_text()
    gradle_home = Path(os.environ.get("GRADLE_USER_HOME", Path.home() / ".gradle"))
    for attempt in range(3):
        try:
            cache_distribution(properties, gradle_home)
            break
        except OSError:
            if attempt == 2:
                raise
            time.sleep(5)
