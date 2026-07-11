import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// Menu-bar utility: no Dock icon, no Cmd-Tab entry.
app.setActivationPolicy(.accessory)
app.run()
