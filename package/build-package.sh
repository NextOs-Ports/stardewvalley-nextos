#!/usr/bin/env bash
# Build the deterministic, universal, BYO-data public release.
set -euo pipefail

export LC_ALL=C
export TZ=UTC

fail() {
  printf 'package error: %s\n' "$*" >&2
  exit 1
}

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PORT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd -P)
ALLOWLIST="$SCRIPT_DIR/package-files.txt"
SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-1785628800}
OUTPUT=${1:-"$SCRIPT_DIR/dist/stardewvalley.zip"}
RELEASE=$(tr -d '\r\n' < "$PORT_DIR/version.txt")

for tool in bash cmp comm cut find grep install mktemp python3 readelf rm \
            sed sh sha256sum sort touch unzip wc zip; do
  command -v "$tool" >/dev/null 2>&1 || fail "missing host tool: $tool"
done
case "$SOURCE_DATE_EPOCH" in
  ''|*[!0-9]*) fail "SOURCE_DATE_EPOCH must be a Unix timestamp" ;;
esac
[ $((SOURCE_DATE_EPOCH % 2)) -eq 0 ] ||
  fail "SOURCE_DATE_EPOCH must use ZIP two-second granularity"
[ -f "$ALLOWLIST" ] || fail "missing package allowlist"

EXPECTED=$(mktemp "${TMPDIR:-/tmp}/stardew-allowlist.XXXXXX")
sort -u "$ALLOWLIST" > "$EXPECTED"
cmp -s "$ALLOWLIST" "$EXPECTED" ||
  fail "package-files.txt must be sorted and unique"
