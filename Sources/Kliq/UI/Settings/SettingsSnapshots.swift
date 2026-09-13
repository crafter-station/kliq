#if DEBUG
import AppKit
import ScreenCaptureKit

/// Debug builds only: when KLIQ_SNAPSHOT_DIR is set, renders every Settings page (as it
/// opens, then with "More options" expanded) and the welcome guide in dark and light mode
/// into that folder as PNGs, then quits. Shots show the window over the desktop picture.
@MainActor
enum SettingsSnapshots {
    static let selectPage = Notification.Name("KliqSnapshotSelectPage")
    static let expandMoreOptions = Notification.Name("KliqSnapshotExpandMoreOptions")

    /// Pages with a "More options" disclosure.
    private static let pagesWithMoreOptions: Set<SettingsPage> = [.general, .sound, .sleep]

    static func runIfRequested(controller: AppController) {
        guard let path = ProcessInfo.processInfo.environment["KLIQ_SNAPSHOT_DIR"], !path.isEmpty else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        Task { @MainActor in
            await run(controller: controller, directory: directory)
            NSApp.terminate(nil)
        }
    }

    private static func run(controller: AppController, directory: URL) async {
        try? await Task.sleep(for: .milliseconds(500))
        controller.showSettings()
        try? await Task.sleep(for: .milliseconds(500))
        let state = controller.state
        let granted = state.accessibilityGranted
        if let settings = window(titled: "Kliq Settings") {
            for page in SettingsPage.allCases {
                await capturePage(page, in: settings, name: page.rawValue, directory: directory)
            }
            // Transient states the normal pass can't show.
            state.accessibilityGranted = false
            state.isSleeping = true
            state.sleepReasons = ["microphone in use", "music playing"]
            state.hotKeyUnavailable = true
            state.notificationsDenied = true
            state.statusMessage = "Kliq couldn't play Thock. Choose another switch set."
            for page in [SettingsPage.general, .sound, .sleep] {
                await capturePage(page, in: settings, name: "\(page.rawValue)-alt", directory: directory)
            }
            settings.orderOut(nil)
        }
        controller.showOnboarding()
        try? await Task.sleep(for: .milliseconds(500))
        if let onboarding = window(titled: "Welcome to Kliq") {
            await capture(onboarding, name: "onboarding-alt", in: directory)
            state.accessibilityGranted = granted
            await capture(onboarding, name: "onboarding", in: directory)
        }
    }

    /// The page as it opens, then with "More options" expanded, then scrolled to its end.
    private static func capturePage(_ page: SettingsPage, in window: NSWindow, name: String, directory: URL) async {
        NotificationCenter.default.post(name: selectPage, object: page)
        await capture(window, name: name, in: directory)
        guard pagesWithMoreOptions.contains(page) else { return }
        NotificationCenter.default.post(name: expandMoreOptions, object: nil)
        await capture(window, name: "\(name)-more", in: directory)
        try? await Task.sleep(for: .milliseconds(200))
        scrollPageToBottom(in: window)
        await capture(window, name: "\(name)-more-bottom", in: directory)
    }

    /// Scrolls the page's form (the scroll view right of the sidebar) to its end.
    private static func scrollPageToBottom(in window: NSWindow) {
        guard let root = window.contentView else { return }
        var queue = [root]
        while !queue.isEmpty {
            let view = queue.removeFirst()
            if let scroll = view as? NSScrollView, let document = scroll.documentView,
               scroll.convert(scroll.bounds, to: root).minX > 150 {
                let clip = scroll.contentView
                let bottom = document.isFlipped ? max(0, document.frame.height - clip.bounds.height) : 0
                clip.scroll(to: NSPoint(x: 0, y: bottom))
                scroll.reflectScrolledClipView(clip)
                return
            }
            queue.append(contentsOf: view.subviews)
        }
    }

    private static func window(titled title: String) -> NSWindow? {
        NSApp.windows.first { $0.title == title && $0.isVisible }
    }

    private static func capture(_ window: NSWindow, name: String, in directory: URL) async {
        for (suffix, appearance) in [("dark", NSAppearance.Name.darkAqua), ("light", .aqua)] {
            NSApp.appearance = NSAppearance(named: appearance)
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            try? await Task.sleep(for: .milliseconds(500))
            let url = directory.appendingPathComponent("\(name)-\(suffix).png")
            let png = await screenCapture(window) ?? cachedDisplay(window)
            try? png?.write(to: url)
        }
    }

    /// The composited window over the desktop picture, with a margin of it around the window.
    /// Other apps' windows are left out. Only used when screen capture is already allowed,
    /// so it never prompts.
    private static func screenCapture(_ window: NSWindow) async -> Data? {
        guard CGPreflightScreenCaptureAccess(),
              let screen = window.screen,
              let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
              let display = content.displays.first(where: { $0.displayID == displayID }),
              let target = content.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) })
        else { return nil }
        // The desktop picture and icons sit on layers below every normal window.
        let desktop = content.windows.filter { $0.windowLayer < 0 }
        let filter = SCContentFilter(display: display, including: desktop + [target])
        let frame = window.frame.insetBy(dx: -40, dy: -40)
        let configuration = SCStreamConfiguration()
        let scale = window.backingScaleFactor
        configuration.sourceRect = CGRect(x: frame.minX - screen.frame.minX, y: screen.frame.maxY - frame.maxY,
                                          width: frame.width, height: frame.height)
        configuration.width = Int(frame.width * scale)
        configuration.height = Int(frame.height * scale)
        configuration.showsCursor = false
        guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    /// Fallback without screen capture access. cacheDisplay skips most SwiftUI layer
    /// content, so the layer tree is rendered on top; scroll views may still come out blank.
    private static func cachedDisplay(_ window: NSWindow) -> Data? {
        // The frame view includes the titlebar and its traffic lights.
        guard let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let layer = view.layer, let context = NSGraphicsContext(bitmapImageRep: rep) {
            let scale = CGFloat(rep.pixelsWide) / view.bounds.width
            context.cgContext.scaleBy(x: scale, y: scale)
            layer.render(in: context.cgContext)
            context.flushGraphics()
        }
        return rep.representation(using: .png, properties: [:])
    }
}
#endif
