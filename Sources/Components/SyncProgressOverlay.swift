import SwiftUI

public struct SyncProgressOverlay: View {
    public let statusText: String
    public let detailText: String
    public let progress: Double
    
    public init(statusText: String, detailText: String = "", progress: Double) {
        self.statusText = statusText
        self.detailText = detailText
        self.progress = progress
    }
    
    public var body: some View {
        ZStack {
            // Dark dimming backdrop
            Color.black.opacity(0.45)
                .edgesIgnoringSafeArea(.all)
            
            // Progress Box
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(width: 56, height: 56)
                    
                    ProgressView()
                        .scaleEffect(1.1)
                }
                
                VStack(spacing: 4) {
                    Text(statusText.isEmpty ? "Syncing with Steam..." : statusText)
                        .font(.system(size: 15, weight: .bold))
                        .multilineTextAlignment(.center)
                    
                    if !detailText.isEmpty {
                        Text(detailText)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                
                // Real-time animated progress bar
                VStack(spacing: 6) {
                    ProgressView(value: max(0.05, min(1.0, progress)), total: 1.0)
                        .progressViewStyle(.linear)
                        .frame(width: 280)
                    
                    HStack {
                        Text("\(Int(progress * 100))%")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.accentColor)
                        Spacer()
                        Text("Please keep window open")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .frame(width: 280)
                }
            }
            .padding(28)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(NSColor.windowBackgroundColor))
                    .shadow(color: Color.black.opacity(0.3), radius: 20, y: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
            )
        }
    }
}
