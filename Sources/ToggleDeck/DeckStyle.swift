import AppKit
import SwiftUI

/// The shared visual language of the dropdown and the settings window.
///
/// Views take geometry, type and fills from here instead of repeating
/// literals, so the two surfaces read as one system.
enum DeckStyle {
  // MARK: Geometry

  static let cardRadius: CGFloat = 10
  static let rowRadius: CGFloat = 7
  static let tileSize: CGFloat = 26
  static let smallTileSize: CGFloat = 20
  /// Card edge to row content.
  static let rowInset: CGFloat = 10
  /// Icon tile to title.
  static let rowSpacing: CGFloat = 10
  /// Dropdown edge to its cards.
  static let panelInset: CGFloat = 12
  static let columnSpacing: CGFloat = 12
  static let switchSize = CGSize(width: 34, height: 20)
  /// Card edge to content in rows without an icon tile.
  static let cardInset: CGFloat = 12
  static let searchFieldHeight: CGFloat = 32

  static let paneInset: CGFloat = 24
  static let paneSpacing: CGFloat = 22
  static let paneMaxWidth: CGFloat = 720

  // MARK: Type

  static let rowTitle = Font.system(size: 13)
  static let rowSubtitle = Font.system(size: 11)
  static let value = Font.system(size: 12)
  static let caption = Font.system(size: 11)
  static let sectionLabel = Font.system(size: 11, weight: .semibold)
  static let cardTitle = Font.system(size: 13, weight: .semibold)
  static let paneTitle = Font.system(size: 22, weight: .bold)
  static let paneSubtitle = Font.system(size: 12.5)

  // MARK: Fills

  // Strengths of black or white ink, so one value works on the popover
  // material, on a window background, and in both appearances.
  static let cardFill = ink(0.038, increased: 0.05)
  static let cardStroke = ink(0.06, increased: 0.4)
  static let hoverFill = ink(0.06, increased: 0.1)
  static let pressedFill = ink(0.1, increased: 0.16)
  static let quietFill = ink(0.068, increased: 0.12)
  static let separator = ink(0.077, increased: 0.35)
  static let switchOff = ink(0.17, increased: 0.45)
  static let warning = Color.orange
  /// Opaque stand-in for the popover material where none exists, such as an
  /// offscreen snapshot.
  static let panelFallback = Color(nsColor: .windowBackgroundColor)

  /// Ink at `opacity`, or at `increased` under Increase Contrast, where a
  /// faint edge is exactly what the user has asked not to get.
  private static func ink(_ opacity: Double, increased: Double) -> Color {
    Color(
      nsColor: NSColor(name: nil) { appearance in
        let match = appearance.bestMatch(from: [
          .aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua,
        ])
        let dark = match == .darkAqua || match == .accessibilityHighContrastDarkAqua
        let highContrast =
          match == .accessibilityHighContrastAqua || match == .accessibilityHighContrastDarkAqua
        return (dark ? NSColor.white : NSColor.black)
          .withAlphaComponent(highContrast ? increased : opacity)
      })
  }

  static var card: RoundedRectangle {
    RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
  }

  static var row: RoundedRectangle {
    RoundedRectangle(cornerRadius: rowRadius, style: .continuous)
  }

  static var searchField: RoundedRectangle {
    RoundedRectangle(cornerRadius: 8, style: .continuous)
  }
}

extension Category {
  /// One hue per category, shown on a control's tile and switch while it is
  /// on. Each is dark enough to carry a white glyph at 3:1 or better in both
  /// appearances, which the stock green, teal and orange are not.
  var tint: Color {
    switch self {
    case .display: return .indigo
    case .connections: return .blue
    case .power: return Color(red: 0.14, green: 0.63, blue: 0.28)
    case .desktop: return .purple
    case .finder: return Color(red: 0, green: 0.59, blue: 0.67)
    case .input: return Color(red: 0.88, green: 0.42, blue: 0)
    case .screenshots: return .pink
    }
  }
}

// MARK: - Building blocks

/// A rounded tile holding one SF Symbol: tinted with a white glyph when lit,
/// quiet when not.
struct IconTile: View {
  let symbol: String
  var tint: Color = .accentColor
  var isLit = true
  var isDimmed = false
  var size: CGFloat = DeckStyle.tileSize

  var body: some View {
    RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
      .fill(isLit ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(DeckStyle.quietFill))
      .frame(width: size, height: size)
      .overlay {
        // Resizable, so a wide symbol shrinks to the same box as a narrow one.
        Image(systemName: symbol)
          .resizable().aspectRatio(contentMode: .fit)
          .fontWeight(.semibold)
          .foregroundStyle(isLit ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.secondary))
          .opacity(isDimmed ? 0.5 : 1)
          .frame(width: size * 0.56, height: size * 0.56)
      }
      .accessibilityHidden(true)
  }
}

