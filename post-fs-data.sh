#!/system/bin/sh

MODDIR=${0%/*}

mkdir -p "$MODDIR/state"

# Standard boot: validate the module before the metamodule mount stage. Never
# start the service here because /vendor has not been overlaid yet.
"$MODDIR/pre-mount.sh" post-fs-data \
  >"$MODDIR/state/post-fs-data.log" 2>&1 || :

exit 0
