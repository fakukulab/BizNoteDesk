import SwiftUI
import SwiftData

struct NoteDetailView: View {
    @Bindable var note: Note
    var onOpenMeeting: (Note) -> Void = { _ in }
    @Query(filter: #Predicate<Note> { $0.categoryRaw == "meeting_minutes" })
    private var meetingNotes: [Note]
    @Environment(\.modelContext) private var context

    @State private var isEditing: Bool
    @State private var workLog: WorkLogTemplateData = .init()
    @State private var meeting: MeetingMinutesTemplateData = .init()
    @State private var exhibition: ExhibitionTemplateData = .init()
    @State private var customTemplate: CustomNoteTemplateData = .init()

    init(note: Note, startsEditing: Bool = false, onOpenMeeting: @escaping (Note) -> Void = { _ in }) {
        self.note = note
        self.onOpenMeeting = onOpenMeeting
        _isEditing = State(initialValue: startsEditing)
        if note.isCustomCategory {
            let stored = TemplateCoder.decode(CustomNoteTemplateData.self, from: note.templateData)
            let defaults = note.customCategory.flatMap {
                TemplateCoder.decode(CustomNoteTemplateData.self, from: $0.templateData)
            }
            _customTemplate = State(initialValue: stored ?? defaults ?? .init())
        } else {
            switch note.category {
            case .workLog:
                _workLog = State(initialValue: note.workLogTemplate ?? .init())
            case .meetingMinutes:
                _meeting = State(initialValue: note.meetingTemplate ?? .init())
            case .exhibition:
                _exhibition = State(initialValue: note.exhibitionTemplate ?? .init())
            }
        }
    }

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

                TagEditorView(tags: $note.tags, isEditing: isEditing)
            }
            .padding(20)
        }
        .navigationTitle(note.title.isEmpty ? String(localized: "note.untitled") : note.title)
        .onChange(of: isEditing, initial: true) { _, editing in
            if editing { updateWorkLogTitleIfNeeded() }
        }
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

    private var editActionTitle: String {
        isEditing
            ? String(localized: "note.edit.done", defaultValue: "편집 완료")
            : String(localized: "note.edit.start", defaultValue: "노트 수정")
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

                Group {
                    if isEditing {
                        TextField(String(localized: "note.title.placeholder"), text: $note.title)
                            .textFieldStyle(.plain)
                            .accessibilityLabel(String(localized: "note.title.placeholder"))
                    } else {
                        Text(note.title.isEmpty ? String(localized: "note.untitled") : note.title)
                    }
                }
                .font(.title.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    isEditing.toggle()
                } label: {
                    Label(editActionTitle, systemImage: isEditing ? "checkmark" : "pencil")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.bordered)
                .help(editActionTitle)
                .accessibilityIdentifier("note.edit.toggle")
            }

            HStack(spacing: 8) {
                Label(note.categoryName, systemImage: note.categoryIconName)
                    .foregroundStyle(note.categoryAccentColor)
                    .font(.callout)

                if isMeeting {
                    noteDate($meeting.meetingDate, includesTime: true)
                } else if isExhibition {
                    noteDate($exhibition.participatingDate)
                } else if isWorkLog {
                    noteDate($workLog.date)
                }

                Spacer()

                Text(note.updatedAt, format: .dateTime.year().month().day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func noteDate(_ date: Binding<Date>, includesTime: Bool = false) -> some View {
        if isEditing {
            DatePicker("", selection: date, displayedComponents: includesTime ? [.date, .hourAndMinute] : .date)
                .labelsHidden()
                .font(.callout)
        } else {
            Text(date.wrappedValue, format: includesTime
                 ? .dateTime.year().month().day().hour().minute()
                 : .dateTime.year().month().day())
                .font(.callout)
        }
    }

    private var freeMemoField: some View {
        NoteMemoEditor(text: $note.content, rtf: isMeeting ? $meeting.memoRTFData : $note.contentRTFData)
            .frame(height: note.isCustomCategory ? 220 : 120)
            .disabled(!isEditing)
    }

    private var meetingsOnWorkLogDate: [Note] {
        meetingNotes.filter { Calendar.current.isDate($0.contentDate, inSameDayAs: workLog.date) }
            .sorted { $0.contentDate < $1.contentDate }
    }

    @ViewBuilder
    private var templateSection: some View {
        if note.isCustomCategory {
            if !customTemplate.sections.isEmpty {
                CustomNoteTemplateView(data: $customTemplate, attachmentPaths: $note.attachmentPaths, isEditing: isEditing)
            }
        } else {
            switch note.category {
            case .workLog:
                WorkLogTemplateView(data: $workLog, attachmentPaths: $note.attachmentPaths,
                                    isEditing: isEditing, meetings: meetingsOnWorkLogDate, onOpenMeeting: onOpenMeeting)
            case .meetingMinutes:
                MeetingMinutesTemplateView(data: $meeting, businessCards: note.businessCards ?? [])
                    .disabled(!isEditing)
            case .exhibition:
                ExhibitionTemplateView(data: $exhibition, businessCards: note.businessCards ?? [])
                    .disabled(!isEditing)
            }
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
