#!/system/bin/sh

# Keep this compatibility entry point, but do not touch global audio state.
# A module-side HAL/audioserver restart is not a validated way to refresh
# late-loaded effects on this firmware.
MODDIR=${0%/*}
STATE_DIR=${PIXAML_STATE_DIR:-"$MODDIR/state"}
mkdir -p "$STATE_DIR"
printf 'SKIPPED reason=unsafe_audio_restart_disabled\n' \
  >"$STATE_DIR/audio-reload.status"
exit 0
