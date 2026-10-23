import AppKit
import SwiftUI

@MainActor
public final class FloatingWidgetManager: ObservableObject {
    public static let shared = FloatingWidgetManager()
    
    @Published public private(set) var isVisible: Bool = false
    @Published public var activeWidgetType: Int = 0
    
    private var panel: NSPanel?
    
    private init() {}
    
    public func toggle(widgetType: Int, state: AppState) {
        if isVisible && activeWidgetType == widgetType {
            close()
        } else {
            show(widgetType: widgetType, state: state)
        }
    }
    
    public func show(widgetType: Int, state: AppState) {
        self.activeWidgetType = widgetType
        
        if let existing = panel {
            existing.contentView = NSHostingView(rootView: FloatingWidgetContainerView(widgetType: widgetType, state: state))
            existing.orderFront(nil)
            isVisible = true
            return
        }
        
        let newPanel = NSPanel(
            contentRect: NSRect(x: 200, y: 300, width: 480, height: 180),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        newPanel.isFloatingPanel = true
        newPanel.level = .floating
        newPanel.backgroundColor = .clear
        newPanel.isOpaque = false
        newPanel.hasShadow = true
        newPanel.isMovableByWindowBackground = true
        newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        newPanel.contentView = NSHostingView(rootView: FloatingWidgetContainerView(widgetType: widgetType, state: state))
        
        newPanel.center()
        newPanel.orderFront(nil)
        self.panel = newPanel
        self.isVisible = true
    }
    
    public func close() {
        panel?.orderOut(nil)
        panel = nil
        isVisible = false
    }
}

private struct FloatingWidgetContainerView: View {
    let widgetType: Int
    @ObservedObject var state: AppState
    @State private var isHovered: Bool = false
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            WidgetRendererView(widgetType: widgetType, state: state)
                .shadow(color: Color.black.opacity(0.4), radius: 16, x: 0, y: 8)
                .padding(14)
            
            // Hover controls (Close & drag indicator)
            if isHovered {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.6))
                    
                    Button(action: {
                        FloatingWidgetManager.shared.close()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundColor(.white.opacity(0.75))
                    }
                    .buttonStyle(.plain)
                }
                .padding(8)
                .background(Color.black.opacity(0.6))
                .cornerRadius(12)
                .padding(18)
                .transition(.opacity)
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}
