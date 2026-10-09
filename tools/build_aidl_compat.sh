#!/bin/sh
# Rebuild the three frozen AIDL NDK compatibility libraries used by Stage C.
# Inputs are pinned AOSP API snapshots; no Pixel firmware binary is modified.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
SDK=${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}
BUILD_TOOLS=36.1.0
NDK_VERSION=28.2.13676358
HW_COMMIT=1a56e38edc2f2f6189ef405ee1edce554e15cbc0
SYS_HW_COMMIT=1b82105349a8af0824ad03f15b0b964dea62e031
NATIVE_COMMIT=4f463a6b1de9198963dc6aff74154a504ba3f8f6

[ -n "$SDK" ] || {
  echo "ANDROID_SDK_ROOT or ANDROID_HOME is required" >&2
  exit 1
}

AIDL="$SDK/build-tools/$BUILD_TOOLS/aidl"
NDK="$SDK/ndk/$NDK_VERSION"
[ -x "$AIDL" ] || { echo "missing $AIDL" >&2; exit 1; }
[ -d "$NDK" ] || { echo "missing $NDK" >&2; exit 1; }

PREBUILT=$(find "$NDK/toolchains/llvm/prebuilt" -mindepth 1 -maxdepth 1 \
  -type d | head -n 1)
CXX="$PREBUILT/bin/aarch64-linux-android35-clang++"
STRIP="$PREBUILT/bin/llvm-strip"
[ -x "$CXX" ] && [ -x "$STRIP" ] || {
  echo "required NDK tools not found" >&2
  exit 1
}

WORK=$(mktemp -d "${TMPDIR:-/tmp}/pixaml-aidl.XXXXXX")
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
SRC="$WORK/src"
GEN="$WORK/gen"
LIB="$WORK/lib"
mkdir -p "$SRC" "$GEN" "$LIB"

fetch_archive() {
  repo=$1
  commit=$2
  path=$3
  dest=$4
  mkdir -p "$dest"
  archive="$WORK/archive.tar.gz"
  curl -L --fail --silent --show-error --retry 5 --retry-all-errors \
    --retry-delay 2 \
    "https://android.googlesource.com/platform/$repo/+archive/$commit/$path.tar.gz" \
    -o "$archive"
  tar -xzf "$archive" -C "$dest"
  rm -f "$archive"
}

fetch_archive hardware/interfaces "$HW_COMMIT" \
  audio/aidl/aidl_api/android.hardware.audio.effect/2 "$SRC/effect2"
fetch_archive hardware/interfaces "$HW_COMMIT" \
  audio/aidl/aidl_api/android.hardware.audio.common/3 "$SRC/audio_common3"
fetch_archive hardware/interfaces "$HW_COMMIT" \
  common/aidl/aidl_api/android.hardware.common/2 "$SRC/common2"
fetch_archive hardware/interfaces "$HW_COMMIT" \
  common/fmq/aidl/aidl_api/android.hardware.common.fmq/1 "$SRC/fmq1"
fetch_archive system/hardware/interfaces "$SYS_HW_COMMIT" \
  media/aidl_api/android.media.audio.common.types/3 "$SRC/media_types3"

mkdir -p "$WORK/binder/include_cpp" "$WORK/binder/include_ndk" \
  "$WORK/binder/include_platform"
for headers in include_cpp include_ndk include_platform; do
  fetch_archive frameworks/native "$NATIVE_COMMIT" \
    "libs/binder/ndk/$headers" "$WORK/binder/$headers"
done

generate() {
  name=$1
  version=$2
  root=$3
  min_sdk=${4:-29}
  hash=$(head -n 1 "$root/.hash")
  out="$GEN/$name"
  mkdir -p "$out/cpp" "$out/include"
  "$AIDL" --lang=ndk --structured --stability=vintf \
    --version="$version" --hash="$hash" --min_sdk_version="$min_sdk" \
    --transaction_names \
    -I"$SRC/media_types3" -I"$SRC/common2" -I"$SRC/fmq1" \
    -I"$SRC/audio_common3" -I"$SRC/effect2" -N"$root" \
    -o "$out/cpp" -h "$out/include" \
    $(find "$root" -type f -name '*.aidl' | sort)
}

