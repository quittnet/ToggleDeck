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

  private var st: ToggleState { engine.state(spec.id) }

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack(alignment: .center, spacing: 8) {
        if showPin {
          Button {
            settings.togglePin(spec.id)
          } label: {
            Image(systemName: settings.isPinned(spec.id) ? "pin.fill" : "pin")
              .font(.system(size: 11))
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
            Text(spec.title)
              .font(.system(size: 12.5))
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
          } else if showDetail, !spec.detail.isEmpty {
            Text(spec.detail)
              .font(.system(size: 10.5))
              .foregroundStyle(.secondary)
              .lineLimit(2)
              .fixedSize(horizontal: false, vertical: true)
          }
        }

        Spacer(minLength: 6)

        if st.busy {
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
    .padding(.vertical, 4)
    .contentShape(Rectangle())
    .opacity(st.stale ? 0.55 : 1)
    .animation(.easeOut(duration: 0.12), value: st.isOn)
  }
}
