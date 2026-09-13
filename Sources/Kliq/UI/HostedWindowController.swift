import AppKit
import SwiftUI

/// A single-instance NSWindow hosting a SwiftUI view, built lazily on first show.
/// The content runs under a transparent titlebar with only the traffic lights showing.
@MainActor
final class HostedWindowController {
    private let title: String
    private let content: () -> AnyView
    private var window: NSWindow?

    init<Content: View>(title: String, content: @escaping () -> Content) {
        self.title = title
        self.content = { AnyView(content()) }
    }

    func show() {
        if window == nil {
            let host = NSHostingController(rootView: content())
            // The views lay out their own titlebar band, so the window is exactly their size.
            host.safeAreaRegions = []
            let window = NSWindow(contentViewController: host)
            window.title = title
            window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            // An empty unified toolbar makes the titlebar 52 pt tall, which centers the
            // traffic lights on the page headers.
            window.toolbar = NSToolbar()
            window.toolbarStyle = .unified
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    func close() {
        window?.close()
    }
}
