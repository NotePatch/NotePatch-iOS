import Foundation
import Combine

@MainActor
final class HomeDashboardState: ObservableObject {
    @Published var destination: HomeDestination?
    @Published private(set) var documentCount = 0
    @Published private(set) var recentDocuments: [LearningDocumentItem] = []
    @Published private(set) var activeTask: TaskItem?
    @Published private(set) var recentNotes: [StudyNoteListItem] = []
    @Published private(set) var learningUnitCount = 0
    @Published private(set) var homeworkCount = 0
    @Published private(set) var isLoadingSupplementaryContent = false
    @Published private var supplementaryErrorText: AppDisplayText?

    var supplementaryError: String? {
        supplementaryErrorText?.resolved()
    }

    func updateDocuments(_ documents: [LearningDocumentItem]) {
        let next = Array(documents.enumerated().sorted(by: Self.documentSort).map(\.element).prefix(5))
        if documentCount != documents.count {
            documentCount = documents.count
        }
        if next != recentDocuments {
            recentDocuments = next
        }
    }

    func updateActiveTask(_ task: TaskItem?) {
        guard task != activeTask else { return }
        activeTask = task
    }

    func beginSupplementaryLoad() {
        supplementaryErrorText = nil
        isLoadingSupplementaryContent = true
    }

    func applySupplementaryContent(
        learningUnits: [LearningUnit],
        homeworks: [HomeworkItem],
        noteGroups: [StudyNoteGroup]
    ) {
        let nextNotes = noteGroups
            .flatMap(\.notes)
            .enumerated()
            .sorted(by: Self.noteSort)
            .map(\.element)
        learningUnitCount = learningUnits.count
        homeworkCount = homeworks.count
        recentNotes = Array(nextNotes.prefix(3))
        supplementaryErrorText = nil
        isLoadingSupplementaryContent = false
    }

    func finishSupplementaryLoad(error: AppDisplayText?) {
        supplementaryErrorText = error
        isLoadingSupplementaryContent = false
    }

    func reset() {
        destination = nil
        documentCount = 0
        recentDocuments = []
        activeTask = nil
        recentNotes = []
        learningUnitCount = 0
        homeworkCount = 0
        isLoadingSupplementaryContent = false
        supplementaryErrorText = nil
    }

    private static func documentSort(
        _ lhs: EnumeratedSequence<[LearningDocumentItem]>.Element,
        _ rhs: EnumeratedSequence<[LearningDocumentItem]>.Element
    ) -> Bool {
        let leftDate = lhs.element.updatedAt.trimmingCharacters(in: .whitespacesAndNewlines)
        let rightDate = rhs.element.updatedAt.trimmingCharacters(in: .whitespacesAndNewlines)
        if leftDate.isEmpty != rightDate.isEmpty {
            return !leftDate.isEmpty
        }
        if !leftDate.isEmpty, leftDate != rightDate {
            return leftDate > rightDate
        }
        return lhs.offset < rhs.offset
    }

    private static func noteSort(
        _ lhs: EnumeratedSequence<[StudyNoteListItem]>.Element,
        _ rhs: EnumeratedSequence<[StudyNoteListItem]>.Element
    ) -> Bool {
        let leftDate = (lhs.element.note.createdAt ?? lhs.element.learningUnit.updatedAt ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let rightDate = (rhs.element.note.createdAt ?? rhs.element.learningUnit.updatedAt ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if leftDate.isEmpty != rightDate.isEmpty {
            return !leftDate.isEmpty
        }
        if !leftDate.isEmpty, leftDate != rightDate {
            return leftDate > rightDate
        }
        if lhs.element.note.versionNo != rhs.element.note.versionNo {
            return lhs.element.note.versionNo > rhs.element.note.versionNo
        }
        return lhs.offset < rhs.offset
    }
}
