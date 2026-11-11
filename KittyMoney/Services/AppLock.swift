import LocalAuthentication
import SwiftUI

/// Optional Face ID / passcode lock for the whole app.
enum AppLock {
    static let key = "faceIDLock"

    /// The system's name and icon for this phone's unlock method.
    static var method: (name: String, icon: String) {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return ("Face ID", "faceid")
        case .touchID: return ("Touch ID", "touchid")
        default: return ("Passcode", "lock")
        }
    }

    static func authenticate() async -> Bool {
        let context = LAContext()
        var error: NSError?
        // Without Face ID or a passcode set up there's nothing to check against, so don't lock the user out.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return true }
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock Kitty Money")
        } catch {
            return false
        }
    }
}

struct LockScreen: View {
    var onUnlock: () -> Void
    @State private var failed = false

    var body: some View {
        VStack(spacing: 18) {
            Image("AppLogo")
                .resizable()
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)
            Text("Kitty Money is locked")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Button {
                Task { await unlock() }
            } label: {
                Image(systemName: AppLock.method.icon)
                    .font(.system(size: 52, weight: .light))
                    .foregroundStyle(Theme.accentText)
                    .frame(width: 88, height: 88)
            }
            .buttonStyle(.plain)
            .padding(.top, 18)
            .accessibilityLabel("Unlock with \(AppLock.method.name)")
            Button {
                Task { await unlock() }
            } label: {
                Text("Unlock with \(AppLock.method.name)")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.onLime)
                    .frame(width: 220, height: 50)
                    .background(Theme.lime, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            if failed {
                Text("Couldn't verify. Try again.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
        .task { await unlock() }
    }

    private func unlock() async {
        if await AppLock.authenticate() {
            onUnlock()
        } else {
            failed = true
        }
    }
}
