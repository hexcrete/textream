// Settings tests must not start servers or overlays when constructing native controls.
final class TextreamService {
    static let shared = TextreamService()
    func updateKeepAwakeActivity(enabled: Bool) {}
    func updateBrowserServer() {}
    func updateDirectorServer() {}
}
