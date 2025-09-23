import SwiftUI

struct ContentView: View {
    @State private var isHovered = false
    
    var body: some View {
        ZStack { // Stack views on top of each other
            // Always visible two small squares
            HStack(spacing: 200) {
                Rectangle()
                    .fill(Color.black)
                    .frame(width: 40, height: 40)
                    .cornerRadius(8)
                Rectangle()
                    .fill(Color.black)
                    .frame(width: 40, height: 40)
                    .cornerRadius(8)
            }
            
            // Big rectangle appears only when hovered
            if isHovered {
                Rectangle()
                    .fill(Color.black)
                    .frame(width: 280, height: 100)
                    .cornerRadius(12)
                    .transition(.scale)
                    .offset(x: 0, y: 30) // Mov
            }
        }
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isHovered = hovering
            }
        }
    }
}

#Preview {
    ContentView()
        .frame(width: 500, height: 250)
        .background(Color.gray.opacity(0.2))
}
