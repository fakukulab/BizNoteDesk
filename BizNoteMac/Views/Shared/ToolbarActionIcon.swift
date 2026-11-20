import SwiftUI

struct ToolbarActionIcon: View {
    let systemName: String
    var isActive: Bool = false

    var body: some View {
        Image(systemName: systemName)
            .foregroundStyle(isActive ? Color.accentColor : Color.primary)
    }
}
