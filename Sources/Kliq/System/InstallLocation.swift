import AppKit
import Darwin
import Foundation

/// Detects running from the disk image or a translocated copy, and offers to move into
/// /Applications, the only place macOS keeps the Accessibility permission and launch at login.
@MainActor
enum InstallLocation {
    private static let destination = URL(fileURLWithPath: "/Applications/Kliq.app")

    /// True when running from a mounted disk image or a quarantined copy macOS moved to a random path.
    nonisolated static var isOutsideApplications: Bool {
        let path = Bundle.main.bundlePath
        guard Bundle.main.bundleURL.pathExtension == "app" else { return false }
        return path.hasPrefix("/Volumes/") || path.contains("/AppTranslocation/")
    }

    /// Asks to move into /Applications. Returns true when the moved copy is opening and this
    /// instance is about to quit, so the caller should not start the app.
    static func offerMove() -> Bool {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Move Kliq to Applications?"
        alert.informativeText = "macOS can only keep Kliq's permission and start it at login when it runs from the Applications folder."
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Not Now").keyEquivalent = "\u{1b}"
        guard alert.runModal() == .alertFirstButtonReturn else { return false }

        do {
            try copyToApplications()
        } catch {
            showMoveFailed()
            return false
        }
        openMovedCopy()
        return true
    }

    private static func copyToApplications() throws {
        let source = originalURL(of: Bundle.main.bundleURL).standardizedFileURL
        let files = FileManager.default
        if source.path != destination.path {
            if files.fileExists(atPath: destination.path) {
                try files.trashItem(at: destination, resultingItemURL: nil)
            }
            try files.copyItem(at: source, to: destination)
        }
        clearQuarantine(destination)
    }

    /// A copied bundle keeps the download quarantine flag, which would get it translocated again.
    private static func clearQuarantine(_ url: URL) {
        var paths = [url.path]
        if let items = FileManager.default.enumerator(atPath: url.path) {
            for case let item as String in items { paths.append(url.appendingPathComponent(item).path) }
        }
        for path in paths { removexattr(path, "com.apple.quarantine", XATTR_NOFOLLOW) }
    }

    private static func openMovedCopy() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: destination, configuration: configuration) { _, error in
            Task { @MainActor in
                // If macOS won't open it, show the copy so the user can open it from Finder.
                if error != nil { NSWorkspace.shared.activateFileViewerSelecting([destination]) }
                NSApp.terminate(nil)
            }
        }
    }

    private static func showMoveFailed() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Kliq couldn't be moved"
        alert.informativeText = "Open the Applications folder in Finder and drag Kliq into it yourself (you may be asked for an administrator name and password), then open Kliq from there. Kliq keeps running for now."
        alert.runModal()
    }

    // MARK: Translocation

    private typealias IsTranslocatedURL = @convention(c) (CFURL, UnsafeMutablePointer<Bool>, UnsafeMutableRawPointer?) -> UInt8
    private typealias CreateOriginalPathForURL = @convention(c) (CFURL, UnsafeMutableRawPointer?) -> Unmanaged<CFURL>?

    /// Where a translocated bundle really lives, using Security calls looked up at runtime.
    /// Returns `url` unchanged when it isn't translocated or the calls are unavailable.
    private static func originalURL(of url: URL) -> URL {
        guard let security = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY) else { return url }
        defer { dlclose(security) }
        guard let isSymbol = dlsym(security, "SecTranslocateIsTranslocatedURL"),
              let originalSymbol = dlsym(security, "SecTranslocateCreateOriginalPathForURL") else { return url }
        let isTranslocatedURL = unsafeBitCast(isSymbol, to: IsTranslocatedURL.self)
        let createOriginalPath = unsafeBitCast(originalSymbol, to: CreateOriginalPathForURL.self)
        var translocated = false
        guard isTranslocatedURL(url as CFURL, &translocated, nil) != 0, translocated,
              let original = createOriginalPath(url as CFURL, nil) else { return url }
        return original.takeRetainedValue() as URL
    }
}
