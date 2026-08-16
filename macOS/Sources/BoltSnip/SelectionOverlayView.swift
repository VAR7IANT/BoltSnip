import AppKit
import Carbon
import CoreGraphics

final class SelectionOverlayView: NSView {
    private let snapshot: NSImage
    private let pixelScaleX: CGFloat
    private let pixelScaleY: CGFloat
    private let onComplete: (CGRect) -> Void
    private let onCancel: () -> Void

    private var dragStart: CGPoint?
    private var selection: CGRect = .zero

    init(
        snapshot: CGImage,
        screenSize: CGSize,
        onComplete: @escaping (CGRect) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.snapshot = NSImage(cgImage: snapshot, size: screenSize)
        self.pixelScaleX = CGFloat(snapshot.width) / screenSize.width
        self.pixelScaleY = CGFloat(snapshot.height) / screenSize.height
        self.onComplete = onComplete
        self.onCancel = onCancel
        super.init(frame: CGRect(origin: .zero, size: screenSize))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        snapshot.draw(in: bounds, from: .zero, operation: .copy, fraction: 1)

        NSColor.black.withAlphaComponent(0.38).setFill()
        bounds.fill()

        guard selection.width >= 1, selection.height >= 1 else { return }

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: selection).addClip()
        snapshot.draw(in: bounds, from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()

        NSColor.white.setStroke()
        let border = NSBezierPath(rect: selection.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1
        border.stroke()

        drawSizeLabel()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        dragStart = clamped(point)
        selection = CGRect(origin: clamped(point), size: .zero)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStart else { return }
        let current = clamped(convert(event.locationInWindow, from: nil))
        selection = rect(from: dragStart, to: current)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let dragStart else { return }
        let current = clamped(convert(event.locationInWindow, from: nil))
        selection = rect(from: dragStart, to: current)
        self.dragStart = nil
        needsDisplay = true

        if selection.width >= 2, selection.height >= 2 {
            onComplete(selection)
        }
    }

    override func keyDown(with event: NSEvent) {
        if Int(event.keyCode) == kVK_Escape {
            onCancel()
        } else {
            super.keyDown(with: event)
        }
    }

    private func rect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    private func clamped(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, bounds.minX), bounds.maxX),
            y: min(max(point.y, bounds.minY), bounds.maxY)
        )
    }

    private func drawSizeLabel() {
        let pixelWidth = Int((selection.width * pixelScaleX).rounded())
        let pixelHeight = Int((selection.height * pixelScaleY).rounded())
        let text = "\(pixelWidth) × \(pixelHeight)"

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white
        ]

        let textSize = (text as NSString).size(withAttributes: attributes)
        let horizontalPadding: CGFloat = 9
        let verticalPadding: CGFloat = 5
        let labelSize = CGSize(
            width: textSize.width + horizontalPadding * 2,
            height: textSize.height + verticalPadding * 2
        )

        var x = selection.minX
        var y = selection.minY - labelSize.height - 7

        if y < bounds.minY + 6 {
            y = selection.maxY + 7
        }

        x = min(max(x, bounds.minX + 6), bounds.maxX - labelSize.width - 6)
        y = min(max(y, bounds.minY + 6), bounds.maxY - labelSize.height - 6)

        let labelRect = CGRect(origin: CGPoint(x: x, y: y), size: labelSize)
        NSColor.black.withAlphaComponent(0.78).setFill()
        NSBezierPath(roundedRect: labelRect, xRadius: 6, yRadius: 6).fill()

        (text as NSString).draw(
            at: CGPoint(x: labelRect.minX + horizontalPadding, y: labelRect.minY + verticalPadding),
            withAttributes: attributes
        )
    }
}
