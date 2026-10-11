import SwiftUI
import UIKit

struct ScriptPaletteEntry: Identifiable {
    let id = UUID()
    var hex: String
}

@Observable
final class ScriptFormattingController {
    var selectedColor: String?
    @ObservationIgnored weak var coordinator: BracketHighlightingTextEditor.Coordinator?
    func applyColor(_ hex: String) { coordinator?.applyColor(hex) }
}

struct ScriptColorBar: View {
    let entries: [ScriptPaletteEntry]
    let formatting: ScriptFormattingController

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 4) {
                ForEach(entries) { entry in
                    Button { formatting.applyColor(entry.hex) } label: {
                        Circle()
                            .fill(Color(uiColor: UIColor(rgbHex: entry.hex)))
                            .frame(width: 18, height: 18)
                            .overlay { Circle().strokeBorder(.primary.opacity(0.2), lineWidth: 1) }
                            .frame(width: 32, height: 36)
                            .overlay {
                                if formatting.selectedColor == entry.hex {
                                    Circle().strokeBorder(.tint, lineWidth: 3).frame(width: 26, height: 26)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Text color \(entry.hex)")
                    .accessibilityAddTraits(formatting.selectedColor == entry.hex ? .isSelected : [])
                }
            }
        }
        .scrollIndicators(.hidden)
        .frame(height: 36)
    }
}

struct ScriptKeyboardAccessory: View {
    let entries: [ScriptPaletteEntry]
    let formatting: ScriptFormattingController
    let dismissKeyboard: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if entries.count > 1 {
                ScriptColorBar(entries: entries, formatting: formatting)
            }
            Spacer(minLength: 0)
            Button("Done", action: dismissKeyboard)
                .fixedSize()
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ScriptPaletteSettings: View {
    @Bindable var model: AppModel

    var body: some View {
        Section {
            HStack(spacing: 0) {
                ForEach(model.editorPalette) { entry in
                    PaletteColorWell(
                        hex: entry.hex,
                        canDelete: model.editorPalette.count > 1,
                        onChange: { model.setPaletteColor($0, id: entry.id) },
                        onDelete: { model.removePaletteColor(id: entry.id) }
                    )
                    .frame(width: 32, height: 32)
                    .frame(maxWidth: .infinity)
                }
                if model.editorPalette.count < AppModel.maximumPaletteColors {
                    Button { model.addPaletteColor() } label: { Image(systemName: "plus") }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .accessibilityLabel("Add palette color")
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Editor Color Palette")
        } footer: {
            Text("Tap a color to customize it. Touch and hold for Delete. Keep 1–8 colors; quick colors are hidden when only one remains.")
        }
    }
}

private struct PaletteColorWell: UIViewRepresentable {
    let hex: String
    let canDelete: Bool
    let onChange: (String) -> Void
    let onDelete: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> UIColorWell {
        let well = UIColorWell()
        well.title = "Palette Color"
        well.supportsAlpha = false
        well.selectedColor = UIColor(rgbHex: hex)
        well.addTarget(context.coordinator, action: #selector(Coordinator.colorChanged(_:)), for: .valueChanged)
        // Own the context menu at the native control level so Form cannot
        // promote a swatch's menu to the entire palette row.
        well.addInteraction(UIContextMenuInteraction(delegate: context.coordinator))
        well.accessibilityLabel = "Palette color \(hex)"
        return well
    }

    func updateUIView(_ well: UIColorWell, context: Context) {
        context.coordinator.parent = self
        if well.selectedColor?.rgbHex != hex {
            well.selectedColor = UIColor(rgbHex: hex)
        }
        well.accessibilityLabel = "Palette color \(hex)"
    }

    final class Coordinator: NSObject, UIContextMenuInteractionDelegate {
        var parent: PaletteColorWell
        init(parent: PaletteColorWell) { self.parent = parent }

        @objc func colorChanged(_ well: UIColorWell) {
            if let color = well.selectedColor { parent.onChange(color.rgbHex) }
        }

        private func preview(for interaction: UIContextMenuInteraction) -> UITargetedPreview? {
            guard let well = interaction.view else { return nil }
            let parameters = UIPreviewParameters()
            parameters.backgroundColor = .clear
            parameters.visiblePath = UIBezierPath(ovalIn: well.bounds)
            return UITargetedPreview(view: well, parameters: parameters)
        }

        func contextMenuInteraction(_ interaction: UIContextMenuInteraction, previewForHighlightingMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
            preview(for: interaction)
        }

        func contextMenuInteraction(_ interaction: UIContextMenuInteraction, previewForDismissingMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
            preview(for: interaction)
        }

        func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
            UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
                guard let self else { return nil }
                let delete = UIAction(title: "Delete", image: UIImage(systemName: "trash"), attributes: parent.canDelete ? [.destructive] : [.destructive, .disabled]) { [weak self] _ in
                    guard let self, parent.canDelete else { return }
                    parent.onDelete()
                }
                return UIMenu(children: [delete])
            }
        }
    }
}
