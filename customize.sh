# The KernelSU/Magisk installer sources this after extracting the ZIP. Keep
# system/vendor as the real module directory; the generic KernelSU handler
# would move it to vendor/ and create the layout Magic Mount-rs rejects.
handle_partition() {
  return 0
}

fail_install() {
  if command -v abort >/dev/null 2>&1; then
    abort "$1"
  fi
  ui_print "$1"
  exit 1
}

ui_print "- Installing PIXAML standalone AML service"

[ -d "$MODPATH/system/vendor" ] || \
  fail_install "! Missing real system/vendor directory"
[ ! -L "$MODPATH/system/vendor" ] || \
  fail_install "! Refusing system/vendor symlink layout"
[ ! -e "$MODPATH/system/lib64/libaudiohal@aidl.so" ] || \
  fail_install "! Refusing automatic libaudiohal@aidl.so activation"
[ -f "$MODPATH/system/vendor/bin/hw/vendor.aml.effect-service" ] || \
  fail_install "! Missing AML service payload"
[ -f "$MODPATH/config/audio_effects_config.xml" ] || \
  fail_install "! Missing AML configuration payload"
[ -f "$MODPATH/staging/hook/aml.so" ] || \
  fail_install "! Missing disabled AML hook payload"
[ -f "$MODPATH/options.conf" ] || \
  fail_install "! Missing service options"
[ -f "$MODPATH/audio-reload.sh" ] || \
  fail_install "! Missing disabled audio-reload compatibility entry point"
[ ! -e "$MODPATH/system/vendor/etc/audio_effects_config.xml" ] || \
  fail_install "! Refusing to mount audio_effects_config.xml over vendor"
[ -f "$MODPATH/compat-manifest.txt" ] || \
  fail_install "! Missing AIDL compatibility manifest"

COMPAT_LIBS="
android.hardware.audio.effect-V2-ndk.so
android.hardware.audio.common-V3-ndk.so
android.media.audio.common.types-V3-ndk.so
"

for lib in $COMPAT_LIBS; do
  [ -f "$MODPATH/system/vendor/lib64/pixaml/$lib" ] || \
    fail_install "! Missing frozen AIDL compatibility library: $lib"
done

set_perm_recursive "$MODPATH/system/vendor" 0 0 0755 0644 \
  u:object_r:vendor_file:s0
set_perm "$MODPATH/system/vendor/bin/hw/vendor.aml.effect-service" \
  0 2000 0755 u:object_r:vendor_file:s0
set_perm "$MODPATH/config/audio_effects_config.xml" \
  0 0 0644 u:object_r:vendor_configs_file:s0
for lib in $COMPAT_LIBS; do
  set_perm "$MODPATH/system/vendor/lib64/pixaml/$lib" \
    0 0 0644 u:object_r:vendor_file:s0
done

for script in pre-mount.sh post-fs-data.sh late-load.sh post-mount.sh \
  service.sh audio-reload.sh validate-service.sh; do
  [ -f "$MODPATH/$script" ] && chmod 0755 "$MODPATH/$script"
done

chmod 0644 "$MODPATH/options.conf" "$MODPATH/compat-manifest.txt" \
  "$MODPATH/config/audio_effects_config.xml" "$MODPATH/staging/hook/aml.so"
chown 0:0 "$MODPATH/options.conf" "$MODPATH/compat-manifest.txt" \
  "$MODPATH/config/audio_effects_config.xml" "$MODPATH/staging/hook/aml.so"

mkdir -p "$MODPATH/state"
chmod 0700 "$MODPATH/state"
chown 0:0 "$MODPATH/state"

# Clear a stale fail-closed marker from an earlier attempt. A clean install
# should make its own mount decision.
rm -f "$MODPATH/skip_mount"

ui_print "- system/vendor preserved as a real directory"
ui_print "- Frozen AIDL V2/V3 libraries installed systemlessly"
ui_print "- Standalone AML service uses module-private config"
ui_print "- Late-load keeps firmware audio HAL/audioserver untouched"
ui_print "- libaudiohal@aidl.so is not generated or mounted"
