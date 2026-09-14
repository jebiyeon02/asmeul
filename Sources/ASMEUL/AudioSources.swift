import Foundation

struct AudioProcess: Identifiable, Hashable {
  // Application PID stays stable when an audio helper restarts.
  let id: UInt32
  let name: String
  let bundleID: String
  let processIDs: [UInt32]
}

struct AudioProcessRecord {
  let id: UInt32
  let pid: Int32
  let bundleID: String?
  let bundlePath: String?
}

struct AudioApplication {
  let pid: Int32
  let name: String
  let bundleID: String
  let bundlePath: String?

  func owns(_ process: AudioProcessRecord) -> Bool {
    if process.pid == pid || process.bundleID == bundleID { return true }
    // Chromium/Electron audio services can be real Core Audio clients while
    // NSRunningApplication exposes no bundle URL for their helper process.
    // Match only the explicit helper namespace so sibling apps such as
    // com.google.Chrome.beta are not folded into the selected application.
    if let processBundleID = process.bundleID,
      processBundleID == bundleID + ".helper"
        || processBundleID.hasPrefix(bundleID + ".helper.")
    {
      return true
    }
    // Chromium/Electron audio lives in nested Helper.app bundles. Do not
    // capture unrelated apps with similar bundle IDs or shared system daemons.
    guard let root = bundlePath, let path = process.bundlePath else { return false }
    return path == root || path.hasPrefix(root + "/")
  }
}

enum AudioSourceSelection: Equatable {
  case system
  case missingApplication
  case waitingForProcesses
  case processes([UInt32])
}

func resolveAudioSource(selected: UInt32, sources: [AudioProcess]) -> AudioSourceSelection {
  guard selected != 0 else { return .system }
  guard let source = sources.first(where: { $0.id == selected }) else {
    return .missingApplication
  }
  guard !source.processIDs.isEmpty else { return .waitingForProcesses }
  return .processes(source.processIDs)
}

func groupedAudioSources(
  applications: [AudioApplication], records: [AudioProcessRecord], selected: UInt32
) -> [AudioProcess] {
  applications.compactMap { app in
    let ids = Array(Set(records.filter { app.owns($0) }.map(\.id))).sorted()
    guard !ids.isEmpty || UInt32(app.pid) == selected else { return nil }
    return AudioProcess(
      id: UInt32(app.pid), name: app.name, bundleID: app.bundleID, processIDs: ids)
  }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
}
