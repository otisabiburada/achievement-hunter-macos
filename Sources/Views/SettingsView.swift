import SwiftUI
import AppKit

public struct SettingsView: View {
    @ObservedObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var isKeyVisible: Bool = false
    @State private var tab: Tab = .account
    
    enum Tab: String, CaseIterable, Identifiable {
        case account = "Account", library = "Library", notifications = "Notifications", advanced = "Advanced"
        var id: String { rawValue }
        var icon: String { switch self { case .account: return "person.crop.circle"; case .library: return "books.vertical"; case .notifications: return "bell"; case .advanced: return "wrench.and.screwdriver" } }
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "gearshape.fill")
                        .foregroundColor(.accentColor)
                    Text("Achievement Hunter - Preferences & Exports")
                        .font(.system(size: 16, weight: .bold))
                }
                
                Spacer()
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 12)
            
            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { t in Label(t.rawValue, systemImage: t.icon).tag(t) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
            
            Divider()
            
            switch tab {
            case .account:
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Direct Steam Account Card
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "person.badge.key.fill")
                                .foregroundColor(.blue)
                                .font(.system(size: 18))
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Direct Steam Account")
                                    .font(.system(size: 14, weight: .bold))
                                Text("Sync your games and achievements directly from your Steam account.")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                        }
                        
                        if state.isAuthenticated, let steamId = state.authenticatedSteamId {
                            HStack(spacing: 12) {
                                RemoteImageView(
                                    url: state.player?.avatarImageURL,
                                    fallbackSystemName: "person.crop.circle.fill",
                                    cornerRadius: 16
                                )
                                .frame(width: 38, height: 38)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(state.player?.personaName ?? "Steam User")
                                            .font(.system(size: 13, weight: .bold))
                                        
                                        HStack(spacing: 3) {
                                            Image(systemName: "checkmark.circle.fill")
                                            Text("Connected")
                                        }
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(.green)
                                    }
                                    
                                    Text("SteamID64: \(steamId)")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                Button(action: {
                                    Task {
                                        await state.fetchDirectlyFromAccount(steamId: steamId)
                                    }
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "arrow.clockwise")
                                        Text("Sync Now")
                                    }
                                    .font(.system(size: 11))
                                }
                                .buttonStyle(.bordered)
                                .disabled(state.isLoading)
                                
                                Button(action: {
                                    state.signOut()
                                }) {
                                    Text("Sign Out")
                                        .font(.system(size: 11))
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.bordered)
                            }
                            .padding(12)
                            .background(Color.green.opacity(0.06))
                            .cornerRadius(8)
                        } else {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Sign in securely through Steam's own login page, or connect with a Steam Web API key.")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                
                                Button(action: {
                                    dismiss()
                                    state.isLoginPresented = true
                                }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "person.badge.key.fill")
                                        Text("Connect Steam Account")
                                    }
                                    .font(.system(size: 13, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                    }
                    .padding(16)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                    .cornerRadius(10)
                    
                    // Start guide
                    HStack(spacing: 12) {
                        Image(systemName: "sparkles").foregroundColor(.accentColor).font(.system(size: 18))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Start guide").font(.system(size: 13, weight: .bold))
                            Text("Walk through sign-in, preferences and tips again.").font(.system(size: 11)).foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("Open Guide") {
                            dismiss()
                            state.isOnboardingPresented = true
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(14)
                    .background(Color.primary.opacity(0.03))
                    .cornerRadius(8)
                    
                }
                .padding(20)
            }
            case .library:
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Library, cache & notifications
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: "externaldrive.fill")
                                .foregroundColor(.accentColor)
                            Text("Library & Cache")
                                .font(.system(size: 13, weight: .bold))
                        }
                        
                        VStack(alignment: .leading, spacing: 3) {
                            if let synced = state.lastSyncedAt {
                                Text("Last synced \(synced.formatted(.relative(presentation: .named))) (\(synced.formatted(date: .abbreviated, time: .shortened)))")
                            } else {
                                Text("Not synced yet")
                            }
                            Text("\(state.games.count) games, \(state.failedGames.count) failed to load")
                        }
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Automatic sync").font(.system(size: 12, weight: .medium))
                                Text("While the app is open, new unlocks in all your games are picked up in the background. The game you're playing is checked about every 2 minutes either way.")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Picker("Automatic sync", selection: $state.autoSyncMinutes) {
                                Text("Off").tag(0)
                                Text("Every 5 minutes").tag(5)
                                Text("Every 10 minutes").tag(10)
                                Text("Every 15 minutes").tag(15)
                                Text("Every 30 minutes").tag(30)
                                Text("Every hour").tag(60)
                            }
                            .labelsHidden()
                            .frame(width: 160)
                        }
                        
                        Text("Syncs only refetch games whose unlock count or playtime changed (or that are over a day old). Schema and rarity data are cached on disk.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        
                        Toggle(isOn: $state.hideGamesWithoutAchievements) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Hide games without achievements")
                                    .font(.system(size: 12, weight: .medium))
                                Text("Also skips re-syncing them (re-checked every few weeks). \(state.hiddenGamesCount) game\(state.hiddenGamesCount == 1 ? "" : "s") currently have none.")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .toggleStyle(.switch)
                        
                        HStack(spacing: 12) {
                            Button(action: {
                                Task { await state.fullResync() }
                            }) {
                                Text("Full Re-sync")
                                    .font(.system(size: 11, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                            }
                            .buttonStyle(.bordered)
                            .disabled(!state.hasAccountConnected || state.isLoading)
                            
                            Button(action: {
                                Task { await state.clearCacheAndResync() }
                            }) {
                                Text("Clear Cache & Re-sync")
                                    .font(.system(size: 11, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                            }
                            .buttonStyle(.bordered)
                            .disabled(state.isLoading)
                        }
                    }
                    .padding(14)
                    .background(Color.primary.opacity(0.03))
                    .cornerRadius(8)
                    
                    // Data Export & Reports Section
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: "square.and.arrow.up.fill")
                                .foregroundColor(.accentColor)
                            Text("Export Backlog & Reports")
                                .font(.system(size: 13, weight: .bold))
                        }
                        
                        Text("Export your complete Steam achievement library and completion history to external productivity apps.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 12) {
                            Button(action: {
                                state.exportMarkdown()
                                dismiss()
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "doc.text.fill")
                                    Text("Export to Markdown (.md)")
                                }
                                .font(.system(size: 11, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.bordered)
                            
                            Button(action: {
                                state.exportCSV()
                                dismiss()
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "tablecells.fill")
                                    Text("Export to CSV (.csv)")
                                }
                                .font(.system(size: 11, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(14)
                    .background(Color.primary.opacity(0.03))
                    .cornerRadius(8)
                    

                    
                }
                .padding(20)
            }
            case .notifications:
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(isOn: $state.notificationPolicy.enabled) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Notify me about new unlocks").font(.system(size: 12, weight: .medium))
                                Text("A macOS banner when the app notices a new achievement.").font(.system(size: 10)).foregroundColor(.secondary)
                            }
                        }.toggleStyle(.switch)
                        
                        Divider()
                        
                        Toggle(isOn: $state.notificationPolicy.dailySummary) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("One daily summary instead of a banner per unlock").font(.system(size: 12, weight: .medium))
                                Text("Unlocks are collected and announced together once a day.").font(.system(size: 10)).foregroundColor(.secondary)
                            }
                        }.toggleStyle(.switch).disabled(!state.notificationPolicy.enabled)
                        if state.notificationPolicy.dailySummary {
                            DatePicker("Send the summary at", selection: minuteBinding(\.summaryMinute), displayedComponents: .hourAndMinute)
                                .font(.system(size: 12)).disabled(!state.notificationPolicy.enabled)
                        }
                        
                        Divider()
                        
                        Toggle(isOn: $state.notificationPolicy.quietHoursEnabled) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Quiet hours").font(.system(size: 12, weight: .medium))
                                Text("No banners in this window. Whatever you unlock meanwhile arrives as one summary afterwards.").font(.system(size: 10)).foregroundColor(.secondary)
                            }
                        }.toggleStyle(.switch).disabled(!state.notificationPolicy.enabled)
                        if state.notificationPolicy.quietHoursEnabled {
                            HStack(spacing: 16) {
                                DatePicker("From", selection: minuteBinding(\.quietStartMinute), displayedComponents: .hourAndMinute)
                                DatePicker("Until", selection: minuteBinding(\.quietEndMinute), displayedComponents: .hourAndMinute)
                            }
                            .font(.system(size: 12)).disabled(!state.notificationPolicy.enabled)
                        }
                        
                        Divider()
                        
                        Toggle(isOn: $state.notificationPolicy.celebrateUltraRare) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Celebrate ultra-rare unlocks").font(.system(size: 12, weight: .medium))
                                Text("A big card in the app and a special banner for achievements almost nobody has.").font(.system(size: 10)).foregroundColor(.secondary)
                            }
                        }.toggleStyle(.switch)
                        if state.notificationPolicy.celebrateUltraRare {
                            HStack {
                                Text("Counts as ultra-rare below").font(.system(size: 12))
                                Picker("", selection: $state.notificationPolicy.ultraRarePercent) {
                                    Text("0.5% of players").tag(0.5)
                                    Text("1% of players").tag(1.0)
                                    Text("2% of players").tag(2.0)
                                    Text("5% of players").tag(5.0)
                                }
                                .labelsHidden().frame(width: 160)
                            }
                        }
                    }
                    .padding(14)
                    .background(Color.primary.opacity(0.03))
                    .cornerRadius(8)
                }
                .padding(20)
            }
            case .advanced:
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Advanced: Optional API Key
                    DisclosureGroup("Advanced: Steam Web API Key (Optional)") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("If you prefer using an official Valve Web API key instead of direct account login:")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("Steam Web API Key")
                                        .font(.system(size: 12, weight: .medium))
                                    
                                    Spacer()
                                    
                                    Button(action: {
                                        if let url = URL(string: "https://steamcommunity.com/dev/apikey") {
                                            NSWorkspace.shared.open(url)
                                        }
                                    }) {
                                        HStack(spacing: 3) {
                                            Text("Get API Key")
                                            Image(systemName: "arrow.up.right")
                                        }
                                        .font(.system(size: 10))
                                        .foregroundColor(.accentColor)
                                    }
                                    .buttonStyle(.plain)
                                }
                                
                                HStack {
                                    if isKeyVisible {
                                        TextField("Enter 32-character API Key", text: $state.apiKey)
                                            .textFieldStyle(.roundedBorder)
                                            .font(.system(size: 11, design: .monospaced))
                                    } else {
                                        SecureField("Enter 32-character API Key", text: $state.apiKey)
                                            .textFieldStyle(.roundedBorder)
                                            .font(.system(size: 11, design: .monospaced))
                                    }
                                    
                                    Button(action: { isKeyVisible.toggle() }) {
                                        Image(systemName: isKeyVisible ? "eye.slash" : "eye")
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Custom SteamID64")
                                    .font(.system(size: 12, weight: .medium))
                                TextField("e.g. 76561198000000001", text: $state.steamIdOrVanity)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 11))
                            }
                            
                            Button(action: {
                                Task {
                                    await state.syncWithSteam()
                                }
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "link")
                                    Text("Connect via API Key")
                                }
                                .font(.system(size: 11))
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.top, 8)
                    }
                    .font(.system(size: 12, weight: .medium))
                    .padding(14)
                    .background(Color.primary.opacity(0.02))
                    .cornerRadius(8)
                    
                    // Diagnostics
                    HStack(spacing: 12) {
                        Image(systemName: "stethoscope").foregroundColor(.accentColor).font(.system(size: 18))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Diagnostic log").font(.system(size: 13, weight: .bold))
                            Text("Sign-in and sync steps, with no passwords, tokens or cookies. Handy when something doesn't load.")
                                .font(.system(size: 11)).foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("Show in Finder") {
                            if FileManager.default.fileExists(atPath: AppLog.shared.url.path) {
                                NSWorkspace.shared.activateFileViewerSelecting([AppLog.shared.url])
                            } else {
                                NSWorkspace.shared.open(AppLog.shared.url.deletingLastPathComponent())
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(14)
                    .background(Color.primary.opacity(0.03))
                    .cornerRadius(8)
                    
                    // Keyboard Shortcuts Cheat Sheet
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Keyboard Shortcuts")
                            .font(.system(size: 12, weight: .bold))
                        
                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                            GridRow {
                                Text("⌘ 1 to ⌘ 9").font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary)
                                Text("Switch sections in sidebar order (Library, Now Playing, Road to 100, ...)").font(.system(size: 11))
                            }
                            GridRow {
                                Text("⌘ K").font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary)
                                Text("Quick open: jump to any game, section or action").font(.system(size: 11))
                            }
                            GridRow {
                                Text("⌘ F").font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary)
                                Text("Search your games").font(.system(size: 11))
                            }
                            GridRow {
                                Text("⌘ [  /  ⌘ ]").font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary)
                                Text("Back / forward").font(.system(size: 11))
                            }
                            GridRow {
                                Text("⌘ ⇧ P").font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary)
                                Text("Share your profile card").font(.system(size: 11))
                            }
                            GridRow {
                                Text("⌘ R").font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary)
                                Text("Sync library with Steam").font(.system(size: 11))
                            }
                            GridRow {
                                Text("⌘ ⇧ E").font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary)
                                Text("Export library report to Markdown").font(.system(size: 11))
                            }
                        }
                    }
                    .padding(14)
                    .background(Color.primary.opacity(0.03))
                    .cornerRadius(8)
                }
                .padding(20)
            }
            }
        }
        .frame(width: 580, height: 640)
    }
    
    /// A time-of-day picker bound to a "minutes after midnight" setting.
    private func minuteBinding(_ keyPath: WritableKeyPath<NotificationPolicy, Int>) -> Binding<Date> {
        Binding(
            get: {
                let m = state.notificationPolicy[keyPath: keyPath]
                return Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                state.notificationPolicy[keyPath: keyPath] = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            }
        )
    }
}
