#!/usr/bin/env bash
# Process-scope boundary for the native NXExtract UI.
#
# The tested NextOS S905X5M path must load SDL2/KMSDRM from the firmware.  A
# game/compatibility library path can interpose another SDL2 and leave setup
# behind a black screen, so the clean path exists only in this child process.

sdv_platform_path() {
  local root=${1:-/} absolute_path=$2

  root=${root%/}
  [ -n "$root" ] || root=/
  if [ "$root" = / ]; then
    printf '%s\n' "$absolute_path"
  else
    printf '%s%s\n' "$root" "$absolute_path"
  fi
}

sdv_is_nextos() {
  local root=${1:-/} os_release

  os_release=$(sdv_platform_path "$root" /etc/os-release)
  [ -r "$os_release" ] &&
    LC_ALL=C command grep -Eiq \
      'nextos|retro[[:space:]_-]*elite' "$os_release"
}

sdv_file_has_x5m_signature() {
  local path=$1

  [ -r "$path" ] || return 1
  LC_ALL=C command tr '\000' '\n' < "$path" 2>/dev/null |
    LC_ALL=C command grep -Eiq \
      '^(amlogic,[[:space:]]*s7d|amlogic,[[:space:]]*s905x5m|s905x5m)$'
}

sdv_is_tested_x5m_nextos() {
  local root=${1:-/} machine=${2:-} marker

  case "$machine" in
    aarch64|arm64) ;;
    *) return 1 ;;
  esac
  sdv_is_nextos "$root" || return 1

  for marker in \
    "$(sdv_platform_path "$root" /proc/device-tree/compatible)" \
    "$(sdv_platform_path "$root" /sys/firmware/devicetree/base/compatible)" \
    "$(sdv_platform_path "$root" /sys/devices/soc0/soc_id)"; do
    sdv_file_has_x5m_signature "$marker" && return 0
  done
  return 1
}

sdv_run_extractor() {
  local game_dir=$1 control_folder=$2 root=$3 machine=$4
  local firmware_ld_path
  shift 4

  if sdv_is_tested_x5m_nextos "$root" "$machine"; then
    firmware_ld_path="/usr/local/lib/aarch64-linux-gnu:/usr/lib/aarch64-linux-gnu:/lib/aarch64-linux-gnu:/usr/lib:/lib:$control_folder/libs:$control_folder/libs.aarch64"
    printf '[launcher] NXExtract using the X5M firmware SDL2/KMSDRM scope\n'
    (
      unset SDL_VIDEODRIVER SDL_VIDEO_DRIVER
      export LD_LIBRARY_PATH="$firmware_ld_path"
      export NXEXTRACT_GAME_DIR="$game_dir"
      "$game_dir/run-extractor.sh" "$@"
    )
  else
    NXEXTRACT_GAME_DIR="$game_dir" \
      "$game_dir/run-extractor.sh" "$@"
  fi
}
