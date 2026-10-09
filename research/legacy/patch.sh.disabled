#!/system/bin/sh
exec 2>"$MODPATH/debug.txt"
set -x

# Paths
MOD_SYS="$MODPATH/system"
MOD_LIB64="$MOD_SYS/lib64"

# Metamodule catalog structure check
if [ -d "$MODPATH/vendor" ] && [ ! -L "$MODPATH/vendor" ]; then
	MOD_VENDOR="$MODPATH/vendor"
else
	MOD_VENDOR="$MODPATH/system/vendor"
fi
# Paths - continue
MOD_VEN_LIB64="$MOD_VENDOR/lib64"
MOD_VEN_BIN="$MOD_VENDOR/bin/hw"
MOD_VEN_ETC="$MOD_VENDOR/etc"
LIBAUDIOHAL="/system/lib64/libaudiohal@aidl.so"
PATCHELF="$MODPATH/patchelf"

[ -f "$PATCHELF" ] && chmod 0755 "$PATCHELF"

# Function for installing file and set permissions
install_file() {
	local src="$1"
	local dest="$2"
	local perm="$3"
	local owner="$4"
	local context="$5"

	mkdir -p "$(dirname "$dest")"

	if [ -f "$src" ]; then
		cp -f "$src" "$dest"
		chmod "$perm" "$dest"
		chown "$owner" "$dest"
		chcon "$context" "$dest" 2>/dev/null
	else
		echo " -- Source file not found: $src -- " >&2
	fi
}

# Creating catalogs (if needed)
mkdir -p "$MOD_LIB64" "$MOD_VEN_LIB64" "$MOD_VEN_BIN" "$MOD_VEN_ETC"

# Source .aml.sh if exists
chmod 755 $MODPATH/aml.sh
. "$MODPATH/aml.sh"

# Checking if any aml.so is missing. If so, copy it to every location, just in case
if [ ! -f "$MOD_LIB64/aml.so" ] || [ ! -f "$MOD_VEN_LIB64/aml.so" ] || [ ! -f "$MODPATH/aml.so" ]; then
	AML_SRC="$MODPATH/files/aml.so"
	install_file "$AML_SRC" "$MOD_LIB64/aml.so" "644" "0:0" "u:object_r:system_file:s0"
	install_file "$AML_SRC" "$MOD_VEN_LIB64/aml.so" "644" "0:0" "u:object_r:vendor_file:s0"
	install_file "$AML_SRC" "$MODPATH/aml.so" "644" "0:0" "u:object_r:system_file:s0"
fi

# Copying service
SVC_SRC="$MODPATH/files/vendor.aml.effect-service"
SVC_DEST="$MOD_VEN_BIN/vendor.aml.effect-service"

# Copying AML service IF not exist
if [ ! -f "$SVC_DEST" ]; then
	install_file "$SVC_SRC" "$SVC_DEST" "755" "0:2000" "u:object_r:vendor_file:s0"
fi

# Copying and patching libaudiohal on the fly.
# This approach save from bootloop after OTA
# Google might bump dependency version and... bootloop if good file is not there
MOD_LIBAUDIOHAL="$MOD_LIB64/libaudiohal@aidl.so"

if [ -f "$LIBAUDIOHAL" ]; then
	install_file "$LIBAUDIOHAL" "$MOD_LIBAUDIOHAL" "644" "0:0" "u:object_r:system_lib_file:s0"
	chcon --reference="$LIBAUDIOHAL" "$MOD_LIBAUDIOHAL"

	"$PATCHELF" --add-needed aml.so "$MOD_LIBAUDIOHAL"
	"$PATCHELF" --clear-symbol-version AServiceManager_waitForService "$MOD_LIBAUDIOHAL"

	if [ -f "$MODPATH/aml_map.txt" ]; then
		"$PATCHELF" --rename-dynamic-symbols "$MODPATH/aml_map.txt" "$MOD_LIBAUDIOHAL"
	fi
