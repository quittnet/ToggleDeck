import SwiftUI

/// Pointer size and shake to locate, laid out as the rows of a settings card.
@MainActor
struct PointerControlsView: View {
  @ObservedObject var pointer: PointerController
  @ViewState<Double> private var draftScale = 1
  @ViewState<Bool> private var isDragging = false
  @ViewState<Task<Void, Never>?> private var pendingChange = nil

  private let inset = DeckStyle.cardInset

  private var canEdit: Bool { pointer.available && !pointer.isLoading && !pointer.isApplying }
  private var draftLabel: String { "\(Int((draftScale * 100).rounded()))%" }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: 10) {
        HStack {
          Text("Pointer size").font(DeckStyle.rowTitle)
          Spacer()
          if pointer.isLoading {
            Text("Reading…").font(DeckStyle.value).foregroundStyle(.secondary)
          } else if !pointer.available {
            Text("Unavailable").font(DeckStyle.value).foregroundStyle(.secondary)
          } else if pointer.isApplying {
            DeckSpinner()
          } else {
            Text(draftLabel).font(DeckStyle.value).monospacedDigit().foregroundStyle(.secondary)
              .accessibilityLabel("Pointer size: \(draftLabel)")
          }
        }
        .frame(minHeight: 18)
        // No `step:`: on macOS it draws one tick mark per step. The setter
        // rounds instead, so the committed precision stays at 5%.
        Slider(
          value: Binding(
            get: { draftScale },
            set: { value in
              let rounded = (value * 20).rounded() / 20
              draftScale = rounded
              if !isDragging { scheduleKeyboardScale(rounded) }
            }),
          in: PointerSettings.supportedScale
        ) { editing in
          isDragging = editing
          cancelPendingChange()
          if !editing { requestScale(draftScale) }
        }
        .disabled(!canEdit).accessibilityLabel("Pointer size")
        .accessibilityValue(draftLabel)
        .help("Adjust your Mac’s pointer size. Changes apply when you finish dragging.")
        PointerSizeChips(current: pointer.available ? draftScale : nil) { requestScale($0) }
          .disabled(!canEdit)
      }
      .padding(inset)

      DeckSeparator(leadingInset: inset)

      HStack {
        Text("Shake pointer to locate").font(DeckStyle.rowTitle).accessibilityHidden(true)
        Spacer(minLength: 8)
        Toggle(
          "Shake pointer to locate",
          isOn: Binding(
            get: { pointer.settings.shakeToFind },
            set: { enabled in
              cancelPendingChange()
              let scale = draftScale
              Task { @MainActor in
                await pointer.apply(PointerSettings(scale: scale, shakeToFind: enabled))
                draftScale = pointer.settings.scale
              }
            })
        )
        .settingsSwitch().disabled(!canEdit)
      }
      .padding(.horizontal, inset)
      .frame(minHeight: 40)
      .help("Quickly move your mouse or finger on the trackpad to enlarge the pointer briefly.")

      if let error = pointer.error {
        DeckSeparator(leadingInset: inset)
        DeckNotice(message: error) {
          Button("Refresh") { Task { await pointer.refresh() } }
            .disabled(pointer.isRefreshing || pointer.isApplying)
          Button("Full Disk Access…") { CursorColorMenu.openFullDiskAccess() }
          Button("Pointer Settings…") { CursorColorMenu.openPointerSettings() }
        }
        .padding(inset)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .onAppear { draftScale = pointer.settings.scale }
    .onChange(of: pointer.settings) { old, new in
      if !isDragging, !old.matches(new) {
        cancelPendingChange()
        draftScale = new.scale
      }
    }
    .onDisappear { cancelPendingChange() }
    .task { await pointer.refresh(clearError: false) }
  }

  private func requestScale(_ scale: Double) {
    guard canEdit else { return }
    cancelPendingChange()
    draftScale = scale
    Task { @MainActor in await applyScale(scale) }
  }

  private func cancelPendingChange() {
    pendingChange?.cancel()
    pendingChange = nil
  }

  private func scheduleKeyboardScale(_ scale: Double) {
    // Only slider input schedules a delay. Updating the draft after a preset or
    // a confirmed native change must not cancel or duplicate a running commit.
    guard canEdit else { return }
    cancelPendingChange()
    guard abs(scale - pointer.settings.scale) > 0.0001 else { return }
    pendingChange = Task { @MainActor in
      do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
      guard !Task.isCancelled, !isDragging else { return }
      pendingChange = nil
      await applyScale(scale)
    }
  }

  private func applyScale(_ scale: Double) async {
    await pointer.apply(PointerSettings(scale: scale, shakeToFind: pointer.settings.shakeToFind))
    draftScale = pointer.settings.scale
  }
}

/// The common pointer sizes as a row of chips, the current one filled.
struct PointerSizeChips: View {
  static let presets: [Double] = [1, 1.25, 1.5, 2, 3, 4]
  /// Nil marks none, for when the size is unknown.
  let current: Double?
  var choose: (Double) -> Void

  var body: some View {
    HStack(spacing: 6) {
      ForEach(Self.presets, id: \.self) { scale in
        let selected = current.map { abs($0 - scale) < 0.001 } ?? false
        Button("\(Int(scale * 100))%") { choose(scale) }
          .buttonStyle(ChoiceChipButtonStyle(isSelected: selected))
          .accessibilityAddTraits(selected ? .isSelected : [])
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Pointer size presets")
  }
}

private struct ChoiceChipButtonStyle: ButtonStyle {
  let isSelected: Bool
  @ViewState<Bool> private var hovered = false
  @Environment(\.isEnabled) private var enabled

  func makeBody(configuration: Configuration) -> some View {
    let shape = Capsule()
    // The resting fill is already as strong as a row's hover, so hover and
    // press step up from it.
    let fill: Color =
      if isSelected {
        .accentColor
      } else if enabled && configuration.isPressed {
        Color.primary.opacity(0.18)
      } else if enabled && hovered {
        DeckStyle.pressedFill
      } else {
        DeckStyle.quietFill
      }
    configuration.label
      .font(DeckStyle.value.weight(isSelected ? .semibold : .regular)).monospacedDigit()
      .foregroundStyle(isSelected ? Color.white : Color.primary)
      .lineLimit(1)
      .frame(maxWidth: .infinity, minHeight: 24)
      .background(fill, in: shape)
      .contentShape(shape)
      .opacity(enabled ? 1 : 0.5)
      .onHover { hovered = $0 }
  }
}
