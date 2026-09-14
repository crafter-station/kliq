import AppKit
import Observation
import SwiftUI

/// The menu bar item and its menu. The menu is built once and brought up to date each
/// time it opens, and again on any change while it stays open.
@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let controller: AppController
    private let statusItem: NSStatusItem
    private let menu = NSMenu()

    private let header = MenuHeaderView()
    private let accessNotice = MenuNoticeView(buttonTitle: "Allow…")
    private let sleepNotice = MenuNoticeView(buttonTitle: "Wake")
    private let volume = MenuSliderView(accessibilityLabel: "Volume")
    private let accessItem = NSMenuItem()
    private let sleepItem = NSMenuItem()
    private let switchesHeader = NSMenuItem.sectionHeader(title: "Sound")
    private var setItems: [NSMenuItem] = []
    private var shownSetNames: [String]?
    /// Bumped on every open, so tracking left over from an earlier open stops.
    private var openCount = 0
    private var isOpen = false

    #if DEBUG
    /// The live instance, for MenuSnapshots.
    private(set) static weak var current: StatusMenuController?
    #endif

    init(controller: AppController) {
        self.controller = controller
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        #if DEBUG
        Self.current = self
        #endif
        menu.delegate = self
        menu.minimumWidth = MenuMetrics.width
        statusItem.menu = menu
        statusItem.button?.imagePosition = .imageOnly
        build()
        refresh()
        refreshIcon()
    }

    func refreshIcon() {
        guard let button = statusItem.button else { return }
        let settings = controller.settings
        let state = controller.state
        let tip: String
        if !settings.isEnabled {
            tip = "Kliq is off"
        } else if state.isSleeping {
            let reasons = state.sleepReasons.joined(separator: ", ")
            tip = reasons.isEmpty ? "Kliq is sleeping" : "Kliq is sleeping · \(reasons)"
        } else {
            tip = "Kliq is on"
        }
        // The keycap mark, with its K while sound is on and a blank key when off.
        button.image = settings.isEnabled ? Self.iconOn : Self.iconOff
        button.setAccessibilityLabel(tip)
        button.toolTip = tip
        let dim = settings.dimMenuBarIconWhenOff && (!settings.isEnabled || state.isSleeping)
        button.alphaValue = dim ? 0.45 : 1
    }

    private static let iconOn = KliqLogo.menuBarTemplate()

    private static let iconOff: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            var style = KliqLogo.menuBarStyle
            style.letter = false
            KliqLogo.draw(in: rect.insetBy(dx: rect.width * 0.06, dy: rect.width * 0.06), color: .black, style: style)
            return true
        }
        image.isTemplate = true
        return image
    }()

    // MARK: Menu

    func menuWillOpen(_ menu: NSMenu) {
        isOpen = true
        openCount += 1
        track(openCount)
    }

    func menuDidClose(_ menu: NSMenu) {
        isOpen = false
    }

    /// Refreshes now and whenever anything the menu shows changes, until it closes.
    private func track(_ open: Int) {
        guard isOpen, open == openCount else { return }
        withObservationTracking {
            refresh()
        } onChange: { [weak self] in
            Task { @MainActor in self?.track(open) }
        }
    }

    private func build() {
        connect(header.toggle, #selector(enabledChanged(_:)))
        menu.addItem(viewItem(header))

        connect(accessNotice.button, #selector(allowAccess))
        accessNotice.text = "Needs Accessibility access"
        accessItem.view = accessNotice
        menu.addItem(accessItem)

        connect(sleepNotice.button, #selector(wakeNow))
        sleepItem.view = sleepNotice
        menu.addItem(sleepItem)

        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: "Volume"))
        connect(volume.slider, #selector(volumeChanged(_:)))
        menu.addItem(viewItem(volume))

        menu.addItem(.separator())
        menu.addItem(switchesHeader)
        // The set items go here, inserted by refreshSets.

        menu.addItem(.separator())
        menu.addItem(actionItem("Settings…", #selector(openSettings), key: ","))
        menu.addItem(.separator())
        menu.addItem(actionItem("Quit Kliq", #selector(quit), key: "q"))
    }

    private func refresh() {
        let settings = controller.settings
        let state = controller.state
        header.toggle.state = settings.isEnabled ? .on : .off
        if !settings.isEnabled {
            header.statusText = "Off"
        } else if !state.accessibilityGranted {
            header.statusText = "Needs access"
        } else if state.isSleeping {
            header.statusText = "Quiet"
        } else if let selected = state.availableSets.first(where: { $0.name == settings.selectedSetName }) {
            header.statusText = "On · \(selected.displayName)"
        } else {
            header.statusText = "On"
        }
        // Text first, so the row has its final height when the menu measures it on appearing.
        if state.isSleeping {
            let reasons = state.sleepReasons.joined(separator: ", ")
            sleepNotice.text = reasons.isEmpty ? "Sleeping" : "Sleeping · \(reasons)"
        }
        accessItem.isHidden = state.accessibilityGranted
        sleepItem.isHidden = !state.isSleeping
        // Skipped while it matches, so a refresh never fights a drag.
        if abs(volume.doubleValue - settings.volume) > 0.0001 {
            volume.doubleValue = settings.volume
        }
        refreshSets(state.availableSets, selected: settings.selectedSetName)
    }

    /// Rebuilds the set items when the list changed, then moves the checkmark.
    private func refreshSets(_ sets: [SoundSet], selected: String) {
        let names = sets.map(\.name)
        if names != shownSetNames {
            shownSetNames = names
            setItems.forEach(menu.removeItem)
            setItems = sets.map { set in
                let item = NSMenuItem(title: set.displayName, action: #selector(selectSet(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = set.name
                return item
            }
            if setItems.isEmpty {
                let none = NSMenuItem(title: "No sound sets found", action: nil, keyEquivalent: "")
                none.isEnabled = false
                setItems = [none]
            }
            var index = menu.index(of: switchesHeader) + 1
            for item in setItems {
                menu.insertItem(item, at: index)
                index += 1
            }
        }
        for (item, set) in zip(setItems, sets) {
            item.state = set.name == selected ? .on : .off
        }
    }

    private func viewItem(_ view: NSView) -> NSMenuItem {
        let item = NSMenuItem()
        item.view = view
        return item
    }

    private func connect(_ control: NSControl, _ action: Selector) {
        control.target = self
        control.action = action
    }

    private func actionItem(_ title: String, _ action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    // MARK: Actions

    @objc private func enabledChanged(_ sender: NSSwitch) {
        controller.settings.isEnabled = sender.state == .on
    }

    @objc private func volumeChanged(_ sender: NSSlider) {
        controller.settings.volume = sender.doubleValue
        volume.updateReadout()
        // On release, play a few keys at the new level. The task runs after the settings
        // observer has passed the volume to the engine.
        let settings = controller.settings
        if NSApp.currentEvent?.type == .leftMouseUp, settings.isEnabled, !controller.state.isSleeping {
            Task { @MainActor [controller] in controller.previewCurrentSet() }
        }
    }

    @objc private func selectSet(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        controller.selectSet(named: name, preview: true)
    }

    @objc private func wakeNow() {
        menu.cancelTracking()
        controller.wake()
    }

    @objc private func allowAccess() {
        menu.cancelTracking()
        controller.showOnboarding()
    }

    @objc private func openSettings() { controller.showSettings() }
    @objc private func quit() { NSApp.terminate(nil) }
}

#if DEBUG
extension StatusMenuController {
    /// Opens the menu and returns once it closes. Prefers a Retina screen, where it pops up
    /// at the top left, so the capture is 2x; otherwise it opens from the status item.
    func openMenuForSnapshot(appearance: NSAppearance?) {
        menu.appearance = appearance
        if let screen = NSScreen.screens.first(where: { $0.backingScaleFactor >= 2 }) {
            let frame = screen.visibleFrame
            menu.popUp(positioning: nil, at: NSPoint(x: frame.minX + 40, y: frame.maxY - 8), in: nil)
        } else {
            statusItem.button?.performClick(nil)
        }
    }

    func closeMenuForSnapshot() { menu.cancelTracking() }

    /// The window the open menu is drawn in.
    var menuWindowForSnapshot: NSWindow? { header.window }
}
#endif
