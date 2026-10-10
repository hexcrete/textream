import AppKit
import SwiftUI

@main
struct FormattingChecks {
    @MainActor static func main() throws {
        let rich = FormattedPage(runs: [
            TextColorRun(text: "Red ", color: "#ff453a"),
            TextColorRun(text: "blue\n你好 👨‍👩‍👧‍👦 e\u{301}", color: "#4f8cff")
        ])
        let data = try JSONEncoder().encode(FormattedDocument(pages: [rich, FormattedPage()]))
        let roundTrip = try FormattedDocument.load(data)
        assert(roundTrip == [rich, FormattedPage()])
        let legacy = try FormattedDocument.load(Data("[\"Legacy text\",\"\"]".utf8))
        assert(legacy == [FormattedPage("Legacy text"), FormattedPage()])
        do {
            _ = try FormattedDocument.load(Data("{\"version\":999,\"pages\":[{\"runs\":[]}]}".utf8))
            assertionFailure("Unsupported document version accepted")
        } catch { }
        assert(FormattedPage(attributedString: rich.attributedString) == rich)
        assert(TextColorRun.canonicalHex("#A857F7") == "#a857f7")
        assert(TextColorRun.canonicalHex("url(unsafe)") == nil)
        assert(NSColor(rgbHex: "#8e8e93").rgbHex == "#8e8e93")
        checkDefaultBlack()

        var document = EditorDocument(pages: [FormattedPage("same text")])
        document.pages[0] = FormattedPage(runs: [TextColorRun(text: "same text", color: "#ff453a")])
        assert(document.hasUnsavedChanges, "Color-only edits must mark the document dirty")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("roundtrip.textream")
        try document.save(to: file)
        assert(!document.hasUnsavedChanges)
        let savedRoundTrip = try FormattedDocument.load(Data(contentsOf: file))
        assert(savedRoundTrip == document.pages)
        document.pages[0] = FormattedPage("changed")
        let saved = document.savedPages
        do {
            try document.save(to: directory.appendingPathComponent("missing/file.textream"))
            assertionFailure("Impossible save succeeded")
        } catch { }
        assert(document.hasUnsavedChanges && document.savedPages == saved, "Failed save must retain the saved snapshot")

        let words = splitTextIntoWords(rich.text)
        assert(words == ["Red", "blue", "你", "好", "👨‍👩‍👧‍👦", "e\u{301}"])
        assert(rich.wordColors(for: words) == ["#ff453a"] + Array(repeating: "#4f8cff", count: 5))
        assert(paragraphBreakWordIndices(in: rich.text) == [2])
        let unicode = FormattedPage("A\n你好 👨‍👩‍👧‍👦 e\u{301}")
        let unicodeWords = splitTextIntoWords(unicode.text)
        assert(unicode.sourceUTF16Offset(forSpeechOffset: 3, words: unicodeWords) == 3)
        assert(unicode.sourceUTF16Offset(forSpeechOffset: 5, words: unicodeWords) == 4)
        assert(unicode.sourceUTF16Offset(forSpeechOffset: 7, words: unicodeWords) == 16)
        assert(unicode.sourceUTF16Offset(forSpeechOffset: 9, words: unicodeWords) == 19)
        let dictated = rich.updatingText("Red edited blue\n你好 👨‍👩‍👧‍👦 e\u{301}", insertionColor: "#a857f7")
        assert(dictated.wordColors(for: splitTextIntoWords(dictated.text)) == ["#ff453a", "#a857f7"] + Array(repeating: "#4f8cff", count: 5))

        let decoder = JSONDecoder()
        let plainCommand = try decoder.decode(DirectorCommand.self, from: Data("{\"type\":\"setText\",\"text\":\" A  B \\n C \"}".utf8))
        assert(plainCommand.formattedPage == FormattedPage("A B\nC"))
        assert(FormattedPage("A\u{0085}B\u{00a0}C\u{FEFF}D").normalizedForDirector.text == "A B C\u{FEFF}D")
        let formattedCommand = DirectorCommand(type: "updateText", text: rich.text, readCharCount: 4, formattedRuns: rich.runs)
        let received = try decoder.decode(DirectorCommand.self, from: JSONEncoder().encode(formattedCommand))
        assert(received.formattedPage == rich.normalizedForDirector)
        assert(DirectorCommand(type: "setText", text: "mismatch", readCharCount: nil, formattedRuns: rich.runs).formattedPage == nil)
        let locked = rich.prefix(utf16Count: 4)
        assert(locked == FormattedPage(runs: [TextColorRun(text: "Red ", color: "#ff453a")]))

        try checkEditor(rich)
        checkPalette()
        print("PASS: rich/legacy round trips, failed saves, color-only dirty state, dictation colors, CJK/Unicode offsets, Director commands, native editor recoloring and undo/redo, palette persistence and limits")
    }

