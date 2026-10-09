#!/system/bin/sh
if [ -d /data/adb/modules/aml ]; then
	MODPATH=/data/adb/modules/aml
fi
# Define variables
MODSAML="$(find /data/adb/modules -not -path "/data/adb/modules/sv_apixaml/*" -type f \( -name aml.sh -o -name .aml.sh \))"
CFGFILE=/vendor/etc/audio_effects_config.xml

# Metamodule catalog structure check
if [ -d "$MODPATH/vendor" ] && [ ! -L "$MODPATH/vendor" ]; then
	MOD_VENDOR="$MODPATH/vendor"
else
	MOD_VENDOR="$MODPATH/system/vendor"
fi

MODCFGFILE="$MOD_VENDOR/etc/audio_effects_config.xml"
if [ ! -f $CFGFILE ] && [ ! -f $MODCFGFILE ]; then

	mkdir -p $(dirname $MODCFGFILE)
	chmod 0755 $(dirname $MODCFGFILE)
	chown root:shell $(dirname $MODCFGFILE)
	touch $MODCFGFILE
	cat << EOF > $MODCFGFILE
<?xml version="1.0" encoding="UTF-8"?>
<audio_effects_conf version="2.0" xmlns="http://schemas.android.com/audio/audio_effects_conf/v2_0">
	<libraries>
	</libraries>
	<effects>
	</effects>
</audio_effects_conf>
EOF
fi

chmod 0644 $MODCFGFILE
chown root:root $MODCFGFILE

chcon u:object_r:vendor_configs_file:s0 $MODCFGFILE

# Patch v4a if exist
if [ "$MODPATH" != "/data/adb/modules/aml" ]; then
	V4A=$(find /data/adb/modules -type d -name "ViPER4Android-RE")
  V4A2=$(find /data/adb/modules -type d -name "ViPER4Android-RE-AIDL")
	if [ -n  "$V4A" ] || [ -n "$V4A2" ];then
	. "$MODPATH/v4a.sh"
	fi
fi

# Source found scripts
if [ ! -z "$MODSAML" ]; then
	for MODS in ${MODSAML}; do
		chmod 755 "$MODS"
		[ -f "$MODS" ] && . "$MODS"
	done &
fi