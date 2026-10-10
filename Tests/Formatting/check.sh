#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/textream-formatting.XXXXXX")
trap 'rm -rf "$work"' EXIT
src="$root/Textream/Textream"
xcrun swiftc -swift-version 5 -default-isolation MainActor -parse-as-library \
  -module-cache-path "$work/cache" \
  "$src/FormattedText.swift" "$src/TextWords.swift" "$src/DirectorMessages.swift" \
  "$src/TextDirection.swift" "$src/HighlightingTextEditor.swift" \
  "$src/NotchSettings.swift" "$src/EditorPalette.swift" "$src/LanguageDetection.swift" \
  "$root/Tests/Formatting/SettingsDependencies.swift" \
  "$root/Tests/Formatting/FormattingChecks.swift" -o "$work/checks"
"$work/checks"
node "$root/Tests/Formatting/director-checks.js"
