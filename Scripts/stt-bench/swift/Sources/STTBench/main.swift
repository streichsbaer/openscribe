// STTBench: FluidAudio Parakeet and Apple SpeechTranscriber runner for Scripts/stt-bench.
//
//   STTBench '<json config>'                       run one engine (called by run.py)
//   STTBench record-devterms <sentences.json> <dir>  record the developer-terms script
import AVFoundation
import CoreML
import FluidAudio
import Foundation
import Speech

struct Config: Decodable {
    struct Entry: Decodable { let term: String; let aliases: [String] }
    struct Boost: Decodable {
        var rescue: Bool?
        var rescueMinSim: Float?
        var rescueMultiMinSim: Float?
        var taperPivot: Int?
        var taperExponent: Float?
        var minSimilarity: Float?
        var shortLength: Int?
        var shortSimilarity: Float?
    }
    let engine: String
    let sets: [String]
    let manifest: String
    let output: String
    let maxClip: Double
    let fluidAudioModels: String
    let revisions: [String: String]
    let vocabulary: [Entry]?
    let boost: Boost?
}

struct Item: Decodable { let id: String; let wav: String; let dur: Double }

func now() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e9 }

func runEngine(_ config: Config) async throws {
    let manifest = try JSONDecoder().decode(
        [String: [Item]].self, from: Data(contentsOf: URL(fileURLWithPath: config.manifest)))
    let outURL = URL(fileURLWithPath: config.output)
    if !FileManager.default.fileExists(atPath: outURL.path) {
        FileManager.default.createFile(atPath: outURL.path, contents: nil)
    }
    let out = try FileHandle(forWritingTo: outURL)
    out.seekToEndOfFile()
    defer { try? out.close() }

    func runAll(load: Double, _ transcribe: (URL) async throws -> String) async throws {
        _ = try await transcribe(URL(fileURLWithPath: manifest["clips"]![0].wav))  // warm-up
        for set in config.sets {
            for item in manifest[set]! where set != "clips" || item.dur <= config.maxClip {
                let reps = set == "clips" && item.dur <= 150 ? 3 : 1
                for rep in 0..<reps {
                    let t = now()
                    let text = try await transcribe(URL(fileURLWithPath: item.wav))
                    let row: [String: Any] = [
                        "engine": config.engine, "set": set, "id": item.id, "dur": item.dur,
                        "sec": now() - t, "rep": rep, "load": load, "text": text,
                    ]
                    out.write(try JSONSerialization.data(withJSONObject: row) + Data("\n".utf8))
                }
            }
            print("\(config.engine) \(set) done")
        }
    }

    if config.engine.hasPrefix("fluidaudio-") {
        ModelRegistry.revisionOverrides = config.revisions
        let parts = config.engine.split(separator: "@")[0].split(separator: "-").map(String.init)
        let version: AsrModelVersion = ["v2": .v2, "v3": .v3, "ultra": .ultra][parts[1]]!
        let units: MLComputeUnits = parts[2] == "gpu" ? .cpuAndGPU : .cpuAndNeuralEngine
        let root = URL(fileURLWithPath: config.fluidAudioModels)
        let modelDir = root.appendingPathComponent(AsrModels.defaultCacheDirectory(for: version).lastPathComponent)
        _ = try await AsrModels.download(to: modelDir, version: version)
        var booster: ParakeetVocabularyBooster?
        if let vocabulary = config.vocabulary {
            let ctcDir = root.appendingPathComponent(CtcModels.defaultCacheDirectory(for: .ctc110m).lastPathComponent)
            _ = try await CtcModels.download(to: ctcDir, variant: .ctc110m)
            booster = try await ParakeetVocabularyBooster(
                entries: vocabulary.map { VocabularyEntry(term: $0.term, aliases: $0.aliases) },
                modelDirectory: ctcDir,
                tuning: tuning(config.boost))
        }

        let t = now()
        let models = try await AsrModels.load(from: modelDir, version: version, encoderComputeUnits: units)
        let asr = AsrManager(config: .default)
        try await asr.loadModels(models)
        let load = now() - t
        print("\(config.engine): model load \(String(format: "%.2f", load))s")
        let layers = await asr.decoderLayerCount
        let converter = AudioConverter()
        try await runAll(load: load) { url in
            let samples = try converter.resampleAudioFile(url)
            var state = TdtDecoderState.make(decoderLayers: layers)
            let result = try await asr.transcribe(samples, decoderState: &state)
            guard let booster, let timings = result.tokenTimings else { return result.text }
            return await booster.rescore(text: result.text, tokenTimings: timings, samples: samples)
        }
    } else if config.engine == "apple-speechtranscriber" {
        let locale = Locale(identifier: "en_US")
        let t = now()
        let probe = SpeechTranscriber(locale: locale, preset: .transcription)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [probe]) {
            print("installing Apple speech assets for \(locale.identifier)")
            try await request.downloadAndInstall()
        }
        let load = now() - t
        try await runAll(load: load) { url in
            let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
            let file = try AVAudioFile(forReading: url)
            let analyzer = try await SpeechAnalyzer(inputAudioFile: file, modules: [transcriber], finishAfterFile: true)
            var text = ""
            for try await result in transcriber.results where result.isFinal {
                text += String(result.text.characters)
            }
            _ = analyzer
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    } else {
        throw NSError(domain: "STTBench", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unknown engine \(config.engine)"])
    }
}

/// Shipped tuning unless the engine variant overrides a knob. The booster source is OpenScribe's own
/// (Sources/OpenScribe/Providers/ParakeetVocabularyBooster.swift, linked into this target).
func tuning(_ boost: Config.Boost?) -> ParakeetVocabularyBooster.Tuning {
    let shipped = ParakeetVocabularyBooster.shippedTuning
    guard let boost else { return shipped }
    let base = shipped.rescorer
    return .init(
        rescorer: VocabularyRescorer.Config(
            shortTermCbwTaperPivot: boost.taperPivot ?? base.shortTermCbwTaperPivot,
            shortTermCbwTaperExponent: boost.taperExponent ?? base.shortTermCbwTaperExponent,
            spotterRescueMinSimilarity: boost.rescueMinSim ?? base.spotterRescueMinSimilarity,
            spotterRescueMultiWordMinSimilarity: boost.rescueMultiMinSim ?? base.spotterRescueMultiWordMinSimilarity,
            spotterRescueEnabled: boost.rescue ?? base.spotterRescueEnabled),
        minSimilarity: boost.minSimilarity ?? shipped.minSimilarity,
        shortTermMaxLength: boost.shortLength ?? shipped.shortTermMaxLength,
        shortTermMinSimilarity: boost.shortSimilarity ?? shipped.shortTermMinSimilarity)
}

/// Interactive recorder for the developer-terms script: Enter starts, Enter stops, r redoes, s skips.
func recordDevTerms(sentencesPath: String, directory: String) throws {
    struct Sentences: Decodable {
        struct Sentence: Decodable { let id: String; let text: String }
        let sentences: [Sentence]
    }
    let sentences = try JSONDecoder().decode(Sentences.self, from: Data(contentsOf: URL(fileURLWithPath: sentencesPath)))
    let dir = URL(fileURLWithPath: directory)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let settings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16_000, AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
    ]
    let todo = sentences.sentences.filter {
        !FileManager.default.fileExists(atPath: dir.appendingPathComponent("\($0.id).wav").path)
    }
    print("\(todo.count) of \(sentences.sentences.count) sentences left. Read each one naturally, like a dictation.\n")
    var index = 0
    while index < todo.count {
        let s = todo[index]
        print("[\(index + 1)/\(todo.count)] \(s.text)")
        print("  Enter to record, s to skip, q to quit: ", terminator: "")
        let answer = readLine() ?? "q"
        if answer == "q" { break }
        if answer == "s" { index += 1; continue }
        let url = dir.appendingPathComponent("\(s.id).wav")
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.record()
        print("  Recording... Enter to stop: ", terminator: "")
        _ = readLine()
        recorder.stop()
        print("  Saved. Enter to continue, r to redo: ", terminator: "")
        if readLine() == "r" {
            try? FileManager.default.removeItem(at: url)
            continue
        }
        index += 1
    }
}

let args = CommandLine.arguments
if args.count == 4 && args[1] == "record-devterms" {
    try recordDevTerms(sentencesPath: args[2], directory: args[3])
} else if args.count == 2 {
    let config = try JSONDecoder().decode(Config.self, from: Data(args[1].utf8))
    try await runEngine(config)
} else {
    print("usage: STTBench '<json config>' | STTBench record-devterms <sentences.json> <dir>")
    exit(2)
}
