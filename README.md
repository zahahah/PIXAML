# PIXAML — Android 17 AIDL audio module

PIXAML keeps the Audio Modification Library path useful on modern Pixel
firmware without taking ownership of the whole audio stack. This tree carries a
careful AIDLPixelAudioModLibrary v0.9 update for KernelSU Next and Magic
Mount-rs v4.0.10. The validated target is Pixel 10 Pro XL (`mustang`) on
Android 17 `CP2A.260705.006`.

Authors: **lightningzahah, ShadoV90, anonymix007**.

## Stable release: v0.9.6

Tested environment: stable daily use with JamesDSP on a Pixel 10 Pro XL
(`mustang`) running Android 17 with KernelSU Next and Magic Mount-rs. This is
still vendor audio work, so results can change with firmware, root stage, and
module mix. Please report defects through GitHub Issues with device/build
information, root mode, useful logs, and clear reproduction steps.

The module ships the AML service with a module-private empty configuration at
`config/audio_effects_config.xml`. It does not overlay that file onto
`/vendor/etc/audio_effects_config.xml`, and it does not restart audio processes
automatically.

Stage A proved that Magic Mount-rs can mount `/vendor` when `system/vendor` is
a real directory. Stage B kept that layout and found the next blocker: Android
17 no longer provides `android.hardware.audio.effect-V2-ndk.so` under the
SONAME required by the prebuilt AML service.

Stage C adds frozen AIDL V2/V3 compatibility libraries generated from recorded
AOSP API snapshots. They live under the private `/vendor/lib64/pixaml` path.
`post-mount.sh` verifies that the mounted service can resolve its dependencies
with that same private search path before `service.sh` starts anything. These
libraries are not dropped into the global vendor library directory and are not
used by unrelated vendor processes.

Safety properties:

- `system/vendor` is a real directory, never `system/vendor -> ../vendor`.
- `customize.sh` locally disables KernelSU's generic partition rewrite.
- `late-load.sh` supports KernelSU Next late-load/Jailbreak Mode.
- `post-fs-data.sh` and `late-load.sh` only validate the source tree before
  Magic Mount-rs applies the overlay.
- `post-mount.sh` verifies mounted bytes and resolves service dependencies
  without executing the AML service main function.
- The service path does not restart the firmware audio HAL or audioserver in
  either root mode. `audio-reload.sh` is only a compatibility no-op.
- The empty AML XML stays module-private and is not mounted over the firmware
  `/vendor/etc/audio_effects_config.xml`.
- The old automatic patchelf, dependency-renaming, policy, and integration
  scripts are quarantined under `research/legacy/` and excluded from release.

The prebuilt `aml.so` hook stays under `staging/hook/`, outside the mount tree.
`libaudiohal@aidl.so` is not generated or included. The installer and
pre-mount gate both reject an automatically mountable copy because this build
keeps the hook path off by design.

The framework still uses `IFactory/default`; PIXAML does **not** redirect it to
`IFactory/aml`. Seeing `IFactory/aml` registered only proves that the standalone
AML service came up. It does not prove that JamesDSP was discovered, created,
enabled, or heard in the audio path.

Build and test:

~~~sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -v
PYTHONDONTWRITEBYTECODE=1 python3 tools/package_stage_c.py
~~~

Rebuild the frozen AIDL payload when auditing its provenance:

~~~sh
ANDROID_SDK_ROOT=/path/to/sdk tools/build_aidl_compat.sh
~~~

The host tests verify archive contents and safety gates. They do not replace
real device validation for factory discovery, effect creation, audible output,
pause/resume behavior, route changes, or long-running stability. See
`docs/STAGE_C_SERVICE.md` for the service and linker boundary.
