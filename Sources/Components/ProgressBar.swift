import SwiftUI

public struct CustomProgressBar: View {
    public let value: Double // 0 to 100
    public var height: CGFloat = 6
    public var isPerfect: Bool = false
    
    public init(value: Double, height: CGFloat = 6, isPerfect: Bool = false) {
        self.value = value
        self.height = height
        self.isPerfect = isPerfect
    }
    
    private var progressClamped: CGFloat {
        CGFloat(max(0.0, min(100.0, value)) / 100.0)
    }
    
    public var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(Color.primary.opacity(0.12))
                    .frame(height: height)
                
                // Progress fill
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(
                        isPerfect
                            ? LinearGradient(
                                colors: [Color(red: 1.0, green: 0.82, blue: 0.2), Color(red: 1.0, green: 0.6, blue: 0.1)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            : LinearGradient(
                                colors: [Color.blue, Color.cyan],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                    )
                    .frame(width: max(0, geometry.size.width * progressClamped), height: height)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: value)
            }
        }
        .frame(height: height)
    }
}
