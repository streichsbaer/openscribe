import Foundation

enum InstructionEditorTarget: Hashable {
    case transcription
    case polish
}

enum InstructionPersistenceChange: Equatable {
    case none
    case setTranscription(String?)
    case setPolish(String?)
}

struct InstructionEditorPersistence {
    static func changeOnDone(
        target: InstructionEditorTarget,
        transcriptionDraft: String,
        storedTranscription: String?,
        polishDraft: String,
        storedPolish: String?
    ) -> InstructionPersistenceChange {
        switch target {
        case .transcription:
            return changeForTranscription(draft: transcriptionDraft, stored: storedTranscription)
        case .polish:
            return changeForPolish(draft: polishDraft, stored: storedPolish)
        }
    }

    static func changesOnFocusChange(
        from oldFocus: InstructionEditorTarget?,
        to newFocus: InstructionEditorTarget?,
        transcriptionDraft: String,
        storedTranscription: String?,
        polishDraft: String,
        storedPolish: String?
    ) -> [InstructionPersistenceChange] {
        var changes: [InstructionPersistenceChange] = []

        if oldFocus == .transcription, newFocus != .transcription {
            let change = changeForTranscription(draft: transcriptionDraft, stored: storedTranscription)
            if change != .none {
                changes.append(change)
            }
        }

        if oldFocus == .polish, newFocus != .polish {
            let change = changeForPolish(draft: polishDraft, stored: storedPolish)
            if change != .none {
                changes.append(change)
            }
        }

        return changes
    }

    private static func changeForTranscription(draft: String, stored: String?) -> InstructionPersistenceChange {
        let normalized = normalizedInstruction(draft)
        guard normalized != stored else {
            return .none
        }
        return .setTranscription(normalized)
    }

    private static func changeForPolish(draft: String, stored: String?) -> InstructionPersistenceChange {
        let normalized = normalizedInstruction(draft)
        guard normalized != stored else {
            return .none
        }
        return .setPolish(normalized)
    }
}
