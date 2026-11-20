import SwiftUI

extension View {
    func macEditorField() -> some View {
        scrollContentBackground(.hidden)
            .padding(4)
            .macInputSurface()
    }

    func macInputSurface() -> some View {
        let border = RoundedRectangle(cornerRadius: 4)
        return background(Color(nsColor: .textBackgroundColor), in: border)
            .clipShape(border)
            .overlay {
                border.strokeBorder(Color(nsColor: .separatorColor))
                    .allowsHitTesting(false)
            }
    }

    func macGroupSurface() -> some View {
        let border = RoundedRectangle(cornerRadius: 8)
        return background(Color(nsColor: .controlBackgroundColor), in: border)
            .overlay {
                border.strokeBorder(Color(nsColor: .separatorColor).opacity(0.55))
                    .allowsHitTesting(false)
            }
    }
}
