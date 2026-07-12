import AppKit
import ScreenCaptureKit

/// Obtains a capture filter through the system content-sharing picker.
///
/// Direct ScreenCaptureKit captures trigger macOS 15/26's recurring
/// "requesting to bypass the system private window picker" prompt on every
/// capture for apps without notarized identities. Captures made through an
/// SCContentSharingPicker-granted filter are exempt: the user picks the
/// display once (per app run), and subsequent captures are silent.
@MainActor
final class ContentPickerSession: NSObject {
    enum Outcome {
        case filter(SCContentFilter)
        case cancelled
        case failed
    }

    static let shared = ContentPickerSession()

    private var cachedFilter: SCContentFilter?
    private var continuation: CheckedContinuation<Outcome, Never>?

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    /// Returns the cached filter, or presents the system picker and waits
    /// for the user to choose a display.
    func obtainFilter() async -> Outcome {
        if let cachedFilter {
            return .filter(cachedFilter)
        }
        guard continuation == nil else { return .cancelled }

        let picker = SCContentSharingPicker.shared
        var configuration = SCContentSharingPickerConfiguration()
        configuration.allowedPickerModes = [.singleDisplay]
        picker.configuration = configuration
        picker.add(self)
        picker.isActive = true

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            picker.present()
        }
    }

    /// Forget the picked display (e.g. user wants a different one, or the
    /// display layout changed).
    func invalidate() {
        cachedFilter = nil
    }

    @objc private func screensChanged() {
        invalidate()
    }

    private func resolve(_ outcome: Outcome) {
        if case .filter(let filter) = outcome {
            cachedFilter = filter
        }
        // Deactivate the sharing session as soon as the pick is made:
        // leaving it active keeps the system's "screen is being shared"
        // indication on the whole display. The cached filter remains valid
        // for one-shot captures.
        SCContentSharingPicker.shared.isActive = false
        continuation?.resume(returning: outcome)
        continuation = nil
    }
}

extension ContentPickerSession: SCContentSharingPickerObserver {
    nonisolated func contentSharingPicker(
        _ picker: SCContentSharingPicker,
        didUpdateWith filter: SCContentFilter,
        for stream: SCStream?
    ) {
        Task { @MainActor in self.resolve(.filter(filter)) }
    }

    nonisolated func contentSharingPicker(
        _ picker: SCContentSharingPicker,
        didCancelFor stream: SCStream?
    ) {
        Task { @MainActor in self.resolve(.cancelled) }
    }

    nonisolated func contentSharingPickerStartDidFailWithError(_ error: Error) {
        Task { @MainActor in self.resolve(.failed) }
    }
}
