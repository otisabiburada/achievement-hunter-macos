import SwiftUI
import AppKit

/// First-run start guide: sign in, pick preferences, watch the first sync, learn the shortcuts.
/// It can be reopened any time from Settings or ⌘K.
public struct OnboardingView: View {
    @ObservedObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    
    private enum Step: Int, CaseIterable {
        case welcome, connect, preferences, sync, tips
        
        var title: String {
            switch self {
            case .welcome: return "Welcome"
            case .connect: return "Connect Steam"
            case .preferences: return "Preferences"
            case .sync: return "Syncing"
            case .tips: return "You're set"
            }
        }
    }
    
    @State private var step: Step = .welcome
    @State private var showLogin = false
    @State private var loginMode = 0
    @State private var notificationsOn = UnlockNotifier.isEnabled
    
    public init(state: AppState) {
        self.state = state
    }
    
    private var isConnected: Bool { state.isAuthenticated || !state.games.isEmpty }
    
    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            
            Group {
                switch step {
                case .welcome: welcome
                case .connect: connect
                case .preferences: preferences
                case .sync: sync
                case .tips: tips
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 40)
            .padding(.vertical, 24)
            .transition(.opacity)
            
            Divider()
            footer
        }
        .frame(width: 680, height: 560)
        .animation(.easeInOut(duration: 0.2), value: step)
        .sheet(isPresented: $showLogin) {
            SteamLoginSheet(initialMode: loginMode) { result in
                state.handleSteamLoginSuccess(
                    steamId: result.steamId,
                    initialGames: result.games,
                    detectedApiKey: result.apiKey,
                    cookies: result.cookies,
                    webToken: result.webToken
                )
            }
        }
        .onChange(of: state.isAuthenticated) { _, connected in
            // Moves on by itself right after a successful sign-in.
            if connected && step == .connect { step = .preferences }
        }
    }
    
    // MARK: Chrome
    
    private var header: some View {
        HStack(spacing: 14) {
            ForEach(Step.allCases, id: \.rawValue) { s in
                HStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(s.rawValue <= step.rawValue ? Color.accentColor : Color.primary.opacity(0.12))
                            .frame(width: 20, height: 20)
                        if s.rawValue < step.rawValue {
                            Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundColor(.white)
                        } else {
                            Text("\(s.rawValue + 1)").font(.system(size: 10, weight: .bold))
                                .foregroundColor(s == step ? .white : .secondary)
                        }
                    }
                    if s == step {
                        Text(s.title).font(.system(size: 12, weight: .semibold))
                    }
                }
                if s != Step.allCases.last {
                    Rectangle().fill(Color.primary.opacity(0.12)).frame(height: 1).frame(maxWidth: 24)
                }
            }
            Spacer()
            Button("Skip guide") { finish() }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }
    
    private var footer: some View {
        HStack {
            if step != .welcome {
                Button("Back") { go(-1) }
                    .buttonStyle(.bordered)
            }
            Spacer()
            switch step {
            case .welcome:
                Button("Get Started") { go(1) }.buttonStyle(.borderedProminent)
            case .connect:
                if !isConnected {
                    Button("Skip for now") { go(1) }.buttonStyle(.bordered)
                } else {
                    Button("Continue") { go(1) }.buttonStyle(.borderedProminent)
                }
            case .preferences, .sync:
                Button("Continue") { go(1) }.buttonStyle(.borderedProminent)
            case .tips:
                Button("Start Exploring") { finish() }.buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }
    
    private func go(_ delta: Int) {
        if let next = Step(rawValue: step.rawValue + delta) { step = next }
    }
    
    private func finish() {
        state.completeOnboarding()
        dismiss()
    }
    
    private func bullet(_ icon: String, _ title: String, _ text: String, color: Color = .accentColor) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(color)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(text).font(.system(size: 12)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
    
    // MARK: Steps
    
    private var welcome: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 0)
            Image(systemName: "trophy.fill")
                .font(.system(size: 54))
                .foregroundStyle(LinearGradient(colors: [Color(red: 1.0, green: 0.85, blue: 0.3), .orange], startPoint: .top, endPoint: .bottom))
                .shadow(color: .orange.opacity(0.4), radius: 14)
            VStack(spacing: 6) {
                Text("Welcome to Achievement Hunter").font(.system(size: 24, weight: .bold))
                Text("Your whole Steam achievement library in one fast, native app.")
                    .font(.system(size: 14)).foregroundColor(.secondary)
            }
            VStack(alignment: .leading, spacing: 14) {
                bullet("arrow.triangle.2.circlepath", "Syncs everything", "Every game, every achievement, including Steam's new Achievement Sets and DLC.")
                bullet("flag.checkered", "Helps you finish games", "Road to 100%, focus targets, rarity and walkthrough links.")
                bullet("square.and.arrow.up", "Made to share", "Beautiful achievement and profile cards, plus a feed of what you just unlocked.")
            }
            .frame(maxWidth: 480)
            Spacer(minLength: 0)
        }
    }
    
    private var connect: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)
            if isConnected {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill").font(.system(size: 44)).foregroundColor(.green)
                    Text("Connected as \(state.player?.personaName ?? "your Steam account")")
                        .font(.system(size: 18, weight: .bold))
                    Text("Your library is loading. You can keep going while it syncs.")
                        .font(.system(size: 13)).foregroundColor(.secondary)
                }
            } else {
                VStack(spacing: 8) {
                    Text("Sign in with Steam").font(.system(size: 22, weight: .bold))
                    Text("That's all it takes. You sign in on Steam's own page, so the app never sees your password, and there is no API key to copy.")
                        .font(.system(size: 13)).foregroundColor(.secondary)
                        .multilineTextAlignment(.center).frame(maxWidth: 440)
                }
                Button(action: { loginMode = 0; showLogin = true }) {
                    HStack(spacing: 8) {
                        Image(systemName: "person.badge.key.fill")
                        Text("Sign In with Steam").fontWeight(.bold)
                    }
                    .frame(width: 280).padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                
                VStack(alignment: .leading, spacing: 8) {
                    bullet("lock.shield.fill", "Private and local", "Everything stays on your Mac. Your login is stored in a file that is encrypted for this Mac only. There is no password prompt.", color: .green)
                    bullet("eye.fill", "Works with private profiles", "Because you sign in as yourself, your game details can stay private.", color: .blue)
                }
                .frame(maxWidth: 440).padding(.top, 6)
                
                Button("I'd rather use a Steam Web API key") { loginMode = 1; showLogin = true }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(.accentColor)
                    .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
    }
    
    private var preferences: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Make it yours").font(.system(size: 22, weight: .bold))
            Text("You can change all of this later in Settings.").font(.system(size: 13)).foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 16) {
                Toggle(isOn: $state.hideGamesWithoutAchievements) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hide games without achievements").font(.system(size: 13, weight: .semibold))
                        Text("Keeps your list clean and skips them when syncing.").font(.system(size: 11)).foregroundColor(.secondary)
                    }
                }
                Toggle(isOn: $notificationsOn) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Notify me about new unlocks").font(.system(size: 13, weight: .semibold))
                        Text("A macOS notification when a sync finds achievements you just earned. macOS will ask for permission the first time.")
                            .font(.system(size: 11)).foregroundColor(.secondary)
                    }
                }
                .onChange(of: notificationsOn) { _, on in UnlockNotifier.isEnabled = on }
                
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "puzzlepiece.extension.fill").foregroundColor(.purple)
                    Text("Games that use Steam's new Achievement Sets are handled automatically. DLC sets only count once you have the DLC. If one is wrong, right-click the set on the game page.")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                }
                .padding(12)
                .background(Color.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .toggleStyle(.switch)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: 520)
    }
    
    private var sync: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)
            if !isConnected {
                Image(systemName: "person.crop.circle.badge.questionmark").font(.system(size: 44)).foregroundColor(.secondary)
                Text("Nothing to sync yet").font(.system(size: 18, weight: .bold))
                Text("Go back and sign in with Steam to load your library.")
                    .font(.system(size: 13)).foregroundColor(.secondary)
                Button("Back to sign-in") { step = .connect }.buttonStyle(.bordered)
            } else {
                let done = state.isSyncingAchievements ? state.achievementSyncDone : state.achievementSyncTotal
                let total = max(1, state.achievementSyncTotal)
                let inProgress = state.isLoading || state.isSyncingAchievements
                
                Image(systemName: inProgress ? "arrow.triangle.2.circlepath" : "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundColor(inProgress ? .accentColor : .green)
                Text(inProgress ? "Loading your library" : "Your library is ready")
                    .font(.system(size: 20, weight: .bold))
                
                VStack(spacing: 8) {
                    if state.isLoading {
                        ProgressView(value: state.syncProgress).frame(width: 360)
                        Text(state.syncStageText.isEmpty ? "Connecting to Steam..." : state.syncStageText)
                            .font(.system(size: 12)).foregroundColor(.secondary)
                    } else if state.isSyncingAchievements {
                        ProgressView(value: Double(done), total: Double(total)).frame(width: 360)
                        Text("Syncing achievements \(done) of \(state.achievementSyncTotal)")
                            .font(.system(size: 12)).foregroundColor(.secondary)
                    } else {
                        Text("\(state.visibleGames.count) games, \(state.totalUnlockedCount) achievements unlocked")
                            .font(.system(size: 13, weight: .medium))
                    }
                }
                if let error = state.errorMessage {
                    VStack(spacing: 8) {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 12)).foregroundColor(.red)
                            .multilineTextAlignment(.center).frame(maxWidth: 460)
                        Button("Try again") { Task { await state.syncWithSteam() } }.buttonStyle(.bordered)
                    }
                }
                Text("This only takes a long time on the very first sync. Later syncs only fetch what changed.")
                    .font(.system(size: 11)).foregroundColor(.secondary).padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
    }
    
    private var tips: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("A few things worth knowing").font(.system(size: 22, weight: .bold))
            VStack(alignment: .leading, spacing: 12) {
                bullet("command", "⌘K jumps anywhere", "Type a game, a section or an action. ⌘F searches your games, ⌘[ and ⌘] go back and forward.")
                bullet("bell.badge.fill", "Activity Feed", "Every sync is compared with the last one, so new unlocks show up here and as notifications.")
                bullet("play.tv.fill", "Walkthroughs", "Every game and achievement links to TrueSteamAchievements, Steam guides and YouTube.")
                bullet("person.crop.rectangle.stack.fill", "Share your profile", "Sidebar > Share Profile Card (⇧⌘P) makes a shareable image of your stats and rarest unlocks.")
                bullet("questionmark.circle", "Start guide", "You can open this guide again from Settings.")
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: 540)
    }
}
