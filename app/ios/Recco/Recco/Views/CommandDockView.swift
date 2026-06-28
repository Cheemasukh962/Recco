import SwiftUI

/// The minimal floating command dock — the app's single piece of bottom chrome.
///
/// Camera-first and restrained: a small graphite-glass capsule with exactly
/// three controls — scan (left), mic (center), keyboard (right). Transient state
/// appears as a compact pill *above* the dock — a live "Listening…" transcript,
/// a "Processing…" line, or a small error — so the lens stays clean when idle.
///
/// All input paths funnel through `AppModel`:
/// - mic → Deepgram → `runCommand` (press-hold or tap),
/// - scan → `runIdentityCommand` (same identity lane as "find info on him"),
/// - keyboard → typed fallback → `submitTypedCommand`.
struct CommandDockView: View {
    @Environment(AppModel.self) private var appModel
    @FocusState private var typedFocused: Bool
    @State private var showTyped = false

    /// Secondary quick-pick of supported demo commands (never the primary path).
    private let examples = [
        "Find info on him.",
        "Show me AI founders.",
        "Who should I talk to about infra?",
        "Only growth people.",
        "Draft an opener for Ava.",
        "Reset."
    ]

    var body: some View {
        @Bindable var model = appModel

        VStack(spacing: 9) {
            // Transient context: typed field, or a status pill — never both, and
            // nothing at all in the clean idle state.
            if showTyped {
                typedRow(draft: $model.commandDraft)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if let status = statusContext {
                statusPill(status)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            dock
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.85), value: showTyped)
        .animation(.spring(response: 0.34, dampingFraction: 0.85), value: appModel.isListening)
        .animation(.easeInOut(duration: 0.2), value: appModel.voiceError)
        .animation(.easeInOut(duration: 0.2), value: appModel.finalTranscript)
    }

    // MARK: - The dock capsule (always visible)

    private var dock: some View {
        HStack(spacing: 14) {
            DockIconButton(
                system: appModel.isResolvingIdentity ? "scope" : "viewfinder",
                label: "Scan the person in frame",
                active: appModel.isResolvingIdentity
            ) {
                Task { await appModel.runIdentityCommand("Find info on him") }
            }

            VoiceMicButton(size: 52)

            DockIconButton(
                system: showTyped ? "keyboard.chevron.compact.down" : "keyboard",
                label: "Type a command",
                active: showTyped
            ) { toggleTyped() }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .graphiteGlass(corner: 30)
        .fixedSize(horizontal: true, vertical: false)
    }

    // MARK: - Typed fallback row

    private func typedRow(draft: Binding<String>) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "text.cursor")
                .font(.footnote)
                .foregroundStyle(ARTheme.textTertiary)
            TextField("Type a command…", text: draft)
                .textFieldStyle(.plain)
                .font(.subheadline)
                .foregroundStyle(ARTheme.textPrimary)
                .focused($typedFocused)
                .submitLabel(.send)
                .onSubmit(submitTyped)
                .autocorrectionDisabled()

            if appModel.commandDraft.isEmpty {
                Menu {
                    Section("Try saying") {
                        ForEach(examples, id: \.self) { example in
                            Button { runExample(example) } label: {
                                Label(example, systemImage: "quote.bubble")
                            }
                        }
                    }
                } label: {
                    Image(systemName: "text.bubble")
                        .font(.subheadline)
                        .foregroundStyle(ARTheme.textTertiary)
                }
            } else {
                Button(action: submitTyped) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title3)
                        .foregroundStyle(ARTheme.scan)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 340)
        .graphiteGlass(corner: 16)
    }

    // MARK: - Status pill (listening / processing / error)

    private enum StatusContext {
        case error(String)
        case listening(String)
        case processing(String)
    }

    /// The single most relevant transient line, or nil for the clean idle dock.
    private var statusContext: StatusContext? {
        if let error = appModel.voiceError { return .error(error) }
        if appModel.isListening {
            return .listening(appModel.partialTranscript)
        }
        if !appModel.finalTranscript.isEmpty {
            return .processing(appModel.finalTranscript)
        }
        if appModel.isResolvingIdentity {
            return .processing(appModel.identityStatusMessage ?? "Identifying…")
        }
        if appModel.isThinking {
            return .processing("Thinking…")
        }
        return nil
    }

    @ViewBuilder
    private func statusPill(_ context: StatusContext) -> some View {
        switch context {
        case .error(let message):
            pill(icon: "exclamationmark.triangle.fill", accent: ARTheme.danger,
                 title: "Voice unavailable", detail: message)
        case .listening(let partial):
            pill(icon: "waveform", accent: ARTheme.danger, title: "Listening…",
                 detail: partial.isEmpty ? "Speak — release or tap to send." : partial,
                 pulse: true)
        case .processing(let text):
            pill(icon: "ellipsis", accent: ARTheme.scan, title: "Processing…", detail: text)
        }
    }

    /// A compact grey-glass status line. Only the small leading glyph/dot carries
    /// the accent colour — the surface itself stays neutral graphite.
    private func pill(icon: String, accent: Color, title: String, detail: String,
                      pulse: Bool = false) -> some View {
        HStack(spacing: 9) {
            ZStack {
                if pulse { PulseDot(accent: accent) }
                Image(systemName: icon)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(accent)
            }
            .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(ARTheme.textPrimary)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(ARTheme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 7)
        .frame(maxWidth: 320)
        .graphiteGlass(corner: 14)
    }

    // MARK: - Actions

    private func toggleTyped() {
        showTyped.toggle()
        if showTyped {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { typedFocused = true }
        } else {
            typedFocused = false
        }
    }

    private func submitTyped() {
        typedFocused = false
        showTyped = false
        appModel.submitTypedCommand()
    }

    private func runExample(_ text: String) {
        typedFocused = false
        showTyped = false
        appModel.commandDraft = ""
        Task { await appModel.runCommand(text) }
    }
}

