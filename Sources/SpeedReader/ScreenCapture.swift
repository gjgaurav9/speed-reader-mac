import AppKit
import ScreenCaptureKit

/// A captured region of the screen, with everything needed to map
/// image pixels back to global screen coordinates.
struct CaptureResult {
    let image: CGImage
    /// The captured region in AppKit global coordinates (bottom-left origin).
    let region: NSRect
    /// Pixels per point for the display that was captured.
    let scale: CGFloat
}

enum CaptureError: LocalizedError {
    case noPermission
    case displayNotFound
    case regionOutsideSharedDisplay

    var errorDescription: String? {
        switch self {
        case .noPermission: return "Screen Recording permission is required."
        case .displayNotFound: return "Could not find the display to capture."
        case .regionOutsideSharedDisplay:
            return "That area is outside the shared display — use the menu to change the shared display."
        }
    }
}

enum ScreenCapture {
    static func hasPermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Triggers the system Screen Recording prompt (first time only).
    static func requestPermission() {
        CGRequestScreenCaptureAccess()
    }

    static func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }

    /// Capture through a system-picker-granted filter — exempt from the
    /// macOS 15/26 recurring capture-consent prompt. The filter covers a
    /// whole display; `sourceRect` narrows it to the requested region.
    @MainActor
    static func capture(region: NSRect, using filter: SCContentFilter) async throws -> CaptureResult {
        let scale = CGFloat(filter.pointPixelScale)
        let content = filter.contentRect // global, top-left origin, points

        // AppKit global (bottom-left origin) → CG global (top-left origin).
        let primaryHeight = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height
            ?? NSScreen.main?.frame.height ?? 0
        let cgRegion = CGRect(
            x: region.minX,
            y: primaryHeight - region.maxY,
            width: region.width,
            height: region.height
        )

        guard content.insetBy(dx: -2, dy: -2).contains(cgRegion) else {
            throw CaptureError.regionOutsideSharedDisplay
        }

        let config = SCStreamConfiguration()
        config.sourceRect = CGRect(
            x: cgRegion.minX - content.minX,
            y: cgRegion.minY - content.minY,
            width: cgRegion.width,
            height: cgRegion.height
        )
        config.width = Int(cgRegion.width * scale)
        config.height = Int(cgRegion.height * scale)
        config.showsCursor = false
        config.captureResolution = .best

        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )
        return CaptureResult(image: image, region: region, scale: scale)
    }

    /// One-shot capture of `region` (AppKit global coords) on `screen`,
    /// excluding this app's own windows so the widget never appears in
    /// the OCR input. Legacy fallback: triggers the recurring consent
    /// prompt on macOS 15/26.
    @MainActor
    static func capture(region: NSRect, on screen: NSScreen) async throws -> CaptureResult {
        guard hasPermission() else { throw CaptureError.noPermission }

        guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        else { throw CaptureError.displayNotFound }
        let displayID = CGDirectDisplayID(screenNumber.uint32Value)

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID })
        else { throw CaptureError.displayNotFound }

        let pid = pid_t(ProcessInfo.processInfo.processIdentifier)
        let ownWindows = content.windows.filter { $0.owningApplication?.processID == pid }
        let filter = SCContentFilter(display: display, excludingWindows: ownWindows)

        // SCStreamConfiguration.sourceRect is display-local, top-left origin,
        // in points; our region is global AppKit coords (bottom-left origin).
        let displayFrame = screen.frame
        let localRect = CGRect(
            x: region.minX - displayFrame.minX,
            y: displayFrame.maxY - region.maxY,
            width: region.width,
            height: region.height
        )

        let scale = screen.backingScaleFactor
        let config = SCStreamConfiguration()
        config.sourceRect = localRect
        config.width = Int(region.width * scale)
        config.height = Int(region.height * scale)
        config.showsCursor = false
        config.captureResolution = .best

        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )
        return CaptureResult(image: image, region: region, scale: scale)
    }
}
