import SwiftUI
import AppKit

struct PaletteEntry: Identifiable {
    let id = UUID()
    var hex: String
}

struct QuickColorPalette: View {
    let entries: [PaletteEntry]
    let formatting: EditorFormattingController

    var body: some View {
        HStack(spacing: 2) {
            ForEach(entries) { entry in
                Button { formatting.applyColor(entry.hex) } label: {
                    Circle()
                        .fill(Color(nsColor: NSColor(rgbHex: entry.hex)))
                        .frame(width: 12, height: 12)
                        .overlay { Circle().strokeBorder(.black.opacity(0.15), lineWidth: 1) }
                        .frame(width: 24, height: 24)
                        .overlay {
                            if formatting.selectedColor == entry.hex {
                                Circle().strokeBorder(Color.accentColor, lineWidth: 3)
                                    .frame(width: 22, height: 22)
                            }
                        }
                }
                .buttonStyle(.plain)
                .help("Use \(entry.hex) for selected or new text")
                .accessibilityLabel("Text color \(entry.hex)")
                .accessibilityValue(formatting.selectedColor == entry.hex ? "Selected" : "Not selected")
            }
        }
        .padding(.horizontal, 6)
        .fixedSize()
    }
}

/// AppKit owns both the drag session and color panel; SwiftUI never feeds panel.color back during a drag.
struct PaletteSettingsRow: NSViewRepresentable {
    let settings: NotchSettings
    let entries: [PaletteEntry]

    func makeNSView(context: Context) -> PaletteRow {
        let row = PaletteRow(settings: settings)
        row.refresh()
        return row
    }

    func updateNSView(_ row: PaletteRow, context: Context) {
        _ = settings.editorColorPaletteHex
        row.refresh()
    }

    static func dismantleNSView(_ row: PaletteRow, coordinator: ()) { row.closePicker() }
}

class PaletteRow: NSView {
    static let pasteboardType = NSPasteboard.PasteboardType("dev.fka.textream.palette-entry")
    let settings: NotchSettings
    private var buttons: [UUID: PaletteSwatch] = [:]
    private var editingID: UUID?
    private var insertionIndex: Int?
    private let addButton = NSButton()
    private let step: CGFloat = 34

    init(settings: NotchSettings) {
        self.settings = settings
        super.init(frame: .zero)
        registerForDraggedTypes([Self.pasteboardType])
        addButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "Add color")
        addButton.bezelStyle = .regularSquare
        addButton.isBordered = false
        addButton.target = self
        addButton.action = #selector(addColor)
        addSubview(addButton)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize { NSSize(width: step * CGFloat(settings.editorPalette.count + 1), height: 34) }

