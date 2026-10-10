import AppKit

struct TextColorRun: Codable, Equatable {
    var text: String
    var color: String

    init(text: String, color: String = "#ffffff") {
        self.text = text
        self.color = Self.canonicalHex(color) ?? "#ffffff"
    }

    nonisolated static func canonicalHex(_ value: String) -> String? {
        let hex = value.lowercased()
        guard hex.count == 7, hex.first == "#",
              hex.dropFirst().allSatisfy({ "0123456789abcdef".contains($0) }) else { return nil }
        return hex
    }
}

extension NSColor {
    convenience init(rgbHex: String) {
        let value = UInt32((TextColorRun.canonicalHex(rgbHex) ?? "#ffffff").dropFirst(), radix: 16)!
        self.init(srgbRed: CGFloat((value >> 16) & 255) / 255,
                  green: CGFloat((value >> 8) & 255) / 255,
                  blue: CGFloat(value & 255) / 255, alpha: 1)
    }

    var rgbHex: String {
        guard let rgb = usingColorSpace(.sRGB) else { return "#ffffff" }
        func channel(_ value: CGFloat) -> Int { Int((min(1, max(0, value)) * 255).rounded()) }
        return String(format: "#%02x%02x%02x", channel(rgb.redComponent), channel(rgb.greenComponent), channel(rgb.blueComponent))
    }
}

struct FormattedPage: Codable, Equatable {
    private(set) var runs: [TextColorRun]
    var text: String { runs.map(\.text).joined() }

    init(_ text: String = "") { self.init(runs: [TextColorRun(text: text)]) }

    init(runs: [TextColorRun]) {
        self.runs = []
        for run in runs where !run.text.isEmpty {
            let color = TextColorRun.canonicalHex(run.color) ?? "#ffffff"
            if self.runs.last?.color == color {
                self.runs[self.runs.count - 1].text += run.text
            } else {
                self.runs.append(TextColorRun(text: run.text, color: color))
            }
        }
    }

    init(attributedString: NSAttributedString) {
        var runs: [TextColorRun] = []
        attributedString.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: attributedString.length)) { value, range, _ in
            runs.append(TextColorRun(text: (attributedString.string as NSString).substring(with: range),
                                     color: (value as? NSColor)?.rgbHex ?? "#ffffff"))
        }
        self.init(runs: runs)
    }

    var attributedString: NSAttributedString {
        let result = NSMutableAttributedString(string: "")
        for run in runs {
            result.append(NSAttributedString(string: run.text, attributes: [.foregroundColor: NSColor(rgbHex: run.color)]))
        }
        return result
    }

    /// Dictation replaces a changing segment while preserving the colors outside it.
    func updatingText(_ newText: String, insertionColor: String? = nil) -> FormattedPage {
        let old = Array(text), new = Array(newText)
        var prefix = 0
        while prefix < min(old.count, new.count), old[prefix] == new[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < min(old.count, new.count) - prefix,
              old[old.count - 1 - suffix] == new[new.count - 1 - suffix] { suffix += 1 }
        let start = String(old.prefix(prefix)).utf16.count
        let length = String(old.dropFirst(prefix).dropLast(suffix)).utf16.count
        let storage = NSMutableAttributedString(attributedString: attributedString)
        let inherited = start > 0 ? storage.attribute(.foregroundColor, at: start - 1, effectiveRange: nil) as? NSColor : nil
        let color = insertionColor.map { NSColor(rgbHex: $0) } ?? inherited ?? .white
        let replacement = String(new.dropFirst(prefix).dropLast(suffix))
        storage.replaceCharacters(in: NSRange(location: start, length: length),
                                  with: NSAttributedString(string: replacement, attributes: [.foregroundColor: color]))
        return FormattedPage(attributedString: storage)
    }

    /// Projection intentionally uses the first character's color for each display word.
    func wordColors(for words: [String]) -> [String] {
        let source = text as NSString
        var offset = 0
        let storage = attributedString
        return words.map { word in
            let range = source.range(of: word, options: [], range: NSRange(location: offset, length: source.length - offset))
            guard range.location != NSNotFound else { return "#ffffff" }
            offset = NSMaxRange(range)
            let color = (storage.attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? NSColor)?.rgbHex ?? "#ffffff"
            return color == "#000000" ? "#ffffff" : color
        }
    }

    func prefix(utf16Count: Int) -> FormattedPage {
        FormattedPage(attributedString: attributedString.attributedSubstring(from: NSRange(location: 0, length: min(max(0, utf16Count), text.utf16.count))))
    }

    /// Speech inserts one space between display words, even for CJK and paragraph breaks.
    func sourceUTF16Offset(forSpeechOffset count: Int, words: [String]) -> Int {
        guard count > 0 else { return 0 }
        let source = text as NSString
        var speechOffset = 0, sourceOffset = 0
        for word in words {
            let range = source.range(of: word, options: [], range: NSRange(location: sourceOffset, length: source.length - sourceOffset))
            guard range.location != NSNotFound else { return sourceOffset }
            if count <= speechOffset + word.count {
                return range.location + String(word.prefix(max(0, count - speechOffset))).utf16.count
            }
            speechOffset += word.count + 1
            sourceOffset = NSMaxRange(range)
        }
        return source.length
    }

    var normalizedForDirector: FormattedPage {
        var result: [TextColorRun] = []
        var separator = "", separatorColor = "#ffffff"
        func append(_ text: String, _ color: String) {
            if result.last?.color == color { result[result.count - 1].text += text }
            else { result.append(TextColorRun(text: text, color: color)) }
        }
        for run in runs {
            for character in run.text {
                if character.isWhitespace {
                    if separator.isEmpty { separatorColor = run.color }
                    separator = character == "\r" || character == "\n" || character == "\r\n" ? "\n" : (separator.isEmpty ? " " : separator)
                } else {
                    if !result.isEmpty, !separator.isEmpty { append(separator, separatorColor) }
                    separator = ""
                    append(String(character), run.color)
                }
            }
        }
        return FormattedPage(runs: result)
    }
}

struct FormattedDocument: Codable {
    let version: Int
    let pages: [FormattedPage]

    init(pages: [FormattedPage]) { version = 1; self.pages = pages }

    static func load(_ data: Data) throws -> [FormattedPage] {
        let decoder = JSONDecoder()
        if let legacy = try? decoder.decode([String].self, from: data), !legacy.isEmpty {
            return legacy.map { FormattedPage($0) }
        }
        let document = try decoder.decode(Self.self, from: data)
        guard document.version == 1, !document.pages.isEmpty else {
            throw NSError(domain: "TextreamDocument", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Unsupported or empty Textream document. The open document has not been changed."])
        }
        return document.pages.map { FormattedPage(runs: $0.runs) }
    }
}

struct EditorDocument {
    var pages: [FormattedPage]
    private(set) var savedPages: [FormattedPage]
    var hasUnsavedChanges: Bool { pages != savedPages }

    init(pages: [FormattedPage] = [FormattedPage()]) {
        self.pages = pages
        savedPages = pages
    }

    mutating func save(to url: URL) throws {
        let data = try JSONEncoder().encode(FormattedDocument(pages: pages))
        try data.write(to: url, options: .atomic)
        savedPages = pages
    }
}
