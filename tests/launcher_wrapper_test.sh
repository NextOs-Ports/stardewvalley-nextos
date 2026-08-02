#!/usr/bin/env bash
set -euo pipefail

REPO=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/sdv-launcher-test.XXXXXX")
cleanup() {
  rm -rf -- "$TMP_ROOT"
}
trap cleanup EXIT INT TERM

fail() {
  printf 'launcher wrapper test failed: %s\n' "$*" >&2
  exit 1
}

ROM_ROOT="$TMP_ROOT/custom-roms"
mkdir -p "$ROM_ROOT/ports/sdvnextos" "$ROM_ROOT/ports_scripts"
cp -- "$REPO/arkos/Stardew Valley (NextOS).sh" \
  "$ROM_ROOT/ports/Stardew Valley (NextOS).sh"
cp -- "$REPO/arkos/Stardew Valley (NextOS).sh" \
  "$ROM_ROOT/ports_scripts/Stardew Valley (NextOS).sh"

cat > "$ROM_ROOT/ports/sdvnextos/run.sh" <<'SH'
#!/usr/bin/env bash
HELPER_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
printf '%s\n' "$HELPER_DIR/run.sh" "$#" "$@"
exit 37
SH
chmod +x "$ROM_ROOT/ports/sdvnextos/run.sh"

for entry in \
  "$ROM_ROOT/ports/Stardew Valley (NextOS).sh" \
  "$ROM_ROOT/ports_scripts/Stardew Valley (NextOS).sh"
do
  set +e
  output=$(cd / && sh "$entry" 'first argument' second)
  status=$?
  set -e
  [ "$status" -eq 37 ] || fail "exit status was not propagated by $entry"
  expected=$(printf '%s\n' \
    "$ROM_ROOT/ports/sdvnextos/run.sh" 2 'first argument' second)
  [ "$output" = "$expected" ] || fail "target or arguments were wrong for $entry"
done

printf 'launcher wrapper tests: PASS\n'
