#!/usr/bin/env bash
# Universal PortMaster/NextOS runtime for Stardew Valley Android 1.6.15.3.
# The launcher does not force an SDL video or audio backend; firmware-native
# SDL/OpenAL negotiation remains available on every supported device.

SDV_RUNTIME_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" \
  2>/dev/null && pwd -P) || exit 1
PORTNAME="Stardew Valley (NextOS)"
XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"

if [ -d /opt/system/Tools/PortMaster ]; then
  controlfolder=/opt/system/Tools/PortMaster
elif [ -d /opt/tools/PortMaster ]; then
  controlfolder=/opt/tools/PortMaster
elif [ -d "$XDG_DATA_HOME/PortMaster" ]; then
  controlfolder=$XDG_DATA_HOME/PortMaster
elif [ -d /roms/ports/PortMaster ]; then
  controlfolder=/roms/ports/PortMaster
else
  controlfolder=/storage/.config/PortMaster
fi

[ -f "$controlfolder/control.txt" ] &&
  source "$controlfolder/control.txt"
case "${CFW_NAME:-}" in
  ''|*[!A-Za-z0-9._-]*) ;;
  *) [ -f "$controlfolder/mod_${CFW_NAME}.txt" ] &&
       source "$controlfolder/mod_${CFW_NAME}.txt" ;;
esac
declare -F get_controls >/dev/null 2>&1 && get_controls
: "${ESUDO:=}"
: "${CUR_TTY:=/dev/tty0}"

launcher_error() {
  printf 'Stardew Valley: %s\n' "$*" >&2
  exit 1
}

GAMEDIR=$SDV_RUNTIME_DIR
[ -f "$GAMEDIR/extractor.json" ] &&
[ -f "$GAMEDIR/nxextract-runtime-env.sh" ] ||
  launcher_error "runtime files are missing from game directory"

CURRENT_BIN="$GAMEDIR/stardewvalley"
COMPAT_BIN="$GAMEDIR/stardewvalley.multi"

process_starttime() {
  local stat_line stat_fields
  local -a fields

  IFS= read -r stat_line < "/proc/$1/stat" 2>/dev/null || return 1
  stat_fields=${stat_line#*) }
  read -r -a fields <<< "$stat_fields"
  [ "${#fields[@]}" -ge 20 ] || return 1
  case "${fields[19]}" in
    ''|*[!0-9]*) return 1 ;;
  esac
  printf '%s\n' "${fields[19]}"
}

LOCK_FILE=
LOCK_DIR=
LOCK_KIND=
LOCK_START=

lock_cleanup() {
  local owner_pid owner_start

  if [ "$LOCK_KIND" = mkdir ] && [ -r "$LOCK_DIR/owner" ]; then
    read -r owner_pid owner_start < "$LOCK_DIR/owner" || return
    if [ "$owner_pid" = "$$" ] && [ "$owner_start" = "$LOCK_START" ]; then
      rm -f -- "$LOCK_DIR/owner"
      rmdir -- "$LOCK_DIR" 2>/dev/null || true
    fi
  fi
}

acquire_launch_lock() {
  local lock_pid lock_start live_start stale_dir

  LOCK_FILE="$GAMEDIR/.stardew-launch.lock"
  LOCK_DIR="$GAMEDIR/.stardew-launch.lock.d"
  LOCK_START=$(process_starttime "$$")
  case "$LOCK_START" in
    ''|*[!0-9]*) launcher_error "could not identify launcher process" ;;
  esac

  if command -v flock >/dev/null 2>&1; then
    exec 9>"$LOCK_FILE" || launcher_error "could not open launch lock"
    flock -n 9 || launcher_error "another Stardew Valley launcher is active"
    LOCK_KIND=flock
  else
    while ! mkdir "$LOCK_DIR" 2>/dev/null; do
      [ -r "$LOCK_DIR/owner" ] || launcher_error "launch lock has no owner"
      read -r lock_pid lock_start < "$LOCK_DIR/owner" ||
        launcher_error "launch lock is invalid"
      case "$lock_pid:$lock_start" in
        *[!0-9:]*|:*|*:) launcher_error "launch lock is invalid" ;;
      esac
      live_start=$(process_starttime "$lock_pid")
      [ "$live_start" != "$lock_start" ] ||
        launcher_error "another Stardew Valley launcher is active"
      stale_dir="${LOCK_DIR}.stale.$$.$LOCK_START"
      if mv -- "$LOCK_DIR" "$stale_dir" 2>/dev/null; then
        rm -f -- "$stale_dir/owner"
        rmdir -- "$stale_dir" 2>/dev/null || true
      fi
    done
    printf '%s %s\n' "$$" "$LOCK_START" > "$LOCK_DIR/owner" ||
      launcher_error "could not record launch lock owner"
    LOCK_KIND=mkdir
  fi
}

