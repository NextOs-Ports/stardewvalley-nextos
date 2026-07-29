#!/bin/bash
# build.sh -- Stardew Valley Mono so-loader (host NextOS toolchain, iteracao rapida)
# Release glibc<=2.30 via build_buster.sh (depois).
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

TC=~/NextOS-Elite-Edition/build.NextOS-Retro-Elite-Edition-Amlogic-old.aarch64-4/toolchain
CC=$TC/bin/aarch64-libreelec-linux-gnu-gcc
SR=$TC/aarch64-libreelec-linux-gnu/sysroot

# Loader Mono + ponte SDL/EGL minima (SDL resolvido via dlsym no device).
SRCS="src/main.c src/so_util.c src/jni_shim.c src/imports.gen.c \
      src/bionic_shims.c src/pthread_bridge.c src/sdv_egl_bridge.c \
      src/util.c src/error.c"

$CC --sysroot="$SR" -I src -O2 -fPIC -fno-omit-frame-pointer -rdynamic \
    -DPORT_WINDOW_TITLE='"Stardew Valley"' \
    -Wno-unused-parameter -Wno-unused-function \
    -o stardewvalley $SRCS \
    -ldl -lm -lpthread

echo "OK: $HERE/stardewvalley"
$TC/bin/aarch64-libreelec-linux-gnu-objdump -p stardewvalley 2>/dev/null | \
  grep NEEDED || true
