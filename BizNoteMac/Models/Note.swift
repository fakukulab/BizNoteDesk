import SwiftData
import Foundation
import SwiftUI

@Model
final class Note {
    static let customCategoryRawValue = "custom"

    var id: UUID = UUID()
    var title: String = ""
    var categoryRaw: String = NoteCategory.workLog.rawValue
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var content: String = ""
    var tags: [String] = []

    var templateData: String = "{}"

    @Relationship(deleteRule: .nullify, inverse: \BusinessCard.note)
    var businessCards: [BusinessCard]? = []

    @Relationship(deleteRule: .nullify)
    var customCategory: CustomCategory? = nil

    var attachmentPaths: [String] = []

    var isFavorite: Bool = false

    var category: NoteCategory {
        get { NoteCategory(rawValue: categoryRaw) ?? .workLog }
        set { categoryRaw = newValue.rawValue }
    }

    var isCustomCategory: Bool { categoryRaw == Note.customCategoryRawValue }

    var categorySelection: NoteCategorySelection {
        get {
            if isCustomCategory, let customCategory {
                return .custom(customCategory)
            }
            return .builtin(category)
        }
        set {
            switch newValue {
            case .builtin(let c):
                categoryRaw = c.rawValue
                customCategory = nil
            case .custom(let c):
                categoryRaw = Note.customCategoryRawValue
                customCategory = c
            }
        }
    }

    var categoryName: String { categorySelection.localizedName }
    var categoryIconName: String { categorySelection.systemIconName }
    var categoryAccentColor: Color { categorySelection.accentColor }

    /// The date shown in note lists — the date recorded inside the note's own
    /// template content (work log date, meeting date, exhibition date) rather
    /// than the note's last-modified timestamp, so it stays in sync whenever
    /// that in-note date is edited.
    var contentDate: Date {
        guard !isCustomCategory else { return updatedAt }
        switch category {
        case .workLog:
            return workLogTemplate?.date ?? updatedAt
        case .meetingMinutes:
            return meetingTemplate?.meetingDate ?? updatedAt
        case .exhibition:
            return exhibitionTemplate?.participatingDate ?? updatedAt
        }
    }

    /// Decodes the work log template. When the stored JSON has no `date` yet
    /// (e.g. a note created with an empty "{}" template), the note's creation
    /// date is used instead of today, so the work log date doesn't silently
    /// move to the current day every time the note is read.
    var workLogTemplate: WorkLogTemplateData? {
        guard var data = TemplateCoder.decode(WorkLogTemplateData.self, from: templateData) else { return nil }
        if !TemplateCoder.containsKey("date", in: templateData) {
            data.date = createdAt
        }
        return data
    }

    /// Same as `workLogTemplate`: a missing meeting date falls back to the
    /// note's creation date instead of today.
    var meetingTemplate: MeetingMinutesTemplateData? {
        guard var data = TemplateCoder.decode(MeetingMinutesTemplateData.self, from: templateData) else { return nil }
        if !TemplateCoder.containsKey("meetingDate", in: templateData) {
            data.meetingDate = createdAt
        }
        return data
    }

    /// Same as `workLogTemplate`: missing exhibition dates fall back to the
    /// note's creation date instead of today.
    var exhibitionTemplate: ExhibitionTemplateData? {
        guard var data = TemplateCoder.decode(ExhibitionTemplateData.self, from: templateData) else { return nil }
        if !TemplateCoder.containsKey("participatingDate", in: templateData) {
            data.participatingDate = createdAt
        }
        if !TemplateCoder.containsKey("eventStartDate", in: templateData) {
            data.eventStartDate = createdAt
        }
        if !TemplateCoder.containsKey("eventEndDate", in: templateData) {
            data.eventEndDate = createdAt
        }
        return data
    }

    init(
        title: String = "",
        category: NoteCategory = .workLog,
        content: String = ""
    ) {
        self.id = UUID()
        self.title = title
        self.categoryRaw = category.rawValue
        self.content = content
        self.createdAt = Date()
        self.updatedAt = Date()
        self.tags = []
        switch category {
        case .workLog:
            var workLog = WorkLogTemplateData()
            workLog.date = self.createdAt
            self.templateData = TemplateCoder.encode(workLog)
        case .meetingMinutes:
            var meeting = MeetingMinutesTemplateData()
            meeting.meetingDate = self.createdAt
            self.templateData = TemplateCoder.encode(meeting)
        case .exhibition:
            var exhibition = ExhibitionTemplateData()
            exhibition.participatingDate = self.createdAt
            exhibition.eventStartDate = self.createdAt
            exhibition.eventEndDate = self.createdAt
            self.templateData = TemplateCoder.encode(exhibition)
        }
        self.businessCards = []
        self.customCategory = nil
        self.attachmentPaths = []
        self.isFavorite = false
    }

    init(title: String, customCategory: CustomCategory, content: String = "") {
        self.id = UUID()
        self.title = title
        self.categoryRaw = Note.customCategoryRawValue
        self.content = content
        self.createdAt = Date()
        self.updatedAt = Date()
        self.tags = []
        self.templateData = "{}"
        self.businessCards = []
        self.customCategory = customCategory
        self.attachmentPaths = []
        self.isFavorite = false
    }
}
