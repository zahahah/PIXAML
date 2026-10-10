#!/system/bin/sh

MODDIR=${0%/*}
STATE_DIR="$MODDIR/state"
SOURCE_SERVICE="$MODDIR/system/vendor/bin/hw/vendor.aml.effect-service"
MOUNTED_SERVICE=/vendor/bin/hw/vendor.aml.effect-service
SOURCE_CONFIG="$MODDIR/config/audio_effects_config.xml"
PRIVATE_CONFIG="$SOURCE_CONFIG"
STATUS="$STATE_DIR/post-mount.status"
COMPAT_DIR=/vendor/lib64/pixaml
COMPAT_LIBS="
android.hardware.audio.effect-V2-ndk.so
android.hardware.audio.common-V3-ndk.so
android.media.audio.common.types-V3-ndk.so
"

mkdir -p "$STATE_DIR"

not_ready() {
  printf 'BLOCKED reason=%s\n' "$1" >"$STATUS"
  exit 0
}

[ ! -f "$MODDIR/skip_mount" ] || not_ready skip_mount_present
[ -x "$MOUNTED_SERVICE" ] || not_ready mounted_service_missing
[ -f "$PRIVATE_CONFIG" ] || not_ready private_config_missing
cmp -s "$SOURCE_SERVICE" "$MOUNTED_SERVICE" || \
  not_ready mounted_service_mismatch

for lib in $COMPAT_LIBS; do
  source_lib="$MODDIR/system/vendor/lib64/pixaml/$lib"
  mounted_lib="$COMPAT_DIR/$lib"
  [ -f "$mounted_lib" ] || not_ready "mounted_compat_library_missing_$lib"
  cmp -s "$source_lib" "$mounted_lib" || \
    not_ready "mounted_compat_library_mismatch_$lib"
done

ls -lZ "$MOUNTED_SERVICE" "$PRIVATE_CONFIG" \
  "$COMPAT_DIR/android.hardware.audio.effect-V2-ndk.so" \
  "$COMPAT_DIR/android.hardware.audio.common-V3-ndk.so" \
  "$COMPAT_DIR/android.media.audio.common.types-V3-ndk.so" \
  >"$STATE_DIR/mounted-contexts.txt" 2>&1

# --list resolves DT_NEEDED without entering the service main function or
# registering Binder. If it fails, keep autostart blocked.
if ! LD_LIBRARY_PATH="$COMPAT_DIR" \
  /system/bin/linker64 --list "$MOUNTED_SERVICE" \
  >"$STATE_DIR/linker-list.txt" 2>&1; then
  not_ready linker_dependency_resolution_failed
fi

printf 'READY service=mounted config=private dependencies=resolved\n' \
  >"$STATUS"
exit 0