/// A switch drawn in SwiftUI. It shows state only; the row around it is the
/// control, so it is hidden from accessibility.
struct DeckSwitch: View {
  let isOn: Bool
  var tint: Color = .accentColor

  var body: some View {
    Capsule()
      .fill(isOn ? AnyShapeStyle(tint) : AnyShapeStyle(DeckStyle.switchOff))
      .frame(width: DeckStyle.switchSize.width, height: DeckStyle.switchSize.height)
      .overlay(alignment: isOn ? .trailing : .leading) {
        Circle().fill(.white)
          .shadow(color: .black.opacity(0.2), radius: 1, y: 0.5)
          .padding(2)
      }
      .accessibilityHidden(true)
  }
}

/// A progress indicator that also draws in `ImageRenderer` snapshots, where
/// the AppKit-backed `ProgressView` renders nothing.
struct DeckSpinner: View {
  var snapshot = false

  var body: some View {
    if snapshot {
      Circle().trim(from: 0.1, to: 0.85).stroke(Color.secondary, lineWidth: 1.5)
        .frame(width: 14, height: 14).accessibilityHidden(true)
    } else {
      ProgressView().controlSize(.small)
    }
  }
}

/// The hairline between two rows of a card, inset to the title's leading edge.
struct DeckSeparator: View {
  var leadingInset: CGFloat = DeckStyle.rowInset + DeckStyle.tileSize + DeckStyle.rowSpacing

  var body: some View {
    Rectangle().fill(DeckStyle.separator).frame(height: 1)
      .padding(.leading, leadingInset).accessibilityHidden(true)
  }
}

struct DeckSectionLabel: View {
  let title: String

  var body: some View {
    Text(title).font(DeckStyle.sectionLabel).foregroundStyle(.secondary)
      .accessibilityAddTraits(.isHeader)
  }
}

extension View {
  /// The grouped container behind a set of rows.
  func deckCard() -> some View {
    background(DeckStyle.cardFill, in: DeckStyle.card)
      .overlay { DeckStyle.card.strokeBorder(DeckStyle.cardStroke, lineWidth: 1) }
  }

  /// The frame of an inline search field. The caller supplies the icon, the
  /// text field and any buttons, with its own horizontal padding.
  func deckSearchField(isFocused: Bool) -> some View {
    frame(height: DeckStyle.searchFieldHeight)
      .background(DeckStyle.cardFill, in: DeckStyle.searchField)
      .overlay {
        DeckStyle.searchField.strokeBorder(
          isFocused ? Color.accentColor.opacity(0.8) : DeckStyle.cardStroke, lineWidth: 1)
      }
  }
}

/// A plain full-width action inside a popover or card, laid out like a menu
/// item: leading text, highlight on hover.
struct DeckActionButtonStyle: ButtonStyle {
  static let textInset: CGFloat = 8
  var minHeight: CGFloat = 26
  /// Gap between the highlight and the container edge, for rows in a card.
  var highlightInset: CGFloat = 0
  @ViewState<Bool> private var hovered = false
  @Environment(\.isEnabled) private var enabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(DeckStyle.rowTitle)
      .foregroundStyle(enabled ? HierarchicalShapeStyle.primary : .tertiary)
      .lineLimit(1)
      .padding(.horizontal, Self.textInset + highlightInset)
      .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
      .contentShape(Rectangle())
      .background {
        DeckStyle.row
          .fill(
            enabled && configuration.isPressed
              ? DeckStyle.pressedFill : (enabled && hovered ? DeckStyle.hoverFill : .clear)
          )
          .padding(.horizontal, highlightInset).padding(.vertical, highlightInset > 0 ? 1 : 0)
      }
      .onHover { hovered = $0 }
  }
}

