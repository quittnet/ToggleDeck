import CoreAudio
import Foundation

struct AudioOutput: Identifiable, Equatable, Sendable {
  let uid: String
  let name: String
  let deviceID: UInt32
  var id: String { uid }
}

struct AudioSnapshot: Equatable, Sendable {
  var outputs: [AudioOutput]
  var selectedUID: String?
  var volume: Double?
  var canSetVolume: Bool
  var isMuted: Bool?
  var canSelectOutput: Bool

  static let empty = AudioSnapshot(
    outputs: [], selectedUID: nil, volume: nil, canSetVolume: false, isMuted: nil,
    canSelectOutput: false)
  static let sample = AudioSnapshot(
    outputs: [
      AudioOutput(uid: "preview-speakers", name: "Mac Speakers", deviceID: 1),
      AudioOutput(uid: "preview-headphones", name: "Headphones", deviceID: 2),
    ], selectedUID: "preview-speakers", volume: 0.55, canSetVolume: true, isMuted: false,
    canSelectOutput: true)

  var selected: AudioOutput? { outputs.first { $0.uid == selectedUID } }
  var isValid: Bool {
    let unique = Set(outputs.map(\.uid)).count == outputs.count
    let validVolume = volume.map { $0.isFinite && (0...1).contains($0) } ?? true
    return unique && outputs.allSatisfy { !$0.uid.isEmpty && !$0.name.isEmpty }
      && (selectedUID == nil || selected != nil)
      && validVolume
      && (!canSetVolume || (selected != nil && volume != nil))
  }
}

/// Public HAL properties only. Reading and installing listeners never changes audio settings.
enum AudioSystem {
  private static let system = AudioObjectID(kAudioObjectSystemObject)

  static func read() -> AudioSnapshot? {
    guard let outputs = outputs(),
      let selectedID = uint32(system, kAudioHardwarePropertyDefaultOutputDevice)
    else { return nil }
    let selected = outputs.first { $0.deviceID == selectedID }
    let controls = selected.map { volumeControls($0.deviceID) } ?? []
    let values = controls.map(\.value)
    return AudioSnapshot(
      outputs: outputs, selectedUID: selected?.uid, volume: values.max(),
      canSetVolume: !controls.isEmpty && controls.allSatisfy(\.settable),
      isMuted: selected.flatMap { muted($0.deviceID) },
      canSelectOutput: settable(system, kAudioHardwarePropertyDefaultOutputDevice))
  }

  static func selectOutput(_ uid: String) -> String? {
    guard let device = outputs()?.first(where: { $0.uid == uid }) else {
      return "That output is no longer connected. Refresh and choose another device."
    }
    guard settable(system, kAudioHardwarePropertyDefaultOutputDevice) else {
      return "macOS cannot change the output here. Open Sound Settings."
    }
    var address = address(kAudioHardwarePropertyDefaultOutputDevice)
    var requested = AudioDeviceID(device.deviceID)
    let status = AudioObjectSetPropertyData(
      system, &address, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &requested)
    return status == noErr
      ? nil : "The output could not be changed. Refresh or open Sound Settings."
  }

  static func setVolume(_ uid: String, value: Double) -> String? {
    guard value.isFinite, (0...1).contains(value) else {
      return "Choose a volume between 0 and 100 percent."
    }
    guard let device = outputs()?.first(where: { $0.uid == uid }),
      uint32(system, kAudioHardwarePropertyDefaultOutputDevice) == device.deviceID
    else {
      return "The output changed or disconnected. Refresh and try again."
    }
    let controls = volumeControls(device.deviceID)
    guard !controls.isEmpty, controls.allSatisfy(\.settable) else {
      return "Adjust volume on this device."
    }
    // Preserve the stereo balance when the device has channel controls instead of a master.
    let largest = controls.map(\.value).max() ?? 0
    var written: [VolumeControl] = []
    for control in controls {
      var scalar = Float32(largest > 0 ? value * control.value / largest : value)
      var property = address(
        kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput,
        element: control.element)
      let status = AudioObjectSetPropertyData(
        device.deviceID, &property, 0, nil, UInt32(MemoryLayout<Float32>.size), &scalar)
      if status != noErr {
        // A second-channel failure should not leave the balance changed where rollback is possible.
        for previous in written {
          var old = Float32(previous.value)
          var oldProperty = address(
            kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput,
            element: previous.element)
          _ = AudioObjectSetPropertyData(
            device.deviceID, &oldProperty, 0, nil, UInt32(MemoryLayout<Float32>.size), &old)
        }
        return "The volume could not be changed. Refresh or adjust it on this device."
      }
      written.append(control)
    }
    // Volume scalar changes deliberately leave all mute properties untouched.
    return nil
  }

