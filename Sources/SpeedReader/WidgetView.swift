import SwiftUI

/// State the app pushes into the widget (status line under the Read button,
/// collapsed/expanded presentation).
final class WidgetViewModel: ObservableObject {
    @Published var statusMessage: String?
    @Published var isCollapsed = false

    private var clearTask: Task<Void, Never>?

    func flash(_ message: String, for seconds: Double = 4) {
        statusMessage = message
        clearTask?.cancel()
        clearTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.statusMessage = nil
        }
    }
}

/// The always-on-top widget: speed + mode controls and the Read button.
struct WidgetView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var model: WidgetViewModel
    var onStartReading: () -> Void
    var onToggleCollapse: () -> Void

    @State private var showSettings = false

    var body: some View {
        if model.isCollapsed {
            CollapsedPill(onExpand: onToggleCollapse)
        } else {
            expandedBody
        }
    }

    private var expandedBody: some View {
        VStack(spacing: 12) {
            header

            wpmControl

            Picker("Mode", selection: $settings.readingModeRaw) {
                ForEach(ReadingMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .help(settings.readingMode.help)

            if showSettings {
                settingsRows
            }

            Button(action: onStartReading) {
                Label("Read Screen", systemImage: "text.viewfinder")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)

            if let message = model.statusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: model.statusMessage)
        .padding(16)
        .frame(width: 260)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.12))
        )
    }

    private var header: some View {
        HStack {
            Image(systemName: "hare.fill")
                .foregroundStyle(.tint)
            Text("Speed Reader")
                .font(.headline)
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { showSettings.toggle() }
            } label: {
                Image(systemName: "gearshape")
                    .foregroundStyle(showSettings ? .primary : .secondary)
            }
            .buttonStyle(.plain)
            .help("Reading options")
            Button(action: onToggleCollapse) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Minimize to a line (click the line to reopen)")
        }
    }

    private var wpmControl: some View {
        VStack(spacing: 4) {
            HStack {
                Text("\(Int(settings.wpm)) wpm")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                Spacer()
                Text(AppSettings.paceLabel(for: settings.wpm))
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(AppSettings.paceColor(for: settings.wpm).opacity(0.18)))
                    .foregroundStyle(AppSettings.paceColor(for: settings.wpm))
            }
            Slider(value: $settings.wpm, in: AppSettings.wpmRange, step: 25)
        }
    }

    private var settingsRows: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Guide style")
                    .font(.callout)
                Spacer()
                Picker("Guide style", selection: $settings.guideStyleRaw) {
                    ForEach(GuideStyle.allCases) { style in
                        Text(style.rawValue).tag(style.rawValue)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
            HStack {
                Text("Words per step")
                    .font(.callout)
                Spacer()
                Stepper(value: $settings.chunkSize, in: 1...4) {
                    Text("\(settings.chunkSize)")
                        .monospacedDigit()
                }
                .fixedSize()
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

/// The minimized state: a slim orange line, Pomodoro-style. Orange is the
/// Speed Reader signature so it's never confused with the (blue) Pomodoro.
private struct CollapsedPill: View {
    var onExpand: () -> Void

    @State private var hovering = false

    var body: some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [Color.orange, Color(red: 1.0, green: 0.45, blue: 0.2)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: 120, height: hovering ? 12 : 8)
            .shadow(color: .orange.opacity(hovering ? 0.7 : 0.45), radius: hovering ? 8 : 5)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .onHover { inside in
                withAnimation(.easeOut(duration: 0.12)) { hovering = inside }
            }
            .onTapGesture(perform: onExpand)
            .help("Speed Reader — click to open")
    }
}
