import Foundation
import SwiftUI
import Testing
import UIKit
@testable import TextreamiOS

@MainActor
private final class FormattingUndoTextView: UITextView {
    private let formattingUndoManager = UndoManager()
    override var undoManager: UndoManager? { formattingUndoManager }
}

@MainActor
struct FormattingTests {
    @Test func richScriptAndPalettePersistWithLegacyMigration() throws {
        let suite = "TextreamFormattingTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("Legacy script", forKey: "ios.script")
        let model = AppModel(defaults: defaults)
        #expect(model.formattedScript == FormattedPage("Legacy script"))
        let rich = FormattedPage(runs: [TextColorRun(text: "Red ", color: "#ff453a"), TextColorRun(text: "你好 👨‍👩‍👧‍👦", color: "#4f8cff")])
        model.formattedScript = rich
        let id = model.editorPalette[0].id
        model.setPaletteColor("#123456", id: id)
        let restored = AppModel(defaults: defaults)
        #expect(restored.formattedScript == rich)
        #expect(restored.editorPalette[0].hex == "#123456")
        #expect(model.configuration().formattedScript == rich)
        #expect(PromptScript(rich).words.map(\.colorHex) == ["#ff453a", "#4f8cff", "#4f8cff", "#4f8cff"])
        #expect(try FormattedDocument.load(JSONEncoder().encode(FormattedDocument(pages: [rich]))) == [rich])
    }

    @Test func paletteLimitsAndStablePickerIdentity() throws {
        let suite = "TextreamPaletteTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults)
        #expect(model.editorPalette.count == 8)
        model.addPaletteColor()
        #expect(model.editorPalette.count == 8)
        let editedID = model.editorPalette[1].id
        model.removePaletteColor(id: model.editorPalette[0].id)
        model.setPaletteColor("#abcdef", id: editedID)
        #expect(model.editorPalette[0].hex == "#abcdef")
        for entry in model.editorPalette.dropFirst() { model.removePaletteColor(id: entry.id) }
        model.removePaletteColor(id: editedID)
        #expect(model.editorPalette.count == 1)
        model.setPaletteColor("#ffffff", id: editedID)
        for _ in 0..<10 { model.addPaletteColor() }
        #expect(model.editorPalette.count == 8)
        #expect(model.editorPalette.last?.hex == "#ff9e0a")
    }

    @Test func appearanceAndCueStylingKeepCanonicalColors() throws {
        let page = FormattedPage(runs: [TextColorRun(text: "Black ", color: "#000000"), TextColorRun(text: "white "), TextColorRun(text: "[red cue]", color: "#ff453a")])
        let text = NSMutableAttributedString(attributedString: page.editorAttributedString)
        BracketCueTextStyling.apply(to: text, font: .systemFont(ofSize: 17))
        #expect(FormattedPage(attributedString: text) == page)
        for offset in [0, 6] {
            let color = try #require(text.attribute(.foregroundColor, at: offset, effectiveRange: nil) as? UIColor)
            #expect(color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark)).rgbHex == "#ffffff")
            #expect(color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)).rgbHex == "#000000")
        }
        #expect((text.attribute(.foregroundColor, at: 12, effectiveRange: nil) as? UIColor)?.rgbHex == "#ff453a")
        #expect(page.wordColors(for: ["Black", "white"]) == ["#ffffff", "#ffffff"])
    }

    @Test func editorSelectionTypingAndUndoPreserveColors() async throws {
        var page = FormattedPage(runs: [TextColorRun(text: "Red ", color: "#ff453a"), TextColorRun(text: "blue", color: "#4f8cff")])
        let original = page
        let formatting = ScriptFormattingController()
        var editor = BracketHighlightingTextEditor(page: Binding(get: { page }, set: { page = $0 }), isFocused: .constant(false), accessibilityLabel: "Script", accessibilityIdentifier: "testEditor", formatting: formatting, palette: AppModel.defaultEditorPalette.map { ScriptPaletteEntry(hex: $0) })
        let coordinator = editor.makeCoordinator()
        let view = FormattingUndoTextView(usingTextLayoutManager: false)
        view.delegate = coordinator
        coordinator.update(view, force: true)
        let accessory = try #require(view.inputAccessoryView)
        #expect(accessory.bounds.height == 48)
        coordinator.update(view, force: false)
        #expect(view.inputAccessoryView === accessory)
        editor.palette = [ScriptPaletteEntry(hex: "#ffffff")]
        coordinator.parent = editor
        coordinator.update(view, force: false)
        #expect(view.inputAccessoryView == nil)
        let undo = try #require(view.undoManager)
        undo.removeAllActions()
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        view.selectedRange = NSRange(location: 0, length: 3)
        coordinator.applyColor("#a857f7")
        undo.endUndoGrouping()
        #expect(page.runs.first?.color == "#a857f7")
        await Task.yield()
        #expect(formatting.selectedColor == "#a857f7")
        #expect(undo.canUndo)
        undo.undo()
        #expect(page == original)
        #expect(undo.canRedo)
        undo.redo()
        #expect(page.runs.first?.color == "#a857f7")
        undo.groupsByEvent = true
        view.selectedRange = NSRange(location: 3, length: 0)
        coordinator.applyColor("#33d64a")
        view.insertText("new")
        coordinator.textViewDidChange(view)
        #expect(page.text == "Rednew blue")
        #expect(page.wordColors(for: ["new"]) == ["#33d64a"])
        let before = view.attributedText
        coordinator.parent = editor
        coordinator.update(view, force: false)
        #expect(view.attributedText == before)
        view.selectedRange = NSRange(location: 0, length: view.textStorage.length)
        coordinator.reportSelection()
        await Task.yield()
        #expect(formatting.selectedColor == nil)
        view.delegate = nil
    }
}
