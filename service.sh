#!/system/bin/sh

MODDIR=${0%/*}
STATE_DIR="$MODDIR/state"
OPTIONS="$MODDIR/options.conf"
SERVICE=/vendor/bin/hw/vendor.aml.effect-service
CONFIG="$MODDIR/config/audio_effects_config.xml"
COMPAT_DIR=/vendor/lib64/pixaml
LOG="$STATE_DIR/service.log"
STATUS="$STATE_DIR/service.status"
DEFAULT_FACTORY=android.hardware.audio.effect.IFactory/default
AML_FACTORY=android.hardware.audio.effect.IFactory/aml

mkdir -p "$STATE_DIR"

if ! grep -qx 'PIXAML_SERVICE_AUTOSTART=1' "$OPTIONS" 2>/dev/null; then
  printf 'DISABLED option=PIXAML_SERVICE_AUTOSTART\n' >"$STATUS"
  exit 0
fi

if ! grep -qx 'READY service=mounted config=private dependencies=resolved' \
  "$STATE_DIR/post-mount.status" 2>/dev/null; then
  printf 'BLOCKED reason=post_mount_not_ready\n' >"$STATUS"
  exit 0
fi

if pidof vendor.aml.effect-service >/dev/null 2>&1; then
  if service check "$AML_FACTORY" 2>/dev/null | grep -q ': found'; then
      printf 'REGISTERED reason=already_started pid=%s audio_reload=disabled\n' \
        "$(pidof vendor.aml.effect-service)" >"$STATUS"
  else
    printf 'RUNNING reason=already_started binder=pending\n' >"$STATUS"
  fi
  exit 0
fi

waited=0
while [ "$waited" -lt 30 ]; do
  if service check "$DEFAULT_FACTORY" 2>/dev/null | grep -q ': found'; then
    break
  fi
  waited=$((waited + 1))
  sleep 1
done

if [ "$waited" -ge 30 ]; then
  printf 'BLOCKED reason=default_factory_timeout\n' >"$STATUS"
  exit 0
fi

: >"$LOG"
{
  printf 'starting mode=%s late_load=%s context=%s\n' \
    "${KSU_RUNTIME_MODE:-unknown}" "${KSU_LATE_LOAD:-0}" \
    "$(id -Z 2>/dev/null || echo unknown)"
} >>"$LOG"

LD_LIBRARY_PATH="$COMPAT_DIR" \
  "$SERVICE" "$CONFIG" >>"$LOG" 2>&1 &

pid=$!
printf '%s\n' "$pid" >"$STATE_DIR/service.pid"

waited=0
while [ "$waited" -lt 15 ]; do
  if service check "$AML_FACTORY" 2>/dev/null | grep -q ': found'; then
    printf 'REGISTERED pid=%s monitor=disabled hook=disabled audio_reload=disabled\n' \
      "$pid" >"$STATUS"
    ps -AZ 2>/dev/null | grep '[v]endor.aml.effect-service' \
      >"$STATE_DIR/service-context.txt" 2>&1 || :
    exit 0
  fi
  if ! kill -0 "$pid" 2>/dev/null; then
    wait "$pid"
    exit_code=$?
    printf 'EXITED before_binder_registration code=%s inspect=%s\n' \
      "$exit_code" "$LOG" >"$STATUS"
    exit 0
  fi
  waited=$((waited + 1))
  sleep 1
done

printf 'BLOCKED reason=binder_registration_timeout pid=%s inspect=%s\n' \
  "$pid" "$LOG" >"$STATUS"

# Fail closed: if the process did not publish its Binder endpoint, do not
# leave it running. Send one best-effort SIGTERM; never loop or restart.
if kill -0 "$pid" 2>/dev/null; then
  kill "$pid" 2>/dev/null || :
fi

exit 0
