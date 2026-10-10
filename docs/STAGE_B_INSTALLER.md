# Stage B — corrected installer and late-load support

## Confirmed mount issue

Magic Mount-rs v4.0.10 mounted the Stage A marker after `system/vendor` stayed
a real directory. The failing PIXAML-style layout came from KernelSU's generic
`handle_partition()` helper: it moved the vendor payload to `vendor/` and left
`system/vendor -> ../vendor`. Magic Mount-rs treats that as a root-promoted
symlink and skips `/vendor`.

Stage B overrides `handle_partition()` only inside the installer shell. That is
the same narrow fix proven by the Stage A v1.1 probe. It does not patch
KernelSU, Magic Mount-rs, or any physical partition.

## Installed layout

~~~text
/data/adb/modules/sv_apixaml/
├── system/
│   └── vendor/                         # real directory
│       └── bin/hw/vendor.aml.effect-service
├── config/
│   └── audio_effects_config.xml        # module-private, not mounted over /vendor/etc
├── staging/
│   └── hook/aml.so                     # not mounted
├── options.conf                        # service option gate
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

1. `post-fs-data.sh` runs the fail-closed pre-mount validator.
2. Magic Mount-rs mounts `system/vendor` into `/vendor`.
3. `post-mount.sh` compares source and mounted files, then runs
   `linker64 --list` against the service.
4. `service.sh` starts only if the option gate and post-mount gate are both
   ready.

KernelSU Next late-load/Jailbreak Mode:

1. KernelSU calls `late-load.sh` instead of `post-fs-data.sh`.
2. `late-load.sh` records `KSU_LATE_LOAD`/`KSU_RUNTIME_MODE` and invokes the
   same pre-mount validator.
3. KernelSU invokes the metamodule mount, `post-mount.sh`, and `service.sh`
   in that order.

The service is not launched from `late-load.sh`; that stage runs before the
systemless `/vendor` overlay exists. KernelSU Next documents `late-load.sh` as
the replacement for `post-fs-data.sh` and exports `KSU_LATE_LOAD=1` in this
mode:

https://github.com/KernelSU-Next/KernelSU-Next/blob/dev/website/docs/guide/metamodule.md#late-load-mode

## Fail-closed behavior

Before the metamodule runs, `pre-mount.sh` creates `skip_mount` if:

- `system/vendor` is absent or a symlink;
- the AML service or private configuration is absent; or
- a critical `system/lib64/libaudiohal@aidl.so` unexpectedly appears.

After mounting, `post-mount.sh` withholds readiness if a mounted payload differs
or any DT_NEEDED dependency fails to resolve. `service.sh` also requires the
explicit option gate:

~~~text
PIXAML_SERVICE_AUTOSTART=1
~~~

The service has no restart loop, no audioserver restart, and no fallback bind
mount.

## Binary compatibility boundary

The service ELF moved without changing a byte. Its current DT_NEEDED entries
include:

~~~text
android.hardware.audio.effect-V2-ndk.so
android.media.audio.common.types-V3-ndk.so
android.hardware.audio.common-V3-ndk.so
android.hardware.common.fmq-V1-ndk.so
~~~

Stage B did not rename these dependencies or copy newer V4/V5 libraries under
older names. Stable AIDL versioning is not a license to change an ELF SONAME by
hand. The on-device `linker64 --list` result is the gate for the exact Pixel
firmware namespace.

The tested device reported a 4096-byte kernel page size, matching the prebuilt
4 KiB segment alignment. That removes one loader risk, but it does not prove
AIDL ABI compatibility.

No SELinux rule is loaded in this stage. Mounted contexts and denials should be
observed before proposing the smallest possible policy for service execution and
Binder registration. The broad v0.9 policy is preserved only under
`research/legacy/` and is excluded from the ZIP.

## Initial validation boundary

Do not install this artifact together with the original PIXAML. It uses the same
module ID and is an update/replacement. Keep JamesDSP disabled for this isolated
installer test.

After a user-controlled install and reboot, collect:

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
- post-mount is `READY` only when the unmodified V2/V3 dependency closure is
  available; `BLOCKED reason=linker_dependency_resolution_failed` is a safe and
  useful result because it prevents the service test;
- service state follows the option and post-mount gates;
- linker output lists every resolved dependency;
- `IFactory/default` exists and `IFactory/aml` does not before service testing;
- no AML process is running before service testing;
- `/vendor/etc/audio_effects_config.xml` is not overlaid by this module.

Do not move to service or hook testing until dependency output, SELinux
observations, and Binder validation are understood. Enabling the service is a
separate step and still does not enable the native hook.

## Rollback

Disable or uninstall only `sv_apixaml` in KernelSU Next Manager and reboot. If
Android does not reach a usable state, use the established AshReXcue route to
create:

~~~text
/data/adb/modules/sv_apixaml/disable
~~~

Do not remove or alter Magic Mount-rs, AshReXcue, physical partitions, SELinux
enforcement, or the bootloader as part of rollback.

## OTA behavior

Stage B never copies or patches the firmware `libaudiohal@aidl.so`, so it
cannot carry a stale modified copy across an OTA. A future hook stage must
derive a fresh candidate from the current firmware, record its source hash,
validate ABI/symbols, and keep it outside `system/` until explicit activation.
