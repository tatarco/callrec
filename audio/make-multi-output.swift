// make-multi-output [speaker-name] — create a Multi-Output Device named "Call Capture"
// that fans system audio to your speakers AND to BlackHole 2ch, so it can be recorded.
// Defaults to whatever your current output device is. This is what you'd otherwise click
// together by hand in Audio MIDI Setup.
import CoreAudio
import Foundation

func prop(_ s: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: s, mScope: kAudioObjectPropertyScopeGlobal,
                               mElement: kAudioObjectPropertyElementMain)
}

func str(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
    var addr = prop(selector)
    var size = UInt32(MemoryLayout<CFString?>.size)
    var out: CFString? = nil
    let st = withUnsafeMutablePointer(to: &out) {
        AudioObjectGetPropertyData(id, &addr, 0, nil, &size, $0)
    }
    return st == noErr ? out as String? : nil
}

func devices() -> [AudioObjectID] {
    var addr = prop(kAudioHardwarePropertyDevices)
    var size: UInt32 = 0
    AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size)
    var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids)
    return ids
}

// current default output, used when no name is given
var cur: AudioObjectID = 0
var csize = UInt32(MemoryLayout<AudioObjectID>.size)
var caddr = prop(kAudioHardwarePropertyDefaultOutputDevice)
AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &caddr, 0, nil, &csize, &cur)

let wantSpeaker = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : (str(cur, kAudioObjectPropertyName) ?? "")

if devices().contains(where: { str($0, kAudioObjectPropertyName) == "Call Capture" }) {
    print("'Call Capture' already exists")
    exit(0)
}

var uids: [String: String] = [:]
for d in devices() {
    if let n = str(d, kAudioObjectPropertyName), let u = str(d, kAudioDevicePropertyDeviceUID) {
        uids[n] = u
    }
}

guard let spk = uids[wantSpeaker] else {
    print("no output device named '\(wantSpeaker)'. found: \(uids.keys.sorted())")
    exit(1)
}
guard let bh = uids["BlackHole 2ch"] else {
    print("BlackHole 2ch not found — install it first: brew install --cask blackhole-2ch")
    print("(then `sudo killall coreaudiod` if it doesn't show up)")
    exit(1)
}

let desc: [String: Any] = [
    kAudioAggregateDeviceNameKey as String: "Call Capture",
    kAudioAggregateDeviceUIDKey as String: "org.zazet.callcapture",
    kAudioAggregateDeviceIsPrivateKey as String: 0,   // persists, visible in Audio MIDI Setup
    kAudioAggregateDeviceIsStackedKey as String: 1,   // stacked aggregate == Multi-Output Device
    kAudioAggregateDeviceMasterSubDeviceKey as String: spk,  // real hardware is the clock master
    kAudioAggregateDeviceSubDeviceListKey as String: [
        [kAudioSubDeviceUIDKey as String: spk,
         kAudioSubDeviceDriftCompensationKey as String: 0],
        [kAudioSubDeviceUIDKey as String: bh,
         kAudioSubDeviceDriftCompensationKey as String: 1],  // virtual device drifts; correct it
    ],
]

var newID: AudioObjectID = 0
let st = AudioHardwareCreateAggregateDevice(desc as CFDictionary, &newID)
guard st == noErr else { print("create failed: OSStatus \(st)"); exit(1) }
print("created 'Call Capture' (\(wantSpeaker) + BlackHole 2ch)")
