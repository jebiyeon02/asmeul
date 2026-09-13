import AVFoundation
import AudioCore
import Foundation

struct AmbienceScene: Identifiable {
  let id: Int
  let name: String
  let detail: String
  let symbol: String
  static let all: [AmbienceScene] = [
    .init(id: 0, name: "배경 없음", detail: "음악의 공간감만 조절합니다", symbol: "waveform"),
    .init(id: 1, name: "동굴", detail: "바위 천장의 물방울 · 멀리 번지는 메아리", symbol: "mountain.2"),
    .init(id: 2, name: "창가의 비", detail: "창밖에 내리는 실제 스테레오 빗소리", symbol: "cloud.rain"),
    .init(id: 3, name: "심야 라디오", detail: "멀리 들리는 일본어 방송 · 창밖의 비 · 음악 없음", symbol: "radio"),
    .init(
      id: 4, name: "도쿄 사무실", detail: "창밖의 비와 도시 · 책상의 필기 · 먼 일본어 방송",
      symbol: "building.2.crop.circle"),
    .init(id: 5, name: "황혼의 호숫가", detail: "풀벌레 · 부드러운 바람 · 잔물결 · 희미한 방울", symbol: "sun.horizon"),
  ]
}

/// Asset decoding happens before publishing immutable PCM banks to the C++ engine.
enum SoundLibrary {
  static func decode(_ url: URL) throws -> (samples: [Float], rate: Double) {
    let file = try AVAudioFile(forReading: url)
    guard file.length > 0,

      let buffer = AVAudioPCMBuffer(
        pcmFormat: file.processingFormat,
        frameCapacity: AVAudioFrameCount(
          min(file.length, AVAudioFramePosition(file.processingFormat.sampleRate * 180))))
    else { throw CocoaError(.fileReadCorruptFile) }
    try file.read(into: buffer, frameCount: buffer.frameCapacity)
    guard let channels = buffer.floatChannelData, !buffer.format.isInterleaved else {
      throw CocoaError(.fileReadCorruptFile)
    }
    let frames = Int(buffer.frameLength)
    let right = min(1, Int(buffer.format.channelCount) - 1)
    var samples = [Float](repeating: 0, count: frames * 2)
    for i in 0..<frames {
      samples[i * 2] = channels[0][i]
      samples[i * 2 + 1] = channels[right][i]
    }
    return (samples, buffer.format.sampleRate)
  }
  static func loadResources(into engine: HollowEngine) throws {
    let bundled = Bundle.main.resourceURL?.appendingPathComponent("Hollow_Hollow.bundle")
    let resources = bundled.flatMap { Bundle(url: $0) } ?? Bundle.module
    let assets = [
      (0, "cave"), (1, "cave-echo"), (2, "rain"), (3, "twilight-piano"), (8, "crickets"),
      (9, "lake"), (10, "writing"), (11, "keyboard"), (12, "grass"), (13, "city"),
      (14, "memory-chimes"),
    ]
    for (slot, name) in assets {
      let ext = slot == 3 || slot == 14 ? "wav" : "mp3"
      guard let url = resources.url(forResource: name, withExtension: ext) else {
        throw CocoaError(.fileNoSuchFile)
      }
      let asset = try decode(url)
      let success = asset.samples.withUnsafeBufferPointer {
        hollow_load_sound(
          engine, Int32(slot), $0.baseAddress, UInt32(asset.samples.count / 2), asset.rate)
      }
      guard success == 1 else { throw CocoaError(.fileReadCorruptFile) }
    }
  }
}

