import AppKit

/// Work queued before the run loop exists is deferred until the app has finished launching;
/// windows ordered front earlier than that can be silently dropped for an unbundled process.
final class AppDelegate: NSObject, NSApplicationDelegate {
    var onLaunch: () -> Void = {}

    func applicationDidFinishLaunching(_ notification: Notification) { onLaunch() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

/// Writes a line to stderr. Stdout is reserved for JSON-RPC.
func log(_ message: String) {
    FileHandle.standardError.write(("your-turn: " + message + "\n").data(using: .utf8)!)
}
