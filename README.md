# PIXAML — Android 17 AIDL audio module

This repository contains a staged, fail-safe correction of
AIDLPixelAudioModLibrary v0.9 for KernelSU Next and Magic Mount-rs v4.0.10.
The validated target is Pixel 10 Pro XL (`mustang`) on Android 17
`CP2A.260705.006`.

Authors: **lightningzahah, ShadoV90, anonymix007**.

## Stable release: v0.9.6

Tested environment: Stable use alongside JamesDSP on a Pixel 10 Pro XL
(`mustang`) running Android 17 with KernelSU Next and Magic Mount-rs. Results
may vary by device, firmware, and root mode. Please report defects through
GitHub Issues with device/build details, root mode, relevant logs, and steps
to reproduce.

The source packages the AML service with a module-private empty
configuration at `config/audio_effects_config.xml`. It no longer overlays that
file onto `/vendor/etc/audio_effects_config.xml`, and it still does not restart
audio processes automatically.

Stage A proved that Magic Mount-rs mounts `/vendor` correctly when
`system/vendor` is a real directory. Stage B then proved the corrected module
layout and found the next blocker: Android 17 does not provide
`android.hardware.audio.effect-V2-ndk.so` under the SONAME required by the
prebuilt service.

Stage C added reproducibly generated frozen AIDL V2/V3 compatibility libraries
under the private `/vendor/lib64/pixaml` directory and starts the AML service
only after a successful post-mount linker check using that same private search
path. It does not replace same-named libraries for unrelated vendor processes.

Safety properties:

- `system/vendor` is a real directory, never `system/vendor -> ../vendor`.
- `customize.sh` locally disables KernelSU's generic partition rewrite.
- `late-load.sh` supports KernelSU Next late-load/Jailbreak Mode.
- `post-fs-data.sh` and `late-load.sh` perform pre-mount validation only.
- `post-mount.sh` verifies the mounted payload and resolves the service's
  dynamic dependencies without executing its main function.
- The service path does not restart the firmware audio HAL or audioserver in
  either mode. `audio-reload.sh` is a no-op compatibility entry point.
- The empty AML XML is module-private and is not mounted over the firmware
  `/vendor/etc/audio_effects_config.xml`.
- The old automatic patchelf, dependency-renaming, policy, and integration
  scripts are quarantined under `research/legacy/` and excluded from release.

The prebuilt `aml.so` hook is stored under `staging/hook/`, outside the mount
tree. `libaudiohal@aidl.so` is neither generated nor included. The installer
and pre-mount gate both reject an automatically mountable copy.

The framework continues using `IFactory/default`; the module does **not**
redirect it to `IFactory/aml`. Registering `IFactory/aml` does not prove that
the framework discovered, created, or applied JamesDSP.

Build and test:

~~~sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -v
PYTHONDONTWRITEBYTECODE=1 python3 tools/package_stage_c.py
~~~

Rebuild the frozen AIDL payload when auditing its provenance:

~~~sh
ANDROID_SDK_ROOT=/path/to/sdk tools/build_aidl_compat.sh
~~~

The host tests verify archive contents and safety guards, but do not replace
device-specific validation. See `docs/STAGE_C_SERVICE.md` for service and
linker details.
