#!/usr/bin/env bash
set -euo pipefail

# metal-lib-smoke.sh — Validate prebuilt Metal libraries load on this macOS SDK.
#
# Usage:
#   Scripts/ci/metal-lib-smoke.sh [--package-path <path>]
#
# - Builds the SDLKit package to materialize Generated/metal/*.metallib artifacts.
# - Locates metallibs under the build bundle and tries device.makeLibrary(URL:) on each.
# - Exits non‑zero if any metallib fails to load with MTLLibraryError (e.g., "Invalid library file").

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PKG_PATH="${1:-$ROOT_DIR/External/SDLKit}"

if [[ ! -d "$PKG_PATH" ]]; then
  echo "[metal-lib-smoke] Package path not found: $PKG_PATH" >&2
  exit 2
fi

echo "[metal-lib-smoke] Building SDLKit at $PKG_PATH (debug)…"
swift build --package-path "$PKG_PATH" -c debug >/dev/null

echo "[metal-lib-smoke] Locating metallibs…"
LIBS=()
while IFS= read -r -d '' lib; do
  LIBS+=("$lib")
done < <(find "$PKG_PATH/.build" -type f -path "*/SDLKit_SDLKit.bundle/Generated/metal/*.metallib" -print0 2>/dev/null)

# Optional filter by name list: SDLKIT_SMOKE_LIBS="unlit_triangle,basic_lit" (empty = all)
if [[ -n "${SDLKIT_SMOKE_LIBS:-}" ]]; then
  NAMES_CSV="$SDLKIT_SMOKE_LIBS"
  FILTERED=()
  IFS=',' read -ra NAMES <<<"$NAMES_CSV"
  for lib in "${LIBS[@]}"; do
    base="$(basename "$lib")"  # e.g. unlit_triangle.metallib
    name="${base%.metallib}"
    for n in "${NAMES[@]}"; do
      if [[ "$name" == "$n" ]]; then FILTERED+=("$lib"); break; fi
    done
  done
  LIBS=("${FILTERED[@]}")
fi

if [[ ${#LIBS[@]} -eq 0 ]]; then
  echo "[metal-lib-smoke] No metallibs found under $PKG_PATH/.build" >&2
  exit 3
fi

SWIFT_SRC="$(mktemp -t metal-lib-check).swift"
cat >"$SWIFT_SRC" <<'SWIFT'
import Foundation
import Metal

guard let device = MTLCreateSystemDefaultDevice() else {
  fputs("[metal-lib-smoke] No Metal device available\n", stderr)
  exit(5)
}

var failures = 0
for path in CommandLine.arguments.dropFirst() {
  let url = URL(fileURLWithPath: path)
  do {
    _ = try device.makeLibrary(URL: url)
    print("OK \(path)")
  } catch {
    fputs("FAIL \(path): \(error)\n", stderr)
    failures += 1
  }
}
exit(Int32(failures))
SWIFT

BIN="${SWIFT_SRC%.swift}"
echo "[metal-lib-smoke] Compiling loader…"
swiftc -O -o "$BIN" "$SWIFT_SRC"

echo "[metal-lib-smoke] Probing \(${#LIBS[@]}\) metallib(s)…"
set +e
"$BIN" "${LIBS[@]}"
status=$?
set -e

if [[ $status -ne 0 ]]; then
  echo "[metal-lib-smoke] One or more metallibs failed to load." >&2
  if [[ "${SDLKIT_ALLOW_INLINE_FALLBACK:-0}" == "1" ]]; then
    echo "[metal-lib-smoke] Inline Metal fallback is allowed; proceeding (non-fatal)." >&2
    exit 0
  fi
  exit $status
fi

echo "[metal-lib-smoke] All metallibs loaded successfully."
