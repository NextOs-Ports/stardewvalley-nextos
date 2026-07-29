#!/bin/bash
# Monta o pacote instalavel do Stardew Valley (NextOS).
#
# O zip extrai DIRETO na raiz de roms do aparelho (/roms ou /storage/roms) e ja'
# cai no lugar certo:
#
#   ports/Stardew Valley (NextOS).sh          <- ArkOS/ROCKNIX/PortMaster leem daqui
#   ports/sdvnextos/...                       <- o port
#   ports_scripts/Stardew Valley (NextOS).sh  <- o ES do EmuELEC/NextOS le' DAQUI
#
# Os dois launchers sao COPIAS completas (o ES nao regenera um do outro).
#
# BYO-DATA: nao vai um byte de dado de jogo aqui dentro — nem APK, nem assets,
# nem as libs nativas. O usuario poe o APK dele e o port extrai na 1a execucao.
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
PORT="$(cd "$HERE/.." && pwd)"
OUT="${1:-$HERE/dist}"
STAGE="$OUT/stage"
LAUNCHER="Stardew Valley (NextOS).sh"
ZIP="$OUT/Stardew Valley (NextOS).zip"

rm -rf "$STAGE" "$ZIP"
mkdir -p "$STAGE/ports/sdvnextos/tools" "$STAGE/ports_scripts" "$STAGE/fonte"

# --- o port ------------------------------------------------------------------
cp "$PORT/stardewvalley.multi" "$STAGE/ports/sdvnextos/"
cp "$PORT/stardewvalley"       "$STAGE/ports/sdvnextos/"   # build NextOS, alternativa
cp "$PORT/arkos/alsoft.conf"   "$STAGE/ports/sdvnextos/"
cp "$PORT/tools/stardew_extract.sh" "$STAGE/ports/sdvnextos/tools/"
cp "$PORT/INSTALAR.md"         "$STAGE/ports/sdvnextos/"

# --- launcher nos DOIS lugares ----------------------------------------------
cp "$PORT/arkos/$LAUNCHER" "$STAGE/ports/$LAUNCHER"
cp "$PORT/arkos/$LAUNCHER" "$STAGE/ports_scripts/$LAUNCHER"
chmod +x "$STAGE/ports/$LAUNCHER" "$STAGE/ports_scripts/$LAUNCHER" \
         "$STAGE/ports/sdvnextos/stardewvalley.multi" \
         "$STAGE/ports/sdvnextos/stardewvalley" \
         "$STAGE/ports/sdvnextos/tools/stardew_extract.sh"

# --- fonte, pra quem quiser compilar ----------------------------------------
cp -r "$PORT/src" "$STAGE/fonte/"
cp "$PORT/build_buster.sh" "$PORT/build.sh" "$PORT/buster_compat.h" "$STAGE/fonte/"
cp "$PORT/README.md" "$STAGE/fonte/README-dev.md"
[ -f "$PORT/HANDOFF.md" ] && cp "$PORT/HANDOFF.md" "$STAGE/fonte/"

# --- leia-me na raiz do zip --------------------------------------------------
cp "$HERE/LEIA-ME.md" "$STAGE/LEIA-ME.md"

# --- zipa --------------------------------------------------------------------
( cd "$STAGE" && zip -rq "$ZIP" . )
rm -rf "$STAGE"

# --- conferencia obrigatoria: nenhum dado de jogo ----------------------------
if unzip -l "$ZIP" | grep -qiE '\.apk$|\.obb$|/assets/|/libs/|_apk_extract'; then
  echo "ERRO: o pacote levou dado de jogo. Abortado."
  exit 1
fi
echo "OK -> $ZIP  ($(du -h "$ZIP" | cut -f1))"
unzip -l "$ZIP" | tail -n +4 | head -20