/// A problem plus the actions that can resolve it.
struct DeckNotice<Actions: View>: View {
  let message: String
  @ViewBuilder var actions: () -> Actions

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Image(systemName: "exclamationmark.triangle.fill")
        .font(DeckStyle.value).foregroundStyle(DeckStyle.warning).accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 8) {
        Text(message).font(DeckStyle.value).fixedSize(horizontal: false, vertical: true)
        HStack(spacing: 8) { actions() }.controlSize(.small)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

// MARK: - Dropdown rows

/// Hover, press and keyboard-focus treatment shared by every dropdown row.
/// The highlight is inset so it sits inside the card that holds the row.
struct DeckRowButtonStyle: ButtonStyle {
  var isFocused = false
  /// False while a click would do nothing, such as mid-write.
  var highlights = true
  @ViewState<Bool> private var hovered = false
  @Environment(\.isEnabled) private var enabled

  func makeBody(configuration: Configuration) -> some View {
    let active = enabled && highlights
    configuration.label
      .background {
        DeckStyle.row
          .fill(
            active && configuration.isPressed
              ? DeckStyle.pressedFill : (active && hovered ? DeckStyle.hoverFill : .clear)
          )
          .padding(.horizontal, 3).padding(.vertical, 1)
      }
      .overlay {
        DeckStyle.row.strokeBorder(isFocused ? Color.accentColor : .clear, lineWidth: 2)
          .padding(.horizontal, 3).padding(.vertical, 1)
      }
      .onHover { hovered = $0 }
  }
}

/// The label of a dropdown row that opens a picker instead of flipping a
/// switch: leading tile, title, current value, disclosure chevron.
struct DeckValueRowLabel<Leading: View>: View {
  let title: String
  var subtitle: String? = nil
  let value: String
  var isBusy = false
  var snapshot = false
  @ViewBuilder var leading: () -> Leading

  var body: some View {
    HStack(spacing: DeckStyle.rowSpacing) {
      leading().frame(width: DeckStyle.tileSize, height: DeckStyle.tileSize)
      VStack(alignment: .leading, spacing: 1) {
        Text(title).font(DeckStyle.rowTitle).lineLimit(1)
        if let subtitle {
          Text(subtitle).font(DeckStyle.rowSubtitle).foregroundStyle(.secondary).lineLimit(1)
        }
      }
      Spacer(minLength: 6)
      if isBusy { DeckSpinner(snapshot: snapshot) }
      Text(value).font(DeckStyle.value).foregroundStyle(.secondary).lineLimit(1)
      Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
        .foregroundStyle(.tertiary).accessibilityHidden(true)
    }
    .padding(.horizontal, DeckStyle.rowInset)
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(Rectangle())
  }
}

// MARK: - Settings panes

/// Scrolling layout of a settings pane: header, then sections, held to a
/// readable width.
struct PaneScaffold<Content: View>: View {
  @ViewBuilder var content: () -> Content

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: DeckStyle.paneSpacing) { content() }
        .paneColumn()
        .padding(.vertical, DeckStyle.paneInset)
    }
  }
}

/// Title block at the top of every settings pane.
struct PaneHeader<Accessory: View>: View {
  let title: String
  var subtitle: String? = nil
  @ViewBuilder var accessory: () -> Accessory

  var body: some View {
    HStack(alignment: .top, spacing: 16) {
      VStack(alignment: .leading, spacing: 3) {
        Text(title).font(DeckStyle.paneTitle).accessibilityAddTraits(.isHeader)
        if let subtitle {
          Text(subtitle).font(DeckStyle.paneSubtitle).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      Spacer(minLength: 0)
      accessory()
    }
  }
}

extension PaneHeader where Accessory == EmptyView {
  init(title: String, subtitle: String? = nil) {
    self.init(title: title, subtitle: subtitle) { EmptyView() }
  }
}

/// A titled card in a settings pane. Rows supply their own padding.
struct PaneSection<Content: View>: View {
  var title: String? = nil
  var footer: String? = nil
  @ViewBuilder var content: () -> Content

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if let title {
        Text(title).font(DeckStyle.cardTitle).padding(.leading, 2)
          .accessibilityAddTraits(.isHeader)
      }
      VStack(alignment: .leading, spacing: 0) { content() }
        .frame(maxWidth: .infinity, alignment: .leading)
        .deckCard()
      if let footer {
        Text(footer).font(DeckStyle.caption).foregroundStyle(.secondary).padding(.leading, 2)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }
}

/// A row of a settings card with no icon tile: label and optional caption,
/// control trailing. The control carries the accessible name, so the visible
/// title is hidden from VoiceOver rather than read twice.
struct SettingsRow<Trailing: View>: View {
  let title: String
  var caption: String? = nil
  @ViewBuilder var trailing: () -> Trailing

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        Text(title).font(DeckStyle.rowTitle).accessibilityHidden(true)
        if let caption {
          Text(caption).font(DeckStyle.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      Spacer(minLength: 12)
      trailing()
    }
    .settingsRowPadding()
  }
}

/// The hairline between rows that have no icon tile.
struct SettingsSeparator: View {
  var body: some View { DeckSeparator(leadingInset: DeckStyle.cardInset) }
}

extension View {
  /// Holds pane content that is not inside a `PaneScaffold` to the same
  /// column, so headers and card edges line up across every pane.
  func paneColumn() -> some View {
    frame(maxWidth: DeckStyle.paneMaxWidth, alignment: .leading)
      .padding(.horizontal, DeckStyle.paneInset)
      .frame(maxWidth: .infinity)
  }

  func settingsRowPadding() -> some View {
    padding(.horizontal, DeckStyle.cardInset).padding(.vertical, 9)
      .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
  }

  /// The switch used by every settings row, the same size as a control row's.
  func settingsSwitch() -> some View {
    labelsHidden().toggleStyle(.switch).controlSize(.small)
  }
}
