import SwiftUI

/// A quiet stone surface: a soft gradient with a few faint veins. Drawn once per size.
struct MarbleBackground: View {
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            LinearGradient(colors: [theme.background, theme.backgroundEdge, theme.background],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Canvas { context, size in
                var generator = SeededGenerator(seed: 41)
                context.addFilter(.blur(radius: 2.5))
                for index in 0..<7 {
                    var path = Path()
                    var x = CGFloat.random(in: -0.2...1.0, using: &generator) * size.width
                    var y: CGFloat = -20
                    path.move(to: CGPoint(x: x, y: y))
                    while y < size.height + 40 {
                        let dx = CGFloat.random(in: -34...58, using: &generator)
                        let dy = CGFloat.random(in: 40...110, using: &generator)
                        path.addQuadCurve(to: CGPoint(x: x + dx, y: y + dy),
                                          control: CGPoint(x: x + dx * 1.6, y: y + dy * 0.4))
                        x += dx
                        y += dy
                    }
                    let opacity = (theme.isDark ? 0.05 : 0.09) + Double(index % 3) * 0.015
                    context.stroke(path, with: .color(theme.vein.opacity(opacity)),
                                   lineWidth: CGFloat.random(in: 0.6...2.2, using: &generator))
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E3779B97F4A7C15 | 1 }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

extension View {
    /// Places the view over the marble for the current theme.
    func marbleBackground() -> some View {
        background(MarbleBackground())
    }
}
