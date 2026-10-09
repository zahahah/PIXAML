#!/usr/bin/env python3
"""Build the deterministic PIXAML v0.9.6 module ZIP."""

from __future__ import annotations

import hashlib
import pathlib
import zipfile


ROOT = pathlib.Path(__file__).resolve().parents[1]
OUTPUT_DIR = ROOT / "dist"
ZIP_PATH = OUTPUT_DIR / "AIDLPixelAudioModLibrary-v0.9.6.zip"
FIXED_TIME = (2020, 1, 1, 0, 0, 0)

PAYLOADS = {
    "module.prop": 0o100644,
    "customize.sh": 0o100644,
    "options.conf": 0o100644,
    "compat-manifest.txt": 0o100644,
    "pre-mount.sh": 0o100755,
    "post-fs-data.sh": 0o100755,
    "late-load.sh": 0o100755,
    "post-mount.sh": 0o100755,
    "service.sh": 0o100755,
    "audio-reload.sh": 0o100755,
    "validate-service.sh": 0o100755,
    "system/vendor/bin/hw/vendor.aml.effect-service": 0o100755,
    "config/audio_effects_config.xml": 0o100644,
    "system/vendor/lib64/pixaml/android.hardware.audio.effect-V2-ndk.so": 0o100644,
    "system/vendor/lib64/pixaml/android.hardware.audio.common-V3-ndk.so": 0o100644,
    "system/vendor/lib64/pixaml/android.media.audio.common.types-V3-ndk.so": 0o100644,
    "staging/hook/aml.so": 0o100644,
}


def build(output: pathlib.Path = ZIP_PATH) -> str:
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_STORED) as archive:
        for relative, mode in PAYLOADS.items():
            source = ROOT / relative
            if not source.is_file():
                raise FileNotFoundError(source)
            info = zipfile.ZipInfo(relative, FIXED_TIME)
            info.create_system = 3
            info.external_attr = (mode & 0xFFFF) << 16
            archive.writestr(info, source.read_bytes())
    return hashlib.sha256(output.read_bytes()).hexdigest()


def main() -> None:
    digest = build()
    checksum = ZIP_PATH.with_suffix(ZIP_PATH.suffix + ".sha256")
    checksum.write_text(
        f"{digest}  {ZIP_PATH.relative_to(ROOT).as_posix()}\n", encoding="ascii"
    )
    print(ZIP_PATH.relative_to(ROOT))
    print(f"SHA256 {digest}")


if __name__ == "__main__":
    main()
