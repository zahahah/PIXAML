#!/system/bin/sh
MODPATH=${0%/*}
exec 2>$MODPATH/post.txt
set -x

chmod 755 $MODPATH/patch.sh
. $MODPATH/patch.sh
chmod 755 $MODPATH/permissions.sh
. $MODPATH/permissions.sh
chmod 755 $MODPATH/sepolicy.rule

exec /vendor/bin/hw/vendor.aml.effect-service & 2>/dev/null
