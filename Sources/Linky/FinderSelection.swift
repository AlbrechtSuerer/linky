import Foundation

enum FinderSelectionError: Error {
    case notAllowed
    case other(String)
}

/// Reads the current Finder selection via Apple Events.
enum FinderSelection {
    private static let source = """
    tell application "Finder"
        set thePaths to {}
        repeat with anItem in (get selection)
            set end of thePaths to POSIX path of (anItem as alias)
        end repeat
        return thePaths
    end tell
    """

    static func read() -> Result<[URL], FinderSelectionError> {
        var errorInfo: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return .failure(.other("Script")) }
        let result = script.executeAndReturnError(&errorInfo)

        if let errorInfo {
            let code = errorInfo[NSAppleScript.errorNumber] as? Int ?? 0
            if code == -1743 || code == -1744 { return .failure(.notAllowed) }
            return .failure(.other(errorInfo[NSAppleScript.errorMessage] as? String ?? "Error \(code)"))
        }

        var urls: [URL] = []
        if result.numberOfItems > 0 {
            for i in 1...result.numberOfItems {
                if let path = result.atIndex(i)?.stringValue {
                    urls.append(URL(fileURLWithPath: path))
                }
            }
        }
        return .success(urls)
    }
}
