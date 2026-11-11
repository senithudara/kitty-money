import SwiftUI
import SwiftData

enum AppTab: Hashable {
    case home, budgets, payments, settings
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppLock.key) private var lockEnabled = false
    @State private var tab: AppTab = .home
    @State private var showingAdd = false
    @State private var isLocked = UserDefaults.standard.bool(forKey: AppLock.key)

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch tab {
                case .home: HomeView(selectedTab: $tab)
                case .budgets: BudgetsView()
                case .payments: PaymentsView()
                case .settings: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            KittyTabBar(selection: $tab) { showingAdd = true }
        }
        .background(Theme.background.ignoresSafeArea())
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .sheet(isPresented: $showingAdd, onDismiss: refreshReminders) {
            AddTransactionView()
        }
        .overlay {
            if lockEnabled && isLocked {
                LockScreen { isLocked = false }
                    .transition(.opacity)
            }
        }
        .task {
            SeedData.seedIfNeeded(context)
            SeedData.ensureIncomeCategories(context)
            SeedData.ensureDefaultKeywords(context)
            await Reminders.requestPermission()
            await ExchangeRates.refreshIfNeeded()
            await RenewalProcessor.run(in: context)
            await Reminders.refresh(in: context)
            await LogoSync.fillMissing(in: context)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task {
                    await RenewalProcessor.run(in: context)
                    await Reminders.refresh(in: context)
                }
            case .background:
                if lockEnabled { isLocked = true }
                WidgetSync.update(from: context)
            default:
                break
            }
        }
    }

    private func refreshReminders() {
        Task { await Reminders.refresh(in: context) }
    }
}

struct KittyTabBar: View {
    @Binding var selection: AppTab
    var onAdd: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            item(.home, title: "Home", icon: "house")
            item(.budgets, title: "Budgets", icon: "chart.pie")
            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.onLime)
                    .frame(width: 54, height: 54)
                    .background(Theme.lime, in: Circle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Add transaction")
            item(.payments, title: "Payments", icon: "calendar")
            item(.settings, title: "Settings", icon: "slider.horizontal.3")
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 2)
        .background(Theme.tabBar.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.separator).frame(height: 0.5)
        }
    }

    private func item(_ tab: AppTab, title: String, icon: String) -> some View {
        let isActive = selection == tab
        return Button {
            selection = tab
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(isActive ? Theme.accentText : Theme.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

#Preview {
    RootView()
        .modelContainer(PreviewData.container)
}
