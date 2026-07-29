#!/bin/bash
# PORTMASTER: stardewvalley.zip, Stardew Valley (NextOS).sh
#
# Stardew Valley Android (Mono/.NET 8 AOT + MonoGame) por so-loader proprio.
# BYO-DATA: requer o APK do jogo (sua copia legal) — ver tools/stardew_extract.sh.
#
# O launcher e' curto de proposito: quem negocia resolucao, versao de GLES,
# formato do backbuffer e os caminhos de assets/libs/saves e' o BINARIO
# (ver suportando_outros_devices/). Aqui fica so' o que e' do frontend.

PORTNAME="Stardew Valley (NextOS)"
XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"

if [ -d "/opt/system/Tools/PortMaster" ]; then
  controlfolder="/opt/system/Tools/PortMaster"
elif [ -d "/opt/tools/PortMaster" ]; then
  controlfolder="/opt/tools/PortMaster"
elif [ -d "$XDG_DATA_HOME/PortMaster" ]; then
  controlfolder="$XDG_DATA_HOME/PortMaster"
else
  controlfolder="/roms/ports/PortMaster"
fi

[ -f "$controlfolder/control.txt" ] && source "$controlfolder/control.txt"
[ -f "$controlfolder/mod_${CFW_NAME:-}.txt" ] \
  && source "$controlfolder/mod_${CFW_NAME}.txt"
command -v get_controls >/dev/null 2>&1 && get_controls

# Acha a pasta do port entre os nomes conhecidos. `sdvnextos` e' o nome novo;
# `stardewvalley` e' onde mora quem instalou a versao anterior — assim o pacote
# aproveita os dados (e os saves) de quem ja tinha o port, sem copiar nada.
SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" 2>/dev/null && pwd -P)"
directory="${directory:-roms}"
GAMEDIR=""
for candidate in "$SCRIPT_DIR/sdvnextos" "/${directory#/}/ports/sdvnextos" \
                 /roms/ports/sdvnextos /storage/roms/ports/sdvnextos \
                 "$SCRIPT_DIR/stardewvalley" "/${directory#/}/ports/stardewvalley" \
                 /roms/ports/stardewvalley /storage/roms/ports/stardewvalley; do
  if [ -f "$candidate/stardewvalley.multi" ] || [ -f "$candidate/stardewvalley" ]; then
    GAMEDIR="$candidate"
    break
  fi
done
[ -n "$GAMEDIR" ] || GAMEDIR="/${directory#/}/ports/sdvnextos"
mkdir -p "$GAMEDIR" 2>/dev/null
cd "$GAMEDIR" || exit 1
[ -s "$GAMEDIR/debug.log" ] && mv -f "$GAMEDIR/debug.log" "$GAMEDIR/debug.prev.log"
exec > "$GAMEDIR/debug.log" 2>&1

chmod +x "$GAMEDIR/stardewvalley.multi" "$GAMEDIR/tools/stardew_extract.sh" 2>/dev/null

# 1a execucao: extrai os dados do APK (BYO-DATA).
if [ ! -f "$GAMEDIR/libs/libmonosgen-2.0.so" ] || [ ! -d "$GAMEDIR/assets/Content" ]; then
  bash "$GAMEDIR/tools/stardew_extract.sh" "$GAMEDIR" || { sleep 10; exit 1; }
fi

# Uma instancia so' — por /proc/*/exe, que pega binario trocado a quente.
for p in /proc/[0-9]*/exe; do
  case "$(readlink "$p" 2>/dev/null)" in
    */ports/sdvnextos/stardewvalley*|*/ports/stardewvalley/stardewvalley*)
      kill -9 "$(basename "$(dirname "$p")")" 2>/dev/null ;;
  esac
done

# Firmware primeiro; no RK3326 a libmali que casa com o kernel mora em
# /usr/local (a de /usr/lib e' antiga e o contexto GL nem sobe).
export LD_LIBRARY_PATH="/usr/local/lib/aarch64-linux-gnu:/usr/local/lib:/usr/lib:$GAMEDIR:${LD_LIBRARY_PATH:-}:/usr/lib/aarch64-linux-gnu:/lib/aarch64-linux-gnu:$controlfolder/libs:$controlfolder/libs.aarch64:$GAMEDIR/libs"

export HOME="$GAMEDIR"
[ -f "$GAMEDIR/alsoft.conf" ] && export ALSOFT_CONF="$GAMEDIR/alsoft.conf"
export SDL_GAMECONTROLLER_USE_BUTTON_LABELS=0
[ -n "${sdl_controllerconfig:-}" ] && export SDL_GAMECONTROLLERCONFIG="$sdl_controllerconfig"

# Escapes de bisseccao num device novo (todos default-OFF; ver INSTALAR.md):
#   SDV_TILES_X / SDV_DPI ....... enquadramento da camera
#   SDV_WIDTH / SDV_HEIGHT ...... crava a resolucao
#   SDV_NO_FORCE_GLES=1 ......... nao pedir a lib GLES/EGL
#   SDV_EXCL_FS=1 ............... fullscreen exclusivo
#   AUDIO_DRIVER=pulse|alsa ..... backend do OpenAL, quando ficar mudo
[ -n "${AUDIO_DRIVER:-}" ] && export ALSOFT_DRIVERS="$AUDIO_DRIVER"

echo "[port] $PORTNAME"
command -v pm_platform_helper >/dev/null 2>&1 && pm_platform_helper "$GAMEDIR/stardewvalley.multi"
"$GAMEDIR/stardewvalley.multi"
status=$?
command -v pm_finish >/dev/null 2>&1 && pm_finish
exit "$status"
