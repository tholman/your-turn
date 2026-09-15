import SwiftUI

/// Title, the points to hit, and links worth using.
struct Sidebar: View {
    @Environment(\.look) private var look
    @ObservedObject var model: EditorModel
    @FocusState private var focusedPoint: String?
    @State private var rowFrames: [String: CGRect] = [:]
    @State private var dragging: (id: String, offset: CGFloat)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(model.request.title)
                    .font(Theme.serif(24))
                    .foregroundStyle(look.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 30)
                    .padding(.top, 44)
                if !model.request.context.isEmpty {
                    Text(model.request.context)
                        .font(Theme.font(13))
                        .foregroundStyle(look.ink.opacity(0.66))
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 30)
                        .padding(.top, 10)
                }

                VStack(spacing: 0) {
                    ForEach($model.points) { $point in
                        PointRow(point: $point,
                                 editing: model.editingID == point.id,
                                 focus: $focusedPoint,
                                 onCommit: model.commitEdit,
                                 onEdit: { model.edit(point.id) },
                                 onDelete: { model.remove(point.id) })
                            .background(GeometryReader { geometry in
                                Color.clear.preference(key: RowFrames.self, value: [point.id: geometry.frame(in: .named("points"))])
                            })
                            .offset(y: dragging?.id == point.id ? dragging!.offset : 0)
                            .zIndex(dragging?.id == point.id ? 1 : 0)
                            .opacity(dragging?.id == point.id ? 0.85 : 1)
                            .gesture(
                                DragGesture(minimumDistance: 6, coordinateSpace: .named("points"))
                                    .onChanged { value in dragging = (point.id, value.translation.height) }
                                    .onEnded { value in
                                        defer { dragging = nil }
                                        guard let frame = rowFrames[point.id] else { return }
                                        let centre = frame.midY + value.translation.height
                                        // Land on the row whose middle is nearest to where this one was dropped.
                                        let order = model.points.map(\.id)
                                        let nearest = order.min { (rowFrames[$0]?.midY ?? 0 - centre).magnitude < (rowFrames[$1]?.midY ?? 0 - centre).magnitude }
                                        if let nearest = nearest, let index = order.firstIndex(of: nearest) { model.movePoint(point.id, to: index) }
                                    }
                            )
                    }
                }
                .coordinateSpace(name: "points")
                .onPreferenceChange(RowFrames.self) { rowFrames = $0 }
                .padding(.horizontal, 20)
                .padding(.top, 22)
                .onChange(of: model.editingID) { focusedPoint = $0 }

                Button(action: model.addPoint) {
                    HStack(spacing: 7) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .bold))
                        Text("Add a point")
                    }
                    .font(Theme.font(12, "Medium"))
                    .foregroundStyle(look.mute)
                    .padding(.horizontal, 30)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                let notes = model.notes
                if !notes.isEmpty {
                    SectionLabel("NOTES")
                    VStack(spacing: 0) {
                        ForEach(Array(notes.enumerated()), id: \.offset) { _, entry in
                            NoteRow(quote: entry.quote, note: entry.note,
                                    onSelect: { model.select(entry.range) },
                                    onDelete: { model.removeNote(at: entry.range) })
                        }
                    }
                    .padding(.horizontal, 20)
                }

                let links = model.links
                if !links.isEmpty {
                    SectionLabel("LINKS")
                    VStack(spacing: 0) {
                        ForEach(links) { reference in
                            LinkRow(reference: reference) { model.useLink(reference) }
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
            .padding(.bottom, 20)
        }
    }
}

private struct SectionLabel: View {
    @Environment(\.look) private var look
    var text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(Theme.font(10, "DemiBold"))
            .tracking(1.6)
            .foregroundStyle(look.mute)
            .padding(.horizontal, 30)
            .padding(.top, 24)
            .padding(.bottom, 8)
    }
}

struct NoteRow: View {
    @Environment(\.look) private var look
    var quote: String
    var note: String
    var onSelect: () -> Void
    var onDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("“\(quote)”")
                .font(Theme.font(11.5))
                .foregroundStyle(look.mute)
                .lineLimit(1)
            Text(note)
                .font(Theme.font(12, "Medium"))
                .foregroundStyle(look.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .contextMenu {
            Button("Select text", action: onSelect)
            Button("Remove note", action: onDelete)
        }
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(look.mute)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Remove this note")
                .padding(.top, 5)
                .padding(.trailing, 4)
            }
        }
        .onHover { hovering = $0 }
        .help("Select this text")
    }
}