  private static func outputs() -> [AudioOutput]? {
    guard let devices = uint32Array(system, kAudioHardwarePropertyDevices) else { return nil }
    return devices.compactMap { device in
      guard uint32(device, kAudioDevicePropertyDeviceIsAlive) == 1,
        let streams = uint32Array(
          device, kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeOutput),
        !streams.isEmpty,
        uint32(
          device, kAudioDevicePropertyDeviceCanBeDefaultDevice,
          scope: kAudioDevicePropertyScopeOutput) != 0,
        let uid = string(device, kAudioDevicePropertyDeviceUID), !uid.isEmpty
      else { return nil }
      let name = string(device, kAudioObjectPropertyName) ?? "Audio Output"
      return AudioOutput(uid: uid, name: name.isEmpty ? "Audio Output" : name, deviceID: device)
    }.sorted {
      let comparison = $0.name.localizedCaseInsensitiveCompare($1.name)
      return comparison == .orderedSame ? $0.uid < $1.uid : comparison == .orderedAscending
    }
  }

  private struct VolumeControl {
    let element: AudioObjectPropertyElement
    let value: Double
    let settable: Bool
  }

  private static func volumeControls(_ device: AudioDeviceID) -> [VolumeControl] {
    func control(_ element: AudioObjectPropertyElement) -> VolumeControl? {
      guard
        let scalar = float32(
          device, kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput,
          element: element), scalar.isFinite, (0...1).contains(scalar)
      else { return nil }
      return VolumeControl(
        element: element, value: Double(scalar),
        settable: settable(
          device, kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput,
          element: element))
    }
    if let master = control(kAudioObjectPropertyElementMain) { return [master] }
    let stereo = uint32Array(
      device, kAudioDevicePropertyPreferredChannelsForStereo, scope: kAudioDevicePropertyScopeOutput
    )
    let channels: [UInt32]
    if let stereo, stereo.count == 2 { channels = stereo } else { channels = [1, 2] }
    var seen = Set<UInt32>()
    return channels.filter { $0 != 0 && seen.insert($0).inserted }.compactMap(control)
  }

  private static func muted(_ device: AudioDeviceID) -> Bool? {
    if let master = uint32(
      device, kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput)
    {
      return master != 0
    }
    let channels = volumeControls(device).map(\.element)
    let values = channels.compactMap {
      uint32(device, kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput, element: $0)
    }
    return values.isEmpty ? nil : values.allSatisfy { $0 != 0 }
  }

