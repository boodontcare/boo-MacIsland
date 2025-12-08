//
//  MacIslandApp.swift
//  MacIsland
//
//  Created by Joshua Wong on 2025-08-30.
//

import SwiftUI
import AppKit

@main
class MacIslandApp: NSObject, NSApplicationDelegate {
    class OverlayWindow: NSWindow {
        override var canBecomeKey: Bool { true }
    }

    var overlayWindow: OverlayWindow?

    static func main() {
        let delegate = MacIslandApp()
        NSApplication.shared.delegate = delegate
        NSApplication.shared.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        createOverlayWindow()
    }

    func createOverlayWindow() {
        let screen = NSScreen.main!
        let screenRect = screen.frame

        // Position at top center, similar to Dynamic Island
        // Increased height to accommodate the full expanded view
        let windowWidth: CGFloat = 500
        let windowHeight: CGFloat = 200
        // Manual positioning: adjust x and y values for your screen
        // x = horizontal position from left edge (0 = left edge)
        // y = vertical position from bottom edge (0 = bottom edge)
        // Example for 1920x1080 screen: x=710, y=880 (top center)
        let x: CGFloat = 598.8
        let y: CGFloat = 924.4

        overlayWindow = OverlayWindow(
            contentRect: NSRect(x: x, y: y, width: windowWidth, height: windowHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        overlayWindow!.isOpaque = false
        overlayWindow!.backgroundColor = .clear
        overlayWindow!.level = .statusBar
        overlayWindow!.hasShadow = false
        overlayWindow!.ignoresMouseEvents = false
        overlayWindow!.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let hostingView = NSHostingView(rootView: ContentView())
        // Ensure content is anchored to top of window, not centered
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        overlayWindow!.contentView = hostingView

        // Add constraints to pin the hosting view to the top
        if let contentView = overlayWindow!.contentView {
            NSLayoutConstraint.activate([
                hostingView.topAnchor.constraint(equalTo: contentView.topAnchor),
                hostingView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                hostingView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                hostingView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
            ])
        }

        overlayWindow!.makeKeyAndOrderFront(nil)
    }
}
