import SwiftUI
import SwiftData
import UserNotifications
import UIKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Query private var transactions: [MoneyTransaction]
    @Query(sort: \Account.sortOrder) private var accounts: [Account]

    @AppStorage("appearance") private var appearance: AppearanceMode = .system
    @AppStorage("displayName") private var displayName = ""
    @AppStorage(ReminderSettings.leadDaysKey) private var leadDays = ReminderSettings.defaultLeadDays
    @AppStorage(ReminderSettings.hourKey) private var reminderHour = ReminderSettings.defaultHour
    @AppStorage(ReminderSettings.minuteKey) private var reminderMinute = ReminderSettings.defaultMinute
    @AppStorage(ReminderSettings.lowBalanceKey) private var lowBalanceWarnings = true
    @AppStorage(AppLock.key) private var lockEnabled = false
    @AppStorage(WidgetSync.hideAmountsKey) private var hideWidgetAmounts = false

    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var exportFile: ExportFile?
    @AppStorage(Backup.lastBackupKey) private var lastBackupTime: Double = 0
    @State private var backupDocument: BackupDocument?
    @State private var showingBackupExporter = false
    @State private var showingRestorePicker = false
    @State private var pendingRestore: BackupFile?
    @State private var backupMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ScreenTitle(text: "Settings")

                    group("Your name") {
                        TextField("Shown in the greeting on Home", text: $displayName)
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.textPrimary)
                            .textInputAutocapitalization(.words)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 52)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }

                    group("Appearance") {
                        PillSegments(options: AppearanceMode.allCases, selection: $appearance) { $0.rawValue }
                    }

                    group("Total balance") {
                        VStack(alignment: .leading, spacing: 8) {
                            VStack(spacing: 0) {
                                ForEach(accounts) { account in
                                    Toggle(isOn: Binding(
                                        get: { account.includeInTotal },
                                        set: { account.includeInTotal = $0 }
                                    )) {
                                        HStack(spacing: 12) {
                                            LogoTile(name: account.shortName, colorHex: account.colorHex, logoData: account.logoData, size: 30)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(account.name)
                                                    .font(.system(size: 15))
                                                    .foregroundStyle(Theme.textPrimary)
                                                Text(Money.format(account.balance, decimals: true))
                                                    .font(.system(size: 12))
                                                    .foregroundStyle(Theme.textSecondary)
                                            }
                                        }
                                    }
                                    .tint(Theme.lime)
                                    .padding(.horizontal, 16)
                                    .frame(minHeight: 56)
                                    if account.id != accounts.last?.id {
                                        divider
                                    }
                                }
                            }
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            Text("Only accounts that are on count towards the balance on Home. You can also touch and hold the balance card there.")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textSecondary)
                                .padding(.leading, 4)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    group("Reminders") {
                        VStack(spacing: 0) {
                            if notificationStatus != .authorized && notificationStatus != .provisional {
                                notificationsOffRow
                                divider
                            }
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Remind me before a payment")
                                    .font(.system(size: 15))
                                    .foregroundStyle(Theme.textPrimary)
                                HStack(spacing: 8) {
                                    ForEach([1, 3, 7], id: \.self) { days in
                                        leadChip(days)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            divider
                            DatePicker("Reminder time", selection: reminderTime, displayedComponents: .hourAndMinute)
                                .font(.system(size: 15))
                                .foregroundStyle(Theme.textPrimary)
                                .padding(.horizontal, 16)
                                .frame(minHeight: 52)
                            divider
                            Toggle(isOn: $lowBalanceWarnings) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Low balance warnings")
                                        .font(.system(size: 15))
                                        .foregroundStyle(Theme.textPrimary)
                                    Text("When the account can't cover a payment")
                                        .font(.system(size: 13))
                                        .foregroundStyle(Theme.textSecondary)
                                }
                            }
                            .tint(Theme.lime)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 60)
                        }
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }

                    group("Money") {
                        VStack(spacing: 0) {
                            NavigationLink {
                                AccountsView()
                            } label: {
                                navRow("Accounts", detail: "\(accounts.count)")
                            }
                            .buttonStyle(.plain)
                            divider
                            NavigationLink {
                                WealthView()
                            } label: {
                                navRow("Savings and investments", detail: "")
                            }
                            .buttonStyle(.plain)
                            divider
                            HStack {
                                Text("Categories and limits")
                                Spacer()
                                Text("In Budgets")
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.textPrimary)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 52)
                        }
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }

                    group("SMS tracking") {
                        NavigationLink {
                            SMSTrackingView()
                        } label: {
                            navRow("Set up and test SMS tracking", detail: "")
                        }
                        .buttonStyle(.plain)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }

                    group("Privacy and data") {
                        VStack(spacing: 0) {
                            Toggle("Lock with Face ID", isOn: $lockEnabled)
                                .font(.system(size: 15))
                                .foregroundStyle(Theme.textPrimary)
                                .tint(Theme.lime)
                                .padding(.horizontal, 16)
                                .frame(minHeight: 52)
                            divider
                            Toggle("Hide amounts in widgets", isOn: $hideWidgetAmounts)
                                .font(.system(size: 15))
                                .foregroundStyle(Theme.textPrimary)
                                .tint(Theme.lime)
                                .padding(.horizontal, 16)
                                .frame(minHeight: 52)
                                .onChange(of: hideWidgetAmounts) { _, _ in
                                    WidgetSync.update(from: context)
                                }
                            divider
                            Button {
                                if let url = DataExport.transactionsCSV(transactions) {
                                    exportFile = ExportFile(url: url)
                                }
                            } label: {
                                navRow("Export transactions", detail: "CSV")
                            }
                            .buttonStyle(.plain)
                            .disabled(transactions.isEmpty)
                            divider
                            Button {
                                makeBackup()
                            } label: {
                                navRow("Back up all data", detail: "")
                            }
                            .buttonStyle(.plain)
                            divider
                            Button {
                                showingRestorePicker = true
                            } label: {
                                navRow("Restore from backup", detail: "")
                            }
                            .buttonStyle(.plain)
                        }
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        Text(backupMessage ?? lastBackupText)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.leading, 4)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    footer
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .background(Theme.background)
            .toolbar(.hidden, for: .navigationBar)
            .task { await loadNotificationStatus() }
            .onChange(of: leadDays) { _, _ in refreshReminders() }
            .onChange(of: reminderHour) { _, _ in refreshReminders() }
            .onChange(of: reminderMinute) { _, _ in refreshReminders() }
            .onChange(of: lowBalanceWarnings) { _, _ in refreshReminders() }
            .fileExporter(
                isPresented: $showingBackupExporter,
                document: backupDocument,
                contentType: .json,
                defaultFilename: Backup.suggestedFileName
            ) { result in
                switch result {
                case .success:
                    lastBackupTime = Date().timeIntervalSince1970
                    backupMessage = "Backup saved."
                case .failure(let error):
                    backupMessage = "Couldn't save the backup: \(error.localizedDescription)"
                }
            }
            .fileImporter(isPresented: $showingRestorePicker, allowedContentTypes: [.json]) { result in
                loadBackup(result)
            }
            .confirmationDialog(
                "Replace all data with this backup?",
                isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }),
                titleVisibility: .visible
            ) {
                Button("Replace and restore", role: .destructive) { restorePending() }
            } message: {
                Text(restoreMessage)
            }
            .sheet(item: $exportFile) { file in
                ShareSheet(items: [file.url])
                    .presentationDetents([.medium, .large])
            }
        }
    }

    // MARK: Pieces

    private var divider: some View {
        Divider().overlay(Theme.separator).padding(.leading, 16)
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .padding(.leading, 4)
            content()
        }
    }

    private func navRow(_ title: String, detail: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Text(detail)
                .foregroundStyle(Theme.textSecondary)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
        }
        .font(.system(size: 15))
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }

    private func leadChip(_ days: Int) -> some View {
        let isSelected = leadDays == days
        return Button {
            leadDays = days
        } label: {
            Text(days == 1 ? "1 day" : "\(days) days")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isSelected ? Theme.onLime : Theme.textPrimary)
                .padding(.horizontal, 14)
                .frame(minHeight: 36)
                .background(isSelected ? Theme.lime : Theme.cardRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var notificationsOffRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "bell.slash")
                .foregroundStyle(Theme.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("Notifications are off")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Text("Reminders can't be delivered until you allow them.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button("Allow") {
                Task { await allowNotifications() }
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Theme.accentText)
        }
        .padding(16)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Image("AppLogo")
                .resizable()
                .frame(width: 40, height: 40)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Kitty Money")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1") · Data stays on this iPhone")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.top, 4)
    }

    // MARK: Logic

    private var reminderTime: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: reminderHour, minute: reminderMinute, second: 0, of: Date()) ?? Date()
            },
            set: { newValue in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                reminderHour = parts.hour ?? ReminderSettings.defaultHour
                reminderMinute = parts.minute ?? ReminderSettings.defaultMinute
            }
        )
    }

    private func loadNotificationStatus() async {
        notificationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    private func allowNotifications() async {
        let current = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        if current == .denied {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                openURL(url)
            }
        } else {
            await Reminders.requestPermission()
            await Reminders.refresh(in: context)
        }
        await loadNotificationStatus()
    }

    // MARK: Backup

    private var lastBackupText: String {
        guard lastBackupTime > 0 else {
            return "No backup yet. Save one to Files or iCloud Drive before big updates."
        }
        let date = Date(timeIntervalSince1970: lastBackupTime)
        let text = "Last backup \(date.formatted(.relative(presentation: .named)))."
        let days = Date().timeIntervalSince(date) / 86_400
        return days > 14 ? text + " It's been a while, consider making a new one." : text
    }

    private var restoreMessage: String {
        guard let pendingRestore else { return "" }
        let date = pendingRestore.createdAt.formatted(date: .abbreviated, time: .shortened)
        return "Backup from \(date): \(pendingRestore.summary). Everything currently in the app will be replaced."
    }

    private func makeBackup() {
        do {
            let data = try Backup.encode(Backup.make(from: context))
            backupDocument = BackupDocument(data: data)
            backupMessage = nil
            showingBackupExporter = true
        } catch {
            backupMessage = "Couldn't create the backup: \(error.localizedDescription)"
        }
    }

    private func loadBackup(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                pendingRestore = try Backup.decode(data)
            } catch {
                backupMessage = "That file isn't a Kitty Money backup."
            }
        case .failure(let error):
            backupMessage = "Couldn't open the file: \(error.localizedDescription)"
        }
    }

    private func restorePending() {
        guard let file = pendingRestore else { return }
        pendingRestore = nil
        do {
            try Backup.restore(file, into: context)
            backupMessage = "Restored: \(file.summary)."
            refreshReminders()
        } catch {
            backupMessage = "Restore failed: \(error.localizedDescription)"
        }
    }

    private func refreshReminders() {
        Task { await Reminders.refresh(in: context) }
    }
}

#Preview {
    SettingsView()
        .modelContainer(PreviewData.container)
}
