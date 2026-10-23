import SwiftUI
import AppKit

/// ⌘K: type to jump to a game, a section or an action. ↑/↓ to move, ⏎ to open, esc to close.
public struct QuickOpenView: View {
    @ObservedObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selection = 0
    @FocusState private var focused: Bool
    
    private struct Item: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let icon: String
        let action: () -> Void
    }
    
    private var items: [Item] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        var result: [Item] = []
        
        let sections = NavigationSection.allCases.filter { q.isEmpty || $0.rawValue.lowercased().contains(q) }
        result += sections.map { section in
            Item(id: "s-\(section.rawValue)", title: section.rawValue, subtitle: "Go to section", icon: section.iconName) {
                state.selectedSection = section
            }
        }
        
        let actions: [(String, String, String, () -> Void)] = [
            ("Sync with Steam", "Refresh your library (⌘R)", "arrow.clockwise", { Task { await state.syncWithSteam() } }),
            ("Share profile card", "Create a shareable image (⇧⌘P)", "square.and.arrow.up", { state.isProfileSharePresented = true }),
            ("Open the start guide", "Sign-in, preferences and tips", "sparkles", { state.isOnboardingPresented = true }),
            ("Open settings", "Preferences, cache and exports", "gearshape.fill", { state.isSettingsPresented = true }),
            (state.hideGamesWithoutAchievements ? "Show games without achievements" : "Hide games without achievements", "Toggle the library filter", "eye", { state.hideGamesWithoutAchievements.toggle() })
        ]
        result += actions.filter { q.isEmpty || $0.0.lowercased().contains(q) }.map { a in
            Item(id: "a-\(a.0)", title: a.0, subtitle: a.1, icon: a.2, action: a.3)
        }
        
        if !q.isEmpty {
            let games = state.visibleGames.filter { $0.name.lowercased().contains(q) }
                .sorted { ($0.name.lowercased().hasPrefix(q) ? 0 : 1, $0.name) < ($1.name.lowercased().hasPrefix(q) ? 0 : 1, $1.name) }
                .prefix(8)
            result = games.map { g in
                Item(id: "g-\(g.appId)", title: g.name,
                     subtitle: g.totalAchievements > 0 ? "\(g.unlockedAchievements)/\(g.totalAchievements) • \(Int(g.completionPercentage))%" : "Game",
                     icon: g.isPerfect ? "crown.fill" : "gamecontroller.fill") { state.openGame(g.appId) }
            } + result
        }
        return result
    }
    
    public var body: some View {
        let list = items
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("Jump to a game, section or action...", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .focused($focused)
                    .onSubmit { run(list) }
                    // On the field itself: a focused text field would otherwise swallow the arrow keys.
                    .onKeyPress(.downArrow) { selection = min(selection + 1, max(0, list.count - 1)); return .handled }
                    .onKeyPress(.upArrow) { selection = max(selection - 1, 0); return .handled }
            }
            .padding(14)
            
            Divider()
            
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(Array(list.enumerated()), id: \.element.id) { index, item in
                            Button(action: { selection = index; run(list) }) {
                                HStack(spacing: 10) {
                                    Image(systemName: item.icon)
                                        .frame(width: 22)
                                        .foregroundColor(index == selection ? .white : .accentColor)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(item.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                                        Text(item.subtitle).font(.system(size: 11))
                                            .foregroundColor(index == selection ? .white.opacity(0.8) : .secondary)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(index == selection ? Color.accentColor : Color.clear))
                                .foregroundColor(index == selection ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                            .id(index)
                        }
                        if list.isEmpty {
                            Text("Nothing matches \"\(query)\"")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .padding(24)
                        }
                    }
                    .padding(8)
                }
                .onChange(of: selection) { _, new in proxy.scrollTo(new) }
            }
        }
        .frame(width: 520, height: 420)
        .onAppear { focused = true }
        .onChange(of: query) { _, _ in selection = 0 }
    }
    
    private func run(_ list: [Item]) {
        guard list.indices.contains(selection) else { return }
        let action = list[selection].action
        dismiss()
        action()
    }
}
