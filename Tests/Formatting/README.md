# Formatting checks

Run on macOS with Xcode's Swift compiler and Node.js installed:

```sh
./Tests/Formatting/check.sh
```

The checks compile the production document model, editor coordinator, word
splitter, settings, palette controls, and Director message types. Server/overlay
side effects are replaced only in the settings test executable. JavaScript
checks load the production Director formatting script directly.

Covered: legacy/rich file round trips, unsupported versions, atomic-save failure
safety, color-only dirty state, native RTF decoding, undo/redo, native caret and
mixed-selection feedback, dictation color preservation, Unicode/CJK word colors
and offsets, optional Director messages, whitespace/paragraph normalization,
read/unread color splitting, palette persistence and limits, missed drops,
cancelled drags, drag-away removal, and the neutral-gray ninth preset.
Remote checks execute the generated reader HTML and cover per-word colors,
read/current dimming, cue colors, black-to-white fallback, live text/color edits,
legacy state fallback, and mirror controls.

## Desktop acceptance checks

Build output stays at:

`/Users/macbook/Developer/textream/Textream/build/Build/Products/Debug/Textream.app`

- Paste multi-color RTF. Select text and recolor it. Type at color boundaries,
  move the caret, select mixed colors, and select a color outside the palette.
- Check that highlighting a selection leaves its original colors visible.
  Undo and redo pasting, typing, and recoloring.
- Dictate into colored text. Switch pages, save, and reopen. Change only a
  color and confirm that the document becomes unsaved. Cancel a save during
  an open/import attempt and confirm the current document remains intact.
- In settings, click an entry and drag the native color picker continuously.
  Close settings and reopen them, then restart the app to verify persistence.
  Verify the picker closes with settings and starts on the entry's current color.
- Reorder by dropping between entries. A drop inside the row must never delete.
  Drag downward outside the row to remove. Escape must cancel without deletion.
  The final color must not be removable. Add must disable at nine entries.
- Check the quick toolbar at 1, 3, and 9 entries, with the sidebar open and
  closed and with a narrow window. At one entry, the entire item must disappear.
- Check colored words and paragraph dividers in pinned, floating, fullscreen,
  and external-display projections, using all three reading modes.

## Director acceptance checks

- Enable upstream Director Mode and open its address. Type, paste colored
  paragraphs, recolor a selection, and set a color for subsequent typing.
- Start reading and edit the unread portion. Confirm the read prefix cannot
  be edited, the selection survives boundary advances, and colors reach projection.
- Include CJK, emoji, combining accents, and multiple paragraphs. Check that
  progress and the locked boundary agree with the actual text.
- Change the palette while connected. Check that the dots update and disappear
  when one entry remains. Check the top bar at narrow browser widths.

## File compatibility

New saves are version-1 JSON objects containing pages of text/color runs.
Legacy arrays of strings load as white text. Unmodified upstream Textream
cannot open the new format. Tests never overwrite an existing document.

The automated checks do not certify microphone recognition, physical external
displays, native drag gestures, or toolbar appearance. Those require the actual
app and the manual checks above.

## iOS formatting

The iOS and macOS targets share `Textream/Shared/FormattedText.swift`. The iOS
script and ordered palette persist locally using UserDefaults; old plain scripts
load as white text. Settings uses native color pickers. Touch and hold a palette
entry to delete it, or use plus to add one (1–8 entries; plus is hidden at eight). The expanded editor
provides a horizontally scrollable color bar above the keyboard, hidden at one
entry. Cue fonts/backgrounds remain presentation-only; cue color settings still
control stage directions in projection.

Build the app and compile tests without launching Simulator:

```sh
xcodebuild -project Textream/Textream.xcodeproj -scheme TextreamiOS \
  -configuration Debug -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath Textream/build-ios CODE_SIGNING_ALLOWED=NO build-for-testing
```

Run the TextreamiOS scheme's tests in Xcode after choosing an installed Simulator.
`FormattingTests` covers rich persistence, legacy migration, palette limits,
stable picker identities, default light/dark colors, Unicode/CJK projection,
selection recoloring, typing colors, undo/redo, and mixed-selection feedback.
Before accepting the UI, test colored paste, picker interaction/persistence,
keyboard bar layout on iPhone/iPad, and colors in Read and Record modes.
