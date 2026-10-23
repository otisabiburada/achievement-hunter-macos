import SwiftUI

/// "What changed since last time": achievements that unlocked between syncs, newest first.
public struct ActivityFeedView: View {
    @ObservedObject var state: AppState
    @State private var notificationsOn = UnlockNotifier.isEnabled
    /// How many days (that have activity) are shown; "Show earlier days" adds more. Only these are built.
    @State private var daysShown = 5
    /// Days whose full list is open; every other day shows its 10 newest unlocks.
    @State private var expandedDays: Set<Date> = []
    private static let perDayLimit = 10
    private static let daysStep = 5
    
    public init(state: AppState) {
        self.state = state
    }
    
    private func title(for day: Date) -> String {
        if Calendar.current.isDateInToday(day) { return "Today" }
        if Calendar.current.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(date: .complete, time: .omitted)
    }
    
    public var body: some View {
        let feed = state.activityDays(maxDays: daysShown)
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Image(systemName: "bell.badge.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.orange)
                            Text("Activity Feed")
                                .font(.system(size: 24, weight: .bold))
                        }
                        Text("Your latest unlocks, newest first, with the time you earned them. New ones are marked.")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        Toggle("Notify me", isOn: $notificationsOn)
                            .toggleStyle(.switch)
                            .onChange(of: notificationsOn) { _, on in UnlockNotifier.isEnabled = on }
                        if !state.unlockFeed.isEmpty {
                            Button("Clear feed") { state.clearFeed() }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                }
                
                if feed.days.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "tray")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("No new unlocks yet")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Play a game, then sync (⌘R). New unlocks show up here and as a notification.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(40)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
                    .cornerRadius(10)
                } else {
                    ForEach(feed.days) { day in
                        daySection(day)
                    }
                    
                    if feed.hasMore {
                        Button(action: { daysShown += Self.daysStep }) {
                            HStack(spacing: 6) {
                                Image(systemName: "clock.arrow.circlepath")
                                Text("Show \(Self.daysStep) earlier days")
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(24)
        }
        .onDisappear { state.markFeedSeen() }
    }
    
    /// One day: its 10 newest unlocks, and an open/close button when there are more.
    @ViewBuilder
    private func daySection(_ day: ActivityDay) -> some View {
        let isExpanded = expandedDays.contains(day.day)
        let visible = isExpanded ? day.events : Array(day.events.prefix(Self.perDayLimit))
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title(for: day.day).uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
                Text("\(day.count)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color.primary.opacity(0.08), in: Capsule())
                    .foregroundColor(.secondary)
                Spacer()
            }
            
            LazyVStack(spacing: 8) {
                ForEach(visible) { event in
                    row(event)
                }
            }
            
            if day.count > Self.perDayLimit {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        if isExpanded { expandedDays.remove(day.day) } else { expandedDays.insert(day.day) }
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        Text(isExpanded ? "Show less" : "Show \(day.count - Self.perDayLimit) more")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private func row(_ event: UnlockEvent) -> some View {
        let a = event.achievement
        return HStack(spacing: 12) {
            RemoteImageView(url: a.iconUrl.flatMap { URL(string: $0) }, fallbackSystemName: "trophy.fill", cornerRadius: 8)
                .frame(width: 44, height: 44)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(a.displayName)
                        .font(.system(size: 13, weight: .bold))
                    if !event.isSeen {
                        Text("NEW")
                            .font(.system(size: 9, weight: .heavy))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.orange)
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                    }
                }
                Text(event.gameName)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                if !a.descriptionText.isEmpty {
                    Text(a.descriptionText)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                if let tier = a.rarityTier {
                    RarityBadge(tier: tier, percentage: a.globalPercent, compact: true)
                }
                Text(event.happenedAt.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
        .cornerRadius(10)
    }
}
