import CoreGraphics

final class EventTapService {
    typealias EventHandler = (CGEventType, CGEvent) -> Unmanaged<CGEvent>?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var eventHandler: EventHandler?

    deinit {
        stop()
    }

    @discardableResult
    func start(eventsOfInterest: CGEventMask, handler: @escaping EventHandler) -> Bool {
        eventHandler = handler

        if eventTap != nil {
            return true
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventsOfInterest,
            callback: Self.eventTapCallback,
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        runLoopSource = source
        return true
    }

    func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }
        eventTap = nil
        eventHandler = nil
    }

    func reenable() {
        guard let eventTap else {
            return
        }
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    private static let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }

        let service = Unmanaged<EventTapService>.fromOpaque(userInfo).takeUnretainedValue()
        guard let handler = service.eventHandler else {
            return Unmanaged.passUnretained(event)
        }
        return handler(type, event)
    }
}
