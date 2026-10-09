#!/system/bin/sh
MOD_SYS="$MODPATH/system"

if [ -d "$MODPATH/vendor" ] && [ ! -L "$MODPATH/vendor" ]; then
	MOD_VENDOR="$MODPATH/vendor"
else
	MOD_VENDOR="$MODPATH/system/vendor"
fi

if [ -d "$MOD_SYS" ]; then
	find "$MOD_SYS" -type d -exec chmod 755 {} +
	find "$MOD_SYS" -type f -exec chmod 644 {} +

	chown -R root:root "$MOD_SYS"
	chcon -R u:object_r:system_file:s0 "$MOD_SYS"
fi

if [ -d "$MOD_VENDOR" ]; then
	find "$MOD_VENDOR" -type d -exec chmod 755 {} +
	find "$MOD_VENDOR" -type f -exec chmod 644 {} +

	chown -R root:root "$MOD_VENDOR"
	chcon -R u:object_r:vendor_file:s0 "$MOD_VENDOR"

	if [ -d "$MOD_VENDOR/etc" ]; then
		chown -R root:shell "$MOD_VENDOR/etc"
		chcon -R u:object_r:vendor_configs_file:s0 "$MOD_VENDOR/etc"
	fi

	if [ -d "$MOD_VENDOR/bin" ]; then
		find "$MOD_VENDOR/bin" -type f -exec chmod 755 {} +
		chcon -R u:object_r:vendor_file:s0 "$MOD_VENDOR/bin"
	fi
fi

MOD_LIBAUDIOHAL="$MOD_SYS/lib64/libaudiohal@aidl.so"
SYS_LIBAUDIOHAL="/system/lib64/libaudiohal@aidl.so"

if [ -f "$SYS_LIBAUDIOHAL" ] && [ -n "$MOD_LIBAUDIOHAL" ]; then
	chcon --reference "$SYS_LIBAUDIOHAL" "$MOD_LIBAUDIOHAL"
fi