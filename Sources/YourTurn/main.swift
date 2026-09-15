import AppKit

// Your Turn: a native panel where the human writes one piece of copy, driven by Claude over MCP.
//
//   your-turn --mcp         run as an MCP server on stdio (default)
//   your-turn --demo        show a sample panel, print the result as JSON, exit
//   your-turn --file <path> show the panel for a JSON request file, print the result, exit
//   --snapshot <png>       with --demo or --file: also render the panel to a PNG
//   your-turn --test        run the self-tests

func usage() -> Never {
    let text = """
    Your Turn: a native panel for human-written copy, driven by an agent over MCP.

      your-turn --mcp         run as an MCP server on stdio (default)
      your-turn --demo        show a sample panel, print the result as JSON, exit
      your-turn --file <path> show the panel for a JSON request file, print the result, exit
      --snapshot <png>       (with --demo/--file) also render the panel to a PNG
      your-turn --test        run the self-tests and exit non-zero on failure
      your-turn --history [n] print the last n sends (default 10)
      your-turn --icon <dir>  write the app icon as an .iconset folder
      --screenshots <dir>    (with --demo) render the README screenshots and exit
      --theme <mode>         (with a render flag) system, light, dark or paper, not saved
      --gif <path>           (with --demo) record a scripted run as a GIF and exit

    Register with Claude Code:
      claude mcp add --scope user your-turn -- /path/to/your-turn --mcp
    """
    FileHandle.standardError.write((text + "\n").data(using: .utf8)!)
    exit(2)
}

let args = Array(CommandLine.arguments.dropFirst())
Keymap.shared.load()

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
Menus.install()

let panels = PanelQueue()
var server: MCPServer?   // retained for the life of the process

/// Shows one request, prints the result, exits. Used by --demo and --file.
func runOnce(_ request: WriteRequest) {
    panels.quiet = args.contains("--snapshot") || args.contains("--screenshots") || args.contains("--gif")
    if let i = args.firstIndex(of: "--theme"), i + 1 < args.count, let mode = Settings.ThemeMode(rawValue: args[i + 1]) {
        Settings.shared.transient = true
        Settings.shared.theme = mode
    }
    delegate.onLaunch = {
        panels.present(request) { result in
            Snapshot.onFinish?()
            print(result.jsonString())
            exit(result.status == .sent ? 0 : 1)
        }
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            Snapshot.schedule(panels, to: args[i + 1])
        }
        if let i = args.firstIndex(of: "--screenshots"), i + 1 < args.count {
            Snapshot.screenshots(panels, to: args[i + 1])
        }
        if let i = args.firstIndex(of: "--gif"), i + 1 < args.count {
            Snapshot.gif(panels, to: args[i + 1])
        }
    }
}

if args.contains("--help") || args.contains("-h") {
    usage()
} else if args.contains("--test") {
    exit(SelfTests.run())
} else if let i = args.firstIndex(of: "--history") {
    let count = i + 1 < args.count ? Int(args[i + 1]) ?? 10 : 10
    print(History.summary(count: count))
    exit(0)
} else if let i = args.firstIndex(of: "--icon"), i + 1 < args.count {
    do { try DockIcon.writeIconset(to: args[i + 1]); exit(0) } catch { log("\(error)"); exit(1) }
} else if args.contains("--demo") {
    runOnce(.sample)
} else if let i = args.firstIndex(of: "--file"), i + 1 < args.count {
    let url = URL(fileURLWithPath: args[i + 1])
    guard let data = try? Data(contentsOf: url),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let request = try? WriteRequest.parse(object) else {
        log("could not read a request from \(url.path)")
        exit(2)
    }
    runOnce(request)
} else if args.isEmpty || args.contains("--mcp") {
    delegate.onLaunch = {
        server = MCPServer(present: panels.present)
        server?.start()
    }
} else {
    usage()
}

app.run()
