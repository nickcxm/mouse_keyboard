import CoreGraphics
import CoreVideo
import QuartzCore

final class MouseMovementEngine {
    enum Direction: Hashable {
        case up
        case down
        case left
        case right
    }

    struct Profile {
        let baseStep: CGFloat
        let maxStep: CGFloat
        let accelerationIncrement: CGFloat
    }

    private enum Config {
        static let repeatThresholdSeconds: CFTimeInterval = 0.08
        static let fallbackTickSeconds: CFTimeInterval = 1.0 / 120.0
        static let minimumTickSeconds: CFTimeInterval = 1.0 / 240.0
        static let maximumTickSeconds: CFTimeInterval = 1.0 / 30.0
        static let boostMultiplier: CGFloat = 2.0
        static let fineTuneMultiplier: CGFloat = 0.35
        static let minimumStep: CGFloat = 1
    }

    var onMove: ((CGFloat, CGFloat) -> Void)?

    private var profile: Profile
    private var activeDirections: Set<Direction> = []
    private var isBoostEnabled = false
    private var isFineTuneEnabled = false

    private var displayLink: CVDisplayLink?
    private var lastTickTimestamp: CFTimeInterval = 0
    private var isTickQueued = false

    private var lastMoveTimestamp: CFTimeInterval = 0
    private var acceleratedStep: CGFloat = 0

    init(initialProfile: Profile) {
        profile = initialProfile
    }

    deinit {
        stop()
    }

    func setProfile(_ profile: Profile) {
        self.profile = profile
    }

    func setDirection(_ direction: Direction, isPressed: Bool) {
        if isPressed {
            activeDirections.insert(direction)
            startIfNeeded()
            moveOnce(tickSeconds: Config.fallbackTickSeconds)
        } else {
            activeDirections.remove(direction)
            if activeDirections.isEmpty {
                stop()
                resetState()
            }
        }
    }

    func setBoostEnabled(_ enabled: Bool) {
        isBoostEnabled = enabled
        if !activeDirections.isEmpty {
            moveOnce(tickSeconds: Config.fallbackTickSeconds)
        }
    }

    func setFineTuneEnabled(_ enabled: Bool) {
        isFineTuneEnabled = enabled
        if !activeDirections.isEmpty {
            moveOnce(tickSeconds: Config.fallbackTickSeconds)
        }
    }

    func clearModifiers() {
        isBoostEnabled = false
        isFineTuneEnabled = false
    }

    func stopAndReset() {
        stop()
        activeDirections.removeAll()
        clearModifiers()
        resetState()
    }

    func resetState() {
        acceleratedStep = 0
        lastMoveTimestamp = 0
        lastTickTimestamp = 0
    }

    private func startIfNeeded() {
        guard displayLink == nil else {
            return
        }

        var link: CVDisplayLink?
        guard CVDisplayLinkCreateWithActiveCGDisplays(&link) == kCVReturnSuccess, let link else {
            tickMovement(tickSeconds: Config.fallbackTickSeconds)
            return
        }

        let userInfo = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        CVDisplayLinkSetOutputCallback(link, Self.displayLinkCallback, userInfo)
        displayLink = link
        lastTickTimestamp = 0
        CVDisplayLinkStart(link)
    }

    private func stop() {
        if let displayLink {
            CVDisplayLinkStop(displayLink)
        }
        displayLink = nil
        lastTickTimestamp = 0
        isTickQueued = false
    }

    private static let displayLinkCallback: CVDisplayLinkOutputCallback = { _, _, _, _, _, userInfo in
        guard let userInfo else {
            return kCVReturnSuccess
        }
        let engine = Unmanaged<MouseMovementEngine>.fromOpaque(userInfo).takeUnretainedValue()
        engine.queueTickFromDisplayLink()
        return kCVReturnSuccess
    }

    private func queueTickFromDisplayLink() {
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }

            guard !isTickQueued else {
                return
            }
            isTickQueued = true

            let now = CACurrentMediaTime()
            let tickSeconds: CFTimeInterval
            if lastTickTimestamp > 0 {
                tickSeconds = min(max(now - lastTickTimestamp, Config.minimumTickSeconds), Config.maximumTickSeconds)
            } else {
                tickSeconds = Config.fallbackTickSeconds
            }

            lastTickTimestamp = now
            tickMovement(tickSeconds: tickSeconds)
            isTickQueued = false
        }
    }

    private func tickMovement(tickSeconds: CFTimeInterval) {
        guard !activeDirections.isEmpty else {
            stop()
            return
        }
        moveOnce(tickSeconds: tickSeconds)
    }

    private func moveOnce(tickSeconds: CFTimeInterval) {
        let step = nextStep(tickSeconds: tickSeconds)
        var dx: CGFloat = 0
        var dy: CGFloat = 0

        if activeDirections.contains(.left) { dx -= step }
        if activeDirections.contains(.right) { dx += step }
        if activeDirections.contains(.up) { dy -= step }
        if activeDirections.contains(.down) { dy += step }

        if dx != 0 || dy != 0 {
            onMove?(dx, dy)
        }
    }

    private func nextStep(tickSeconds: CFTimeInterval) -> CGFloat {
        let now = CACurrentMediaTime()
        let withinRepeatWindow = (now - lastMoveTimestamp) <= Config.repeatThresholdSeconds
        let intervalScale = CGFloat(tickSeconds / Config.repeatThresholdSeconds)

        if withinRepeatWindow {
            let start = max(acceleratedStep, profile.baseStep)
            acceleratedStep = min(start + (profile.accelerationIncrement * intervalScale), profile.maxStep)
        } else {
            acceleratedStep = profile.baseStep
        }

        lastMoveTimestamp = now

        var step = acceleratedStep * intervalScale
        if isBoostEnabled {
            step *= Config.boostMultiplier
        }
        if isFineTuneEnabled {
            step *= Config.fineTuneMultiplier
        }

        return max(step, Config.minimumStep * intervalScale)
    }
}
