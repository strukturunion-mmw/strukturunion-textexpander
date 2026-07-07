import AppKit

// Manual app bootstrap so we can run as an accessory (menu-bar) app that
// optionally shows a Dock icon, and install the AppDelegate before launch.
// Program start is already on the main thread, so assuming main-actor
// isolation here is safe and lets us construct the @MainActor delegate.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
