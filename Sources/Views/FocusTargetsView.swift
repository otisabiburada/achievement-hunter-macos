import SwiftUI
import AppKit

public struct FocusTargetsView: View {
    @ObservedObject var state: AppState
    @State private var editingNotesTargetId: String? = nil
    @State private var noteDraft: String = ""
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.orange)
                            Text("Focus Targets & Grinding Dashboard")
                                .font(.system(size: 24, weight: .bold))
                        }
                        Text("Pin specific achievements you are currently pursuing across any game to track them in one place.")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Text("\(state.pinnedTargets.count) Targets Pinned")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.orange.opacity(0.15))
                        .foregroundColor(.orange)
                        .cornerRadius(8)
                }
                
                if state.pinnedTargets.isEmpty {
                    VStack(spacing: 14) {
                        Spacer()
                        Image(systemName: "pin.slash")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary.opacity(0.4))
                        Text("No achievements currently pinned to Focus Targets.")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Click the pin icon (📌) on any achievement card or in the 'Road to 100%' view to start tracking your grinding targets here.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 400)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, minHeight: 320)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(state.pinnedTargets) { target in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 12) {
                                    // Target Icon
                                    RemoteImageView(
                                        url: target.achievement.grayIconUrl.flatMap { URL(string: $0) } ?? target.achievement.iconUrl.flatMap { URL(string: $0) },
                                        fallbackSystemName: "scope",
                                        cornerRadius: 8
                                    )
                                    .frame(width: 48, height: 48)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(target.gameName)
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundColor(.secondary)
                                            
                                            Text("•")
                                                .foregroundColor(.secondary.opacity(0.4))
                                            
                                            if let tier = target.achievement.rarityTier {
                                                RarityBadge(tier: tier, percentage: target.achievement.globalPercent, compact: true)
                                            }
                                        }
                                        
                                        Text(target.achievement.displayName)
                                            .font(.system(size: 15, weight: .bold))
                                        
                                        Text(target.achievement.descriptionText)
                                            .font(.system(size: 12))
                                            .foregroundColor(.secondary)
                                            .lineLimit(2)
                                    }
                                    
                                    Spacer()
                                    
                                    // Walkthrough Links
                                    Button(action: {
                                        state.openWalkthrough(for: target.achievement, gameName: target.gameName)
                                    }) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "play.tv.fill")
                                            Text("Walkthrough")
                                        }
                                        .font(.system(size: 11, weight: .medium))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Color.blue.opacity(0.12))
                                        .foregroundColor(.blue)
                                        .cornerRadius(6)
                                    }
                                    .buttonStyle(.plain)
                                    
                                    // Unpin button
                                    Button(action: {
                                        state.removePinnedTarget(id: target.id)
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.secondary)
                                            .font(.system(size: 16))
                                    }
                                    .buttonStyle(.plain)
                                }
                                
                                // User Grinding Note Section
                                HStack {
                                    Image(systemName: "note.text")
                                        .foregroundColor(.secondary)
                                        .font(.system(size: 11))
                                    
                                    if editingNotesTargetId == target.id {
                                        TextField("Add grinding notes (e.g. Need chapter 4 save, collect 10 more tokens)...", text: $noteDraft, onCommit: {
                                            state.updateTargetNote(id: target.id, note: noteDraft)
                                            editingNotesTargetId = nil
                                        })
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(size: 11))
                                        
                                        Button("Save") {
                                            state.updateTargetNote(id: target.id, note: noteDraft)
                                            editingNotesTargetId = nil
                                        }
                                        .font(.system(size: 10))
                                    } else {
                                        Text(target.notes.isEmpty ? "Click to add your personal grinding strategy note..." : target.notes)
                                            .font(.system(size: 11))
                                            .foregroundColor(target.notes.isEmpty ? .secondary.opacity(0.7) : .primary)
                                            .italic(target.notes.isEmpty)
                                        
                                        Spacer()
                                        
                                        Button(action: {
                                            noteDraft = target.notes
                                            editingNotesTargetId = target.id
                                        }) {
                                            Image(systemName: "pencil")
                                                .font(.system(size: 10))
                                                .foregroundColor(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.primary.opacity(0.03))
                                .cornerRadius(6)
                            }
                            .padding(14)
                            .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                            .cornerRadius(12)
                        }
                    }
                }
            }
            .padding(24)
        }
    }
}
