#if DEBUG
import AppKit
import ScreenCaptureKit

/// Debug builds only: when KLIQ_MENU_SNAPSHOT_DIR is set, opens the menu bar menu in a
/// few states, saves each in dark and light mode into that folder as PNGs, then quits.
@MainActor
enum MenuSnapshots {
    static func runIfRequested(controller: AppController) {
        guard let path = ProcessInfo.processInfo.environment["KLIQ_MENU_SNAPSHOT_DIR"], !path.isEmpty,
              let menu = StatusMenuController.current else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        Task { @MainActor in
            await run(controller: controller, menu: menu, directory: directory)
            NSApp.terminate(nil)
        }
    }

    private static func run(controller: AppController, menu: StatusMenuController, directory: URL) async {
        try? await Task.sleep(for: .milliseconds(800))
        // An unsigned debug binary has no Accessibility access, so the welcome guide opens.
        for window in NSApp.windows where window.title == "Welcome to Kliq" { window.orderOut(nil) }
        let state = controller.state
        let settings = controller.settings
        let wasEnabled = settings.isEnabled

        state.accessibilityGranted = true
        await capture(menu, name: "menu", in: directory)

        // Sleep starts while the menu is open, and a second reason wraps the line, so this
        // also checks that the open menu shows, grows and shrinks the row.
        await capture(menu, name: "menu-sleeping", in: directory) {
            state.isSleeping = true
            state.sleepReasons = ["microphone in use"]
            try? await Task.sleep(for: .milliseconds(300))
            state.sleepReasons.append("music playing")
        }
        state.isSleeping = false
        state.sleepReasons = []

        state.accessibilityGranted = false
        settings.isEnabled = false
        await capture(menu, name: "menu-off", in: directory)
        settings.isEnabled = wasEnabled
    }

    /// Opens the menu, applies `whileOpen`, and saves it. The menu opens from a run loop
    /// timer rather than this task, so tasks keep running while it tracks, as they do when
    /// someone clicks the status item. Activity elsewhere can close the menu early, so each
    /// pass gets a few tries.
    private static func capture(_ menu: StatusMenuController, name: String, in directory: URL,
                                whileOpen: () async -> Void = {}) async {
        for (suffix, appearance) in [("dark", NSAppearance.Name.darkAqua), ("light", .aqua)] {
            for _ in 0..<3 {
                let open = Timer(timeInterval: 0, repeats: false) { _ in
                    MainActor.assumeIsolated { menu.openMenuForSnapshot(appearance: NSAppearance(named: appearance)) }
                }
                RunLoop.main.add(open, forMode: .common)
                try? await Task.sleep(for: .milliseconds(300))
                await whileOpen()
                try? await Task.sleep(for: .milliseconds(500))
                var saved = false
                if let window = menu.menuWindowForSnapshot, let png = await screenCapture(window) ?? cachedDisplay(window) {
                    saved = (try? png.write(to: directory.appendingPathComponent("\(name)-\(suffix).png"))) != nil
                }
                menu.closeMenuForSnapshot()
                try? await Task.sleep(for: .milliseconds(300))
                if saved { break }
            }
        }
    }

    /// The composited menu, material included. Only used when screen capture is already
    /// allowed, so it never prompts.
    private static func screenCapture(_ window: NSWindow) async -> Data? {
        guard CGPreflightScreenCaptureAccess(),
              let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
              let target = content.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) })
        else { return nil }
        let configuration = SCStreamConfiguration()
        let scale = window.backingScaleFactor
        configuration.width = Int(window.frame.width * scale)
        configuration.height = Int(window.frame.height * scale)
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        let filter = SCContentFilter(desktopIndependentWindow: target)
        guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    /// Fallback without screen capture access: the menu's views without the material.
    private static func cachedDisplay(_ window: NSWindow) -> Data? {
        guard let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }
}
#endif
