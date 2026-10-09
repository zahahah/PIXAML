#!/system/bin/sh

MODDIR=${0%/*}
STAGE=${1:-unknown}
STATE_DIR="$MODDIR/state"
STATUS="$STATE_DIR/pre-mount.status"

mkdir -p "$STATE_DIR"

block_mount() {
  printf 'BLOCKED stage=%s reason=%s\n' "$STAGE" "$1" >"$STATUS"
  # KernelSU metamodules recognize skip_mount. Failing closed prevents an
  # accidental critical system library or invalid vendor layout from mounting.
  touch "$MODDIR/skip_mount"
  exit 1
}

[ -d "$MODDIR/system/vendor" ] || block_mount missing_system_vendor_directory
[ ! -L "$MODDIR/system/vendor" ] || block_mount system_vendor_is_symlink
[ ! -e "$MODDIR/system/lib64/libaudiohal@aidl.so" ] || \
  block_mount critical_audio_hook_present
[ -f "$MODDIR/system/vendor/bin/hw/vendor.aml.effect-service" ] || \
  block_mount aml_service_missing
[ -f "$MODDIR/config/audio_effects_config.xml" ] || \
  block_mount aml_config_missing

for lib in \
  android.hardware.audio.effect-V2-ndk.so \
  android.hardware.audio.common-V3-ndk.so \
  android.media.audio.common.types-V3-ndk.so; do
  [ -f "$MODDIR/system/vendor/lib64/pixaml/$lib" ] || \
    block_mount "compat_library_missing_$lib"
done

printf 'READY stage=%s layout=system/vendor hook=disabled\n' "$STAGE" \
  >"$STATUS"
exit 0
