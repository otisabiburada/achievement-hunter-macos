import SwiftUI
import AppKit

public struct WelcomeConnectView: View {
    @ObservedObject var state: AppState
    @State private var steamIdInput: String = ""
    @State private var apiKeyInput: String = ""
    @State private var isKeyVisible: Bool = false
    
    public init(state: AppState) {
        self.state = state
    }
    
    /// An API key needs both the key and the profile it should read.
    private var canConnectWithKey: Bool {
        !apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !steamIdInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    public var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            // App Branding Icon & Title
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.1, green: 0.15, blue: 0.25), Color(red: 0.05, green: 0.08, blue: 0.14)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 80, height: 80)
                        .overlay(
                            Circle().strokeBorder(Color(red: 1.0, green: 0.82, blue: 0.2).opacity(0.4), lineWidth: 2)
                        )
                        .shadow(color: Color(red: 1.0, green: 0.82, blue: 0.2).opacity(0.2), radius: 12)
                    
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 36))
                        .foregroundColor(Color(red: 1.0, green: 0.82, blue: 0.2))
                }
                
                Text("Achievement Hunter")
                    .font(.system(size: 26, weight: .bold))
                
                Text("Track, hunt, and showcase your achievements across your full Steam library.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 480)
            }
            
            // Connection Box
            VStack(spacing: 14) {
                // Sign in with Steam (recommended)
                Button(action: {
                    state.isLoginPresented = true
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: "person.badge.key.fill")
                            .font(.system(size: 16))
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sign In with Steam")
                                .font(.system(size: 14, weight: .bold))
                            Text("Recommended. Loads your whole library. No API key needed.")
                                .font(.system(size: 11))
                                .opacity(0.9)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 18))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .shadow(color: Color.blue.opacity(0.3), radius: 6, y: 3)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: 460)
                
                HStack {
                    Rectangle().fill(Color.primary.opacity(0.1)).frame(height: 1)
                    Text("OR USE A STEAM WEB API KEY")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundColor(.secondary)
                    Rectangle().fill(Color.primary.opacity(0.1)).frame(height: 1)
                }
                .frame(maxWidth: 460)
                .padding(.vertical, 2)
                
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Steam Profile URL, Vanity Name or SteamID64")
                            .font(.system(size: 11, weight: .semibold))
                        
                        HStack(spacing: 8) {
                            Image(systemName: "link")
                                .foregroundColor(.secondary)
                                .font(.system(size: 12))
                            
                            TextField("e.g. steamcommunity.com/id/yourname or 76561198000000001", text: $steamIdInput)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12))
                        }
                        .padding(8)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                        )
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Steam Web API Key")
                                .font(.system(size: 11, weight: .semibold))
                            Spacer()
                            Button("Get Free API Key ↗") {
                                if let url = URL(string: "https://steamcommunity.com/dev/apikey") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                            .font(.system(size: 10))
                            .buttonStyle(.plain)
                            .foregroundColor(.accentColor)
                        }
                        
                        HStack {
                            if isKeyVisible {
                                TextField("Enter 32-character Steam Web API Key", text: $apiKeyInput)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 11, design: .monospaced))
                            } else {
                                SecureField("Enter 32-character Steam Web API Key", text: $apiKeyInput)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 11, design: .monospaced))
                            }
                            Button(action: { isKeyVisible.toggle() }) {
                                Image(systemName: isKeyVisible ? "eye.slash" : "eye")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        Text("An API key reads your profile through Steam's official API, so your Game details must be set to Public.")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .padding(.top, 2)
                    }
                    
                    if let err = state.errorMessage {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text(err)
                                .font(.system(size: 11))
                                .foregroundColor(.red)
                        }
                        .padding(.top, 2)
                        
                        if err.localizedCaseInsensitiveContains("private") || err.localizedCaseInsensitiveContains("public") {
                            Button("Open Steam Privacy Settings ↗") {
                                NSWorkspace.shared.open(SteamPrivacyHelp.settingsURL)
                            }
                            .font(.system(size: 11))
                            .buttonStyle(.plain)
                            .foregroundColor(.accentColor)
                        }
                    }
                    
                    Button(action: {
                        state.apiKey = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        state.steamIdOrVanity = steamIdInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        Task {
                            await state.syncWithSteam()
                        }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("Connect with API Key")
                        }
                        .font(.system(size: 12, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(canConnectWithKey ? Color(NSColor.controlAccentColor) : Color.gray.opacity(0.3))
                        .foregroundColor(.white)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canConnectWithKey)
                }
                .padding(14)
                .frame(maxWidth: 460)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.7))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
            }
            
            // Privacy help
            DisclosureGroup("Using an API key and my games don't load") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array([
                        "Open Steam (app or website) and go to your Profile > Edit Profile > Privacy Settings.",
                        "Set \"My profile\" to Public.",
                        "Set \"Game details\" to Public, and untick \"Always keep my total playtime private\".",
                        "For Friend Compare also set \"Friends List\" to Public.",
                        "Wait a few minutes (Steam can be slow to apply it), then connect again."
                    ].enumerated()), id: \.offset) { item in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(item.offset + 1).")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(.accentColor)
                            Text(item.element)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                    Button("Open Steam Privacy Settings ↗") {
                        NSWorkspace.shared.open(SteamPrivacyHelp.settingsURL)
                    }
                    .font(.system(size: 11))
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                }
                .padding(.top, 6)
            }
            .font(.system(size: 11, weight: .medium))
            .frame(maxWidth: 460)
            .padding(.top, 2)
            
            Spacer()
        }
        .padding(26)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            apiKeyInput = state.apiKey
            steamIdInput = state.steamIdOrVanity
        }
    }
}
