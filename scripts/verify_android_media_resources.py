#!/usr/bin/env python3
"""Check runtime-resolved notification icons in the actual packaged APK."""

import argparse
from pathlib import Path
import re
import subprocess
import sys
import zipfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("apk", type=Path)
    parser.add_argument("--aapt", required=True, type=Path)
    args = parser.parse_args()
    resources = subprocess.check_output(
        [str(args.aapt), "dump", "--values", "resources", str(args.apk)],
        text=True,
    )
    expected = (
        "ic_notification_music",
        "audio_service_pause",
        "audio_service_play_arrow",
        "audio_service_skip_next",
        "audio_service_skip_previous",
        "audio_service_stop",
        "audio_service_fast_forward",
        "audio_service_fast_rewind",
    )
    failures = []
    with zipfile.ZipFile(args.apk) as archive:
        for name in expected:
            paths = re.findall(
                r"^\s+resource 0x[0-9a-f]+ [^\s]+:drawable/"
                + re.escape(name)
                + r':[^\n]*\n\s+\(string(?:8|16)\) "([^"\n]+)"',
                resources,
                flags=re.MULTILINE,
            )
            if not paths:
                failures.append(f"drawable/{name} has no packaged resource value")
                continue
            for path in set(paths):
                if path not in archive.namelist() or not archive.read(path):
                    failures.append(f"drawable/{name} has missing/empty asset {path}")
    if failures:
        print(f"Media notification resources FAILED: {args.apk.name}", file=sys.stderr)
        for failure in failures:
            print(f"  {failure}", file=sys.stderr)
        return 1
    print(f"Media notification resources OK: {args.apk.name} ({len(expected)} icons)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
