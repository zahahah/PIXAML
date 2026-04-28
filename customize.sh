AIDLCHECK=$(find /vendor/lib64/soundfx /odm/lib64/soundfx /system/lib64/soundfx -type f -name *aidl.so)
if [ -z "$AIDLCHECK" ]; then
  ui_print " -- AIDL audiofx not found -- "
  ui_print " -- Abort installation -- "
  exit 1
fi

SKIPUNZIP=1
#creating folders, unzipping files in proper places and giving proper permissions to created folders
unzip -qo "$ZIPFILE" -x 'META-INF/*' 'customize.sh' -d $MODPATH >&2
. $MODPATH/patch.sh

echo " "
echo " "
echo " -- Big thanks to @Shiftr182, @ratelutz, @BlackBurds, @felek73 and other super hepful people -- "
echo " -- for tests and patience -- "