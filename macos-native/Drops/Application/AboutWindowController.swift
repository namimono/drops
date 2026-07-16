import AppKit
import SwiftUI

@MainActor
final class AboutWindowController: NSWindowController {
    init() {
        let hosting = NSHostingController(rootView: AboutRootView())
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 240),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.aboutWindowTitle
        window.contentViewController = hosting
        window.center()
        super.init(window: window)

        NotificationCenter.default.addObserver(
            forName: .dropsLanguageDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.window?.title = L10n.aboutWindowTitle
            self?.window?.contentViewController = NSHostingController(rootView: AboutRootView())
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showAbout() {
        window?.title = L10n.aboutWindowTitle
        window?.contentViewController = NSHostingController(rootView: AboutRootView())
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct AboutRootView: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)
            Text(L10n.appName)
                .font(.title2.weight(.semibold))
            Text(L10n.aboutVersion(version, build))
                .foregroundColor(.secondary)
            Text(L10n.aboutBlurb)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
            Spacer(minLength: 0)
            Text("Copyright © 2026 click.shakepin")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(24)
        .frame(width: 360, height: 240)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.aboutWindowTitle)
    }
}