matching_game_pids() {
  local process pid comm command_line executable working_directory matched

  for process in /proc/[0-9]*; do
    [ -d "$process" ] || continue
    pid=${process##*/}
    [ "$pid" = "$$" ] && continue
    [ "$pid" = "${PPID:-}" ] && continue
    comm=
    IFS= read -r comm < "$process/comm" 2>/dev/null || true
    command_line=$(LC_ALL=C command tr '\000' ' ' \
      < "$process/cmdline" 2>/dev/null || true)
    executable=$(command readlink "$process/exe" 2>/dev/null || true)
    working_directory=$(command readlink "$process/cwd" 2>/dev/null || true)
    matched=0

    case "$executable" in
      "$CURRENT_BIN"|"$CURRENT_BIN (deleted)"|\
      "$COMPAT_BIN"|"$COMPAT_BIN (deleted)"|\
      */ports/sdvnextos/stardewvalley|\
      */ports/sdvnextos/stardewvalley\ \(deleted\)|\
      */ports/sdvnextos/stardewvalley.multi|\
      */ports/sdvnextos/stardewvalley.multi\ \(deleted\)|\
      */ports/stardewvalley/stardewvalley|\
      */ports/stardewvalley/stardewvalley\ \(deleted\)|\
      */ports/stardewvalley/stardewvalley.multi|\
      */ports/stardewvalley/stardewvalley.multi\ \(deleted\))
        matched=1 ;;
    esac
    if [ "$matched" -eq 0 ]; then
      case "$working_directory:$comm:$command_line" in
        */ports/sdvnextos:*:stardewvalley:*|\
        */ports/stardewvalley:*:stardewvalley:*|\
        */ports/sdvnextos:*:*stardewvalley.multi*|\
        */ports/stardewvalley:*:*stardewvalley.multi*)
          matched=1 ;;
      esac
    fi
    [ "$matched" -eq 0 ] || printf '%s\n' "$pid"
  done
}

stop_existing_game() {
  local old_pids pid attempt remaining

  old_pids=$(matching_game_pids)
  if [ -n "$old_pids" ]; then
    for pid in $old_pids; do
      printf '[launcher] stopping old Stardew instance pid=%s\n' "$pid"
      kill "$pid" 2>/dev/null || true
    done
    attempt=0
    remaining=$(matching_game_pids)
    while [ -n "$remaining" ] && [ "$attempt" -lt 20 ]; do
      sleep 0.5
      attempt=$((attempt + 1))
      remaining=$(matching_game_pids)
    done
    if [ -n "$remaining" ]; then
      for pid in $remaining; do
        printf '[launcher] forcing old Stardew instance pid=%s\n' "$pid"
        kill -9 "$pid" 2>/dev/null || true
      done
      sleep 1
    fi
  fi
  remaining=$(matching_game_pids)
  [ -z "$remaining" ] ||
    launcher_error "an old game instance could not be stopped: $remaining"
}

finish_done=0
finish_frontend_once() {
  [ "$finish_done" -eq 0 ] || return
  finish_done=1
  ${ESUDO:-} chmod 666 "$CUR_TTY" 2>/dev/null || true
  [ -w "$CUR_TTY" ] && printf '\033c' >> "$CUR_TTY" 2>/dev/null || true
  command -v pm_finish >/dev/null 2>&1 && pm_finish
}

finish_on_exit() {
  local status=$?
  trap - EXIT
  lock_cleanup
  finish_frontend_once
  exit "$status"
}

trap finish_on_exit EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

cd "$GAMEDIR" || launcher_error "could not enter game directory"
acquire_launch_lock
if [ -s "$GAMEDIR/debug.log" ]; then
  mv -f -- "$GAMEDIR/debug.log" "$GAMEDIR/debug.prev.log"
fi
exec > "$GAMEDIR/debug.log" 2>&1
release_version=$(command tr -d '\r\n' < "$GAMEDIR/version.txt" 2>/dev/null || true)
printf '=== %s | release %s | %s ===\n' \
  "$PORTNAME" "${release_version:-unknown}" "$(date -Is 2>/dev/null || date)"

