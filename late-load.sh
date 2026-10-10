#!/system/bin/sh

MODDIR=${0%/*}

mkdir -p "$MODDIR/state"

# KernelSU Next runs this in late-load/Jailbreak Mode instead of
# post-fs-data.sh. The /vendor overlay is not ready yet, so this stage only
# validates the source tree. post-mount.sh and service.sh run later.
{
  printf 'KSU_LATE_LOAD=%s\n' "${KSU_LATE_LOAD:-unset}"
  printf 'KSU_RUNTIME_MODE=%s\n' "${KSU_RUNTIME_MODE:-unset}"
  "$MODDIR/pre-mount.sh" late-load
} >"$MODDIR/state/late-load.log" 2>&1 || :

exit 0
