import AppKit
import SwiftUI

struct RetryModelOption: Identifiable {
    let id: String
    let title: String
    let providerID: String
    let model: String
}

struct SearchableModelSelector: View {
    let options: [RetryModelOption]
    @Binding var selectedID: String
    let disabled: Bool

    @State private var isOpen = false
    @State private var searchText = ""
    @FocusState private var isFocused: Bool

    private var selectedTitle: String {
        options.first(where: { $0.id == selectedID })?.title ?? "Select model"
    }

    var body: some View {
        if isOpen {
            TextField("Search model...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .font(.system(size: NSFont.smallSystemFontSize))
                .focused($isFocused)
                .onExitCommand { closeDropdown() }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        isFocused = true
                    }
                }
                .background(
                    DropdownAnchor(
                        isOpen: $isOpen,
                        searchText: $searchText,
                        selectedID: $selectedID,
                        options: options,
                        onClose: { closeDropdown() }
                    )
                )
        } else {
            Button {
                guard !disabled else { return }
                isOpen = true
                searchText = ""
            } label: {
                HStack(spacing: 5) {
                    Text(selectedTitle)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(PopoverPalette.muted)
                }
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(PopoverPalette.control)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(PopoverPalette.controlStroke, lineWidth: 1)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(disabled)
        }
    }

    private func closeDropdown() {
        isOpen = false
        searchText = ""
        isFocused = false
    }
}

/// Invisible NSView that anchors a floating NSPanel dropdown below the text field.
private struct DropdownAnchor: NSViewRepresentable {
    @Binding var isOpen: Bool
    @Binding var searchText: String
    @Binding var selectedID: String
    let options: [RetryModelOption]
    let onClose: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.anchorView = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.applyState(
            options: options,
            searchText: searchText
        )

