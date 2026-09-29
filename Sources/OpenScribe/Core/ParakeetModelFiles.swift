import Foundation

/// Pinned Core ML files for the Parakeet engine, generated with Scripts/pin_model_files.py.
/// Regenerate both lists together when moving to a new model revision.
enum ParakeetModelFiles {
    static let ultraRepository = "FluidInference/parakeet-ultra-coreml"
    static let ultraRevision = "95eaa59a39d4394f047a4dc5cce480388a60d1b6"
    static let vocabularyBoostRepository = "FluidInference/parakeet-ctc-110m-coreml"
    static let vocabularyBoostRevision = "accdafd8cf8a2ff1cabe3c11e54416b405d409aa"

    // FluidInference/parakeet-ultra-coreml at 95eaa59a39d4394f047a4dc5cce480388a60d1b6
    static let ultraFiles: [ModelAssetFile] = [
        .init(path: "Decoder.mlmodelc/analytics/coremldata.bin", sizeBytes: 243, sha256: "fe92b6cfaa012abd5248c0bc877832f19807015abffc60d87b8ccc8ccb48b3b5"),
        .init(path: "Decoder.mlmodelc/coremldata.bin", sizeBytes: 560, sha256: "3b06e66768f0df7e21795f50e2b29300e33eeb1a2579dc42c695279c2d308497"),
        .init(path: "Decoder.mlmodelc/model.mil", sizeBytes: 13110, sha256: "956f600207f88396017ca5c96cfa3acd5bfee60835a5b44b762e033a8fb28955"),
        .init(path: "Decoder.mlmodelc/weights/weight.bin", sizeBytes: 23604992, sha256: "02a0d219f281b9665bc10c8768649403b2eebbbf4b44c627041d948e0de11bb4"),
        .init(path: "Encoder.mlmodelc/analytics/coremldata.bin", sizeBytes: 243, sha256: "d87101d824d6723cf95304da33755c3c60e762663b9ef2b0c4bd0aa166a09a0d"),
        .init(path: "Encoder.mlmodelc/coremldata.bin", sizeBytes: 514, sha256: "397a84a4062f563cbc5f56077c674f09a61d85be5090f61d2f1932afb92ac0fe"),
        .init(path: "Encoder.mlmodelc/model.mil", sizeBytes: 1002653, sha256: "f5d601568a4171d99a314c0fe3f6bc67715da2623732a3fb566e050ea83e5848"),
        .init(path: "Encoder.mlmodelc/weights/weight.bin", sizeBytes: 594211328, sha256: "315ba01f33cadbf601d43ac7f5c86208b7aa75fdaa34705c9869d5abe3521c9b"),
        .init(path: "JointDecisionv3.mlmodelc/analytics/coremldata.bin", sizeBytes: 243, sha256: "68d38ca646aebafa7a9329e2efda50f5767c49e89fdb5f77f212072bb66f97c4"),
        .init(path: "JointDecisionv3.mlmodelc/coremldata.bin", sizeBytes: 592, sha256: "5e3af5a4ce686f6c237cadbd9284e10d333bc0e1546633cd0e430e6194044bc4"),
        .init(path: "JointDecisionv3.mlmodelc/model.mil", sizeBytes: 11777, sha256: "791b3c3cf3eb2079c84623fc880f6bba008d1366e5f8b03e9a8ed8bd4d7194a0"),
        .init(path: "JointDecisionv3.mlmodelc/weights/weight.bin", sizeBytes: 12642764, sha256: "3f310b85b82341c53ec383025ab094a4e462ee1c592e1ad7c6bfe39cff66ca25"),
        .init(path: "Preprocessor.mlmodelc/analytics/coremldata.bin", sizeBytes: 243, sha256: "c9beeb989c8d66f8be11df59bc6df277ec76cee404f6865b46243835ef562f6d"),
        .init(path: "Preprocessor.mlmodelc/coremldata.bin", sizeBytes: 486, sha256: "dbde3f2300842c1fd51ef3ff948a0bcffe65ffd2dca10707f2509f32c1d65b1d"),
        .init(path: "Preprocessor.mlmodelc/metadata.json", sizeBytes: 2841, sha256: "2a98699e22d279dd37fa1d238aeb1c6db1df0d6fad687775324157689d8f3acf"),
        .init(path: "Preprocessor.mlmodelc/model.mil", sizeBytes: 28181, sha256: "4b8518a956450fec57f06c2a21bdffc26973f7f1fa6842fb38fe917f896b6b93"),
        .init(path: "Preprocessor.mlmodelc/weights/weight.bin", sizeBytes: 491072, sha256: "129b76e3aeafa8afa3ea76d995b964b145fe83700d579f6ff42c4c38fa0968ea"),
        .init(path: "config.json", sizeBytes: 414, sha256: "965c69bf500c7be18958df6438dc1ba897721690ae412937ca7c91e28cec1870"),
        .init(path: "parakeet_v3_vocab.json", sizeBytes: 151122, sha256: "7ec60e05f1b24480736ec0eed40900f4626bce1fa9a60fd700ec7e2a59198735"),
        .init(path: "parakeet_vocab.json", sizeBytes: 151122, sha256: "7ec60e05f1b24480736ec0eed40900f4626bce1fa9a60fd700ec7e2a59198735")
    ]

