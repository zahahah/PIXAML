#!/system/bin/sh

MODDIR=${0%/*}

mkdir -p "$MODDIR/state"

# KernelSU Next invokes this in late-load (Jailbreak Mode) instead of
# post-fs-data.sh. It is still a pre-mount stage, so it only validates the
# source tree. post-mount.sh and service.sh run later in both lifecycles.
{
  printf 'KSU_LATE_LOAD=%s\n' "${KSU_LATE_LOAD:-unset}"
  printf 'KSU_RUNTIME_MODE=%s\n' "${KSU_RUNTIME_MODE:-unset}"
  "$MODDIR/pre-mount.sh" late-load
} >"$MODDIR/state/late-load.log" 2>&1 || :

exit 0
