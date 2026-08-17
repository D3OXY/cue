import SwiftUI

/// The sheet: search on top, section header, item list (append-bottom), composer
/// at the bottom. Liquid Glass surface.
struct SheetView: View {
    @Bindable var model: SheetModel
    @State private var draft = ""
    @FocusState private var composerFocused: Bool

    var body: some View {
        VStack(spacing: 12) {
            header
            sectionHeader
            itemList
            composer
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .padding(8)
        .onExitCommand {
            if !model.query.isEmpty {
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
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search", text: $model.query)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.quinary, in: .capsule)

            Button {
                model.pinned.toggle()
            } label: {
                Image(systemName: model.pinned ? "pin.fill" : "pin")
            }
            .buttonStyle(.borderless)
            .help(model.pinned ? "Unpin" : "Keep open")

            Menu {
                // Sections land here in ticket 9; Settings in ticket 17.
                Button("Quit Cue") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis")
            }
            .buttonStyle(.borderless)
            .menuIndicator(.hidden)
        }
    }

    private var sectionHeader: some View {
        HStack {
            Text("INBOX")
                .font(.caption.weight(.semibold))
                .kerning(1)
                .foregroundStyle(.secondary)
            Rectangle()
                .fill(.quaternary)
                .frame(height: 1)
        }
    }

    private var itemList: some View {
        ScrollViewReader { proxy in
            List(selection: $model.selection) {
                ForEach(model.visibleItems) { item in
                    ItemRow(item: item, selected: model.selection.contains(item.id)) {
                        model.toggle(item.id)
                    }
                    .id(item.id)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    // Reorder while filtered would scramble indexes; only offer it unfiltered.
                    .moveDisabled(!model.query.isEmpty)
                }
                .onMove { model.move(from: $0, to: $1) }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .onDeleteCommand { model.deleteSelection() }
            .onChange(of: model.items.count) {
                if let last = model.visibleItems.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var composer: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "plus.circle")
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            TextField("Add a note, type a prompt, or describe a task", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .focused($composerFocused)
                .onSubmit {
                    model.add(draft)
                    draft = ""
                }
        }
        .padding(12)
        .background(.quinary, in: .rect(cornerRadius: 14))
    }
}

private struct ItemRow: View {
    let item: SheetModel.Item
    let selected: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: toggle) {
                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.done ? .secondary : .primary)
            }
            .buttonStyle(.borderless)
            Text(item.text)
                .strikethrough(item.done)
                .foregroundStyle(item.done ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.quinary, in: .rect(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(.tint, lineWidth: selected ? 1.5 : 0)
        )
        .opacity(item.done ? 0.6 : 1)
    }
}
