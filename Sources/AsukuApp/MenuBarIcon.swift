import SwiftUI

/// Custom menu bar icon: terminal prompt with notification badge
struct MenuBarIcon: View {
    let hasPending: Bool
    let contextPressure: Bool

    init(hasPending: Bool, contextPressure: Bool = false) {
        self.hasPending = hasPending
        self.contextPressure = contextPressure
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: "apple.terminal")
                .font(.system(size: 14, weight: .medium))

            if hasPending {
                Circle()
                    .fill(.red)
                    .frame(width: 6, height: 6)
                    .offset(x: 2, y: -2)
            } else if contextPressure {
                Circle()
                    .fill(.orange)
                    .frame(width: 6, height: 6)
                    .offset(x: 2, y: -2)
            }
        }
    }
}
