import SwiftUI

/// Marquee-style label that scrolls long text from right to left.
struct ScrollingLabelView: View {
    let label: String
    var font: Font = .subheadline
    var speed: Double = 30
    var spacing: CGFloat = 40
    var delay: Double = 0.8

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var isAnimating = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                if shouldScroll {
                    HStack(spacing: spacing) {
                        textView
                        textView
                    }
                    .offset(x: isAnimating ? -(textWidth + spacing) : 0)
                    .onAppear { startAnimation() }
                    .onChange(of: textWidth) { _, _ in startAnimation() }
                    .onChange(of: containerWidth) { _, _ in startAnimation() }
                } else {
                    textView
                }
            }
            .onAppear { containerWidth = proxy.size.width }
            .onChange(of: proxy.size.width) { _, newValue in
                containerWidth = newValue
            }
        }
        .clipped()
    }

    private var textView: some View {
        Text(label)
            .font(font)
            .lineLimit(1)
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .preference(key: TextWidthKey.self, value: proxy.size.width)
                }
            )
            .onPreferenceChange(TextWidthKey.self) { value in
                textWidth = value
            }
    }

    private var shouldScroll: Bool {
        textWidth > containerWidth && containerWidth > 0
    }

    private func startAnimation() {
        guard shouldScroll else {
            isAnimating = false
            return
        }
        isAnimating = false
        let travel = textWidth + spacing
        let duration = max(travel / speed, 1)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
                isAnimating = true
            }
        }
    }
}

private struct TextWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
