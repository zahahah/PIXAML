#!/system/bin/sh
MODPATH=${0%/*}
exec 2>$MODPATH/service_debug.txt
set -x

if ! ps -e | grep -q "[v]endor.aml.effect-service"; then
	exec /vendor/bin/hw/vendor.aml.effect-service &
fi

AUD=$(find $MODPATH -type f -name "audio_effects_config.xml")
if [ ! -z "$AUD" ]; then
	MOUNTED=false
	for i in $AUD; do
	j="/vendor/etc/audio_effects_config.xml"
	if [ -f "$j" ] && ! cmp -s "$i" "$j"; then
	echo " -- Files $i and $j are different. Mounting modded file. -- "
		mount -o bind "$i" "$j"
		MOUNTED=true
	fi
	done

	if [ "$MOUNTED" = true ]; then
	killall -q audioserver
	fi
fi

set +x
#restarting service
while sleep 5; do
	if ! ps -e | grep -q "[v]endor.aml.effect-service"; then
		exec /vendor/bin/hw/vendor.aml.effect-service
	fi
done &