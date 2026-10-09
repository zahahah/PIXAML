#!/system/bin/sh

MODDIR=${0%/*}
SERVICE=/vendor/bin/hw/vendor.aml.effect-service
CONFIG="$MODDIR/config/audio_effects_config.xml"
COMPAT_DIR=/vendor/lib64/pixaml

printf '%s\n' '== PIXAML service validation (read-only) =='
printf 'runtime_mode=%s late_load=%s\n' \
  "${KSU_RUNTIME_MODE:-unknown}" "${KSU_LATE_LOAD:-0}"

printf '%s\n' '-- module layout --'
ls -ld "$MODDIR/system/vendor"

printf '%s\n' '-- mounted payload contexts --'
ls -lZ "$SERVICE" "$MODDIR/config/audio_effects_config.xml" \
  "$COMPAT_DIR/android.hardware.audio.effect-V2-ndk.so" \
  "$COMPAT_DIR/android.hardware.audio.common-V3-ndk.so" \
  "$COMPAT_DIR/android.media.audio.common.types-V3-ndk.so"

printf '%s\n' '-- dynamic dependency resolution --'
LD_LIBRARY_PATH="$COMPAT_DIR" /system/bin/linker64 --list "$SERVICE"

printf '%s\n' '-- relevant PID 1 mounts --'
grep -E 'vendor\.aml\.effect-service|/vendor/lib64/pixaml' \
  /proc/1/mountinfo 2>/dev/null || :

printf '%s\n' '-- Binder factories --'
service check android.hardware.audio.effect.IFactory/default
service check android.hardware.audio.effect.IFactory/aml

printf '%s\n' '-- AML process --'
pidof vendor.aml.effect-service 2>/dev/null || printf '%s\n' 'not running'
ps -AZ 2>/dev/null | grep '[v]endor.aml.effect-service' || :

printf '%s\n' '-- recorded lifecycle state --'
cat "$MODDIR/state/pre-mount.status" 2>/dev/null
cat "$MODDIR/state/post-mount.status" 2>/dev/null
cat "$MODDIR/state/service.status" 2>/dev/null
cat "$MODDIR/state/audio-reload.status" 2>/dev/null

printf '%s\n' '-- JamesDSP in live default factory --'
/system/bin/dumpsys android.hardware.audio.effect.IFactory/default 2>/dev/null | \
  grep -iE 'Effects \(|Created effects|james|jdsp|f27317f4|f98765f4' || :

printf '%s\n' '-- recent AML / SELinux evidence --'
logcat -b all -d -v brief 2>/dev/null | \
  grep -E 'AHAL_Effect|vendor\.aml\.effect-service|avc:.*(aml|service_manager)' | \
  tail -n 80 || :