/// Original fictional station scripts. The system voice is rendered locally into memory;
/// no personal/imitated voices, live broadcasts, or captured user audio are used.
@MainActor final class RadioVoiceBuilder {
  private var synthesizer: AVSpeechSynthesizer?
  private var timeout: Task<Void, Never>?
  private var collector: Collector?
  private var stopped = false
  static let scripts = [
    "こちらは、ホロウの架空の街からお届けする、夕方の放送です。街の図書館では、古い写真を集めた、小さな展示会が開かれています。窓辺の机には、訪れた人が残した短い手紙も並び、静かな時間が流れています。",
    "続いて、街の話題です。川沿いの商店街では、店先に季節の花が飾られています。帰り道に足を止め、花を眺める人の姿も見られました。いつもの道にも、ゆっくり歩くと、違った表情が見つかるかもしれません。",
    "ここからは、暮らしの便りです。今夜は、雨の日の読書についてお話しします。本のページをめくる音と、窓をたたく雨の音。慌ただしい一日の終わりに、好きな一冊を開いてみてはいかがでしょうか。",
    "ホロウ、夕方の放送をお聞きいただいています。住宅街の小さな喫茶店から、手書きのお便りが届きました。雨宿りの途中に交わした、何気ない会話。その温かな記憶が、今も店の片隅に残っているそうです。",
  ]
  // AVSpeech delivers PCM on its synthesis queue. This collector is not on the HAL render thread.
  private final class Collector: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Float] = []
    private var rate = 22050.0
    private var done = false
    func append(_ buffer: AVAudioPCMBuffer) -> (samples: [Float], rate: Double)? {
      lock.lock()
      defer { lock.unlock() }
      guard !done else { return nil }
      if buffer.frameLength == 0 {
        done = true
        return (samples, rate)
      }
      rate = buffer.format.sampleRate
      guard samples.count < Int(rate * 80 * 2) else {
        done = true
        return (samples, rate)
      }
      let frames = Int(buffer.frameLength)
      if let data = buffer.floatChannelData {
        let stride = buffer.format.isInterleaved ? Int(buffer.format.channelCount) : 1
        for i in 0..<frames {
          let x = data[0][i * stride]
          samples.append(x)
          samples.append(x)
        }
      } else if let data = buffer.int16ChannelData {
        let stride = buffer.format.isInterleaved ? Int(buffer.format.channelCount) : 1
        for i in 0..<frames {
          let x = Float(data[0][i * stride]) / 32768
          samples.append(x)
          samples.append(x)
        }
      }
      return nil
    }
    func cancel() {
      lock.lock()
      done = true
      samples.removeAll()
      lock.unlock()
    }
  }
  func build(deliver: @escaping (Int, [Float], Double) -> Void, status: @escaping (String) -> Void)
  {
    stopped = false
    let voices = AVSpeechSynthesisVoice.speechVoices().filter {
      $0.language.hasPrefix("ja") && !$0.voiceTraits.contains(.isPersonalVoice)
        && !$0.voiceTraits.contains(.isNoveltyVoice)
    }.sorted { $0.quality.rawValue > $1.quality.rawValue }
    guard
      let voice = voices.first(where: { $0.quality.rawValue > 1 }) ?? voices.first(where: {
        $0.name == "Kyoko"
      }) ?? voices.first
    else {
      status("일본어 음성이 없습니다. macOS 음성을 설치하면 일본어 방송를 들을 수 있어요.")
      return
    }
    buildClip(0, voice: voice, deliver: deliver, status: status)
  }
  private func buildClip(
    _ index: Int, voice: AVSpeechSynthesisVoice, deliver: @escaping (Int, [Float], Double) -> Void,
    status: @escaping (String) -> Void
  ) {
    guard !stopped else { return }
    guard index < Self.scripts.count else {
      status("가상 일본어 방송 · 합성 음성 · 자체 음악 없음")
      return
    }
    status("일본어 방송 음성 준비 중 \(index + 1)/4")
    let collector = Collector()
    self.collector = collector
    let synth = AVSpeechSynthesizer()
    synthesizer = synth
    let utterance = AVSpeechUtterance(string: Self.scripts[index])
    utterance.voice = voice
    utterance.rate = 0.47
    utterance.pitchMultiplier = 0.93
    timeout?.cancel()
    timeout = Task { [weak self] in
      try? await Task.sleep(for: .seconds(25))
      guard !Task.isCancelled else { return }
      self?.cancel()
      status("방송 음성을 준비하지 못했습니다. 환경음은 계속 사용할 수 있어요.")
    }
    synth.write(utterance) { [weak self] buffer in
      guard let pcm = buffer as? AVAudioPCMBuffer, let result = collector.append(pcm) else {
        return
      }
      Task { @MainActor in
        guard let self, !self.stopped else { return }
        self.timeout?.cancel()
        if result.samples.count > 8 { deliver(index + 4, result.samples, result.rate) }
        self.buildClip(index + 1, voice: voice, deliver: deliver, status: status)
      }
    }
  }
  func cancel() {
    stopped = true
    timeout?.cancel()
    collector?.cancel()
    synthesizer?.stopSpeaking(at: .immediate)
    synthesizer = nil
  }
}
