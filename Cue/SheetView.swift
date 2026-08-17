import SwiftUI

/// The sheet: search on top, section header, item list (append-bottom), composer
/// at the bottom. One Liquid Glass surface; inner elements use fills, never
/// stacked glass. Searching switches the list to global results with badges.
struct SheetView: View {
    @Bindable var model: SheetModel
    @State private var draft = ""
    @FocusState private var composerFocused: Bool

    private static let outerRadius: CGFloat = 26
    private static let innerRadius: CGFloat = 14

    var body: some View {
        VStack(spacing: 12) {
            header
            sectionHeader
            itemList
            composer
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: Self.outerRadius))
        .padding(8)
        .overlay {
            if model.switcherShown {
                SectionSwitcher(model: model)
            }
        }
        .onExitCommand {
            if model.switcherShown {
                model.switcherShown = false
            } else if !model.query.isEmpty {
                model.query = ""
            } else if !model.pinned {
                model.requestClose?()
            }
        }
        .onChange(of: model.presentation) {
            composerFocused = true
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("Search everywhere", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.callout)
                if !model.query.isEmpty {
                    Button {
                        model.query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.quinary, in: .capsule)

            Button {
                withAnimation(.snappy(duration: 0.2)) { model.pinned.toggle() }
            } label: {
                Image(systemName: model.pinned ? "pin.fill" : "pin")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(model.pinned ? Color.accentColor : .secondary)
                    .frame(width: 26, height: 26)
                    .background(.quinary, in: .circle)
            }
            .buttonStyle(.borderless)
            .help(model.pinned ? "Unpin" : "Keep open")

            Menu {
                ForEach(model.sections) { section in
                    Button {
                        model.switchSection(section.id)
                    } label: {
                        if section.id == model.activeSectionID {
                            Label(section.name, systemImage: "checkmark")
                        } else {
                            Text(section.name)
                        }
                    }
                }
                Divider()
                Button("Switch Section…") { model.switcherShown = true }
                    .keyboardShortcut("k")
                Divider()
                Button("Quit Cue") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                    .background(.quinary, in: .circle)
            }
            .buttonStyle(.borderless)
            .menuIndicator(.hidden)
        }
    }

    private var sectionHeader: some View {
        HStack(spacing: 8) {
            Text(model.searching ? "Results" : (model.activeSection?.name ?? "Inbox"))
                .font(.footnote.weight(.semibold))
                .textCase(.uppercase)
                .kerning(1.2)
                .foregroundStyle(.secondary)
                .contextMenu {
                    if !model.searching, model.activeSectionID != Database.inboxID {
                        Button("Delete Section") { model.deleteSection(model.activeSectionID) }
                    }
                }
            Rectangle()
                .fill(.quaternary)
                .frame(height: 1)
        }
        .padding(.horizontal, 2)
    }

    private var itemList: some View {
        ScrollViewReader { proxy in
            List(selection: $model.selection) {
                if model.searching {
                    ForEach(model.hits) { hit in
                        ItemRow(
                            item: hit.item,
                            selected: model.selection.contains(hit.id),
                            radius: Self.innerRadius,
                            badge: hit.archived ? "\(hit.sectionName) · Archived" : hit.sectionName
                        ) {
                            withAnimation(.snappy(duration: 0.25)) { model.toggle(hit.id) }
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 3, leading: 0, bottom: 3, trailing: 0))
                    }
                } else {
                    ForEach(model.items) { item in
                        ItemRow(
                            item: item,
                            selected: model.selection.contains(item.id),
                            radius: Self.innerRadius,
                            badge: nil
                        ) {
                            withAnimation(.snappy(duration: 0.25)) { model.toggle(item.id) }
                        }
                        .id(item.id)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 3, leading: 0, bottom: 3, trailing: 0))
                    }
                    .onMove { model.move(from: $0, to: $1) }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .onDeleteCommand { model.deleteSelection() }
            .onChange(of: model.items.count) {
                if let last = model.items.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var composer: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "plus.circle")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            TextField("Add a note, or type # Section", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.callout)
                .lineLimit(1...5)
                .focused($composerFocused)
                .onSubmit {
                    withAnimation(.snappy(duration: 0.25)) {
                        model.add(draft)
                        draft = ""
                    }
                }
        }
        .padding(12)
        .background(.quinary, in: .rect(cornerRadius: Self.innerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Self.innerRadius)
                .strokeBorder(
                    composerFocused ? AnyShapeStyle(.tint.opacity(0.5)) : AnyShapeStyle(.quaternary),
                    lineWidth: 1
                )
        )
        .animation(.easeOut(duration: 0.15), value: composerFocused)
    }
}

private struct ItemRow: View {
    let item: ItemRecord
    let selected: Bool
    let radius: CGFloat
    let badge: String?
    let toggle: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Button(action: toggle) {
                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(item.done ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.borderless)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.text)
                    .font(.callout)
                    .strikethrough(item.done, color: .secondary)
                    .foregroundStyle(item.done ? .secondary : .primary)
                    .lineLimit(6)
                if let badge {
                    Text(badge)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.quinary, in: .rect(cornerRadius: radius))
        .overlay(
            RoundedRectangle(cornerRadius: radius)
                .strokeBorder(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), lineWidth: 1.5)
        )
        .opacity(item.done ? 0.55 : 1)
    }
}

/// ⌘K overlay: type to filter sections, Enter switches (creating if new),
/// click a row to switch. Esc closes (handled by the parent's onExitCommand).
private struct SectionSwitcher: View {
    @Bindable var model: SheetModel
    @State private var text = ""
    @FocusState private var focused: Bool

    private var filtered: [SectionRecord] {
        text.isEmpty
            ? model.sections
            : model.sections.filter { $0.name.localizedCaseInsensitiveContains(text) }
    }

    var body: some View {
        VStack(spacing: 8) {
            TextField("Switch or create section", text: $text)
                .textFieldStyle(.plain)
                .font(.callout)
                .focused($focused)
                .onSubmit {
                    let name = text.trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty {
                        model.createOrSwitchSection(named: name)
                    } else {
                        model.switcherShown = false
                    }
                }
                .padding(10)
                .background(.quinary, in: .rect(cornerRadius: 10))

            ForEach(filtered) { section in
                Button {
                    model.switchSection(section.id)
                } label: {
                    HStack {
                        Text(section.name)
                        Spacer()
                        if section.id == model.activeSectionID {
                            Image(systemName: "checkmark")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .contentShape(.rect(cornerRadius: 8))
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(12)
        .frame(width: 260)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
        .shadow(color: .black.opacity(0.25), radius: 24, y: 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 70)
        .onAppear { focused = true }
    }
}
