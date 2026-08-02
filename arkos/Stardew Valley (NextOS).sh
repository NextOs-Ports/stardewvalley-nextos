#!/bin/sh
# Standard PortMaster entry point. The full multi-device runtime stays beside
# the game files so ports/ and ports_scripts/ share one implementation.

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd -P) ||
  exit 1

for launcher in \
  "$SCRIPT_DIR/sdvnextos/run.sh" \
  "$SCRIPT_DIR/../ports/sdvnextos/run.sh" \
  /roms/ports/sdvnextos/run.sh \
  /roms2/ports/sdvnextos/run.sh \
  /storage/roms/ports/sdvnextos/run.sh
do
  if [ -f "$launcher" ] && [ ! -L "$launcher" ]; then
    exec bash "$launcher" "$@"
  fi
done

printf '%s\n' 'Stardew Valley: ports/sdvnextos/run.sh not found' >&2
exit 1
