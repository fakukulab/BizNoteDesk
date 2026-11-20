import EventKit
import Foundation
import SwiftData

@MainActor
final class CalendarReminderSyncService {
    static let shared = CalendarReminderSyncService()

    struct Destination: Identifiable, Equatable {
        let id: String
        let title: String
        let sourceTitle: String
    }

    private let eventStore = EKEventStore()
    private let defaults = UserDefaults.standard
    private let calendarIdentifierKey = "integration.selectedEventCalendarIdentifier"
    private var workLogSyncTasks: [UUID: Task<Void, Never>] = [:]
    private var pendingWorkLogEventRemovals: [UUID: [UUID: Date]] = [:]
    private let reminderListIdentifierKey = "integration.selectedReminderListIdentifier"

    private init() {}

    func eventCalendars(requestAccess: Bool) async -> [Destination] {
        guard await hasEventAccess(requestIfNeeded: requestAccess) else { return [] }
        return destinations(for: .event)
    }

    func reminderLists(requestAccess: Bool) async -> [Destination] {
        guard await hasReminderAccess(requestIfNeeded: requestAccess) else { return [] }
        return destinations(for: .reminder)
    }

    func syncEvent(for preset: ExhibitionPreset) async {
        guard defaults.bool(forKey: "integration.syncEventsWithCalendar"),
              await hasEventAccess(requestIfNeeded: true),
              let calendar = selectedCalendar(for: .event, identifierKey: calendarIdentifierKey) else { return }

        let event = preset.calendarEventIdentifier
            .flatMap { eventStore.event(withIdentifier: $0) }
            ?? EKEvent(eventStore: eventStore)

        event.calendar = calendar
        event.title = preset.name.isEmpty ? String(localized: "note.untitled") : preset.name
        event.startDate = Calendar.current.startOfDay(for: preset.startDate)
        event.endDate = allDayEndDate(for: preset.endDate)
        event.isAllDay = true
        event.location = preset.venue
        event.notes = eventNotes(for: preset)

        do {
            try eventStore.save(event, span: .thisEvent, commit: true)
            preset.calendarEventIdentifier = event.eventIdentifier
        } catch {
            eventStore.reset()
        }
    }

    func removeEvent(for preset: ExhibitionPreset) async {
        guard let identifier = preset.calendarEventIdentifier,
              await hasEventAccess(requestIfNeeded: false),
              let event = eventStore.event(withIdentifier: identifier) else { return }
        do {
            try eventStore.remove(event, span: .thisEvent, commit: true)
        } catch {
            eventStore.reset()
        }
    }

    func scheduleWorkLogSync(for note: Note, previous: WorkLogTemplateData) {
        let noteID = note.id
        let currentIDs = Set(note.workLogTemplate?.majorEvents.map(\.id) ?? [])
        for event in previous.majorEvents where !currentIDs.contains(event.id) {
            pendingWorkLogEventRemovals[noteID, default: [:]][event.id] = previous.date
        }

        workLogSyncTasks[noteID]?.cancel()
        workLogSyncTasks[noteID] = Task { [weak note] in
            do {
                try await Task.sleep(for: .milliseconds(400))
            } catch {
                return
            }
            await syncWorkLogEvents(for: note)
            guard !Task.isCancelled else { return }
            workLogSyncTasks[noteID] = nil
        }
    }

    func syncWorkLogEvents(for note: Note?) async {
        guard let note, !note.isDeleted,
              note.categoryRaw == NoteCategory.workLog.rawValue,
              let initial = note.workLogTemplate,
              !initial.majorEvents.isEmpty || pendingWorkLogEventRemovals[note.id] != nil,
              defaults.bool(forKey: "integration.syncEventsWithCalendar"),
              await hasEventAccess(requestIfNeeded: true),
              !Task.isCancelled, !note.isDeleted, note.modelContext != nil,
              let data = note.workLogTemplate,
              let calendar = selectedCalendar(for: .event, identifierKey: calendarIdentifierKey) else { return }

        let currentIDs = Set(data.majorEvents.map(\.id))
        let removed = pendingWorkLogEventRemovals.removeValue(forKey: note.id) ?? [:]
        for (id, date) in removed where !currentIDs.contains(id) {
            if !removeWorkLogEvent(id: id, date: date) {
                pendingWorkLogEventRemovals[note.id, default: [:]][id] = date
            }
        }

        for entry in data.majorEvents {
            let title = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else {
                _ = removeWorkLogEvent(id: entry.id, date: data.date)
                continue
            }
            let event = findWorkLogEvent(id: entry.id, date: data.date) ?? EKEvent(eventStore: eventStore)
            let start = Calendar.current.startOfDay(for: data.date)
            let end = allDayEndDate(for: data.date)
            if event.calendar?.calendarIdentifier == calendar.calendarIdentifier,
               event.title == title, event.startDate == start, event.endDate == end, event.isAllDay {
                continue
            }
            event.calendar = calendar
            event.title = title
            event.isAllDay = true
            event.startDate = start
            event.endDate = end
            event.url = workLogEventURL(for: entry.id)
            do {
                try eventStore.save(event, span: .thisEvent, commit: true)
                defaults.set(event.eventIdentifier, forKey: workLogEventKey(for: entry.id))
            } catch {
                eventStore.reset()
            }
        }
    }

    func removeWorkLogEvents(noteID: UUID, data: WorkLogTemplateData) async {
        workLogSyncTasks.removeValue(forKey: noteID)?.cancel()
        var removed = pendingWorkLogEventRemovals.removeValue(forKey: noteID) ?? [:]
        for entry in data.majorEvents {
            removed[entry.id] = data.date
        }
        guard !removed.isEmpty, await hasEventAccess(requestIfNeeded: false) else { return }
        for (id, date) in removed {
            _ = removeWorkLogEvent(id: id, date: date)
        }
    }

