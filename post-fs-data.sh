#!/system/bin/sh

MODDIR=${0%/*}

mkdir -p "$MODDIR/state"

# Standard boot path: validate before the metamodule mount stage. Do not
# start the service here; /vendor has not been overlaid yet.
"$MODDIR/pre-mount.sh" post-fs-data \
  >"$MODDIR/state/post-fs-data.log" 2>&1 || :

exit 0
