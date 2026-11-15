import Combine
import CoreAudio
import Foundation

/// Lists CoreAudio output devices and keeps the list current when devices
/// are plugged in/out or the system default changes.
///
/// Playback routing itself is done per-player via `AVPlayer.audioOutputDeviceUniqueID`,
/// so selecting a device here never changes the system-wide default output.
@MainActor
final class AudioDeviceManager: ObservableObject {
    struct Device: Identifiable, Hashable {
        let id: AudioDeviceID
        /// Persistent CoreAudio UID (survives reboots and reconnects, unlike `id`).
        let uid: String
        let name: String
        let isDefault: Bool
    }

    @Published private(set) var devices: [Device] = []

    private var listenerBlock: AudioObjectPropertyListenerBlock?

    init() {
        refresh()
        installListeners()
    }

    // Note: no deinit cleanup — the single instance is owned by `RadioPlayer`, which lives
    // for the whole app lifetime.

    func refresh() {
        let defaultID = Self.currentDefaultOutputDevice()
        let updated = Self.fetchOutputDevices()
            .map { Device(id: $0.id, uid: $0.uid, name: $0.name, isDefault: $0.id == defaultID) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if updated != devices {
            devices = updated
        }
    }

    func contains(uid: String) -> Bool {
        devices.contains { $0.uid == uid }
    }

    /// Resolves a legacy numeric device ID (settings ≤ 1.0.2) to its UID.
    func uid(forDeviceID id: AudioDeviceID) -> String? {
        devices.first { $0.id == id }?.uid
    }

    // MARK: - Change notifications

    private func installListeners() {
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            // Delivered on the main queue (see below).
            MainActor.assumeIsolated { self?.refresh() }
        }
        listenerBlock = block
        for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultOutputDevice] {
            var address = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block)
        }
    }

    // MARK: - CoreAudio queries

    private nonisolated static func currentDefaultOutputDevice() -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        return status == noErr ? deviceID : 0
    }

    private nonisolated static func fetchOutputDevices() -> [(id: AudioDeviceID, uid: String, name: String)] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize) == noErr else {
            return []
        }
        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = Array(repeating: AudioDeviceID(0), count: deviceCount)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &deviceIDs) == noErr else {
            return []
        }

        return deviceIDs.compactMap { id in
            guard hasOutputChannels(deviceID: id),
                  let uid = stringProperty(kAudioDevicePropertyDeviceUID, of: id)
            else { return nil }
            let name = stringProperty(kAudioObjectPropertyName, of: id) ?? "Unknown Device"
            return (id: id, uid: uid, name: name)
        }
    }

    private nonisolated static func hasOutputChannels(deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize) == noErr, dataSize > 0 else {
            return false
        }
        let rawBuffer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { rawBuffer.deallocate() }
        let bufferList = rawBuffer.bindMemory(to: AudioBufferList.self, capacity: 1)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, bufferList) == noErr else {
            return false
        }
        let audioBufferList = UnsafeMutableAudioBufferListPointer(bufferList)
        return audioBufferList.reduce(0) { $0 + Int($1.mNumberChannels) } > 0
    }

    private nonisolated static func stringProperty(_ selector: AudioObjectPropertySelector, of deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) { ptr in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, ptr)
        }
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }
}