// MARK: - Graphite glass surface

/// The shared minimal surface for every dock element: translucent graphite glass,
/// a thin low-opacity light stroke, and a soft black shadow — no neon glow.
private struct GraphiteGlass: ViewModifier {
    var corner: CGFloat

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: corner, style: .continuous) }

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: shape)
            .background(Color(red: 0.09, green: 0.10, blue: 0.12).opacity(0.66), in: shape)
            .overlay(shape.strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
            .clipShape(shape)
            .shadow(color: .black.opacity(0.35), radius: 12, y: 5)
    }
}

private extension View {
    func graphiteGlass(corner: CGFloat) -> some View { modifier(GraphiteGlass(corner: corner)) }
}

// MARK: - Dock icon button

/// A minimal circular side control: a 44pt-tappable glyph on a faint graphite
/// disc. Icon-only so it survives Dynamic Type without wrapping; tints to the
/// cyan accent only while active.
private struct DockIconButton: View {
    let system: String
    let label: String
    var active: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(active ? ARTheme.scan : ARTheme.textSecondary)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.white.opacity(0.05)))
                .overlay(
                    Circle().strokeBorder(
                        active ? ARTheme.scan.opacity(0.45) : Color.white.opacity(0.10),
                        lineWidth: 1
                    )
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// A soft pulsing halo behind the "Listening…" icon.
private struct PulseDot: View {
    var accent: Color
    @State private var on = false
    var body: some View {
        Circle()
            .fill(accent.opacity(0.4))
            .frame(width: 16, height: 16)
            .scaleEffect(on ? 1.6 : 0.8)
            .opacity(on ? 0 : 0.8)
            .onAppear {
                withAnimation(.easeOut(duration: 1.1).repeatForever(autoreverses: false)) {
                    on = true
                }
            }
    }
}

// MARK: - Voice mic orb

/// The restrained press-to-talk mic. Hold to talk (release sends), or tap to
/// toggle. Idle: graphite disc, white mic, thin cyan accent ring. Listening: a
/// controlled coral fill with a soft pulse — premium, not a giant bright blob.
private struct VoiceMicButton: View {
    @Environment(AppModel.self) private var appModel
    var size: CGFloat = 52

    @State private var isPressing = false
    @State private var pressStarted = Date()
    @State private var wasListeningAtPress = false
    @State private var pulse = false

    /// Below this hold duration a press counts as a tap (toggle), not push-to-talk.
    private let tapThreshold: TimeInterval = 0.45

    private var listening: Bool { appModel.isListening }
    private var coral: Color { ARTheme.danger }

    var body: some View {
        ZStack {
            Circle()
                .fill(listening ? coral.opacity(0.95) : Color(red: 0.15, green: 0.16, blue: 0.18))
                .frame(width: size, height: size)
                .overlay(
                    Circle().strokeBorder(
                        listening ? coral.opacity(0.85) : ARTheme.scan.opacity(0.45),
                        lineWidth: 1.5
                    )
                )
                .shadow(color: (listening ? coral : .black).opacity(listening ? 0.45 : 0.35),
                        radius: listening ? 10 : 7, y: 3)
                .overlay {
                    if listening {
                        Circle()
                            .stroke(coral.opacity(0.5), lineWidth: 1.5)
                            .scaleEffect(pulse ? 1.5 : 1.0)
                            .opacity(pulse ? 0 : 0.7)
                    }
                }

            Image(systemName: listening ? "waveform" : "mic.fill")
                .font(.system(size: size * 0.36, weight: .semibold))
                .foregroundStyle(listening ? .white : ARTheme.textPrimary)
        }
        .scaleEffect(isPressing ? 0.92 : 1.0)
        .opacity(appModel.isVoiceAvailable ? 1.0 : 0.5)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: listening)
        .animation(.spring(response: 0.25), value: isPressing)
        .gesture(pressGesture)
        .onChange(of: listening) { _, isOn in
            pulse = false
            if isOn {
                withAnimation(.easeOut(duration: 1.1).repeatForever(autoreverses: false)) {
                    pulse = true
                }
            }
        }
        .accessibilityLabel(listening ? "Listening, tap to stop" : "Hold or tap to speak")
    }

    private var pressGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard !isPressing else { return }
                isPressing = true
                pressStarted = Date()
                wasListeningAtPress = appModel.isListening
                if !appModel.isListening { appModel.startListening() }
            }
            .onEnded { _ in
                isPressing = false
                let held = Date().timeIntervalSince(pressStarted) >= tapThreshold
                if held {
                    appModel.stopListening()           // push-to-talk release
                } else if wasListeningAtPress {
                    appModel.stopListening()           // tap an already-live mic → stop
                }
                // else: a quick tap that just started listening → stay live; a
                // second tap (wasListeningAtPress == true) stops and runs.
            }
    }
}
