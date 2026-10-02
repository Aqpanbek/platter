import AppKit
import SwiftUI

/// The menu bar icon: left click opens the Platter panel, right click a quick scene menu.
/// The same panel also lives in a regular window, for when the icon is hidden behind the notch.
final class StatusController: NSObject, NSPopoverDelegate, NSWindowDelegate {
    private let player: NowPlayingService
    private let prefs: Preferences
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private var window: NSWindow?

    init(player: NowPlayingService, prefs: Preferences) {
        self.player = player
        self.prefs = prefs
        super.init()

        item.autosaveName = "PlatterStatusItem"
        if let button = item.button {
            button.image = StatusIcon.make()
            button.toolTip = "Platter"
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        popover.behavior = .transient
        popover.delegate = self
    }

    /// A fresh panel each time it opens; it is torn down on close so its live progress
    /// clock doesn't keep ticking in the background.
    private func makePanel() -> NSViewController {
        NSHostingController(rootView: MenuView(player: player, prefs: prefs))
    }

    func popoverDidClose(_ notification: Notification) {
        popover.contentViewController = nil
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showQuickMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        guard let button = item.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            player.refresh()
            popover.contentViewController = makePanel()
            NSApp.activate()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showQuickMenu() {
        let menu = NSMenu()
        let header = NSMenuItem(title: "Scene", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for kind in SceneKind.allCases {
            let mi = NSMenuItem(title: kind.title, action: #selector(pickScene(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = kind.rawValue
            mi.state = prefs.scene == kind ? .on : .off
            mi.image = NSImage(systemSymbolName: kind.symbol, accessibilityDescription: nil)
            menu.addItem(mi)
        }
        menu.addItem(.separator())
        let lightHeader = NSMenuItem(title: "Lighting", action: nil, keyEquivalent: "")
        lightHeader.isEnabled = false
        menu.addItem(lightHeader)
        for light in Lighting.allCases {
            let mi = NSMenuItem(title: light.title, action: #selector(pickLighting(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = light.rawValue
            mi.state = prefs.lighting == light ? .on : .off
            mi.image = NSImage(systemSymbolName: light.symbol, accessibilityDescription: nil)
            menu.addItem(mi)
        }
        menu.addItem(.separator())
        let hide = NSMenuItem(title: "Hide When Paused", action: #selector(toggleHideWhenPaused), keyEquivalent: "")
        hide.target = self
        hide.state = prefs.hideWhenPaused ? .on : .off
        menu.addItem(hide)
        let open = NSMenuItem(title: "Open Platter…", action: #selector(openWindow), keyEquivalent: ",")
        open.target = self
        menu.addItem(open)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Platter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        // Attach just for this click so a left click keeps opening the panel.
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    @objc private func pickScene(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let kind = SceneKind(rawValue: raw) else { return }
        prefs.scene = kind
    }

    @objc private func pickLighting(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let light = Lighting(rawValue: raw) else { return }
        prefs.lighting = light
    }

    @objc private func toggleHideWhenPaused() {
        prefs.hideWhenPaused.toggle()
    }

    /// Shows the panel as an ordinary window.
    @objc func openWindow() {
        if window == nil {
            let w = NSWindow(contentViewController: makePanel())
            w.title = "Platter"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            window = w
        }
        popover.performClose(nil)
        player.refresh()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

/// A small vinyl record drawn as a template image, so it follows the menu bar's light/dark tint.
enum StatusIcon {
    static func make() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let c = CGPoint(x: 9, y: 9)
            func ring(_ r: CGFloat) -> CGRect { CGRect(center: c, radius: r) }

            ctx.setFillColor(.black)
            ctx.fillEllipse(in: ring(7.6))
            // Cut grooves, the label edge and the spindle hole out of the disc.
            ctx.setBlendMode(.clear)
            ctx.setLineWidth(0.75)
            ctx.strokeEllipse(in: ring(6.0))
            ctx.strokeEllipse(in: ring(4.7))
            ctx.setLineWidth(0.9)
            ctx.strokeEllipse(in: ring(3.1))
            ctx.fillEllipse(in: ring(0.95))
            // A glint across the grooves.
            ctx.setLineWidth(1.1)
            ctx.setLineCap(.round)
            ctx.addArc(center: c, radius: 5.35, startAngle: .pi * 0.58, endAngle: .pi * 0.80, clockwise: false)
            ctx.strokePath()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Platter"
        return image
    }
}
