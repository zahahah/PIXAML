#!/usr/bin/env python3
"""Verify the frozen AIDL payload against the unchanged AML service ELF."""

from __future__ import annotations

import os
import pathlib
import re
import subprocess
import sys


ROOT = pathlib.Path(__file__).resolve().parents[1]
LIBDIR = ROOT / "system/vendor/lib64/pixaml"
SERVICE = ROOT / "system/vendor/bin/hw/vendor.aml.effect-service"
LIBRARIES = (
    "android.hardware.audio.effect-V2-ndk.so",
    "android.hardware.audio.common-V3-ndk.so",
    "android.media.audio.common.types-V3-ndk.so",
)
PACKAGED_OR_PLATFORM_NEEDED = {
    *LIBRARIES,
    "android.hardware.common-V2-ndk.so",
    "android.hardware.common.fmq-V1-ndk.so",
    "libbinder_ndk.so",
    "libc++.so",
    "libc.so",
    "libdl.so",
}


def find_tool(name: str) -> pathlib.Path:
    sdk = os.environ.get("ANDROID_SDK_ROOT") or os.environ.get("ANDROID_HOME")
    if not sdk:
        raise SystemExit("ANDROID_SDK_ROOT or ANDROID_HOME is required")
    candidates = sorted(
        pathlib.Path(sdk).glob(f"ndk/*/toolchains/llvm/prebuilt/*/bin/{name}"),
        reverse=True,
    )
    if not candidates:
        raise SystemExit(f"unable to find {name} in Android NDK")
    return candidates[0]


def run(*args: object) -> str:
    return subprocess.check_output([str(arg) for arg in args], text=True)


def dynamic_value(readelf: pathlib.Path, path: pathlib.Path, tag: str) -> list[str]:
    output = run(readelf, "-d", path)
    return re.findall(rf"\({re.escape(tag)}\).*?\[(.*?)\]", output)


def dynamic_symbols(nm: pathlib.Path, path: pathlib.Path, flag: str) -> set[str]:
    output = run(nm, "-D", flag, path)
    return {line.split()[-1] for line in output.splitlines() if line.strip()}


def main() -> int:
    readelf = find_tool("llvm-readelf")
    nm = find_tool("llvm-nm")

    for name in LIBRARIES:
        path = LIBDIR / name
        header = run(readelf, "-h", path)
        if "AArch64" not in header or "ELF64" not in header:
            raise SystemExit(f"{name}: expected ELF64 AArch64")
        if dynamic_value(readelf, path, "SONAME") != [name]:
            raise SystemExit(f"{name}: SONAME mismatch")
        needed = dynamic_value(readelf, path, "NEEDED")
        if "libc++.so" not in needed or "libc++_shared.so" in needed:
            raise SystemExit(f"{name}: wrong C++ runtime dependency: {needed}")
        unexpected = set(needed) - PACKAGED_OR_PLATFORM_NEEDED
        if unexpected:
            raise SystemExit(
                f"{name}: unexpected DT_NEEDED entries: {sorted(unexpected)}"
            )
        program_headers = run(readelf, "-l", path)
        load_lines = [line for line in program_headers.splitlines() if "LOAD" in line]
        if not load_lines or any("0x4000" not in line for line in load_lines):
            raise SystemExit(f"{name}: expected 16 KiB LOAD alignment")
        data = path.read_bytes()
        if b"/var/folders/" in data or b"/tmp/pixaml-aidl." in data:
            raise SystemExit(f"{name}: contains a non-reproducible host path")

    service_undefined = dynamic_symbols(nm, SERVICE, "--undefined-only")
    effect_defined = dynamic_symbols(
        nm, LIBDIR / "android.hardware.audio.effect-V2-ndk.so", "--defined-only"
    )
    required = {
        symbol
        for symbol in service_undefined
        if symbol.startswith("_ZN4aidl") or symbol.startswith("_ZNK4aidl")
    }
    missing = required - effect_defined
    if missing:
        raise SystemExit(
            "effect V2 library does not export required service symbols:\n"
            + "\n".join(sorted(missing))
        )

    print(f"ELF compatibility verified: {len(required)} service AIDL symbols")
    return 0


if __name__ == "__main__":
    sys.exit(main())
