// Settings tests must not start servers or overlays when constructing native controls.
final class TextreamService {
    static let shared = TextreamService()
    func updateKeepAwakeActivity(enabled: Bool) {}
    func updateBrowserServer() {}
    func updateDirectorServer() {}
}

final class SpeechRecognizer {
    var recognizedCharCount = 0
    var isListening = false
    var isSpeaking = false
    var lastSpokenText = ""
    var audioLevels: [Double] = []
}
