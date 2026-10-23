import Foundation
import AppKit

public final class DiscordRPCService: ObservableObject {
    public static let shared = DiscordRPCService()
    
    @Published public var isEnabled: Bool = true
    @Published public var currentStatus: String = "Hunting Achievements"
    @Published public var currentDetails: String = ""
    
    public init() {}
    
    public func updatePresence(game: SteamGame?, player: SteamPlayer?) {
        guard isEnabled else { return }
        
        if let game = game {
            currentStatus = "Hunting in \(game.name)"
            currentDetails = "\(game.unlockedAchievements)/\(game.totalAchievements) Unlocked (\(Int(game.completionPercentage))%)"
        } else if let player = player {
            currentStatus = "Achievement Hunter"
            currentDetails = "\(player.personaName)'s Library"
        } else {
            currentStatus = "Achievement Hunter"
            currentDetails = "Ready to hunt"
        }
    }
    
    public var formattedDiscordSnippet: String {
        """
        [Achievement Hunter]
        Status: \(currentStatus)
        Details: \(currentDetails)
        """
    }
    
    public func copyStatusToClipboard() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString("\(currentStatus) - \(currentDetails)", forType: .string)
    }
}