    @MainActor static func checkDefaultBlack() {
        _ = NSApplication.shared
        let page = FormattedPage(runs: [TextColorRun(text: "Black ", color: "#000000"),
                                        TextColorRun(text: "gray", color: "#202020"),
                                        TextColorRun(text: " default", color: "#ffffff")])
        assert(page.wordColors(for: ["Black", "gray"]) == ["#ffffff", "#202020"])
        var boundPage = page
        let editor = HighlightingTextEditor(
            page: Binding(get: { boundPage }, set: { boundPage = $0 }), formatting: EditorFormattingController(),
            caretPosition: .constant(nil), editorCaretPosition: .constant(0))
        let coordinator = editor.makeCoordinator()
        let view = FormattingTextView()
        view.textStorage?.setAttributedString(page.attributedString)
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            view.appearance = NSAppearance(named: appearance)
            // Exercise the normal editor styling path, not just the rendering helper.
            coordinator.applyHighlighting(view)
            let rendered = view.layoutManager?.temporaryAttribute(.foregroundColor, atCharacterIndex: 0, effectiveRange: nil) as? NSColor
            assert(rendered?.rgbHex == (appearance == .darkAqua ? "#ffffff" : "#000000"))
            let defaultRendered = view.layoutManager?.temporaryAttribute(.foregroundColor, atCharacterIndex: 10, effectiveRange: nil) as? NSColor
            assert(defaultRendered?.rgbHex == rendered?.rgbHex)
            assert(view.layoutManager?.temporaryAttribute(.foregroundColor, atCharacterIndex: 6, effectiveRange: nil) == nil)
            assert(FormattedPage(attributedString: view.attributedString()) == page,
                   "Appearance must not change saved colors")
        }
    }

    @MainActor static func checkEditor(_ rich: FormattedPage) throws {
        _ = NSApplication.shared
        var page = rich
        var caret: Int? = nil
        var position = 0
        let formatting = EditorFormattingController()
        let editor = HighlightingTextEditor(
            page: Binding(get: { page }, set: { page = $0 }), formatting: formatting,
            caretPosition: Binding(get: { caret }, set: { caret = $0 }),
            editorCaretPosition: Binding(get: { position }, set: { position = $0 })
        )
        let coordinator = editor.makeCoordinator()
        formatting.coordinator = coordinator
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        view.allowsUndo = true
        view.isRichText = true
        view.textStorage?.setAttributedString(rich.attributedString)
        view.delegate = coordinator
        coordinator.textView = view
        coordinator.applyHighlighting(view)
        assert(FormattedPage(attributedString: view.attributedString()) == rich)
        view.setSelectedRange(NSRange(location: 0, length: 3))
        window.undoManager?.beginUndoGrouping()
        coordinator.applyColor("#a857f7")
        window.undoManager?.endUndoGrouping()
        assert(page.runs.first?.color == "#a857f7")
        window.undoManager?.undo()
        assert(FormattedPage(attributedString: view.attributedString()) == rich, "Selection recoloring must support native undo")
        window.undoManager?.redo()
        assert(FormattedPage(attributedString: view.attributedString()).runs.first?.color == "#a857f7")
        view.setSelectedRange(NSRange(location: 3, length: 0))
        coordinator.applyColor("#33d64a")
        assert((view.typingAttributes[.foregroundColor] as? NSColor)?.rgbHex == "#33d64a")
        view.insertText("new", replacementRange: view.selectedRange())
        assert(page.text.hasPrefix("Rednew"))
        assert(page.wordColors(for: ["new"]) == ["#33d64a"])
        coordinator.reportSelection()
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        assert(formatting.selectedColor == "#33d64a")
        view.setSelectedRange(NSRange(location: 0, length: 3))
        coordinator.reportSelection()
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        assert(formatting.selectedColor == "#a857f7")
        assert((view.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)?.rgbHex == "#a857f7")
        view.setSelectedRange(NSRange(location: 0, length: 7))
        coordinator.reportSelection()
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        assert(formatting.selectedColor == nil, "Mixed selections must not select a dot")
        view.setSelectedRange(NSRange(location: 3, length: 0))
        coordinator.reportSelection()
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        assert(formatting.selectedColor == "#a857f7", "The caret must use the color before it, not after it")
        // Native RTF decoding includes multiple foreground colors, not fonts in the persisted model.
        let rtf = try rich.attributedString.data(from: NSRange(location: 0, length: rich.attributedString.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        let pasted = try NSAttributedString(data: rtf, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
        assert(FormattedPage(attributedString: pasted) == rich)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setData(rtf, forType: .rtf)
        view.selectAll(nil)
        assert(view.readSelection(from: pasteboard), "The native editor must accept formatted RTF paste")
        view.didChangeText()
        assert(page == rich, "Native paste and cue/font normalization must retain every foreground color")
        coordinator.bumpTimer?.invalidate()
    }

    @MainActor static func checkPalette() {
        let defaults = UserDefaults.standard
        let original = defaults.object(forKey: "editorColorPaletteHex")
        defer {
            if let original { defaults.set(original, forKey: "editorColorPaletteHex") }
            else { defaults.removeObject(forKey: "editorColorPaletteHex") }
        }
        defaults.set(NotchSettings.defaultEditorPalette, forKey: "editorColorPaletteHex")
        let settings = NotchSettings()
        assert(settings.editorPalette.count == 9 && settings.editorPalette.last?.hex == "#8e8e93")
        let id = settings.editorPalette[1].id
        settings.editorPalette[1].hex = "#123456"
        assert(NotchSettings().editorColorPaletteHex[1] == "#123456", "Continuous edits must persist without a settings-close commit")
        let entry = settings.editorPalette.remove(at: 1)
        settings.editorPalette.insert(entry, at: 4)
        assert(settings.editorPalette[4].id == id && settings.editorPalette[4].hex == "#123456")
        let row = PaletteRow(settings: settings)
        row.frame = NSRect(x: 0, y: 0, width: 460, height: 34)
        let window = NSWindow(contentRect: row.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = row
        row.refresh()
        let addButton = row.subviews.first as! NSButton
        assert(!addButton.isEnabled)
        let count = settings.editorPalette.count
        row.dragEnded(id: id, point: window.convertPoint(toScreen: NSPoint(x: 5, y: 16)), operation: [], cancelled: false)
        assert(settings.editorPalette.count == count, "Missed drops inside the row must never remove an entry")
        row.dragEnded(id: id, point: window.convertPoint(toScreen: NSPoint(x: 5, y: -100)), operation: [], cancelled: true)
        assert(settings.editorPalette.count == count, "Escaping a drag must not delete")
        row.dragEnded(id: id, point: window.convertPoint(toScreen: NSPoint(x: 5, y: -100)), operation: [], cancelled: false)
        assert(settings.editorPalette.count == count - 1, "Dragging away must remove an entry")
        settings.editorPalette = Array(settings.editorPalette.prefix(1))
        row.refresh()
        row.dragEnded(id: settings.editorPalette[0].id, point: window.convertPoint(toScreen: NSPoint(x: 5, y: -100)), operation: [], cancelled: false)
        assert(settings.editorPalette.count == 1, "The last color cannot be removed")
        settings.editorPalette = NotchSettings.defaultEditorPalette.dropLast().map { PaletteEntry(hex: $0) }
        row.refresh()
        addButton.performClick(nil)
        assert(settings.editorPalette.count == 9 && settings.editorPalette.last?.hex == "#8e8e93")
        defaults.set(Array(repeating: "#ffffff", count: 12), forKey: "editorColorPaletteHex")
        assert(NotchSettings().editorPalette.count == 9)
        defaults.set(["invalid"], forKey: "editorColorPaletteHex")
        assert(NotchSettings().editorColorPaletteHex == ["#ffffff"])
        let formatting = EditorFormattingController()
        let widths = [1, 3, 9].map { count in
            let entries = NotchSettings.defaultEditorPalette.prefix(count).map { PaletteEntry(hex: $0) }
            let view = NSHostingView(rootView: QuickColorPalette(entries: entries, formatting: formatting))
            return view.fittingSize.width
        }
        assert(widths[0] < widths[1] && widths[1] < widths[2], "Quick palette width must follow the actual count")
    }
}