${ESUDO:-} chmod +x \
  "$CURRENT_BIN" \
  "$COMPAT_BIN" \
  "$GAMEDIR/run.sh" \
  "$GAMEDIR/run-extractor.sh" \
  "$GAMEDIR/nxextract.py" \
  "$GAMEDIR/nxextract-ui" \
  "$GAMEDIR/nxextract-runtime-env.sh" \
  "$GAMEDIR/tools/prepare_stardew_data.py" \
  2>/dev/null || true
${ESUDO:-} chmod 666 "$CUR_TTY" /dev/uinput 2>/dev/null || true

stop_existing_game

extractor_env=$GAMEDIR/nxextract-runtime-env.sh
[ -f "$extractor_env" ] && [ ! -L "$extractor_env" ] ||
  launcher_error "NXExtract runtime helper is missing or unsafe"
# shellcheck source=nxextract-runtime-env.sh
source "$extractor_env"
declare -F sdv_run_extractor >/dev/null 2>&1 ||
  launcher_error "NXExtract runtime helper is incomplete"
machine=$(uname -m 2>/dev/null) || launcher_error "cannot identify architecture"
sdv_run_extractor "$GAMEDIR" "$controlfolder" / "$machine" || {
  status=$?
  launcher_error "game-data preparation failed ($status)"
}
if [ "${SDV_EXTRACTOR_ONLY:-0}" = 1 ]; then
  printf '[launcher] extractor-only validation completed\n'
  exit 0
fi

is_nextos=0
if [ -r /etc/os-release ] &&
   LC_ALL=C grep -Eiq 'nextos|retro[[:space:]_-]*elite' /etc/os-release; then
  is_nextos=1
fi
if [ "$is_nextos" -eq 1 ]; then
  BIN=$CURRENT_BIN
  BUILD_PROFILE=nextos-current
else
  BIN=$COMPAT_BIN
  BUILD_PROFILE=external-compat
fi
[ -x "$BIN" ] || launcher_error "runtime loader is missing: $(basename "$BIN")"

# Firmware libraries stay first so SDL, EGL, Mali and OpenAL always match the
# running kernel/CFW. Android DSOs remain last and are opened explicitly by the
# custom loader, never interposed over the host libc stack.
export LD_LIBRARY_PATH="/usr/local/lib/aarch64-linux-gnu:/usr/local/lib:/usr/lib/aarch64-linux-gnu:/lib/aarch64-linux-gnu:/usr/lib:/lib:$controlfolder/libs:$controlfolder/libs.aarch64:$GAMEDIR:$GAMEDIR/libs${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export SDV_LIBDIR="$GAMEDIR/libs"
[ -f "$GAMEDIR/alsoft.conf" ] && export ALSOFT_CONF="$GAMEDIR/alsoft.conf"
for pulse_socket in /var/run/pulse/native /run/pulse/native; do
  if [ -z "${PULSE_SERVER:-}" ] && [ -S "$pulse_socket" ]; then
    export PULSE_SERVER="unix:$pulse_socket"
    break
  fi
done
case "${AUDIO_DRIVER:-}" in
  '') ;;
  pipewire|pulse|alsa) export ALSOFT_DRIVERS=$AUDIO_DRIVER ;;
  *) launcher_error "AUDIO_DRIVER must be pipewire, pulse or alsa" ;;
esac

export SDL_GAMECONTROLLER_USE_BUTTON_LABELS=0
[ -n "${sdl_controllerconfig:-}" ] &&
  export SDL_GAMECONTROLLERCONFIG=$sdl_controllerconfig
memory_kib=$(awk '/MemTotal/{print $2; exit}' /proc/meminfo 2>/dev/null || true)
case "$memory_kib" in
  ''|*[!0-9]*) memory_kib=0 ;;
esac
if [ "$memory_kib" -gt 0 ] && [ "$memory_kib" -lt 1200000 ]; then
  export MALLOC_ARENA_MAX=2
  export MALLOC_TRIM_THRESHOLD_=131072
  export MALLOC_MMAP_THRESHOLD_=65536
fi

printf '[launcher] runtime=%s binary=%s video=%s audio=%s\n' \
  "$BUILD_PROFILE" "$(basename "$BIN")" \
  "${SDL_VIDEODRIVER:-firmware-auto}" \
  "${ALSOFT_DRIVERS:-openal-auto}"
if command -v pm_platform_helper >/dev/null 2>&1; then
  pm_platform_helper "$BIN" >/dev/null ||
    launcher_error "PortMaster could not prepare frontend lifecycle"
fi

"$BIN"
exit $?
