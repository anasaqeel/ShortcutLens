import SwiftUI

/// The centered shortcut sheet. Colors are all system semantic colors
/// (`.primary`, `.secondary`, the `.regularMaterial` background) so the
/// sheet automatically matches whichever appearance — light or dark — the
/// user currently has selected in System Settings, with no manual theme
/// switching logic required.
///
/// Columns come pre-computed from ``CheatSheetLayout`` rather than being
/// flowed by a `LazyVGrid`, because the window is sized to the layout: the
/// two have to agree on the arrangement for everything to fit on screen
/// without scrolling.
struct CheatSheetView: View {
    let appName: String
    let appIcon: NSImage?
    let plan: CheatSheetLayout.Plan?
    let state: State

    enum State {
        case loading
        case loaded
        /// macOS hasn't granted Accessibility access, so the menu bar can't
        /// be read at all. Worth calling out explicitly — otherwise this is
        /// indistinguishable from an app that genuinely has no shortcuts.
        case needsPermission
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CheatSheetLayout.Chrome.headerBottomSpacing) {
            header

            switch state {
            case .loading:
                centeredMessage {
                    ProgressView("Reading \(appName)'s shortcuts\u{2026}")
                }
            case .needsPermission:
                centeredMessage {
                    VStack(spacing: 10) {
                        Text("Accessibility access is needed")
                            .font(.title3.weight(.semibold))
                        Text("Enable CheatSheet in System Settings \u{203A} Privacy & Security \u{203A} Accessibility, then relaunch it.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 420)
                    }
                }
            case .loaded:
                if let plan, !plan.columns.isEmpty {
                    if plan.needsScrolling {
                        ScrollView { columnsView(plan) }
                    } else {
                        columnsView(plan)
                    }
                } else {
                    centeredMessage {
                        Text("No shortcuts found for \(appName).")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(CheatSheetLayout.Chrome.outerPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.separator, lineWidth: 0.5)
        )
    }

    private func columnsView(_ plan: CheatSheetLayout.Plan) -> some View {
        HStack(alignment: .top, spacing: CheatSheetLayout.Chrome.columnSpacing) {
            ForEach(Array(plan.columns.enumerated()), id: \.offset) { _, column in
                VStack(alignment: .leading, spacing: CheatSheetLayout.Chrome.cardSpacing) {
                    ForEach(column) { group in
                        GroupCard(group: group, density: plan.density)
                    }
                    Spacer(minLength: 0)
                }
                .frame(width: plan.columnWidth, alignment: .top)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func centeredMessage<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack {
            Spacer()
            content()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var header: some View {
        HStack(spacing: 12) {
            if let appIcon {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 30, height: 30)
            }
            Text(appName)
                .font(.title2.bold())
            Spacer()
            Text("Release \u{2318} to dismiss")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .frame(height: CheatSheetLayout.Chrome.headerHeight)
    }
}

private struct GroupCard: View {
    let group: ShortcutGroup
    let density: CheatSheetLayout.Density

    /// Builds the key combination as a single `Text`, interpolating SF
    /// Symbols for keys with no drawable character (Globe, mic). Because
    /// they're interpolated rather than laid out separately, they inherit
    /// the row's font size and weight automatically.
    static func keysText(_ keys: KeyCombination) -> Text {
        keys.elements.reduce(Text(verbatim: "")) { partial, element in
            switch element {
            case .text(let text):
                return partial + Text(verbatim: text)
            case .symbol(let name):
                return partial + Text(Image(systemName: name))
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Bold and full-strength, with a rule beneath it: when several
            // menus are stacked in one column, the heading is what tells you
            // where File ends and Edit begins.
            VStack(alignment: .leading, spacing: 3) {
                Text(group.menuPath)
                    .font(density.usesSmallText ? .headline : .title3.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Divider()
            }
            .frame(height: density.groupHeaderHeight, alignment: .top)

            // Shortcut first, in a fixed-width trailing-aligned column: the
            // keys line up as a scannable rail, and the wasted gap that a
            // title-then-Spacer-then-keys row creates disappears, which
            // leaves room for longer titles at the same column width.
            ForEach(group.entries) { entry in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Self.keysText(entry.keys)
                        .font(
                            .system(
                                density.usesSmallText ? .callout : .body,
                                design: .rounded
                            ).weight(.semibold)
                        )
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .frame(width: density.keysColumnWidth, alignment: .trailing)
                    Text(entry.title)
                        .font(density.usesSmallText ? .callout : .body)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, density.rowVerticalPadding)
                .frame(height: density.rowHeight)
            }
        }
        .padding(.horizontal, density.cardHorizontalPadding)
        .padding(.vertical, density.cardVerticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
