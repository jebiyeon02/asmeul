import AVFoundation
import AudioCore
import Foundation

extension Bundle {
  static var module: Bundle { Bundle(path: CommandLine.arguments[1])! }
}

@main struct PreviewRender {
  @MainActor static func main() async throws {
    let engine = hollow_create()!
    defer { hollow_destroy(engine) }
    let durations = try SoundLibrary.loadResources(into: engine)
    guard durations.count == 25, durations[1, default: 0] > 930,
      durations[14, default: 0] > 20, durations[20, default: 0] > 80,
      durations[32, default: 0] > 40, durations[33, default: 0] > 4,
      durations[34, default: 0] > 4, durations[35, default: 0] > 4
    else { throw CocoaError(.fileReadCorruptFile) }
    print("PASS: all 25 bundled files decoded, including fallen leaves, snow steps, deep-space drones, and the existing wave, fire, birds, cicada and underwater sounds")
    let resourceBundle = Bundle(path: CommandLine.arguments[1])!
    guard let importURL = resourceBundle.url(forResource: "user-wave-1.mp3", withExtension: nil),
      try SoundLibrary.load(url: importURL, slot: 21, into: engine) > 20
    else { throw CocoaError(.fileReadCorruptFile) }
    print("PASS: a user MP3 loaded into custom slot 21")
    let destination = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory:true)
    try FileManager.default.createDirectory(at:destination,withIntermediateDirectories:true)
    for name in ["binaural-asmr-mix"] {
      let rate = 48000.0, frames = UInt32(40 * 48000)
      hollow_configure(engine, 0, 0, 0, 0.85, 0)
      hollow_spatial(engine, 1)
      hollow_position(engine, 1, 1, 0.3)
      hollow_position(engine, 2, 4, 0.5)
      hollow_position(engine, 4, 1, 0.1)
      hollow_position(engine, 6, 2, 0.2)
      hollow_mix(engine, 0.65, 0, 1)
      for slot: Int32 in [1, 2, 4, 6] { hollow_track_gain(engine, slot, 0.45) }
      var samples = [Float](repeating:0,count:Int(frames)*2)
      samples.withUnsafeMutableBufferPointer { hollow_render_offline(engine,$0.baseAddress,frames,rate) }
      guard samples.allSatisfy({$0.isFinite && abs($0)<=0.95001}) else { throw CocoaError(.fileReadCorruptFile) }
      let rms = sqrt(samples.reduce(0.0){$0+Double($1*$1)}/Double(samples.count))
      guard rms > 0.001 else { throw CocoaError(.fileReadCorruptFile) }
      let format = AVAudioFormat(standardFormatWithSampleRate:rate,channels:2)!
      let buffer = AVAudioPCMBuffer(pcmFormat:format,frameCapacity:frames)!
      buffer.frameLength=frames
      for i in 0..<Int(frames) {buffer.floatChannelData![0][i]=samples[i*2];buffer.floatChannelData![1][i]=samples[i*2+1]}
      let file=try AVAudioFile(forWriting:destination.appendingPathComponent(name+".wav"),settings:[AVFormatIDKey:kAudioFormatLinearPCM,AVSampleRateKey:rate,AVNumberOfChannelsKey:2,AVLinearPCMBitDepthKey:16,AVLinearPCMIsFloatKey:false])
      try file.write(from:buffer)
      print("PASS \(name): 40s stereo; RMS \(rms), peak \(samples.map{abs($0)}.max() ?? 0)")
    }
  }
}