    // FluidInference/parakeet-ctc-110m-coreml at accdafd8cf8a2ff1cabe3c11e54416b405d409aa
    static let vocabularyBoostFiles: [ModelAssetFile] = [
        .init(path: "AudioEncoder.mlmodelc/analytics/coremldata.bin", sizeBytes: 243, sha256: "8906c823e9bb3bf6b16d9f0308f98cd70573526333ad85dd767dc3f9ae6b25fa"),
        .init(path: "AudioEncoder.mlmodelc/coremldata.bin", sizeBytes: 505, sha256: "a88b002b58193b4c31211754cdfdf220a85f9651dc61caf336ab84400cbc191a"),
        .init(path: "AudioEncoder.mlmodelc/metadata.json", sizeBytes: 3456, sha256: "4f288bfe5cbe867ef1e592cdae33578b2fe59ada69182fc12209879558f985c2"),
        .init(path: "AudioEncoder.mlmodelc/model.mil", sizeBytes: 1060924, sha256: "2f84ef93a69115e55f3b5d8ce695b3c937de1833d4d229620634fae967cd587e"),
        .init(path: "AudioEncoder.mlmodelc/weights/weight.bin", sizeBytes: 100778304, sha256: "af0734b4a5d7465ad9e8bb170f0c53c5e6b91ebb75a9bdf88d3f59ae4ad6aebd"),
        .init(path: "MelSpectrogram.mlmodelc/analytics/coremldata.bin", sizeBytes: 243, sha256: "22f2a8cba1de25c984050566b534a1d8caf22a82f9fe6c1c6f3149a0dd7e8ae3"),
        .init(path: "MelSpectrogram.mlmodelc/coremldata.bin", sizeBytes: 330, sha256: "3a32ec67c76aa0aa2faef518413c311493e89aeb7fa11289fa4b8653ab8a160c"),
        .init(path: "MelSpectrogram.mlmodelc/metadata.json", sizeBytes: 1962, sha256: "5e11d21a65c02bcfc37db43e941978e5d60d59e0efeadfda08e41f33b4f835d3"),
        .init(path: "MelSpectrogram.mlmodelc/model.mil", sizeBytes: 12584, sha256: "0a7cb5693b39667295218bac5c7c09053f6bcd4b32699a83d06ac35d14ac6b79"),
        .init(path: "MelSpectrogram.mlmodelc/weights/weight.bin", sizeBytes: 567712, sha256: "0a89c055bfde9022029d3cc59a23e949385e063974460d8eaec3a7614c3eaaa8"),
        .init(path: "tokenizer.json", sizeBytes: 360106, sha256: "9f7c517c0bf644b1b690ab037bab4d4c53aecd38e047e7154d011013ab9160db"),
        .init(path: "vocab.json", sizeBytes: 16086, sha256: "319d386eead79aadc80df9c3ecc8340d1a727efb7c02a8847eb940380dd61e1f")
    ]
}
