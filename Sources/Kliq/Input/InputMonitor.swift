import CoreGraphics
import Foundation

/// Listen-only CGEvent tap for keyboard and mouse events, run on its own thread
/// so main-thread work (menus, windows) never delays a click.
final class InputMonitor {
    enum Event {
        case keyDown(keyCode: Int64, isRepeat: Bool)
        case keyUp(keyCode: Int64)
        case modifierDown(keyCode: Int64)
        case modifierUp(keyCode: Int64)
        case mouseDown(button: Int)
        case mouseUp(button: Int)
    }

    var handler: (@Sendable (Event) -> Void)?
    private(set) var isRunning = false

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var thread: Thread?
    private var threadRunLoop: CFRunLoop?
    private var startResult = false
    private let started = DispatchSemaphore(value: 0)

    @discardableResult
    func start() -> Bool {
        if isRunning { return true }
        let worker = Thread { [unowned self] in self.threadMain() }
        worker.name = "run.crafter.kliq.event-tap"
        worker.qualityOfService = .userInteractive
        thread = worker
        worker.start()
        started.wait()
        isRunning = startResult
        if !isRunning { thread = nil }
        return isRunning
    }

    func stop() {
        guard isRunning else { return }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source, let threadRunLoop { CFRunLoopRemoveSource(threadRunLoop, source, .commonModes) }
        if let threadRunLoop { CFRunLoopStop(threadRunLoop) }
        tap = nil
        source = nil
        thread = nil
        threadRunLoop = nil
        isRunning = false
    }

    private func threadMain() {
        threadRunLoop = CFRunLoopGetCurrent()
        startResult = createTap()
        started.signal()
        guard startResult else { return }
        CFRunLoopRun()
    }

    private func createTap() -> Bool {
        let types: [CGEventType] = [
            .keyDown, .keyUp, .flagsChanged,
            .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp,
        ]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1.rawValue)) }
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: InputMonitor.callback,
            userInfo: userInfo
        ) else { return false }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private static let callback: CGEventTapCallBack = { _, type, event, userInfo in
        if let userInfo {
            let monitor = Unmanaged<InputMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            monitor.handle(type: type, event: event)
        }
        return Unmanaged.passUnretained(event)
    }

    private func handle(type: CGEventType, event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .keyDown:
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            handler?(.keyDown(keyCode: code, isRepeat: isRepeat))
        case .keyUp:
            handler?(.keyUp(keyCode: event.getIntegerValueField(.keyboardEventKeycode)))
        case .flagsChanged:
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            if KeyMapper.isModifierDown(keyCode: code, flags: event.flags) {
                handler?(.modifierDown(keyCode: code))
            } else {
                handler?(.modifierUp(keyCode: code))
            }
        case .leftMouseDown: handler?(.mouseDown(button: 0))
        case .leftMouseUp: handler?(.mouseUp(button: 0))
        case .rightMouseDown: handler?(.mouseDown(button: 1))
        case .rightMouseUp: handler?(.mouseUp(button: 1))
        case .otherMouseDown: handler?(.mouseDown(button: Int(event.getIntegerValueField(.mouseEventButtonNumber))))
        case .otherMouseUp: handler?(.mouseUp(button: Int(event.getIntegerValueField(.mouseEventButtonNumber))))
        default: break
        }
    }
}