    func refresh() {
        let ids = Set(settings.editorPalette.map(\.id))
        for id in Array(buttons.keys) where !ids.contains(id) {
            buttons.removeValue(forKey: id)?.removeFromSuperview()
            if editingID == id { closePicker() }
        }
        for (index, entry) in settings.editorPalette.enumerated() {
            let button = buttons[entry.id] ?? PaletteSwatch(entryID: entry.id, row: self)
            if buttons[entry.id] == nil { buttons[entry.id] = button; addSubview(button) }
            button.frame = NSRect(x: CGFloat(index) * step, y: 2, width: 30, height: 30)
            button.image = NSImage(size: NSSize(width: 26, height: 26), flipped: false) { rect in
                NSColor(rgbHex: entry.hex).setFill()
                NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 7, yRadius: 7).fill()
                NSColor.separatorColor.setStroke()
                NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 7, yRadius: 7).stroke()
                return true
            }
            button.setAccessibilityLabel("Edit palette color \(entry.hex)")
        }
        addButton.frame = NSRect(x: CGFloat(settings.editorPalette.count) * step, y: 2, width: 30, height: 30)
        addButton.isEnabled = settings.editorPalette.count < 9
        invalidateIntrinsicContentSize()
    }

    @objc private func addColor() {
        guard settings.editorPalette.count < 9 else { return }
        let preset = NotchSettings.defaultEditorPalette.first { !settings.editorColorPaletteHex.contains($0) } ?? "#8e8e93"
        settings.editorPalette.append(PaletteEntry(hex: preset))
    }

    func openPicker(for id: UUID) {
        guard let entry = settings.editorPalette.first(where: { $0.id == id }) else { return }
        let panel = NSColorPanel.shared
        panel.setTarget(nil)
        panel.setAction(nil)
        editingID = id
        panel.showsAlpha = false
        panel.isContinuous = true
        panel.color = NSColor(rgbHex: entry.hex)
        panel.setTarget(self)
        panel.setAction(#selector(colorChanged(_:)))
        if let window {
            panel.setFrameOrigin(NSPoint(x: window.frame.midX - panel.frame.width / 2,
                                         y: window.frame.midY - panel.frame.height / 2))
        }
        panel.orderFront(nil)
    }

    @objc private func colorChanged(_ panel: NSColorPanel) {
        guard let id = editingID, let index = settings.editorPalette.firstIndex(where: { $0.id == id }) else { return }
        let hex = panel.color.rgbHex
        if settings.editorPalette[index].hex != hex { settings.editorPalette[index].hex = hex }
    }

    func closePicker() {
        guard editingID != nil else { return }
        editingID = nil
        let panel = NSColorPanel.shared
        panel.setTarget(nil)
        panel.setAction(nil)
        panel.close()
    }

    private func draggedID(_ info: NSDraggingInfo) -> UUID? {
        info.draggingPasteboard.string(forType: Self.pasteboardType).flatMap(UUID.init(uuidString:))
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { draggingUpdated(sender) }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let id = draggedID(sender), buttons[id] != nil else { return [] }
        let point = convert(sender.draggingLocation, from: nil)
        insertionIndex = min(settings.editorPalette.count, max(0, Int((point.x + 2) / step)))
        needsDisplay = true
        return .move
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { insertionIndex = nil; needsDisplay = true }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let id = draggedID(sender), let source = settings.editorPalette.firstIndex(where: { $0.id == id }) else { return false }
        let target = insertionIndex ?? source
        var entries = settings.editorPalette
        let entry = entries.remove(at: source)
        entries.insert(entry, at: min(entries.count, max(0, target - (source < target ? 1 : 0))))
        settings.editorPalette = entries
        insertionIndex = nil
        needsDisplay = true
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if let index = insertionIndex {
            NSColor.controlAccentColor.setFill()
            NSRect(x: max(0, CGFloat(index) * step - 3), y: 1, width: 2, height: 32).fill()
        }
    }

    func dragEnded(id: UUID, point: NSPoint, operation: NSDragOperation, cancelled: Bool) {
        insertionIndex = nil
        needsDisplay = true
        guard !cancelled, operation.isEmpty, settings.editorPalette.count > 1, let window else { return }
        let local = convert(window.convertPoint(fromScreen: point), from: nil)
        // A missed insertion within the row must never delete a color.
        guard !bounds.insetBy(dx: -10, dy: -12).contains(local) else { return }
        settings.editorPalette.removeAll { $0.id == id }
    }
}

class PaletteSwatch: NSButton, NSDraggingSource {
    let entryID: UUID
    weak var row: PaletteRow?
    private var cancelled = false
    private var escapeMonitor: Any?

    init(entryID: UUID, row: PaletteRow) {
        self.entryID = entryID
        self.row = row
        super.init(frame: .zero)
        isBordered = false
        imagePosition = .imageOnly
        target = self
        action = #selector(editColor)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func editColor() { row?.openPicker(for: entryID) }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if next.type == .leftMouseUp { editColor(); return }
            guard hypot(next.locationInWindow.x - event.locationInWindow.x,
                        next.locationInWindow.y - event.locationInWindow.y) > 4 else { continue }
            let item = NSPasteboardItem()
            item.setString(entryID.uuidString, forType: PaletteRow.pasteboardType)
            let draggingItem = NSDraggingItem(pasteboardWriter: item)
            draggingItem.setDraggingFrame(bounds, contents: image)
            cancelled = false
            escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] key in
                if key.keyCode == 53 { self?.cancelled = true }
                return key
            }
            beginDraggingSession(with: [draggingItem], event: next, source: self)
            return
        }
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? .move : []
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        escapeMonitor = nil
        row?.dragEnded(id: entryID, point: screenPoint, operation: operation, cancelled: cancelled)
    }
}
