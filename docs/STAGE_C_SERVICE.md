# Stage C/D — standalone AML service; audio restart disabled

Stage C is the first build that starts the standalone AML service. It is not a
native audio hook release: `libaudiohal@aidl.so` remains absent and
`staging/hook/aml.so` remains outside `system/`.

## Why the Stage B linker check failed

The original prebuilt service is linked against frozen AIDL client libraries:

* `android.hardware.audio.effect-V2-ndk.so`
* `android.hardware.audio.common-V3-ndk.so`
* `android.media.audio.common.types-V3-ndk.so`

Android 17 on `mustang` no longer installs the first library under that SONAME.
Stage C supplies the three exact frozen interfaces generated from immutable AOSP
AIDL API snapshots. It does not rename a V4/V5 binary to an older name. Source
API hashes, AOSP revisions, and binary hashes are recorded in
`compat-manifest.txt`; `tools/build_aidl_compat.sh` reproduces the payload.

The service had 23 unresolved `aidl::android::hardware::audio::effect` symbols.
All 23 are exported by the generated V2 library. The generated libraries use
Android platform `std::__1`, depend on `libc++.so`, are ARM64 ELF objects, and
have 16 KiB segment alignment. A 16 KiB-aligned ELF also satisfies the tested 4
KiB kernel page size.

## Runtime safety boundary

The package mounts only these vendor paths systemlessly; the XML stays
module-private and is passed as an argument to the AML process:

~~~text
/vendor/bin/hw/vendor.aml.effect-service
/vendor/lib64/pixaml/android.hardware.audio.effect-V2-ndk.so
/vendor/lib64/pixaml/android.hardware.audio.common-V3-ndk.so
/vendor/lib64/pixaml/android.media.audio.common.types-V3-ndk.so

/data/adb/modules/sv_apixaml/config/audio_effects_config.xml  # not mounted over /vendor/etc
~~~

It does not write physical partitions, patch firmware libraries, load a custom
SELinux policy, or enable the native hook. The compatibility SONAMEs are frozen
versions that are not present in the tested firmware under the required names.
They stay in private `/vendor/lib64/pixaml`; only the AML process receives that
directory through `LD_LIBRARY_PATH`.

`post-mount.sh` compares every mounted payload and runs `linker64 --list` with
the same private `LD_LIBRARY_PATH` used at launch. This resolves the dependency
closure without entering the service main function. Only after that gate passes,
`service.sh` starts one AML service instance with the explicit module-private
XML path. It waits up to 30 seconds for `IFactory/default` and up to 15 seconds
for `IFactory/aml`.

If Binder registration times out while the child is still alive, the script
sends that one child a single SIGTERM. It does not enter a restart loop.

The AML service starts before any native hook exists. A failure cannot redirect
the framework away from the original `IFactory/default`.

## Installation

Use the generated `v0.9.6` ZIP for this stage. Do not install older
`v0.9.3-late-load-reload` artifacts as a diagnostic step because they contain
the automatic audio restart path.

## Validation

~~~sh
adb shell "su -c 'cat /data/adb/modules/sv_apixaml/state/pre-mount.status'"
adb shell "su -c 'cat /data/adb/modules/sv_apixaml/state/post-mount.status'"
adb shell "su -c 'cat /data/adb/modules/sv_apixaml/state/service.status'"
adb shell "su -c 'cat /data/adb/modules/sv_apixaml/state/audio-reload.status'"
adb shell "su -c 'cat /data/adb/modules/sv_apixaml/state/linker-list.txt'"
adb shell "su -c '/data/adb/modules/sv_apixaml/validate-service.sh'"
adb shell "su -c 'service check android.hardware.audio.effect.IFactory/default'"
adb shell "su -c 'service check android.hardware.audio.effect.IFactory/aml'"
adb shell "su -c 'pidof vendor.aml.effect-service'"
adb shell "su -c 'cat /proc/1/mountinfo'" |
  grep -E 'vendor\.aml\.effect-service|/vendor/lib64/pixaml'
~~~

Expected results:

* pre-mount and post-mount are `READY`;
* `linker-list.txt` has no `CANNOT LINK EXECUTABLE`;
* service status is `REGISTERED ... hook=disabled`;
* the working-tree service reports `audio_reload=disabled`; this is not proof
  that JamesDSP was discovered or applied;
* both Binder factories are `found`;
* exactly one AML service process exists;
* no denial involving that process and `service_manager add/find` appears;
* this module does not overlay `/vendor/etc/audio_effects_config.xml`.

Do not proceed to a native hook if any item differs. `BLOCKED`, `EXITED`, a
missing AML Binder service, or an SELinux denial means the standalone service
has not passed.

## Reversal

Disable `sv_apixaml` in KernelSU Next Manager and reboot. If Android is not
usable, use the established AshReXcue mechanism to create:

~~~text
/data/adb/modules/sv_apixaml/disable
~~~

No physical `/system` or `/vendor` restoration is needed because every mount is
temporary and every persistent module file is under `/data/adb/modules`.

## Late-load / Jailbreak Mode

`late-load.sh` performs only source-tree preflight before the metamodule mount.
The shared `post-mount.sh` linker gate and `service.sh` registration gate run
afterward. The service is never started from the pre-mount hook.

At this point the firmware `IFactory/default` may already have cached the old
configuration. The previous automatic HAL/audioserver restart was not proven
safe on this firmware and is disabled here. `audio-reload.sh` only records
`SKIPPED reason=unsafe_audio_restart_disabled`; `service.sh` does not call it or
gate AML registration on its result. This removes that restart path, but it does
not make the cached factory discover JamesDSP.

## Remaining boundary

Passing host tests proves script behavior and packaging. Final device acceptance
still requires the default factory to list the JamesDSP UUID, the app to create
and enable an effect instance, audible processing, stable pause/resume and route
changes, and no relevant AVCs or reboots over time.
