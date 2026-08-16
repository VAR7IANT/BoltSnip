import AppKit
import CoreGraphics

final class CaptureCoordinator {
    static let shared = CaptureCoordinator()

    private var overlayWindows: [OverlayWindow] = []

    private init() {}

    func startAreaCapture() {
        guard overlayWindows.isEmpty else { return }

        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            return
        }

        var captures: [(screen: NSScreen, image: CGImage)] = []

        for screen in NSScreen.screens {
            guard let displayNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                continue
            }

            let displayID = CGDirectDisplayID(displayNumber.uint32Value)
            guard let image = CGDisplayCreateImage(displayID) else {
                continue
            }

            captures.append((screen, image))
        }

        guard !captures.isEmpty else { return }

        overlayWindows = captures.map { capture in
            OverlayWindow(
                screen: capture.screen,
                snapshot: capture.image,
                onComplete: { [weak self] selection in
                    self?.finishCapture(
                        selection: selection,
                        screen: capture.screen,
                        sourceImage: capture.image
                    )
                },
                onCancel: { [weak self] in
                    self?.closeOverlays()
                }
            )
        }

        for window in overlayWindows {
            window.orderFrontRegardless()
        }

        let mouseLocation = NSEvent.mouseLocation
        if let activeWindow = overlayWindows.first(where: { $0.frame.contains(mouseLocation) }) ?? overlayWindows.first {
            activeWindow.makeKeyAndOrderFront(nil)
            activeWindow.makeFirstResponder(activeWindow.contentView)
        }
    }

    private func finishCapture(selection: CGRect, screen: NSScreen, sourceImage: CGImage) {
        let scaleX = CGFloat(sourceImage.width) / screen.frame.width
        let scaleY = CGFloat(sourceImage.height) / screen.frame.height

        var cropRect = CGRect(
            x: selection.minX * scaleX,
            y: (screen.frame.height - selection.maxY) * scaleY,
            width: selection.width * scaleX,
            height: selection.height * scaleY
        ).integral

        let imageBounds = CGRect(x: 0, y: 0, width: sourceImage.width, height: sourceImage.height)
        cropRect = cropRect.intersection(imageBounds)

        guard cropRect.width > 0,
              cropRect.height > 0,
              let cropped = sourceImage.cropping(to: cropRect) else {
            closeOverlays()
            return
        }

        closeOverlays()
        copyToPasteboard(cropped)
    }

    private func copyToPasteboard(_ image: CGImage) {
        let nsImage = NSImage(
            cgImage: image,
            size: NSSize(width: image.width, height: image.height)
        )

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([nsImage])

        let bitmap = NSBitmapImageRep(cgImage: image)
        if let png = bitmap.representation(using: .png, properties: [:]) {
            pasteboard.setData(png, forType: NSPasteboard.PasteboardType("public.png"))
        }
    }

    private func closeOverlays() {
        for window in overlayWindows {
            window.orderOut(nil)
            window.close()
        }
        overlayWindows.removeAll()
    }
}

final class OverlayWindow: NSWindow {
    init(
        screen: NSScreen,
        snapshot: CGImage,
        onComplete: @escaping (CGRect) -> Void,
        onCancel: @escaping () -> Void
    ) {
        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        setFrame(screen.frame, display: false)
        level = .screenSaver
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let view = SelectionOverlayView(
            snapshot: snapshot,
            screenSize: screen.frame.size,
            onComplete: onComplete,
            onCancel: onCancel
        )
        contentView = view
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
