# Your Turn

Native macOS panel + MCP server, one Swift executable wrapped as `.build/YourTurn.app`.
Build with `make app` (plain swiftc; SwiftPM fails without full Xcode); `make install`
also registers the MCP server. Run `make test` after every change: in-process
self-tests in Tests/SelfTests.swift cover Markdown round trips, lists, headings, bold/italic/link
toggling in a real window, the hover bar, notes and asides, layout stability, parsing,
keymap, settings, diff, history, and MCP replies. Verify visuals with
`.build/your-turn --demo --snapshot /tmp/x.png` and read the PNG (a `-selection.png`
twin shows the hover bar).

Rules:
- Nothing but JSON-RPC may go to stdout in `--mcp` mode. Log to stderr via `log()`.
- Design reference is the mymind editor: a light capsule hover bar with a nib and
  an inline field, white canvas, airy. Palette is teal on ink and white (`Theme`),
  with a paper variant. Fonts: Charter for titles and headings, Avenir Next
  elsewhere; both ship with macOS.
- Every paragraph gap lives BEFORE the paragraph (TextStyle); Return must never
  move or resize the line above. Tests check this; keep them passing.
- No hover animations in the sidebar. Ticks, the hover bar and Send do animate.
- Titles are the thing's name only ("Tetrachord"), no dashes or subtitles.
- The tool contract (`your_turn_write` in MCPServer.swift) is what other sessions
  depend on; change it deliberately and update README.md and the `/your-turn` skill.
