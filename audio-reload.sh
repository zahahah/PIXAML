#!/system/bin/sh

# Retained as a safe compatibility entry point for existing installations.
# Restarting the default audio HAL from a module can trigger init recovery and
# is not a validated way to make late-loaded effects visible to the framework.
MODDIR=${0%/*}
STATE_DIR=${PIXAML_STATE_DIR:-"$MODDIR/state"}
mkdir -p "$STATE_DIR"
printf 'SKIPPED reason=unsafe_audio_restart_disabled\n' \
  >"$STATE_DIR/audio-reload.status"
exit 0
