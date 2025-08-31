import SwiftUI

struct ContentView: View {
    @State private var isExpanded = false
    @State private var hoverLeft = false
    @State private var hoverRight = false
    @State private var hoverCenter = false
    @State private var hoverExpanded = false
    
    var body: some View {
        ZStack(alignment: .top) {
            
            // Expanded notch (only shows when isExpanded == true)
            if isExpanded {
                Rectangle()
                    .fill(Color.black)
                    .frame(width: 300, height: 100)
                    .cornerRadius(20)
                    .offset(y: 0)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(1)
                    .onHover { inside in
                        hoverExpanded = inside
                        updateExpandedState()
                    }
            }
            
            // Camera notch region = left square + gap + right square
            HStack(spacing: 200) {
                // Left square
                Rectangle()
                    .fill(Color.black)
                    .frame(width: 40, height: 40)
                    .cornerRadius(8)
                    .onHover { inside in
                        hoverLeft = inside
                        updateExpandedState()
                    }
                
                // Invisible "camera notch" region
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 200, height: 40) // same height as squares
                    .contentShape(Rectangle()) // ensures hover works
                    .onHover { inside in
                        hoverCenter = inside
                        updateExpandedState()
                    }
                
                // Right square
                Rectangle()
                    .fill(Color.black)
                    .frame(width: 40, height: 40)
                    .cornerRadius(8)
                    .onHover { inside in
                        hoverRight = inside
                        updateExpandedState()
                    }
            }
            .opacity(isExpanded ? 0 : 1) // hide small squares when expanded
            .animation(.easeInOut(duration: 0.3), value: isExpanded)
        }
        .frame(height: 150, alignment: .top)
    }
    
    private func updateExpandedState() {
        let hovering = hoverLeft || hoverRight || hoverCenter || hoverExpanded
        withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
            isExpanded = hovering
        }
    }
}

#Preview {
    ContentView()
        .frame(width: 400, height: 200)
        .background(Color.gray.opacity(0.2))
}
