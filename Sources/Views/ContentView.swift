import SwiftUI

public struct ContentView: View {
    @ObservedObject var state: AppState
    
    public init(state: AppState) {
        self.state = state
    }
    
    public var body: some View {
        ZStack {
            if !state.hasAccountConnected {
                // When no account is connected, show full Welcome & Connect screen
                WelcomeConnectView(state: state)
            } else {
                NavigationSplitView {
                    SidebarView(state: state)
                        .navigationSplitViewColumnWidth(min: 270, ideal: 310, max: 370)
                } detail: {
                    VStack(spacing: 0) {
                        SignInBanner(state: state)
                        AchievementSyncBanner(state: state)
                        
                        // Export notification banner
                        if let msg = state.exportMessage {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text(msg)
                                    .font(.system(size: 12, weight: .semibold))
                                Spacer()
                                Button(action: { state.exportMessage = nil }) {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.green.opacity(0.12))
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        
                        switch state.selectedSection {
                        case .library:
                            if let game = state.selectedGame {
                                GameDetailView(game: game, state: state)
                            } else {
                                VStack(spacing: 12) {
                                    Image(systemName: "trophy.circle.fill")
                                        .font(.system(size: 64))
                                        .foregroundColor(.secondary.opacity(0.3))
                                    Text("Select a Game")
                                        .font(.system(size: 18, weight: .semibold))
                                    Text("Choose a game from the sidebar to inspect your achievements.")
                                        .font(.system(size: 13))
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        case .nowPlaying:
                            NowPlayingView(state: state)
                        case .roadTo100:
                            RoadTo100View(state: state)
                        case .focusTargets:
                            FocusTargetsView(state: state)
                        case .analytics:
                            AnalyticsView(state: state)
                        case .hallOfFame:
                            HallOfFameView(state: state)
                        case .friendCompare:
                            FriendCompareView(state: state)
                        case .widgets:
                            WidgetStudioView(state: state)
                        case .activity:
                            ActivityFeedView(state: state)
                        }
                    }
                }
            }
            
            // Fullscreen Sync Progress Overlay when syncing
            if state.isLoading {
                SyncProgressOverlay(
                    statusText: state.syncStageText,
                    detailText: state.syncDetailText,
                    progress: state.syncProgress
                )
                .transition(.opacity)
            }
        }
        .navigationTitle(state.windowTitle)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button(action: { state.goBack() }) { Image(systemName: "chevron.left") }
                    .disabled(!state.canGoBack)
                    .help("Back (⌘[)")
                Button(action: { state.goForward() }) { Image(systemName: "chevron.right") }
                    .disabled(!state.canGoForward)
                    .help("Forward (⌘])")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                if state.isSyncingAchievements {
                    ProgressView(value: Double(state.achievementSyncDone), total: Double(max(1, state.achievementSyncTotal)))
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                        .help("Syncing achievements \(state.achievementSyncDone)/\(state.achievementSyncTotal)")
                }
                Button(action: { state.isQuickOpenPresented = true }) { Image(systemName: "magnifyingglass") }
                    .help("Quick open (⌘K)")
                Button(action: { Task { await state.syncWithSteam() } }) { Image(systemName: "arrow.clockwise") }
                    .disabled(state.isLoading || !state.hasAccountConnected)
                    .help("Sync with Steam (⌘R)")
            }
        }
        .overlay(alignment: .top) {
            if let e = state.celebration {
                CelebrationCard(event: e) { state.celebration = nil }
                    .padding(.top, 14)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: state.celebration?.id)
        .sheet(isPresented: $state.isOnboardingPresented, onDismiss: { state.completeOnboarding() }) {
            OnboardingView(state: state)
        }
        .sheet(isPresented: $state.isQuickOpenPresented) {
            QuickOpenView(state: state)
        }
        .sheet(isPresented: $state.isProfileSharePresented) {
            ProfileShareSheet(state: state)
        }
        .sheet(isPresented: $state.isSettingsPresented) {
            SettingsView(state: state)
        }
        .sheet(isPresented: $state.isLoginPresented) {
            SteamLoginSheet { result in
                state.handleSteamLoginSuccess(
                    steamId: result.steamId,
                    initialGames: result.games,
                    detectedApiKey: result.apiKey,
                    cookies: result.cookies,
                    webToken: result.webToken
                )
            }
        }
        // Keyboard Shortcuts
        .background(
            VStack {
                // ⌘1...⌘8 follow the sidebar order
                ForEach(Array(NavigationSection.allCases.enumerated()), id: \.element) { index, section in
                    Button("") { state.selectedSection = section }
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                }
                Button("") { Task { await state.syncWithSteam() } }.keyboardShortcut("r", modifiers: .command)
                Button("") { state.isQuickOpenPresented = true }.keyboardShortcut("k", modifiers: .command)
                Button("") { state.selectedSection = .library; state.searchFocusToken += 1 }.keyboardShortcut("f", modifiers: .command)
                Button("") { state.goBack() }.keyboardShortcut("[", modifiers: .command)
                Button("") { state.goForward() }.keyboardShortcut("]", modifiers: .command)
                Button("") { state.isProfileSharePresented = true }.keyboardShortcut("p", modifiers: [.command, .shift])
                Button("") { state.exportMarkdown() }.keyboardShortcut("e", modifiers: [.command, .shift])
            }
            .opacity(0)
            .allowsHitTesting(false)
        )
        .frame(minWidth: 980, minHeight: 650)
    }
}

/// Non-blocking progress for the background achievement sync, plus a retry for failed games.
private struct AchievementSyncBanner: View {
    @ObservedObject var state: AppState
    
    var body: some View {
        let failed = state.failedGames.count
        if state.isSyncingAchievements && (!state.syncIsBackground || state.achievementSyncTotal > 25) {
            HStack(spacing: 10) {
                ProgressView(value: Double(state.achievementSyncDone), total: Double(max(1, state.achievementSyncTotal)))
                    .progressViewStyle(.linear)
                    .frame(width: 160)
                Text("Syncing achievements \(state.achievementSyncDone) / \(state.achievementSyncTotal)")
                    .font(.system(size: 12, weight: .semibold))
                Text("Totals update as games load")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
                Button("Stop") { state.cancelAchievementSync() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.accentColor.opacity(0.10))
        } else if failed > 0 {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("\(failed) game\(failed == 1 ? "" : "s") couldn't be loaded")
                    .font(.system(size: 12, weight: .semibold))
                if let reason = state.failedGames.first?.loadError {
                    Text(reason)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button("Retry failed") { state.retryFailedGames() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.orange.opacity(0.12))
        }
    }
}

/// Shown when the app has no way to read the account: no Steam sign-in and no API key.
private struct SignInBanner: View {
    @ObservedObject var state: AppState
    @AppStorage("dismissed_sign_in_banner") private var dismissed = false
    
    var body: some View {
        if (state.needsSignIn || state.achievementsPrivateNotice) && !state.hasSignInSession && !dismissed {
            HStack(spacing: 10) {
                Image(systemName: "person.badge.key.fill").foregroundColor(.accentColor)
                Text(state.achievementsPrivateNotice ? "Sign in with Steam to sync your unlocks" : "Sign in with Steam (or add an API key) to sync")
                    .font(.system(size: 12, weight: .semibold))
                Text(state.achievementsPrivateNotice
                     ? "Your achievements are private, so games show as all locked until you sign in."
                     : "Steam no longer shows game lists to signed-out apps.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Spacer()
                Button("Sign In") { state.isLoginPresented = true }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Button(action: { dismissed = true }) {
                    Image(systemName: "xmark").font(.system(size: 10)).foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Hide this notice")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.accentColor.opacity(0.10))
        }
    }
}


/// The bigger moment for an unlock almost nobody has.
struct CelebrationCard: View {
    let event: UnlockEvent
    let dismiss: () -> Void
    
    var body: some View {
        HStack(spacing: 14) {
            RemoteImageView(url: event.achievement.iconUrl.flatMap { URL(string: $0) }, fallbackSystemName: "trophy.fill", cornerRadius: 10)
                .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles").foregroundColor(.yellow)
                    Text("ULTRA-RARE UNLOCK").font(.system(size: 10, weight: .heavy)).foregroundColor(.yellow)
                }
                Text(event.achievement.displayName).font(.system(size: 15, weight: .bold)).lineLimit(1)
                Text(event.gameName + (event.achievement.globalPercent.map { String(format: " - only %.2f%% of players", $0) } ?? ""))
                    .font(.system(size: 11)).foregroundColor(.secondary).lineLimit(1)
            }
            Button(action: dismiss) { Image(systemName: "xmark.circle.fill").foregroundColor(.secondary) }
                .buttonStyle(.plain)
        }
        .padding(14)
        .frame(maxWidth: 440)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(LinearGradient(colors: [.yellow, .orange, .pink], startPoint: .leading, endPoint: .trailing), lineWidth: 2))
        .shadow(color: .orange.opacity(0.35), radius: 18, y: 6)
    }
}
