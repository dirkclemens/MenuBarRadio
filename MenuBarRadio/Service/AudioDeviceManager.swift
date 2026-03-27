import Combine
import CoreAudio
import Foundation

/// Output audio device listing and selection via CoreAudio.
@MainActor
final class AudioDeviceManager: ObservableObject {
    struct Device: Identifiable, Hashable {
        let id: AudioDeviceID
        let name: String
        let isDefault: Bool
    }

    @Published private(set) var devices: [Device] = []

    func refresh() {
        let defaultID = currentDefaultOutputDevice()
        let outputDevices = Self.fetchOutputDevices()
        devices = outputDevices.map { device in
            Device(id: device.id, name: device.name, isDefault: device.id == defaultID)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func isValidOutputDevice(id: AudioDeviceID) -> Bool {
        devices.contains(where: { $0.id == id })
    }

    func setDefaultOutputDevice(id: AudioDeviceID) -> Bool {
        var deviceID = id
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &deviceID
        )
        return status == noErr
    }

    func setDeviceVolume(id: AudioDeviceID, volume: Float) {
        let scalar = max(0, min(volume, 1))
        if setVolume(deviceID: id, element: kAudioObjectPropertyElementMain, volume: scalar) {
            return
        }
        _ = setVolume(deviceID: id, element: 1, volume: scalar)
        _ = setVolume(deviceID: id, element: 2, volume: scalar)
    }

    private func currentDefaultOutputDevice() -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        return status == noErr ? deviceID : 0
    }

    private static func fetchOutputDevices() -> [(id: AudioDeviceID, name: String)] {
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
            guard hasOutputChannels(deviceID: id) else { return nil }
            return (id: id, name: deviceName(deviceID: id))
        }
    }

    private static func hasOutputChannels(deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize) == noErr else {
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
        let channelCount = audioBufferList.reduce(0) { $0 + Int($1.mNumberChannels) }
        return channelCount > 0
    }

    private static func deviceName(deviceID: AudioDeviceID) -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var cfName: CFString?
        var size = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &cfName) { ptr in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, ptr)
        }
        if status == noErr, let cfName {
            return cfName as String
        }
        return "Unknown Device"
    }

    private func setVolume(deviceID: AudioDeviceID, element: AudioObjectPropertyElement, volume: Float) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
        var vol = volume
        let status = AudioObjectSetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<Float>.size),
            &vol
        )
        return status == noErr
    }
}