fi

# Patching service needed dependency
LIBS_TO_CHECK="android.media.audio.common.types android.hardware.audio.common android.hardware.audio.effect"

# Function for search system file (used in dependency patch)
find_sys_lib() {
	find /system/lib64 /apex/*/lib64 /vendor/lib64 -name "$1-V*-ndk.so" 2>/dev/null | sort | tail -n 1
}

for LIB_NAME in $LIBS_TO_CHECK; do
	CURRENT_NEEDED=$("$PATCHELF" --print-needed "$SVC_DEST" 2>/dev/null | grep "$LIB_NAME" | head -n 1)

	SYSTEM_LIB_PATH=$(find_sys_lib "$LIB_NAME")

	if [ -n "$SYSTEM_LIB_PATH" ]; then
		SYSTEM_LIB_NAME=$(basename "$SYSTEM_LIB_PATH")

		if [ -n "$CURRENT_NEEDED" ] && [ "$CURRENT_NEEDED" != "$SYSTEM_LIB_NAME" ]; then
			"$PATCHELF" --replace-needed "$CURRENT_NEEDED" "$SYSTEM_LIB_NAME" "$SVC_DEST"
			echo " -- Patched $LIB_NAME: $CURRENT_NEEDED -> $SYSTEM_LIB_NAME -- "
		fi

		DEST_LIB="$MOD_VEN_LIB64/$SYSTEM_LIB_NAME"
		if [ ! -f "/vendor/lib64/$SYSTEM_LIB_NAME" ] && [ ! -f "$DEST_LIB" ]; then
			install_file "$SYSTEM_LIB_PATH" "$DEST_LIB" "644" "0:0" "u:object_r:vendor_file:s0"
			echo " -- Copied System Lib: $SYSTEM_LIB_NAME -- "
		fi
	fi
done

# V4A/JDSP trick 
# Copy and rename newest native dependency files
# This will trick V4A and JDSP libs to recognize them and work
EFF_LIB_NAME="android.hardware.audio.effect"
EFF_TYPE_LIB_NAME="android.media.audio.common.types"
AUD_EFF_LIB=$(find_sys_lib "$EFF_LIB_NAME")
AUD_TYPE_EFF_LIB=$(find_sys_lib "$EFF_TYPE_LIB_NAME")

if [ -n "$AUD_EFF_LIB" ]; then
	[ ! -f "$MOD_VEN_LIB64/${EFF_LIB_NAME}-V2-ndk.so" ] && install_file "$AUD_EFF_LIB" "$MOD_VEN_LIB64/${EFF_LIB_NAME}-V2-ndk.so" "644" "0:0" "u:object_r:vendor_file:s0"
	[ ! -f "$MOD_VEN_LIB64/${EFF_LIB_NAME}-V3-ndk.so" ] && install_file "$AUD_EFF_LIB" "$MOD_VEN_LIB64/${EFF_LIB_NAME}-V3-ndk.so" "644" "0:0" "u:object_r:vendor_file:s0"
fi

if [ -n "$AUD_TYPE_EFF_LIB" ]; then
	[ ! -f "$MOD_VEN_LIB64/${EFF_TYPE_LIB_NAME}-V3-ndk.so" ] && install_file "$AUD_TYPE_EFF_LIB" "$MOD_VEN_LIB64/${EFF_TYPE_LIB_NAME}-V3-ndk.so" "644" "0:0" "u:object_r:vendor_file:s0"
fi

chcon -R u:object_r:system_file:s0 "$MOD_SYS" 2>/dev/null
chcon -R u:object_r:vendor_file:s0 "$MOD_VENDOR" 2>/dev/null
chcon -R u:object_r:vendor_configs_file:s0 "$MOD_VEN_ETC" 2>/dev/null

find "$MOD_SYS" "$MOD_VENDOR" -type d -exec chmod 755 {} + 2>/dev/null