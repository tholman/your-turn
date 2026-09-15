import AppKit

/// An unbundled executable has no main menu, so ⌘C/⌘V/⌘Z and every custom key would be dead. Build one.
enum Menus {
    static func install() {
        let main = NSMenu()
        main.addItem(submenu: appMenu())
        main.addItem(submenu: editMenu())
        main.addItem(submenu: formatMenu())
        main.addItem(submenu: pointsMenu())
        NSApp.mainMenu = main
    }

    private static func appMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "Quit Your Turn", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: "Edit")
        menu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        menu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        menu.addItem(.separator())
        Keymap.shared.register(menu.addItem(withTitle: "Look Up Selection", action: #selector(RichTextView.lookUpSelection(_:)), keyEquivalent: ""), for: .lookup)

        let spelling = NSMenu(title: "Spelling and Grammar")
        spelling.addItem(withTitle: "Show Spelling and Grammar", action: #selector(NSText.showGuessPanel(_:)), keyEquivalent: ":")
        spelling.addItem(withTitle: "Check Document Now", action: #selector(NSText.checkSpelling(_:)), keyEquivalent: ";")
        spelling.addItem(.separator())
        spelling.addItem(withTitle: "Check Spelling While Typing", action: #selector(NSTextView.toggleContinuousSpellChecking(_:)), keyEquivalent: "")
        spelling.addItem(withTitle: "Check Grammar With Spelling", action: #selector(NSTextView.toggleGrammarChecking(_:)), keyEquivalent: "")
        menu.addItem(submenu: spelling)
        return menu
    }

    private static func formatMenu() -> NSMenu {
        let menu = NSMenu(title: "Format")
        let keymap = Keymap.shared
        keymap.register(menu.addItem(withTitle: "Bold", action: #selector(RichTextView.toggleBold(_:)), keyEquivalent: ""), for: .bold)
        keymap.register(menu.addItem(withTitle: "Italic", action: #selector(RichTextView.toggleItalic(_:)), keyEquivalent: ""), for: .italic)
        keymap.register(menu.addItem(withTitle: "Add Link…", action: #selector(RichTextView.insertLink(_:)), keyEquivalent: ""), for: .link)
        keymap.register(menu.addItem(withTitle: "Note About Selection…", action: #selector(RichTextView.insertNote(_:)), keyEquivalent: ""), for: .note)
        return menu
    }

    private static func pointsMenu() -> NSMenu {
        let menu = NSMenu(title: "Points")
        let keymap = Keymap.shared
        for n in 1...9 {
            let item = menu.addItem(withTitle: "Tick Point \(n)", action: #selector(PanelController.togglePoint(_:)), keyEquivalent: "\(n)")
            item.tag = n
        }
        menu.addItem(.separator())
        keymap.register(menu.addItem(withTitle: "Add a Point", action: #selector(PanelController.addPoint(_:)), keyEquivalent: ""), for: .addPoint)
        menu.addItem(.separator())
        keymap.register(menu.addItem(withTitle: "Send", action: #selector(PanelController.sendCopy(_:)), keyEquivalent: ""), for: .send)
        keymap.register(menu.addItem(withTitle: "Show Changes", action: #selector(PanelController.toggleDiff(_:)), keyEquivalent: ""), for: .diff)
        keymap.register(menu.addItem(withTitle: "Settings and Keys", action: #selector(PanelController.toggleSettings(_:)), keyEquivalent: ""), for: .keys)
        return menu
    }
}

private extension NSMenu {
    func addItem(submenu: NSMenu) {
        let item = NSMenuItem()
        item.submenu = submenu
        addItem(item)
    }
}