  private static func address(
    _ selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
    element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
  ) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
  }

  private static func settable(
    _ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
    element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
  ) -> Bool {
    var property = address(selector, scope: scope, element: element)
    var writable: DarwinBoolean = false
    return AudioObjectHasProperty(object, &property)
      && AudioObjectIsPropertySettable(object, &property, &writable) == noErr && writable.boolValue
  }

  private static func uint32(
    _ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
    element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
  ) -> UInt32? {
    var property = address(selector, scope: scope, element: element)
    var size = UInt32(MemoryLayout<UInt32>.size)
    var value: UInt32 = 0
    guard AudioObjectGetPropertyData(object, &property, 0, nil, &size, &value) == noErr,
      size == MemoryLayout<UInt32>.size
    else { return nil }
    return value
  }

  private static func float32(
    _ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope, element: AudioObjectPropertyElement
  ) -> Float32? {
    var property = address(selector, scope: scope, element: element)
    var size = UInt32(MemoryLayout<Float32>.size)
    var value: Float32 = 0
    guard AudioObjectGetPropertyData(object, &property, 0, nil, &size, &value) == noErr,
      size == MemoryLayout<Float32>.size
    else { return nil }
    return value
  }

  private static func uint32Array(
    _ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
  ) -> [UInt32]? {
    var property = address(selector, scope: scope)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(object, &property, 0, nil, &size) == noErr,
      size % UInt32(MemoryLayout<UInt32>.stride) == 0
    else { return nil }
    if size == 0 { return [] }
    var values = [UInt32](repeating: 0, count: Int(size) / MemoryLayout<UInt32>.stride)
    let status = values.withUnsafeMutableBytes { buffer in
      AudioObjectGetPropertyData(object, &property, 0, nil, &size, buffer.baseAddress!)
    }
    guard status == noErr, size % UInt32(MemoryLayout<UInt32>.stride) == 0,
      Int(size) <= values.count * MemoryLayout<UInt32>.stride
    else {
      return nil
    }
    return Array(values.prefix(Int(size) / MemoryLayout<UInt32>.stride))
  }

  private static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector)
    -> String?
  {
    var property = address(selector)
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    var value: Unmanaged<CFString>?
    guard AudioObjectGetPropertyData(object, &property, 0, nil, &size, &value) == noErr,
      let value
    else { return nil }
    return value.takeRetainedValue() as String
  }
}

/// The lock protects registrations and teardown; callbacks capture only a Sendable change handler.
final class AudioSystemObservation: @unchecked Sendable {
  private struct Listener {
    let object: AudioObjectID
    var address: AudioObjectPropertyAddress
    let block: AudioObjectPropertyListenerBlock
  }

  private let lock = NSLock()
  private let queue = DispatchQueue(label: "com.user.toggledeck.audio-observation")
  private let changed: @Sendable () -> Void
  private var systemListeners: [Listener] = []
  private var deviceListeners: [Listener] = []
  private var selectedDevice: UInt32?
  private var stopped = false

  init(changed: @escaping @Sendable () -> Void) {
    self.changed = changed
    for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultOutputDevice] {
      if let listener = add(
        AudioObjectID(kAudioObjectSystemObject), selector: selector,
        scope: kAudioObjectPropertyScopeGlobal, element: kAudioObjectPropertyElementMain)
      {
        systemListeners.append(listener)
      }
    }
  }

  func observeDevice(_ device: UInt32?) {
    lock.lock()
    defer { lock.unlock() }
    guard !stopped, selectedDevice != device else { return }
    remove(deviceListeners)
    deviceListeners = []
    selectedDevice = device
    guard let device else { return }
    if let alive = add(
      device, selector: kAudioDevicePropertyDeviceIsAlive, scope: kAudioObjectPropertyScopeGlobal,
      element: kAudioObjectPropertyElementMain)
    {
      deviceListeners.append(alive)
    }
    for selector in [kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyMute] {
      if let listener = add(
        device, selector: selector, scope: kAudioDevicePropertyScopeOutput,
        element: kAudioObjectPropertyElementWildcard)
      {
        deviceListeners.append(listener)
      }
    }
  }

  func stop() {
    lock.lock()
    defer { lock.unlock() }
    guard !stopped else { return }
    stopped = true
    remove(systemListeners + deviceListeners)
    systemListeners = []
    deviceListeners = []
  }

  deinit { stop() }

  private func add(
    _ object: AudioObjectID, selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope, element: AudioObjectPropertyElement
  ) -> Listener? {
    var property = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    let changed = changed
    let block: AudioObjectPropertyListenerBlock = { _, _ in changed() }
    guard AudioObjectAddPropertyListenerBlock(object, &property, queue, block) == noErr else {
      return nil
    }
    return Listener(object: object, address: property, block: block)
  }

  private func remove(_ listeners: [Listener]) {
    for var listener in listeners {
      _ = AudioObjectRemovePropertyListenerBlock(
        listener.object, &listener.address, queue, listener.block)
    }
  }
}