        if isOpen {
            context.coordinator.showPanel()
        } else {
            context.coordinator.hidePanel()
        }
    }

    func makeCoordinator() -> DropdownCoordinator {
        DropdownCoordinator(
            isOpen: $isOpen,
            selectedID: $selectedID,
            options: options,
            searchText: searchText,
            onClose: onClose
        )
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: DropdownCoordinator) {
        coordinator.hidePanel()
    }

    @MainActor class DropdownCoordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        weak var anchorView: NSView?
        var options: [RetryModelOption]
        var searchText: String
        @Binding var isOpen: Bool
        @Binding var selectedID: String
        let onClose: () -> Void

        private var panel: NSPanel?
        private var tableView: NSTableView?
        private var clickMonitor: Any?
        private var keyMonitor: Any?
        private var filteredOptions: [RetryModelOption] = []
        private var optionIDSignature: [String]

        init(
            isOpen: Binding<Bool>,
            selectedID: Binding<String>,
            options: [RetryModelOption],
            searchText: String,
            onClose: @escaping () -> Void
        ) {
            self._isOpen = isOpen
            self._selectedID = selectedID
            self.options = options
            self.searchText = searchText
            self.optionIDSignature = options.map(\.id)
            self.onClose = onClose
            super.init()
        }

        func applyState(options: [RetryModelOption], searchText: String) {
            let nextSignature = options.map(\.id)
            let optionsChanged = nextSignature != optionIDSignature
            let searchChanged = self.searchText != searchText

            self.options = options
            self.searchText = searchText
            self.optionIDSignature = nextSignature

            guard panel != nil, optionsChanged || searchChanged else { return }

            updateFilter()
            reloadTablePreservingSelection()
            repositionPanel()
        }

        func showPanel() {
            updateFilter()

            if let panel = panel {
                repositionPanel()
                panel.orderFront(nil)
                return
            }

            guard let anchor = anchorView, let window = anchor.window else { return }

            let table = NSTableView()
            table.headerView = nil
            table.style = .plain
            table.rowHeight = 24
            table.intercellSpacing = NSSize(width: 0, height: 0)
            table.selectionHighlightStyle = .regular
            table.dataSource = self
            table.delegate = self
            table.target = self
            table.action = #selector(rowClicked)

            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("model"))
            column.isEditable = false
            table.addTableColumn(column)

            let scroll = NSScrollView()
            scroll.documentView = table
            scroll.hasVerticalScroller = true
            scroll.autohidesScrollers = true
            scroll.drawsBackground = false

            let dropdownPanel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 280, height: 200),
                styleMask: [.nonactivatingPanel],
                backing: .buffered,
                defer: true
            )
            dropdownPanel.isFloatingPanel = true
            dropdownPanel.level = .popUpMenu
            dropdownPanel.hasShadow = true
            dropdownPanel.isOpaque = false
            dropdownPanel.backgroundColor = NSColor.controlBackgroundColor

            let container = NSVisualEffectView()
            container.material = .menu
            container.state = .active
            container.maskImage = roundedMask(size: NSSize(width: 280, height: 200), radius: 6)
            container.addSubview(scroll)
            scroll.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                scroll.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
                scroll.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4),
                scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            ])

            dropdownPanel.contentView = container
            self.panel = dropdownPanel
            self.tableView = table

            reloadTablePreservingSelection()
            repositionPanel()
            window.addChildWindow(dropdownPanel, ordered: .above)

            installClickMonitor()
            installKeyMonitor()
        }

        func hidePanel() {
            if let monitor = clickMonitor {
                NSEvent.removeMonitor(monitor)
                clickMonitor = nil
            }
            if let monitor = keyMonitor {
                NSEvent.removeMonitor(monitor)
                keyMonitor = nil
            }
            if let panel = panel {
                panel.parent?.removeChildWindow(panel)
                panel.orderOut(nil)
            }
            panel = nil
            tableView = nil
        }

        // MARK: Event Monitors

        private func installClickMonitor() {
            clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                guard let self = self, self.isOpen else { return event }
                if event.window === self.panel {
                    return event
                }
                if let hitView = event.window?.contentView?.hitTest(
                    event.window?.contentView?.convert(event.locationInWindow, from: nil) ?? .zero
                ), self.isViewInsideTextField(hitView) {
                    return event
                }
                DispatchQueue.main.async { self.onClose() }
                return event
            }
        }

        private func isViewInsideTextField(_ view: NSView) -> Bool {
            var current: NSView? = view
            while let v = current {
                if v is NSTextField { return true }
                current = v.superview
            }
            return false
        }

        private func installKeyMonitor() {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self = self, self.isOpen, let table = self.tableView else { return event }
                guard !self.filteredOptions.isEmpty else { return event }

                switch event.keyCode {
                case 125: // arrow down
                    let next = table.selectedRow + 1
                    if next < self.filteredOptions.count {
                        table.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
                        table.scrollRowToVisible(next)
                    }
                    return nil
                case 126: // arrow up
                    let prev = table.selectedRow - 1
                    if prev >= 0 {
                        table.selectRowIndexes(IndexSet(integer: prev), byExtendingSelection: false)
                        table.scrollRowToVisible(prev)
                    }
                    return nil
                case 36: // return/enter
                    let row = table.selectedRow
                    if row >= 0, row < self.filteredOptions.count {
                        self.selectedID = self.filteredOptions[row].id
                    } else if let first = self.filteredOptions.first {
                        self.selectedID = first.id
                    }
                    DispatchQueue.main.async { self.onClose() }
                    return nil
                default:
                    return event
                }
            }
        }

        // MARK: Filtering & Layout

        private func updateFilter() {
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if query.isEmpty {
                filteredOptions = options
            } else {
                filteredOptions = options.filter { $0.title.lowercased().contains(query) }
            }
        }

        private func repositionPanel() {
            guard let anchor = anchorView, let window = anchor.window, let panel = panel else { return }
            let anchorFrame = anchor.convert(anchor.bounds, to: nil)
            let screenFrame = window.convertToScreen(anchorFrame)
            let panelWidth: CGFloat = max(anchorFrame.width, 280)
            let rowCount = min(filteredOptions.count, 10)
            let panelHeight = CGFloat(max(rowCount, 1)) * 24 + 8
            let origin = NSPoint(
                x: screenFrame.maxX - panelWidth,
                y: screenFrame.minY - panelHeight - 2
            )
            panel.setFrame(NSRect(origin: origin, size: NSSize(width: panelWidth, height: panelHeight)), display: true)
        }

        private func roundedMask(size: NSSize, radius: CGFloat) -> NSImage {
            let image = NSImage(size: size)
            image.lockFocus()
            let path = NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: radius, yRadius: radius)
            NSColor.black.setFill()
            path.fill()
            image.unlockFocus()
            return image
        }

        private func reloadTablePreservingSelection() {
            guard let table = tableView else { return }

            let selectedIDBeforeReload: String? = {
                let row = table.selectedRow
                guard row >= 0, row < filteredOptions.count else { return selectedID }
                return filteredOptions[row].id
            }()

            table.reloadData()

            guard !filteredOptions.isEmpty else { return }

            if let selectedIDBeforeReload,
               let selectedIndex = filteredOptions.firstIndex(where: { $0.id == selectedIDBeforeReload }) {
                table.selectRowIndexes(IndexSet(integer: selectedIndex), byExtendingSelection: false)
                table.scrollRowToVisible(selectedIndex)
            }
        }

        // MARK: NSTableViewDataSource

        func numberOfRows(in tableView: NSTableView) -> Int {
            return max(filteredOptions.count, 1)
        }

        // MARK: NSTableViewDelegate

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard !filteredOptions.isEmpty else {
                let cell = NSTextField(labelWithString: "No matching models")
                cell.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
                cell.textColor = .secondaryLabelColor
                cell.lineBreakMode = .byTruncatingTail
                return cell
            }
            let option = filteredOptions[row]
            let cell = NSTextField(labelWithString: option.title)
            cell.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
            cell.textColor = .labelColor
            cell.lineBreakMode = .byTruncatingTail
            return cell
        }

        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
            !filteredOptions.isEmpty
        }

        @objc private func rowClicked() {
            guard let table = tableView else { return }
            let row = table.clickedRow
            guard row >= 0, row < filteredOptions.count else { return }
            selectedID = filteredOptions[row].id
            onClose()
        }
    }
}