private struct RowFrames: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) { value.merge(nextValue()) { $1 } }
}

struct PointRow: View {
    @Environment(\.look) private var look
    @Binding var point: EditablePoint
    var editing: Bool
    var focus: FocusState<String?>.Binding
    var onCommit: () -> Void
    var onEdit: () -> Void
    var onDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            ZStack {
                Circle()
                    .strokeBorder(point.done ? look.accent : look.mute.opacity(0.55), lineWidth: 1.2)
                Circle()
                    .fill(look.accent)
                    .scaleEffect(point.done ? 1 : 0.01)
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color.white)
                    .opacity(point.done ? 1 : 0)
                    .scaleEffect(point.done ? 1 : 0.4)
            }
            .frame(width: 16, height: 16)
            .padding(.top, 2)
            .accessibilityLabel(point.done ? "Ticked" : "Not ticked")

            Group {
                if editing {
                    TextField("New point", text: $point.label)
                        .textFieldStyle(.plain)
                        .font(Theme.font(13, "Medium"))
                        .focused(focus, equals: point.id)
                        .onSubmit(onCommit)
                        .onExitCommand(perform: onCommit)
                        .onChange(of: focus.wrappedValue) { if $0 != point.id { onCommit() } }
                } else {
                    label
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture { if !editing { point.done.toggle() } }
        .contextMenu {
            Button(point.done ? "Untick" : "Tick") { point.done.toggle() }
            Button("Edit", action: onEdit)
            Divider()
            Button("Remove", action: onDelete)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(point.label), \(point.done ? "ticked" : "not ticked")")
        .animation(.easeOut(duration: 0.34), value: point.done)
        .overlay(alignment: .topTrailing) {
            // Floats over the end of the first line on hover; a soft fade keeps it legible over text.
            if hovering && !editing {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(look.mute)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Remove this point")
                .padding(.leading, 14)
                .background(
                    LinearGradient(colors: [look.sidebar.opacity(0), look.sidebar, look.sidebar], startPoint: .leading, endPoint: .trailing)
                )
                .padding(.top, 5)
                .padding(.trailing, 4)
            }
        }
        .onHover { hovering = $0 }
    }

    /// The label, with a struck copy revealed line by line when done.
    private var label: some View {
        Text(point.label)
            .font(Theme.font(13, "Medium"))
            .foregroundStyle(point.done ? look.mute : look.ink)
            .fixedSize(horizontal: false, vertical: true)
            .overlay(alignment: .leading) {
                Text(point.label)
                    .font(Theme.font(13, "Medium"))
                    .strikethrough(true, color: look.mute)
                    .foregroundStyle(look.mute)
                    .fixedSize(horizontal: false, vertical: true)
                    .mask(StrikeMask(progress: point.done ? 1 : 0, lineHeight: 18))
            }
    }
}

/// Reveals a strike line by line, left to right, so a two-line label strikes the first line then the second.
struct StrikeMask: Shape {
    var progress: CGFloat
    var lineHeight: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let lines = max(1, Int((rect.height / lineHeight).rounded()))
        let height = rect.height / CGFloat(lines)
        var path = Path()
        for line in 0..<lines {
            let local = min(max(progress * CGFloat(lines) - CGFloat(line), 0), 1)
            if local > 0 {
                path.addRect(CGRect(x: rect.minX, y: rect.minY + CGFloat(line) * height, width: rect.width * local, height: height))
            }
        }
        return path
    }
}

struct LinkRow: View {
    @Environment(\.look) private var look
    var reference: Reference
    var onApply: () -> Void
    @State private var hovering = false
    @ObservedObject private var info = LinkInfo.shared

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "link")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(reference.label)
                    .font(Theme.font(12, "Medium"))
                    .foregroundStyle(look.ink)
                    .lineLimit(1)
                Text(info.title(for: reference.url) ?? reference.url.host ?? reference.url.absoluteString)
                    .font(Theme.font(10.5))
                    .foregroundStyle(look.mute)
                    .lineLimit(1)
            }
            .onAppear { info.fetch(reference.url) }
            Spacer(minLength: 0)
            if hovering {
                Button { NSWorkspace.shared.open(reference.url) } label: {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .help("Open in browser")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture(perform: onApply)
        .contextMenu {
            Button("Open") { NSWorkspace.shared.open(reference.url) }
            Button("Copy link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(reference.url.absoluteString, forType: .string)
            }
            Button("Link selected text", action: onApply)
        }
        .onHover { hovering = $0 }
        .help("Opens the page. Select text first to link it instead.")
    }
}
