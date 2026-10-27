#!/bin/bash
# Blocks known Xcode/VS Code malware patterns (XCSSET-style build phases,
# auto-run editor tasks, obfuscated JS loaders) from being committed or pushed.
# Scans the staged index; with --push also scans HEAD. Exit 1 on any match.

set -u
cd "$(git rev-parse --show-toplevel)" || exit 2

SELF=':!scripts/check-xcsset.sh'

# pattern|description
CHECKS=(
  'xxd -p -r|hex-decode chain (XCSSET payload loader)'
  'sh -c \\?"\$\{[A-Za-z0-9_]+\}|shell phase executing a build setting'
  '(curl|wget)[^"]*\| *(ba|z)?sh|remote script piped to shell'
  'base64 +(-d|-D|--decode)[^"]*\| *(ba|z)?sh|base64 payload piped to shell'
  '"runOn" *: *"folderOpen"|VS Code task that auto-runs on folder open'
  'global\[.!.\] *=|obfuscated JS loader marker'
  'osascript -e|inline AppleScript execution'
  'child_process|Node child_process usage'
)

REFS=(--cached)
[ "${1:-}" = --push ] && REFS+=(HEAD)

found=0
for ref in "${REFS[@]}"; do
  [ "$ref" = HEAD ] && ! git rev-parse -q --verify HEAD >/dev/null && continue
  for entry in "${CHECKS[@]}"; do
    pattern="${entry%|*}"
    desc="${entry##*|}"
    if [ "$ref" = --cached ]; then
      hits=$(git grep -I -l -E --cached "$pattern" -- . "$SELF" 2>/dev/null)
    else
      hits=$(git grep -I -l -E "$pattern" HEAD -- . "$SELF" 2>/dev/null | sed 's/^HEAD://')
    fi
    if [ -n "$hits" ]; then
      echo "check-xcsset: [$ref] $desc:" >&2
      echo "$hits" | sed 's/^/  /' >&2
      found=1
    fi
  done
done

# Script payloads disguised as font files.
fonts=$(git ls-files --cached | grep -E '\.(llf|woff2?|ttf|otf|eot)$')
while IFS= read -r f; do
  [ -f "$f" ] || continue
  case "$f" in *.llf) echo "check-xcsset: suspicious font extension: $f" >&2; found=1; continue;; esac
  if file -b "$f" | grep -qiE 'text|script'; then
    echo "check-xcsset: font file is actually text/script: $f" >&2
    found=1
  fi
done <<< "$fonts"

if [ "$found" -ne 0 ]; then
  echo "check-xcsset: FAILED - malware patterns found. Do not commit or push." >&2
  exit 1
fi
echo "check-xcsset: OK"