generate media_types3 3 "$SRC/media_types3"
generate common2 2 "$SRC/common2"
generate fmq1 1 "$SRC/fmq1"
generate audio_common3 3 "$SRC/audio_common3"
generate effect2 2 "$SRC/effect2" 31

# Android platform C++ uses std::__1. The NDK intentionally uses std::__ndk1,
# so build against a temporary header copy with the platform ABI namespace.
cp -R "$PREBUILT/sysroot/usr/include/c++/v1" "$WORK/libcxx-headers"
python3 - "$WORK/libcxx-headers/__config_site" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text()
old = "#define _LIBCPP_ABI_NAMESPACE __ndk1"
if old not in text:
    raise SystemExit("unexpected libc++ ABI namespace configuration")
path.write_text(text.replace(old, "#define _LIBCPP_ABI_NAMESPACE __1"))
PY

# A SONAME-only link stub records the real Android platform dependency
# libc++.so. The stub itself is not shipped.
cat >"$WORK/libcxx_stub.cpp" <<'EOF'
extern "C" void pixaml_libcxx_link_stub() {}
EOF
"$CXX" -shared -fPIC -O2 -nostdlib++ "$WORK/libcxx_stub.cpp" \
  -Wl,-soname,libc++.so -o "$LIB/libc++.so"

INCLUDES="-I$WORK/binder/include_cpp -I$WORK/binder/include_ndk -I$WORK/binder/include_platform"
for generated in media_types3 common2 fmq1 audio_common3 effect2; do
  INCLUDES="$INCLUDES -I$GEN/$generated/include"
done

build_library() {
  generated=$1
  soname=$2
  shift 2
  # shellcheck disable=SC2086
  "$CXX" -shared -fPIC -O2 -g0 -std=c++17 -nostdlib++ -nostdinc++ \
    -ffile-prefix-map="$WORK"=/pixaml-aidl \
    -I"$WORK/libcxx-headers" -Wl,-soname,"$soname" \
    -Wl,--build-id=sha1 $INCLUDES \
    $(find "$GEN/$generated/cpp" -type f -name '*.cpp' | sort) \
    -L"$LIB" -Wl,--no-as-needed -l:libc++.so -Wl,--as-needed \
    "$@" -lbinder_ndk -llog -o "$LIB/$soname"
}

build_library media_types3 android.media.audio.common.types-V3-ndk.so
build_library common2 android.hardware.common-V2-ndk.so
build_library fmq1 android.hardware.common.fmq-V1-ndk.so \
  -l:android.hardware.common-V2-ndk.so
build_library audio_common3 android.hardware.audio.common-V3-ndk.so \
  -l:android.media.audio.common.types-V3-ndk.so
build_library effect2 android.hardware.audio.effect-V2-ndk.so \
  -l:android.media.audio.common.types-V3-ndk.so \
  -l:android.hardware.audio.common-V3-ndk.so \
  -l:android.hardware.common-V2-ndk.so \
  -l:android.hardware.common.fmq-V1-ndk.so

DEST="$ROOT/system/vendor/lib64/pixaml"
mkdir -p "$DEST"
for library in \
  android.hardware.audio.effect-V2-ndk.so \
  android.hardware.audio.common-V3-ndk.so \
  android.media.audio.common.types-V3-ndk.so; do
  "$STRIP" --strip-unneeded "$LIB/$library"
  cp "$LIB/$library" "$DEST/$library"
  chmod 0644 "$DEST/$library"
done

sha256sum "$DEST"/*.so 2>/dev/null || shasum -a 256 "$DEST"/*.so
