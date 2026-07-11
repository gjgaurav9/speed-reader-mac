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

    var errorDescription: String? {
        switch self {
        case .noPermission: return "Screen Recording permission is required."
        case .displayNotFound: return "Could not find the display to capture."
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

    /// One-shot capture of `region` (AppKit global coords) on `screen`,
    /// excluding this app's own windows so the widget never appears in
    /// the OCR input.
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
