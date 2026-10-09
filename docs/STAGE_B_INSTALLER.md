# Stage B — corrected PIXAML installer and late-load support

## Confirmed cause addressed

Magic Mount-rs v4.0.10 successfully mounted the Stage A marker after
`system/vendor` was preserved as a real directory. KernelSU's generic
`handle_partition()` had converted the first probe and PIXAML-style layout
into `system/vendor -> ../vendor`, which Magic Mount-rs classifies as a
symlink promoted at the root. Its root tmpfs guard then skips `/vendor`.

Stage B overrides `handle_partition()` only in the current installer shell.
This is the same localized mechanism proven by the Stage A v1.1 probe. It
does not modify KernelSU or Magic Mount-rs.

## Installed layout

~~~text
/data/adb/modules/sv_apixaml/
├── system/
│   └── vendor/                         # real directory
│       └── bin/hw/vendor.aml.effect-service
├── config/
│   └── audio_effects_config.xml          # module-private, not mounted over /vendor/etc
├── staging/
│   └── hook/aml.so                     # not mounted
├── options.conf                        # service disabled
├── pre-mount.sh
├── post-fs-data.sh
├── late-load.sh
├── post-mount.sh
├── service.sh
└── validate-service.sh
~~~

There is no `system/lib64/libaudiohal@aidl.so`, no mountable `aml.so`, no
active `sepolicy.rule`, and no automatic dependency renaming.

## Standard and Jailbreak Mode lifecycle

Standard KernelSU boot:

1. `post-fs-data.sh` calls the fail-closed pre-mount validator.
2. Magic Mount-rs mounts `system/vendor` into `/vendor`.
3. `post-mount.sh` compares source/mounted files and runs
   `linker64 --list` against the service.
4. `service.sh` exits because autostart defaults to zero.

KernelSU Next late-load/Jailbreak Mode:

1. KernelSU calls `late-load.sh` instead of `post-fs-data.sh`.
2. `late-load.sh` records `KSU_LATE_LOAD`/`KSU_RUNTIME_MODE` and invokes the
   same pre-mount validator.
3. KernelSU invokes the metamodule mount, `post-mount.sh`, and `service.sh`
   in that order.

The service is deliberately not launched from `late-load.sh`: that stage is
before systemless mounts. KernelSU Next documents `late-load.sh` as the
replacement for `post-fs-data.sh` and exports `KSU_LATE_LOAD=1` in this mode:

https://github.com/KernelSU-Next/KernelSU-Next/blob/dev/website/docs/guide/metamodule.md#late-load-mode

## Fail-closed behavior

Before the metamodule runs, `pre-mount.sh` creates `skip_mount` if:

- `system/vendor` is absent or a symlink;
- the AML service or private configuration is absent; or
- a critical `system/lib64/libaudiohal@aidl.so` unexpectedly appears.

After mounting, `post-mount.sh` withholds readiness if the payload differs
or any DT_NEEDED dependency fails to resolve. `service.sh` requires both
readiness and the exact opt-in setting:

~~~text
PIXAML_SERVICE_AUTOSTART=1
~~~

The distributed setting is zero. The service has no restart loop, no
audioserver restart, and no fallback bind mount.

## Binary compatibility remains intentionally unresolved

The service ELF was moved without changing a byte. Its current DT_NEEDED
entries still include:

~~~text
android.hardware.audio.effect-V2-ndk.so
android.media.audio.common.types-V3-ndk.so
android.hardware.audio.common-V3-ndk.so
android.hardware.common.fmq-V1-ndk.so
~~~

Stage B does not rename these dependencies and does not copy newer V4/V5
libraries under older names. Stable AIDL versioning does not justify changing
an ELF SONAME blindly. The on-device `linker64 --list` result is the gate for
the exact Pixel 10 firmware namespace.

The device test already reported a 4096-byte kernel page size, matching the
prebuilt's 4 KiB segment alignment. That removes one device-specific loader
risk but does not prove its AIDL ABI.

No SELinux rule is loaded in this stage. The mounted file contexts and any
denials must be observed before proposing a minimal policy for service
execution and Binder registration. The broad v0.9 policy is preserved only
under `research/legacy/` and is excluded from the ZIP.

## Initial validation boundary

Do not install this artifact together with the original PIXAML. It uses the
same module ID and is an update/replacement. Keep JamesDSP disabled.

After a user-controlled install and reboot, while service autostart remains
zero, collect:

~~~sh
adb shell "su -c 'ls -ld /data/adb/modules/sv_apixaml/system/vendor'"
adb shell "su -c 'find /data/adb/modules/sv_apixaml/system -maxdepth 4 -type f -print'"
adb shell "su -c 'test ! -e /data/adb/modules/sv_apixaml/system/lib64/libaudiohal@aidl.so && echo HOOK_NOT_MOUNTED'"
adb shell "su -c 'cat /data/adb/modules/sv_apixaml/state/pre-mount.status'"
adb shell "su -c 'cat /data/adb/modules/sv_apixaml/state/post-mount.status'"
adb shell "su -c 'cat /data/adb/modules/sv_apixaml/state/service.status'"
adb shell "su -c 'cat /data/adb/modules/sv_apixaml/state/linker-list.txt'"
adb shell "su -c '/data/adb/modules/sv_apixaml/validate-service.sh'"
adb shell "su -c 'pidof vendor.aml.effect-service || true'"
adb shell "su -c 'cat /proc/1/mountinfo'" |
  grep -E ' /vendor/bin/hw/vendor\.aml\.effect-service | /vendor/lib64/pixaml'
adb shell "su -c 'cat /proc/1/mountinfo'" |
  grep -F ' /vendor/etc/audio_effects_config.xml ' && echo UNEXPECTED_VENDOR_XML_OVERLAY || echo VENDOR_XML_NOT_OVERLAID
~~~

Expected at this stage:

- `system/vendor` starts with `d`, not `l`;
- `HOOK_NOT_MOUNTED`;
- pre-mount is `READY`;
- post-mount is `READY` only if the unmodified V2/V3 dependency closure is
  actually available; `BLOCKED reason=linker_dependency_resolution_failed`
  is a safe, useful compatibility result and prevents the service test;
- service state is `DISABLED`;
- linker output lists every resolved dependency;
- `IFactory/default` exists and `IFactory/aml` does not;
- no AML process is running;
- `/vendor/etc/audio_effects_config.xml` is not overlaid by this module.

Do not change the option to one until the dependency output, SELinux plan,
and Binder validation procedure have been reviewed. Enabling the service is
a separate test and still does not enable the native hook.

## Rollback

Disable or uninstall only `sv_apixaml` in KernelSU Next Manager and reboot.
If Android does not reach a usable state, use the already established
AshReXcue route to create:

~~~text
/data/adb/modules/sv_apixaml/disable
~~~

Do not remove or alter Magic Mount-rs, AshReXcue, physical partitions,
SELinux enforcement, or the bootloader as part of rollback.

## OTA behavior

Stage B never copies or patches the firmware's `libaudiohal@aidl.so`, so it
cannot carry a stale modified copy across an OTA. A future hook stage must
derive a fresh candidate from the current firmware, record its source hash,
validate ABI/symbols, and keep it outside `system/` until explicit activation.
