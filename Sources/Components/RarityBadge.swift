import SwiftUI

public struct RarityBadge: View {
    public let tier: RarityTier
    public let percentage: Double?
    public var compact: Bool = false
    
    public init(tier: RarityTier, percentage: Double? = nil, compact: Bool = false) {
        self.tier = tier
        self.percentage = percentage
        self.compact = compact
    }
    
    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: tier.iconName)
                .font(.system(size: compact ? 9 : 11, weight: .bold))
                .foregroundColor(tier.color)
            
            if !compact {
                Text(tier.rawValue)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(tier.color)
            }
            
            if let pct = percentage {
                Text(String(format: "%.1f%%", pct))
                    .font(.system(size: compact ? 10 : 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(tier.color.opacity(0.9))
            }
        }
        .padding(.horizontal, compact ? 6 : 8)
        .padding(.vertical, compact ? 2 : 4)
        .background(
            Capsule()
                .fill(tier.color.opacity(0.14))
                .overlay(
                    Capsule()
                        .strokeBorder(tier.color.opacity(0.3), lineWidth: 0.8)
                )
        )
    }
}
