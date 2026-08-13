// setout "<device name>"  — set the default system output device. Prints current if no arg.
import CoreAudio
import Foundation

func prop(_ s: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: s, mScope: kAudioObjectPropertyScopeGlobal,
                               mElement: kAudioObjectPropertyElementMain)
}
func name(_ id: AudioObjectID) -> String? {
    var a = prop(kAudioObjectPropertyName)
    var size = UInt32(MemoryLayout<CFString?>.size)
    var out: CFString? = nil
    let st = withUnsafeMutablePointer(to: &out) { AudioObjectGetPropertyData(id, &a, 0, nil, &size, $0) }
    return st == noErr ? out as String? : nil
}

var cur: AudioObjectID = 0
var csize = UInt32(MemoryLayout<AudioObjectID>.size)
var caddr = prop(kAudioHardwarePropertyDefaultOutputDevice)
AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &caddr, 0, nil, &csize, &cur)

guard CommandLine.arguments.count > 1 else {
    print(name(cur) ?? "?"); exit(0)
}
let want = CommandLine.arguments[1]

var addr = prop(kAudioHardwarePropertyDevices)
var size: UInt32 = 0
AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size)
var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids)

guard var target = ids.first(where: { name($0) == want }) else {
    print("no device named \(want)"); exit(1)
}
let st = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &caddr, 0, nil,
                                    UInt32(MemoryLayout<AudioObjectID>.size), &target)
print(st == noErr ? "output → \(want)" : "failed: \(st)")
