#!/usr/bin/env bash
set -euo pipefail

out_dir="Tools"; mkdir -p "$out_dir"
out_file="$out_dir/history-audit.txt"

echo "# History Audit — Concurrency/Focus Patterns" > "$out_file"
date >> "$out_file"
echo >> "$out_file"

# Pattern list: label<TAB>regex (extended)
cat >"$out_dir/.history-audit.patterns" <<'PAT'
DispatchQueue.main.async	DispatchQueue\.main\.async
asyncAfter(	asyncAfter\(
Task.detached(	Task\.detached\(
@MainActor	@MainActor\b
@Sendable	@Sendable\b
@unchecked Sendable	@unchecked\s+Sendable
firstResponder/makeFirstResponder/fieldEditor(	makeFirstResponder\(|firstResponder\b|fieldEditor\(
.focused(	\.focused\(
NSApplication.shared.activate	NSApplication\.shared\.activate
NWListener	\bNWListener\b
CoreMIDI imports or calls	\bimport\s+CoreMIDI\b|\bMIDI(Client|Source|Destination|Port|Send|Received)
PAT

while IFS=$'\t' read -r label pat; do
  [ -z "$label" ] && continue
  total=$(git log -E -G "$pat" --pretty=oneline | wc -l | tr -d ' ')
  first=$(git log -E -G "$pat" --pretty=format:'%h %ad %s' --date=short | tail -n 1 || true)
  last=$(git log -E -G "$pat" --pretty=format:'%h %ad %s' --date=short | head -n 1 || true)
  {
    echo "## $label"
    echo "commits: $total"
    echo "first: ${first:-none}"
    echo "last:  ${last:-none}"
    echo
  } >> "$out_file"
done <"$out_dir/.history-audit.patterns"

echo "# Current snapshot (file counts)" >> "$out_file"
rg -n "\\bDispatchQueue\\.main\\.async\\b|asyncAfter\(|Task\\.detached\(|@Sendable\b|@unchecked\\s+Sendable|makeFirstResponder\(|firstResponder\b|fieldEditor\(|\\.focused\(|NSApplication\\.shared\\.activate|\\bNWListener\\b|\\bimport\\s+CoreMIDI\\b|\\bMIDI(Client|Source|Destination|Port|Send|Received)" -S \
  | cut -d: -f1 \
  | sort | uniq -c | sort -nr >> "$out_file"

echo "[history-audit] Wrote $out_file"