while IFS= read -r relative; do
  [ -n "$relative" ] || fail "blank allowlist entry"
  case "$relative" in
    /*|../*|*/../*|*/..|*/./*|./*) fail "unsafe path: $relative" ;;
  esac
done < "$ALLOWLIST"

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/stardew-package.XXXXXX")
STAGE="$TMP_ROOT/stage"
TMP_ZIP="$TMP_ROOT/stardewvalley.zip"
cleanup() {
  rm -rf -- "$TMP_ROOT"
  rm -f -- "$EXPECTED"
}
trap cleanup EXIT INT TERM
mkdir -p -- "$STAGE"

put() {
  local mode=$1 source=$2 destination=$3
  [ -f "$source" ] || fail "missing package source: $source"
  install -D -m "$mode" -- "$source" "$STAGE/$destination"
}

LAUNCHER="Stardew Valley (NextOS).sh"
put 0644 "$SCRIPT_DIR/LEIA-ME.md" "LEIA-ME.md"
put 0755 "$PORT_DIR/arkos/$LAUNCHER" "ports/$LAUNCHER"
put 0755 "$PORT_DIR/arkos/$LAUNCHER" "ports_scripts/$LAUNCHER"
put 0755 "$PORT_DIR/stardewvalley" "ports/sdvnextos/stardewvalley"
put 0755 "$PORT_DIR/stardewvalley.multi" "ports/sdvnextos/stardewvalley.multi"
put 0644 "$PORT_DIR/arkos/alsoft.conf" "ports/sdvnextos/alsoft.conf"
put 0644 "$PORT_DIR/extractor.json" "ports/sdvnextos/extractor.json"
put 0755 "$PORT_DIR/run.sh" "ports/sdvnextos/run.sh"
put 0755 "$PORT_DIR/run-extractor.sh" "ports/sdvnextos/run-extractor.sh"
put 0755 "$PORT_DIR/nxextract-runtime-env.sh" \
  "ports/sdvnextos/nxextract-runtime-env.sh"
put 0755 "$PORT_DIR/nxextract.py" "ports/sdvnextos/nxextract.py"
put 0755 "$PORT_DIR/nxextract-ui" "ports/sdvnextos/nxextract-ui"
put 0755 "$PORT_DIR/tools/prepare_stardew_data.py" \
  "ports/sdvnextos/tools/prepare_stardew_data.py"
put 0644 "$PORT_DIR/tools/liblz4.so.1" \
  "ports/sdvnextos/tools/liblz4.so.1"
put 0644 "$PORT_DIR/gamedata/README.txt" \
  "ports/sdvnextos/gamedata/README.txt"
put 0644 "$PORT_DIR/LZ4-PROVENANCE.md" \
  "ports/sdvnextos/LZ4-PROVENANCE.md"
put 0644 "$PORT_DIR/licenses/LZ4-BSD-2-Clause.txt" \
  "ports/sdvnextos/licenses/LZ4-BSD-2-Clause.txt"
put 0644 "$PORT_DIR/licenses/NXExtract-MIT.txt" \
  "ports/sdvnextos/licenses/NXExtract-MIT.txt"
put 0644 "$PORT_DIR/LICENSE" "ports/sdvnextos/LICENSE"
put 0644 "$PORT_DIR/README.md" "ports/sdvnextos/README.md"
put 0644 "$PORT_DIR/INSTALAR.md" "ports/sdvnextos/INSTALAR.md"
put 0644 "$PORT_DIR/version.txt" "ports/sdvnextos/version.txt"

python3 "$PORT_DIR/tools/build_provenance.py" combine \
  --root "$PORT_DIR" \
  --current-record "$PORT_DIR/.build-provenance/nextos-current.json" \
  --current-binary "$PORT_DIR/stardewvalley" \
  --compat-record "$PORT_DIR/.build-provenance/external-compat.json" \
  --compat-binary "$PORT_DIR/stardewvalley.multi" \
  --release "$RELEASE" \
  --output "$STAGE/ports/sdvnextos/BUILD-PROVENANCE.json"

check_aarch64_glibc_ceiling() {
  local file=$1 ceiling=$2 newest
  readelf -h "$file" | grep 'Machine:.*AArch64' >/dev/null ||
    fail "$file is not AArch64"
  newest=$(readelf --version-info "$file" 2>/dev/null |
    grep -oE 'GLIBC_[0-9]+([.][0-9]+)*' | sed 's/^GLIBC_//' |
    sort -Vu | tail -1)
  [ -n "$newest" ] || return 0
  [ "$(printf '%s\n%s\n' "$ceiling" "$newest" | sort -V | tail -1)" = "$ceiling" ] ||
    fail "$file requires GLIBC_$newest (ceiling $ceiling)"
}

readelf -h "$STAGE/ports/sdvnextos/stardewvalley" |
  grep 'Machine:.*AArch64' >/dev/null || fail "NextOS loader is not AArch64"
readelf --version-info "$STAGE/ports/sdvnextos/stardewvalley" |
  grep 'GLIBC_2[.]43' >/dev/null ||
  fail "NextOS loader was not built for current glibc 2.43"
check_aarch64_glibc_ceiling \
  "$STAGE/ports/sdvnextos/stardewvalley.multi" 2.17
check_aarch64_glibc_ceiling "$STAGE/ports/sdvnextos/nxextract-ui" 2.17
check_aarch64_glibc_ceiling \
  "$STAGE/ports/sdvnextos/tools/liblz4.so.1" 2.17
[ "$(sha256sum "$STAGE/ports/sdvnextos/tools/liblz4.so.1" | cut -d' ' -f1)" = \
  "a65c53e2e7015b636e4f212449eff2016b99736cdf5798fe2cf3672818b88b8b" ] ||
  fail "bundled liblz4 does not match the audited Debian arm64 artifact"

sh -n "$STAGE/ports/$LAUNCHER"
sh -n "$STAGE/ports_scripts/$LAUNCHER"
cmp -s "$STAGE/ports/$LAUNCHER" "$STAGE/ports_scripts/$LAUNCHER" ||
  fail "ports and ports_scripts launchers differ"
[ "$(wc -c < "$STAGE/ports/$LAUNCHER")" -le 2048 ] ||
  fail "visible PortMaster launcher is no longer thin"
bash -n "$STAGE/ports/sdvnextos/run.sh"
bash -n "$STAGE/ports/sdvnextos/run-extractor.sh"
bash -n "$STAGE/ports/sdvnextos/nxextract-runtime-env.sh"
python3 - "$STAGE/ports/sdvnextos/nxextract.py" \
          "$STAGE/ports/sdvnextos/tools/prepare_stardew_data.py" <<'PY'
import sys
for path in sys.argv[1:]:
    with open(path, "rb") as stream:
        compile(stream.read(), path, "exec")
PY
python3 "$STAGE/ports/sdvnextos/nxextract.py" recipe-check \
  --recipe "$STAGE/ports/sdvnextos/extractor.json" >/dev/null

# The extractor recipe pins the SHA-256 of the .stardew-data.json marker that
# prepare_stardew_data.py writes.  Recompute the marker from the shipped
# script and refuse to package a recipe whose pins drifted (the v1.1.7
# regression: script updated, recipe pins left behind).
python3 -B - "$STAGE/ports/sdvnextos" <<'PY'
import hashlib
import importlib.util
import json
import os
import sys

root = sys.argv[1]
spec = importlib.util.spec_from_file_location(
    "prepare_stardew_data",
    os.path.join(root, "tools", "prepare_stardew_data.py"),
)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
marker = module.marker_bytes()
digest = hashlib.sha256(marker).hexdigest()

with open(os.path.join(root, "extractor.json"), "rb") as stream:
    recipe = json.load(stream)
pins = [
    check
    for hook in recipe.get("hooks", ())
    for check in hook.get("checkpoint", ())
    if check.get("path") == module.DATA_MARKER
]
pins.extend(
    check
    for check in recipe.get("validate", ())
    if check.get("path") == module.DATA_MARKER
)
if not pins:
    raise SystemExit("extractor.json no longer validates the data marker")
for check in pins:
    if check.get("sha256") != digest or check.get("size") != len(marker):
        raise SystemExit(
            "extractor.json pins a stale data marker: expected %d bytes %s"
            % (len(marker), digest)
        )
PY

if grep -En '^[[:space:]]*(export[[:space:]]+)?SDL_(VIDEO|AUDIO)DRIVER=' \
    "$STAGE/ports/$LAUNCHER" \
    "$STAGE/ports/sdvnextos/run.sh" \
    "$STAGE/ports/sdvnextos/nxextract-runtime-env.sh"; then
  fail "release must not force an SDL video or audio backend"
fi
if grep -En \
    '(^|[[:space:]])(setsid|nohup|systemctl[[:space:]]+(stop|mask))([[:space:]]|$)' \
    "$STAGE/ports/$LAUNCHER" \
    "$STAGE/ports/sdvnextos/run.sh"; then
  fail "launcher contains a forbidden lifecycle command"
fi
if find "$STAGE" \( \
    -name '*.apk' -o -name '*.apks' -o -name '*.apkm' -o \
    -name '*.xapk' -o -name '*.obb' -o -name '*.dex' -o \
    -name 'libassemblies*.so' -o -name 'libmonosgen*.so' -o \
    -path '*/assets/Content/*' \
  \) -print -quit | grep . >/dev/null; then
  fail "proprietary game data entered the public package"
fi
if find "$STAGE" \( \
    -name '*.log' -o -name '*.raw' -o -name '*.ppm' -o \
    -name '__pycache__' -o -name '*.pyc' -o -name 'HANDOFF.md' \
  \) -print -quit | grep . >/dev/null; then
  fail "development artifact entered the public package"
fi
if grep -IRnE '192[.]168[.]|/home/|/mnt/ARQUIVOS|root@' "$STAGE" \
    --include='*.sh' --include='*.py' --include='*.md' \
    --include='*.txt' --include='*.json'; then
  fail "release text contains a test address or personal path"
fi

(
  cd -- "$STAGE"
  while IFS= read -r relative; do
    [ "$relative" = "ports/sdvnextos/PACKAGE-MANIFEST.sha256" ] && continue
    sha256sum -- "$relative"
  done < "$ALLOWLIST"
) > "$STAGE/ports/sdvnextos/PACKAGE-MANIFEST.sha256"

ACTUAL="$TMP_ROOT/actual.txt"
find "$STAGE" -type f -printf '%P\n' | sort > "$ACTUAL"
cmp -s "$ALLOWLIST" "$ACTUAL" || {
  comm -3 "$ALLOWLIST" "$ACTUAL" >&2
  fail "staged files differ from package-files.txt"
}

find "$STAGE" -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} +
(
  cd -- "$STAGE"
  zip -X -9 -q "$TMP_ZIP" -@ < "$ALLOWLIST"
)
unzip -tq "$TMP_ZIP" >/dev/null
unzip -Z1 "$TMP_ZIP" > "$TMP_ROOT/archive.txt"
cmp -s "$ALLOWLIST" "$TMP_ROOT/archive.txt" ||
  fail "ZIP entries or ordering differ from allowlist"

VERIFY="$TMP_ROOT/verify"
mkdir -p -- "$VERIFY"
unzip -q "$TMP_ZIP" -d "$VERIFY"
(
  cd -- "$VERIFY"
  sha256sum -c ports/sdvnextos/PACKAGE-MANIFEST.sha256 >/dev/null
)

mkdir -p -- "$(dirname -- "$OUTPUT")"
OUTPUT_DIR=$(CDPATH= cd -- "$(dirname -- "$OUTPUT")" && pwd -P)
OUTPUT="$OUTPUT_DIR/$(basename -- "$OUTPUT")"
install -m 0644 -- "$TMP_ZIP" "$OUTPUT"
(
  cd -- "$OUTPUT_DIR"
  sha256sum "$(basename -- "$OUTPUT")" > "$(basename -- "$OUTPUT").sha256"
)
printf 'OK: %s\n' "$OUTPUT"
sha256sum "$OUTPUT"
