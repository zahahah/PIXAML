# PIXAML — Android 17 AIDL audio module

PIXAML keeps the Audio Modification Library path useful on modern Pixel
firmware without taking ownership of the whole audio stack. This tree carries a
careful AIDLPixelAudioModLibrary v0.9 update for KernelSU Next and Magic
Mount-rs v4.0.11. The validated target is Pixel 10 Pro XL (`mustang`) on
Android 17 `CP2A.260705.006`.

Authors: **lightningzahah, ShadoV90, anonymix007**.

## Stable release: v0.9.6

PIXAML is an optional companion to JamesDSP, not a requirement for it. On the
tested Pixel 10 Pro XL (`mustang`), JamesDSP also worked without PIXAML because
it uses Android's default effect factory. PIXAML provides a separate AML
service for setups that need AML-specific compatibility or other AML-based
effects. Whether that is useful depends on the device and the rest of the audio
stack. Results can change with firmware, root stage, and module mix; please
report defects through GitHub Issues with device/build details, root mode,
useful logs, and clear reproduction steps.

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
`IFactory/aml`. JamesDSP can be loaded through the default factory without
PIXAML on the tested Pixel. On other devices, PIXAML may be useful when the
audio setup specifically needs its AML service, but registering `IFactory/aml`
does not by itself make AudioFlinger use that factory. It also does not prove
that JamesDSP was discovered, created, enabled, or heard in the audio path.

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
