
import SwiftUI

struct ScrollLabelView: View {
    let label: String
    var font: Font = .subheadline

    // MARK: - Konfiguration
    private let scrollSpeed: Double = 20      // Pixel pro Sekunde
    private let pauseDuration: Double = 4   // Pause am Anfang & Ende (Sekunden)
    private let textColor: Color = .primary

    // MARK: - State
    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    @State private var isAnimating: Bool = false

    private var needsScrolling: Bool {
        textWidth > containerWidth
    }

    private var scrollDistance: CGFloat {
        textWidth - containerWidth
    }

    private var animationDuration: Double {
        Double(scrollDistance) / scrollSpeed
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Unsichtbarer Text zum Messen der Textbreite
                Text(label)
                    .font(font)
                    .foregroundColor(.clear)
                    .fixedSize()
                    .background(
                        GeometryReader { textGeo in
                            Color.clear
                                .onAppear {
                                    textWidth = textGeo.size.width
                                    containerWidth = geometry.size.width
                                    startScrollingIfNeeded()
                                }
                                .onChange(of: label) { _, _ in
                                    textWidth = textGeo.size.width
                                    containerWidth = geometry.size.width
                                    resetAndScroll()
                                }
                        }
                    )

                // Sichtbarer, scrollender Text
                Text(label)
                    .font(font)
                    .foregroundColor(textColor)
                    .fixedSize()
                    .offset(x: offset, y: 0)
            }
            .frame(width: geometry.size.width, alignment: .leading)
            .clipped()
        }
    }

    // MARK: - Scroll-Logik

    private func startScrollingIfNeeded() {
        guard needsScrolling else { return }
        offset = 0
        isAnimating = true
        scrollForward()
    }

    private func resetAndScroll() {
        isAnimating = false
        offset = 0

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            guard needsScrolling else { return }
            isAnimating = true
            scrollForward()
        }
    }

    /// Scrollt den Text von rechts nach links (Offset: 0 → -scrollDistance)
    private func scrollForward() {
        guard isAnimating else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + pauseDuration) {
            guard isAnimating else { return }

            withAnimation(.linear(duration: animationDuration)) {
                offset = -scrollDistance
            }

            // Nach dem Hinrollen: kurz pausieren, dann zurücksetzen
            DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration + pauseDuration) {
                guard isAnimating else { return }

                withAnimation(.linear(duration: 0.0)) {
                    offset = 0
                }

                scrollForward() // Endlosschleife
            }
        }
    }
}
