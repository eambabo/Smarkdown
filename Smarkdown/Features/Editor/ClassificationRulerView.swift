import AppKit

/// Vertical ruler view that draws colored classification dots in the editor gutter.
///
/// Installed as NSScrollView.verticalRulerView. Receives pre-computed
/// ClassificationMarkers from EditorViewModel (updated after every text change)
/// and draws a filled circle for each visible marker:
///   • Red    — task
///   • Green  — idea
///   • Purple — question
///
/// Coordinate notes:
///   isFlipped = true matches the text view's coordinate system (Y from top).
///   convert(_:from: textView) traverses the view hierarchy and accounts for
///   scroll offset — a line at document Y=500 maps correctly to the ruler's
///   visible-area Y coordinate without manual scroll arithmetic.
final class ClassificationRulerView: NSRulerView {

    struct Marker {
        let characterRange: NSRange
        let type: ClassificationType
    }

    var dots: [Marker] = [] {
        didSet { needsDisplay = true }
    }

    // Match the text view's flipped coordinate system so convert(_:from:)
    // produces correct Y values without manual sign flipping.
    override var isFlipped: Bool { true }

    // MARK: - Drawing

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard
            let textView = clientView as? NSTextView,
            let layoutManager = textView.layoutManager
        else { return }

        let containerOrigin = textView.textContainerOrigin

        for marker in dots {
            // Convert character range → glyph range
            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: marker.characterRange,
                actualCharacterRange: nil
            )
            guard glyphRange.location != NSNotFound, glyphRange.length > 0 else { continue }

            // Line fragment rect is in text-container coordinates.
            var fragmentRect = layoutManager.lineFragmentRect(
                forGlyphAt: glyphRange.location,
                effectiveRange: nil
            )
            guard fragmentRect != .zero else { continue }

            // Translate to text-view (document) coordinates.
            fragmentRect.origin.x += containerOrigin.x
            fragmentRect.origin.y += containerOrigin.y

            // Convert to ruler-view coordinates (handles scroll offset and flip).
            let rectInRuler = convert(fragmentRect, from: textView)

            // Only draw if within the dirty rect.
            guard rectInRuler.intersects(rect) else { continue }

            // Draw a filled circle centered vertically in the line.
            let dotSize: CGFloat = 7
            let dotX = (ruleThickness - dotSize) / 2
            let dotY = rectInRuler.midY - dotSize / 2
            let dotRect = NSRect(x: dotX, y: dotY, width: dotSize, height: dotSize)

            let color: NSColor
            switch marker.type {
            case .task:     color = .systemRed
            case .idea:     color = .systemGreen
            case .question: color = .systemPurple
            }
            color.withAlphaComponent(0.85).setFill()
            NSBezierPath(ovalIn: dotRect).fill()
        }
    }
}
