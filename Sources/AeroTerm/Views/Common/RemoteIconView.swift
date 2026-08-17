import SwiftUI
import AppKit

public struct AgentIconView: View {
    let iconFile: String?
    let fallbackSymbol: String
    let tintColor: Color
    let size: CGFloat

    public init(
        iconFile: String?,
        fallbackSymbol: String = "sparkles",
        tintColor: Color = .purple,
        size: CGFloat = 46
    ) {
        self.iconFile = iconFile
        self.fallbackSymbol = fallbackSymbol
        self.tintColor = tintColor
        self.size = size
    }

    private var loadedImage: NSImage? {
        guard let file = iconFile, !file.isEmpty else { return nil }
        if let url = Bundle.module.url(forResource: file, withExtension: nil, subdirectory: "Icons") {
            return NSImage(contentsOf: url)
        } else if let url = Bundle.main.url(forResource: file, withExtension: nil) {
            return NSImage(contentsOf: url)
        }
        let devPath = "/Users/jackson-hao/code/AeroTerm/Sources/AeroTerm/Resources/Icons/\(file)"
        return NSImage(contentsOfFile: devPath)
    }

    public var body: some View {
        Group {
            if let nsImg = loadedImage {
                Image(nsImage: nsImg)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
                    .cornerRadius(size * 0.22)
                    .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.22)
                        .fill(tintColor.opacity(0.15))
                        .frame(width: size, height: size)

                    Image(systemName: fallbackSymbol)
                        .font(.system(size: size * 0.48, weight: .semibold))
                        .foregroundColor(tintColor)
                }
                .frame(width: size, height: size)
            }
        }
    }
}
