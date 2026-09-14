import AppKit

@main
enum KliqApp {
    @MainActor static var delegate: AppDelegate?

    @MainActor
    static func main() {
        let app = NSApplication.shared
        let appDelegate = AppDelegate()
        delegate = appDelegate
        app.delegate = appDelegate
        app.setActivationPolicy(.accessory)
        app.mainMenu = makeMainMenu(target: appDelegate)
        app.run()
    }

    /// Never shown as a menu bar for an accessory app, but it still routes ⌘Q, ⌘W and the
    /// editing shortcuts while one of Kliq's windows is key.
    @MainActor
    private static func makeMainMenu(target: AppDelegate) -> NSMenu {
        let appMenu = NSMenu(title: "Kliq")
        let settings = appMenu.addItem(withTitle: "Settings…", action: #selector(AppDelegate.showSettings(_:)),
                                       keyEquivalent: ",")
        settings.target = target
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Kliq", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
            .keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")

        let mainMenu = NSMenu()
        for submenu in [appMenu, editMenu, windowMenu] {
            mainMenu.addItem(withTitle: submenu.title, action: nil, keyEquivalent: "").submenu = submenu
        }
        return mainMenu
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: AppController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if NSApp.applicationIconImage == nil || Bundle.main.bundleURL.pathExtension != "app" {
            NSApp.applicationIconImage = NSImage(systemSymbolName: "keyboard.fill", accessibilityDescription: "Kliq")
        }
        // Moving opens the copy in Applications and quits this one, so don't start anything here.
        if InstallLocation.isOutsideApplications, InstallLocation.offerMove() { return }
        let controller = AppController()
        self.controller = controller
        controller.start()
        #if DEBUG
        SettingsSnapshots.runIfRequested(controller: controller)
        MenuSnapshots.runIfRequested(controller: controller)
        #endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.shutdown()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller?.showSettings()
        return true
    }

    @objc func showSettings(_ sender: Any?) {
        controller?.showSettings()
    }
}
