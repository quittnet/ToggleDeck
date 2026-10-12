import SwiftUI

/// One switch, shared by the dropdown and the settings window.
@MainActor
struct ToggleRow: View {
  let spec: ToggleSpec
  @ObservedObject var engine: ToggleEngine
  @ObservedObject var settings: AppSettings

  var showPin = false
  var showDetail = true
  var showCategory = false
  var showMove = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var st: ToggleState { engine.state(spec.id) }

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack(alignment: .center, spacing: 10) {
        Image(systemName: spec.menuSymbol)
          .font(.system(size: 17, weight: .medium))
          .foregroundStyle(
            st.isOn && st.supported && !st.stale ? Color.accentColor : Color.secondary
          )
          .frame(width: 26).accessibilityHidden(true)
        if showPin {
          Button {
            settings.togglePin(spec.id)
          } label: {
            Image(systemName: settings.isPinned(spec.id) ? "pin.fill" : "pin")
              .font(.system(size: 12))
              .frame(width: 28, height: 30)
              .foregroundStyle(settings.isPinned(spec.id) ? Color.accentColor : Color.secondary)
          }
          .buttonStyle(.plain)
          .accessibilityLabel(
            settings.isPinned(spec.id) ? "Unpin \(spec.title)" : "Pin \(spec.title)"
          )
          .help(
            settings.isPinned(spec.id)
              ? "Remove from the menu bar dropdown" : "Add to the menu bar dropdown")
        }

        VStack(alignment: .leading, spacing: 1) {
          HStack(spacing: 5) {
            Text(spec.menuTitle)
              .font(.system(size: 13, weight: .medium))
              .foregroundStyle(st.supported ? .primary : .secondary)
              .lineLimit(1)

            if !st.supported {
              Text("unavailable")
                .font(.system(size: 9.5))
                .padding(.horizontal, 4).padding(.vertical, 1)
                .background(Color.secondary.opacity(0.15), in: Capsule())
                .foregroundStyle(.secondary)
            }

            ForEach(spec.requires.badges, id: \.0) { badge in
              Image(systemName: badge.1)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .help(badge.0)
            }
          }

          if showCategory {
            Text(spec.category.rawValue)
              .font(.system(size: 10))
              .foregroundStyle(.tertiary)
          }
          if showDetail, !spec.detail.isEmpty {
            Text(spec.detail)
              .font(.system(size: 10.5))
              .foregroundStyle(.secondary)
              .lineLimit(2)
              .fixedSize(horizontal: false, vertical: true)
          }
        }

        Spacer(minLength: 6)

        if showMove {
          HStack(spacing: 2) {
            Button {
              settings.movePin(spec.id, by: -1)
            } label: {
              Image(systemName: "chevron.up")
            }
            .disabled(settings.pinned.first == spec.id).accessibilityLabel(
              "Move \(spec.menuTitle) up")
            Button {
              settings.movePin(spec.id, by: 1)
            } label: {
              Image(systemName: "chevron.down")
            }
            .disabled(settings.pinned.last == spec.id).accessibilityLabel(
              "Move \(spec.menuTitle) down")
          }.buttonStyle(DeckButtonStyle()).font(.system(size: 10)).frame(width: 42)
        }

        if st.busy || st.stale {
          ProgressView()
            .controlSize(.small)
            .scaleEffect(0.7)
            .frame(width: 26)
        } else {
          Toggle(
            spec.title,
            isOn: Binding(
              get: { st.isOn },
              set: { newValue in
                Task { await engine.set(spec.id, on: newValue) }
              }
            )
          )
          .labelsHidden()
          .toggleStyle(.switch)
          .controlSize(.small)
          .disabled(!st.supported || st.stale)
          .accessibilityHint(spec.detail)
        }
      }

      if let error = st.error {
        Text(error)
          .font(.system(size: 10))
          .foregroundStyle(.orange)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(.vertical, showDetail ? 10 : 6)
    .contentShape(Rectangle())
    .opacity(st.stale ? 0.55 : 1)
    .accessibilityElement(children: .contain)
    .contextMenu { ControlContextMenu(spec: spec, engine: engine, settings: settings) }
    .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: st.isOn)
  }
}
