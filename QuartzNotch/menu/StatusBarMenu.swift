import Cocoa

class QuartzStatusMenu: NSMenu {
    
    var statusItem: NSStatusItem!
    
    override init() {
        super.init()
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "QuartzNotch")
            button.action = #selector(showMenu)
        }
        
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitAction), keyEquivalent: "q"))
        statusItem.menu = menu
    }

}
