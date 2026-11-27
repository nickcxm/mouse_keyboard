import AppKit
import CoreGraphics

struct LayoutDisplayDescriptor: Sendable {
    let id: CGDirectDisplayID
    let stableIdentifier: String
    let name: String
    let bounds: CGRect
}

struct DisplayTopologyService: Sendable {
    func currentDisplays() -> [LayoutDisplayDescriptor] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }

            let displayID = CGDirectDisplayID(number.uint32Value)
            let serial = CGDisplaySerialNumber(displayID)
            let stableIdentifier = [
                CGDisplayIsBuiltin(displayID) == 1 ? "builtin" : "external",
                String(CGDisplayVendorNumber(displayID)),
                String(CGDisplayModelNumber(displayID)),
                String(serial),
                String(Int(CGDisplayPixelsWide(displayID))),
                String(Int(CGDisplayPixelsHigh(displayID)))
            ].joined(separator: "-")

            return LayoutDisplayDescriptor(
                id: displayID,
                stableIdentifier: stableIdentifier,
                name: screen.localizedName,
                bounds: CGDisplayBounds(displayID)
            )
        }
        .sorted { lhs, rhs in
            if lhs.id == CGMainDisplayID() { return true }
            if rhs.id == CGMainDisplayID() { return false }
            return lhs.bounds.minX < rhs.bounds.minX
        }
    }
}
