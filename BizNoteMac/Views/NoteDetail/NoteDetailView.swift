import SwiftUI
import SwiftData

struct NoteDetailView: View {
    @Bindable var note: Note
    var onOpenMeeting: (Note) -> Void = { _ in }
    @Query(filter: #Predicate<Note> { $0.categoryRaw == "meeting_minutes" })
    private var meetingNotes: [Note]
    @Environment(\.modelContext) private var context

    @State private var workLog: WorkLogTemplateData = .init()
    @State private var meeting: MeetingMinutesTemplateData = .init()
    @State private var exhibition: ExhibitionTemplateData = .init()
    @State private var customTemplate: CustomNoteTemplateData = .init()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                Divider()

                templateSection

                NoteTemplateSection(title: String(localized: "note.freeMemo")) {
                    freeMemoField
                }

                Divider()

                TagEditorView(tags: $note.tags)
            }
            .padding(20)
        }
        .navigationTitle(note.title.isEmpty ? String(localized: "note.untitled") : note.title)
        .onAppear(perform: loadTemplate)
        .onChange(of: workLog) { old, new in
            save(template: new)
            updateWorkLogTitleIfNeeded()
            if old.workItems != new.workItems || old.date != new.date {
                syncWorkLogReminders()
            }
            if old.majorEvents != new.majorEvents || old.date != new.date {
                CalendarReminderSyncService.shared.scheduleWorkLogSync(for: note, previous: old)
            }
        }
        .onChange(of: meeting) { old, new in
            save(template: new)
            if old.actionItems != new.actionItems {
                syncMeetingReminders()
            }
        }
        .onChange(of: exhibition) { _, new in
            save(template: new)
            syncExhibitionReminders()
        }
        .onChange(of: customTemplate) { _, new in
            save(template: new)
        }
        .onChange(of: note.title) { _, _ in touch() }
        .onChange(of: note.content) { _, _ in touch() }
        .onChange(of: note.contentRTFData) { _, _ in touch() }
        .onChange(of: note.tags) { _, _ in touch() }
        .onChange(of: note.attachmentPaths) { _, _ in touch() }
    }

    private var isWorkLog: Bool { !note.isCustomCategory && note.category == .workLog }
    private var isMeeting: Bool { !note.isCustomCategory && note.category == .meetingMinutes }
    private var isExhibition: Bool { !note.isCustomCategory && note.category == .exhibition }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    note.isFavorite.toggle()
                } label: {
                    Image(systemName: note.isFavorite ? "star.fill" : "star")
                        .foregroundStyle(note.isFavorite ? .yellow : .secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(note.isFavorite
                                    ? String(localized: "note.unfavorite")
                                    : String(localized: "note.favorite"))

                if isWorkLog {
                    Text(note.title.isEmpty ? String(localized: "note.untitled") : note.title)
                        .font(.title.weight(.semibold))
                } else {
                    TextField(String(localized: "note.title.placeholder"), text: $note.title)
                        .font(.title.weight(.semibold))
                        .textFieldStyle(.plain)
                        .accessibilityLabel(String(localized: "note.title.placeholder"))
                }
            }

            HStack(spacing: 8) {
                Label(note.categoryName, systemImage: note.categoryIconName)
                    .foregroundStyle(note.categoryAccentColor)
                    .font(.callout)

                if isMeeting {
                    DatePicker("", selection: $meeting.meetingDate)
                        .labelsHidden()
                        .font(.callout)
                } else if isExhibition {
                    DatePicker("", selection: $exhibition.participatingDate, displayedComponents: .date)
                        .labelsHidden()
                        .font(.callout)
                } else if isWorkLog {
                    DatePicker("", selection: $workLog.date, displayedComponents: .date)
                        .labelsHidden()
                        .font(.callout)
                }

                Spacer()

                Text(note.updatedAt, format: .dateTime.year().month().day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var freeMemoField: some View {
        NoteMemoEditor(text: $note.content, rtf: isMeeting ? $meeting.memoRTFData : $note.contentRTFData)
            .frame(height: note.isCustomCategory ? 220 : 120)
    }

    private var meetingsOnWorkLogDate: [Note] {
        meetingNotes.filter { Calendar.current.isDate($0.contentDate, inSameDayAs: workLog.date) }
            .sorted { $0.contentDate < $1.contentDate }
    }

    @ViewBuilder
    private var templateSection: some View {
        if note.isCustomCategory {
            if !customTemplate.sections.isEmpty {
                CustomNoteTemplateView(data: $customTemplate, attachmentPaths: $note.attachmentPaths)
            }
        } else {
            switch note.category {
            case .workLog:
                WorkLogTemplateView(data: $workLog, attachmentPaths: $note.attachmentPaths,
                                    meetings: meetingsOnWorkLogDate, onOpenMeeting: onOpenMeeting)
            case .meetingMinutes:
                MeetingMinutesTemplateView(data: $meeting, businessCards: note.businessCards ?? [])
            case .exhibition:
                ExhibitionTemplateView(data: $exhibition, businessCards: note.businessCards ?? [])
            }
        }
    }

    private func loadTemplate() {
        if note.isCustomCategory {
            let storedTemplate = TemplateCoder.decode(CustomNoteTemplateData.self, from: note.templateData)
            let categoryTemplate = note.customCategory.flatMap { TemplateCoder.decode(CustomNoteTemplateData.self, from: $0.templateData) }
            customTemplate = storedTemplate ?? categoryTemplate ?? .init()
            if storedTemplate == nil, let categoryTemplate {
                note.templateData = TemplateCoder.encode(categoryTemplate)
            }
            return
        }
        switch note.category {
        case .workLog:
            workLog = note.workLogTemplate ?? .init()
            updateWorkLogTitleIfNeeded()
        case .meetingMinutes:
            meeting = note.meetingTemplate ?? .init()
        case .exhibition:
            exhibition = note.exhibitionTemplate ?? .init()
        }
    }

    private func updateWorkLogTitleIfNeeded() {
        guard isWorkLog, shouldUseAutomaticWorkLogTitle else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateStr = formatter.string(from: workLog.date)
        let suffix = String(localized: "workLog.title.autoSuffix", defaultValue: "업무일지")
        let newTitle = "\(dateStr) \(suffix)"
        if note.title != newTitle {
            note.title = newTitle
        }
    }

    private var shouldUseAutomaticWorkLogTitle: Bool {
        let title = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return true }
        let suffix = String(localized: "workLog.title.autoSuffix", defaultValue: "업무일지")
        guard title.hasSuffix(" " + suffix) else { return false }
        let datePrefix = title.prefix(10)
        return datePrefix.count == 10
            && datePrefix.dropFirst(4).first == "-"
            && datePrefix.dropFirst(7).first == "-"
    }

    private func save<T: Codable>(template: T) {
        let encoded = TemplateCoder.encode(template)
        if encoded != note.templateData {
            note.templateData = encoded
            touch()
        }
    }

    private func touch() {
        note.updatedAt = Date()
        try? context.save()
    }

    private func syncWorkLogReminders() {
        for item in workLog.workItems where !item.task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let itemID = item.id
            Task {
                let reminderID = await CalendarReminderSyncService.shared.syncReminder(
                    title: item.task,
                    detail: item.status.localizedName,
                    assignees: [],
                    dueDate: workLog.date,
                    isCompleted: item.status == .done,
                    existingIdentifier: item.reminderIdentifier
                )
                guard let reminderID,
                      let index = workLog.workItems.firstIndex(where: { $0.id == itemID }),
                      workLog.workItems[index].reminderIdentifier != reminderID else { return }
                workLog.workItems[index].reminderIdentifier = reminderID
            }
        }
    }

    private func syncMeetingReminders() {
        for item in meeting.actionItems where !item.task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let itemID = item.id
            Task {
                let reminderID = await CalendarReminderSyncService.shared.syncReminder(
                    title: item.task,
                    detail: item.detail,
                    assignees: item.assignees,
                    dueDate: item.dueDate,
                    isCompleted: item.isCompleted,
                    existingIdentifier: item.reminderIdentifier
                )
                guard let reminderID,
                      let index = meeting.actionItems.firstIndex(where: { $0.id == itemID }),
                      meeting.actionItems[index].reminderIdentifier != reminderID else { return }
                meeting.actionItems[index].reminderIdentifier = reminderID
            }
        }
    }

    private func syncExhibitionReminders() {
        for item in exhibition.tasks where !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let itemID = item.id
            Task {
                let reminderID = await CalendarReminderSyncService.shared.syncReminder(
                    title: item.title,
                    detail: item.detail,
                    assignees: item.assignees,
                    dueDate: item.dueDate,
                    isCompleted: item.isCompleted,
                    existingIdentifier: item.reminderIdentifier
                )
                guard let reminderID,
                      let index = exhibition.tasks.firstIndex(where: { $0.id == itemID }),
                      exhibition.tasks[index].reminderIdentifier != reminderID else { return }
                exhibition.tasks[index].reminderIdentifier = reminderID
            }
        }
    }
}
