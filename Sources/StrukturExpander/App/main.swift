import AppKit

// Manual app bootstrap so we can run as an accessory (menu-bar) app that
// optionally shows a Dock icon, and install the AppDelegate before launch.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