    private func removeWorkLogEvent(id: UUID, date: Date) -> Bool {
        if let event = findWorkLogEvent(id: id, date: date) {
            do {
                try eventStore.remove(event, span: .thisEvent, commit: true)
            } catch {
                eventStore.reset()
                return false
            }
        }
        defaults.removeObject(forKey: workLogEventKey(for: id))
        return true
    }

    private func findWorkLogEvent(id: UUID, date: Date) -> EKEvent? {
        let url = workLogEventURL(for: id)
        if let identifier = defaults.string(forKey: workLogEventKey(for: id)),
           let event = eventStore.event(withIdentifier: identifier), event.url == url {
            return event
        }
        let predicate = eventStore.predicateForEvents(withStart: Calendar.current.startOfDay(for: date),
                                                     end: allDayEndDate(for: date), calendars: nil)
        let event = eventStore.events(matching: predicate).first { $0.url == url }
        if let event {
            defaults.set(event.eventIdentifier, forKey: workLogEventKey(for: id))
        }
        return event
    }

    private func workLogEventKey(for id: UUID) -> String {
        "integration.workLogEvent.\(id.uuidString)"
    }

    private func workLogEventURL(for id: UUID) -> URL? {
        URL(string: "biznote://work-log/event/\(id.uuidString)")
    }

    func syncReminder(
        title: String,
        detail: String,
        assignees: [String],
        dueDate: Date,
        isCompleted: Bool,
        existingIdentifier: String?
    ) async -> String? {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty,
              defaults.bool(forKey: "integration.syncTasksWithReminders"),
              await hasReminderAccess(requestIfNeeded: true),
              let list = selectedCalendar(for: .reminder, identifierKey: reminderListIdentifierKey) else {
            return existingIdentifier
        }

        let reminder = existingIdentifier
            .flatMap { eventStore.calendarItem(withIdentifier: $0) as? EKReminder }
            ?? EKReminder(eventStore: eventStore)

        reminder.calendar = list
        reminder.title = trimmedTitle
        reminder.notes = reminderNotes(detail: detail, assignees: assignees)
        reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: dueDate)
        reminder.isCompleted = isCompleted

        do {
            try eventStore.save(reminder, commit: true)
            return reminder.calendarItemIdentifier
        } catch {
            eventStore.reset()
            return existingIdentifier
        }
    }

    private func destinations(for entityType: EKEntityType) -> [Destination] {
        let calendars = eventStore.calendars(for: entityType)
            .filter(\.allowsContentModifications)
            .filter { isICloudSource($0.source) }

        return calendars
            .sorted {
                let sourceCompare = $0.source.title.localizedStandardCompare($1.source.title)
                if sourceCompare != .orderedSame { return sourceCompare == .orderedAscending }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
            .map { Destination(id: $0.calendarIdentifier, title: $0.title, sourceTitle: $0.source.title) }
    }

    private func selectedCalendar(for entityType: EKEntityType, identifierKey: String) -> EKCalendar? {
        let selectedIdentifier = defaults.string(forKey: identifierKey) ?? ""
        if !selectedIdentifier.isEmpty,
           let calendar = eventStore.calendar(withIdentifier: selectedIdentifier),
           calendar.allowsContentModifications {
            return calendar
        }

        let calendars = eventStore.calendars(for: entityType)
            .filter(\.allowsContentModifications)
            .filter { isICloudSource($0.source) }

        return calendars.first
    }

    private func hasEventAccess(requestIfNeeded: Bool) async -> Bool {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .authorized:
            return true
        case .notDetermined where requestIfNeeded:
            return await withCheckedContinuation { continuation in
                eventStore.requestFullAccessToEvents { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
        default:
            return false
        }
    }

    private func hasReminderAccess(requestIfNeeded: Bool) async -> Bool {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess, .authorized:
            return true
        case .notDetermined where requestIfNeeded:
            return await withCheckedContinuation { continuation in
                eventStore.requestFullAccessToReminders { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
        default:
            return false
        }
    }

    private func isICloudSource(_ source: EKSource) -> Bool {
        source.sourceType == .calDAV && source.title.localizedCaseInsensitiveContains("iCloud")
    }

    private func allDayEndDate(for endDate: Date) -> Date {
        let startOfEndDate = Calendar.current.startOfDay(for: endDate)
        return Calendar.current.date(byAdding: .day, value: 1, to: startOfEndDate) ?? startOfEndDate
    }

    private func eventNotes(for preset: ExhibitionPreset) -> String {
        [
            preset.introduction.isEmpty ? nil : "\(String(localized: "exhibitions.introduction", defaultValue: "행사소개")): \(preset.introduction)",
            preset.exhibitItems.isEmpty ? nil : "\(String(localized: "exhibitions.exhibitItems", defaultValue: "전시품목")): \(preset.exhibitItems)",
            preset.organizer.isEmpty ? nil : "\(String(localized: "exhibitions.organizer", defaultValue: "주최")): \(preset.organizer)",
            preset.supervisor.isEmpty ? nil : "\(String(localized: "exhibitions.supervisor", defaultValue: "주관")): \(preset.supervisor)",
            preset.contact.isEmpty ? nil : "\(String(localized: "exhibitions.contact", defaultValue: "연락처")): \(preset.contact)",
            preset.homepage.isEmpty ? nil : "\(String(localized: "exhibitions.homepage", defaultValue: "홈페이지")): \(preset.homepage)"
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
    }

    private func reminderNotes(detail: String, assignees: [String]) -> String {
        [
            detail.isEmpty ? nil : detail,
            assignees.isEmpty ? nil : "\(String(localized: "template.taskForm.assignee")): \(assignees.joined(separator: ", "))"
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
    }
}
