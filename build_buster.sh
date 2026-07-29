#!/bin/bash
# Build MULTI-DEVICE do so-loader do Stardew Valley (aarch64) no debian:buster
# -> glibc 2.28 (<= 2.30, piso do ArkOS/R36S). O build.sh do host usa a toolchain
# do NextOS e gera binario com glibc nova demais para os outros CFWs.
#
# Run (host):
#   SR=$(ls -d ~/NextOS-Elite-Edition/build*Amlogic-old*.aarch64*/toolchain/aarch64-libreelec-linux-gnu/sysroot | head -1)
#   docker run --rm -v "$PWD":/repo -v "$SR":/nxsr:ro gtactw-arm64-builder:debian-buster \
#     bash /repo/build_buster.sh
#
# SDL2/EGL/GLES e libpng sao resolvidos por dlsym no device; aqui entram so' os
# HEADERS (arch-neutros, vindos do sysroot NextOS) e stubs no link quando preciso.
set -e
CC=${CC:-aarch64-linux-gnu-gcc}
NM=${NM:-aarch64-linux-gnu-nm}
OD=${OD:-aarch64-linux-gnu-objdump}
NXSR=${NXSR:-/nxsr}
OUT=${OUT:-stardewvalley.multi}
cd "$(dirname "$0")"

echo "CC: $($CC --version | head -1)"

SRCS="src/main.c src/so_util.c src/jni_shim.c src/imports.gen.c \
      src/bionic_shims.c src/pthread_bridge.c src/sdv_egl_bridge.c \
      src/util.c src/error.c"

OBJDIR=$(mktemp -d); STUB=$(mktemp -d)
trap 'rm -rf "$OBJDIR" "$STUB"' EXIT

OBJS=""
for f in $SRCS; do
  o="$OBJDIR/$(basename "$f").o"
  # -idirafter: headers da glibc do buster ganham dos do NextOS; o sysroot so'
  # resolve SDL2/EGL/GLES/png, que o buster nao tem.
  $CC -D_GNU_SOURCE -include "$PWD/buster_compat.h" \
      -I src -idirafter "$NXSR/usr/include" \
      -O2 -fPIC -fno-omit-frame-pointer -rdynamic \
      -DPORT_WINDOW_TITLE='"Stardew Valley"' \
      -Wno-unused-parameter -Wno-unused-function \
      -c "$f" -o "$o"
  OBJS="$OBJS $o"
done

# stubs so' p/ simbolos de bibliotecas que vem do device (se sobrar algum undefined)
UND=$($NM --undefined-only $OBJS 2>/dev/null | awk '{print $NF}' | sort -u)
gen() { for s in $(echo "$UND" | grep -E "$1"); do echo "void $s(void){}"; done; }
LIBS="-ldl -lm -lpthread"
if echo "$UND" | grep -qE '^SDL_'; then
  gen '^SDL_' > "$STUB/sdl.c"
  $CC -shared -fPIC -nostdlib -Wl,-soname,libSDL2-2.0.so.0 "$STUB/sdl.c" -o "$STUB/libSDL2.so"
  LIBS="-L$STUB -lSDL2 $LIBS"
fi
if echo "$UND" | grep -qE '^png_'; then
  gen '^png_' > "$STUB/png.c"
  $CC -shared -fPIC -nostdlib -Wl,-soname,libpng16.so.16 "$STUB/png.c" -o "$STUB/libpng16.so"
  LIBS="-L$STUB -lpng16 $LIBS"
fi

$CC -O2 -fPIC -fno-omit-frame-pointer -rdynamic -o "$OUT" $OBJS $LIBS

MAXV=$($OD -T "$OUT" 2>/dev/null | grep -oE 'GLIBC_[0-9.]+' | sort -uV | tail -1)
echo "BUSTER BUILD OK -> $OUT | glibc max = $MAXV (regra: <= GLIBC_2.30)"
$OD -p "$OUT" 2>/dev/null | grep -i NEEDED || true
