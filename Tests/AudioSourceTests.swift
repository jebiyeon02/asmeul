import Foundation

@main struct AudioSourceTests {
  static func main() {
    let chrome = AudioApplication(pid: 100, name: "Chrome", bundleID: "com.google.Chrome", bundlePath: "/Applications/Chrome.app")
    let music = AudioApplication(pid: 200, name: "Music", bundleID: "com.apple.Music", bundlePath: "/System/Applications/Music.app")
    let main = AudioProcessRecord(id: 10, pid: 100, bundleID: "com.google.Chrome", bundlePath: chrome.bundlePath)
    let helper = AudioProcessRecord(id: 11, pid: 101, bundleID: "com.google.Chrome.helper", bundlePath: "/Applications/Chrome.app/Contents/Frameworks/Helper.app")
    let pathlessAudioHelper = AudioProcessRecord(
      id: 15, pid: 105, bundleID: "com.google.Chrome.helper", bundlePath: nil)
    let pathlessRenderer = AudioProcessRecord(
      id: 16, pid: 106, bundleID: "com.google.Chrome.helper.Renderer", bundlePath: nil)
    let other = AudioProcessRecord(id: 12, pid: 201, bundleID: "com.apple.Music", bundlePath: music.bundlePath)
    let similar = AudioProcessRecord(id: 13, pid: 300, bundleID: "com.google.Chrome.beta", bundlePath: "/Applications/Chrome.app Beta/Helper.app")
    let shared = AudioProcessRecord(id: 14, pid: 400, bundleID: "com.apple.WebKit.GPU", bundlePath: "/System/Library/Frameworks/WebKit.framework/GPU.xpc")
    let apps = [chrome, music]
    let sources = groupedAudioSources(
      applications: apps,
      records: [main, helper, pathlessAudioHelper, pathlessRenderer, other, similar, shared, helper],
      selected: 0)
    precondition(sources.count == 2)
    precondition(sources.first { $0.id == 100 }?.processIDs == [10, 11, 15, 16])
    precondition(sources.first { $0.id == 200 }?.processIDs == [12])
    precondition(resolveAudioSource(selected: 0, sources: sources) == .system)
    precondition(resolveAudioSource(selected: 100, sources: sources) == .processes([10, 11, 15, 16]))
    let helperOnly = groupedAudioSources(applications: apps, records: [helper], selected: 0)
    precondition(helperOnly.count == 1 && helperOnly[0].id == 100)
    let silent = groupedAudioSources(applications: apps, records: [], selected: 100)
    precondition(silent.count == 1 && silent[0].processIDs.isEmpty)
    precondition(resolveAudioSource(selected: 100, sources: silent) == .waitingForProcesses)
    let replacement = AudioProcessRecord(id: 99, pid: 102, bundleID: helper.bundleID, bundlePath: helper.bundlePath)
    let restarted = groupedAudioSources(applications: apps, records: [replacement], selected: 100)
    precondition(restarted[0].id == silent[0].id && restarted[0].processIDs == [99])
    precondition(resolveAudioSource(selected: 100, sources: restarted) == .processes([99]))
    precondition(groupedAudioSources(applications: [music], records: [], selected: 100).isEmpty)
    precondition(resolveAudioSource(selected: 100, sources: []) == .missingApplication)
    print("PASS: app/helper grouping, empty-source wait, retry resolution, helper restart and app exit")
  }
}
