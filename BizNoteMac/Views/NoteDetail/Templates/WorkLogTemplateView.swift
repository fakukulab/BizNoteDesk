import SwiftUI
import AppKit

struct WorkLogTemplateView: View {
    @Binding var data: WorkLogTemplateData
    @Binding var attachmentPaths: [String]
    @AppStorage("integration.syncEventsWithCalendar") private var syncEventsWithCalendar = false
    var isEditing = true
    var meetings: [Note] = []
    var onOpenMeeting: (Note) -> Void = { _ in }


    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            majorEventsSection
            if !meetings.isEmpty {
                NoteTemplateSection(title: String(localized: "workLog.relatedMeetings", defaultValue: "같은 날 회의록")) {
                    ForEach(meetings) { meeting in
                        Button {
                            onOpenMeeting(meeting)
                        } label: {
                            Label(meeting.title.isEmpty ? String(localized: "note.untitled") : meeting.title,
                                  systemImage: "arrow.right.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }

            NoteTemplateSection(title: String(localized: "template.workLog.items", defaultValue: "업무")) {
                let statuses = WorkLogTemplateData.WorkItem.TaskStatus.allCases
                NoteTaskBoard(statuses: statuses, title: { $0.localizedName }) { status in
                    ForEach($data.workItems) { $item in
                        if item.status == status {
                            workItemRow($item)
                            Divider()
                        }
                    }
                    Button {
                        data.workItems.append(.init(status: status))
                    } label: {
                        Label(String(localized: "template.workLog.item.add"), systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }
            .disabled(!isEditing)

            labeledEditor(String(localized: "task.status.done"), text: $data.achievements)
            labeledEditor(String(localized: "template.workLog.issues"), text: $data.issues)
            labeledEditor(String(localized: "template.workLog.nextTodos"), text: $data.nextTodos)

            attachmentsSection
        }
    }

    private var majorEventsSection: some View {
        NoteTemplateSection(title: String(localized: "workLog.majorEvents", defaultValue: "주요 행사")) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach($data.majorEvents) { $event in
                    let id = event.id
                    HStack(spacing: 8) {
                        Image(systemName: "calendar")
                            .foregroundStyle(.secondary)
                        TextField(String(localized: "exhibitions.name", defaultValue: "행사명"), text: $event.title)
                            .textFieldStyle(.plain)
                        Button(role: .destructive) {
                            data.majorEvents.removeAll { $0.id == id }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(localized: "action.delete", defaultValue: "삭제"))
                    }
                    .disabled(!isEditing)
                    Divider()
                }
                Button {
                    data.majorEvents.append(.init())
                } label: {
                    Label(String(localized: "exhibitions.add", defaultValue: "행사 추가"), systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .disabled(!isEditing)

                if !syncEventsWithCalendar && !data.majorEvents.isEmpty {
                    SettingsLink {
                        Label(String(localized: "workLog.calendarSettings", defaultValue: "캘린더 연동 설정"),
                              systemImage: "gear")
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }
        }
    }

    @ViewBuilder
    private func workItemRow(_ item: Binding<WorkLogTemplateData.WorkItem>) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Menu {
                ForEach(WorkLogTemplateData.WorkItem.TaskStatus.allCases, id: \.self) { s in
                    Button(s.localizedName) { updateStatus(item, to: s) }
                }
            } label: {
                Image(systemName: "arrow.left.arrow.right.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            AutoHeightTextEditor(text: item.task, minHeight: 20)
                .font(.caption)
                .scrollContentBackground(.hidden)
                .onChange(of: item.wrappedValue.task) { _, _ in
                    syncAchievementIfNeeded(item)
                }

            Button {
                data.workItems.removeAll { $0.id == item.wrappedValue.id }
            } label: { Image(systemName: "minus.circle") }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    private func updateStatus(
        _ item: Binding<WorkLogTemplateData.WorkItem>,
        to newStatus: WorkLogTemplateData.WorkItem.TaskStatus
    ) {
        item.wrappedValue.status = newStatus
        syncAchievementIfNeeded(item)
    }

    /// Completed work items are mirrored into the achievements field so finishing a
    /// task doesn't require re-typing it into the achievements section by hand. Since
    /// the task text keeps changing while the user types, this keeps replacing the
    /// item's previously-written line rather than writing it once and locking,
    /// which used to freeze the copy at whatever text existed after the first keystroke.
    private func syncAchievementIfNeeded(_ item: Binding<WorkLogTemplateData.WorkItem>) {
        guard item.wrappedValue.status == .done else { return }
        let line = item.wrappedValue.task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return }
        if let previous = item.wrappedValue.lastSyncedAchievementText {
            guard previous != line else { return }
            if let range = data.achievements.range(of: previous) {
                data.achievements.replaceSubrange(range, with: line)
            } else {
                data.achievements = data.achievements.isEmpty ? line : data.achievements + "\n" + line
            }
        } else {
            data.achievements = data.achievements.isEmpty ? line : data.achievements + "\n" + line
        }
        item.wrappedValue.lastSyncedAchievementText = line
    }

    @ViewBuilder
    private func labeledEditor(_ title: String, text: Binding<String>) -> some View {
        NoteTemplateSection(title: title) {
            NoteMemoEditor(text: text, rtf: .constant(""), accessibilityTitle: title, bulletOnly: true)
                .frame(minHeight: 72)
                .disabled(!isEditing)
        }
    }

    private var attachmentsSection: some View {
        NoteTemplateSection(title: String(localized: "template.workLog.attachments", defaultValue: "첨부파일")) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(attachmentPaths, id: \.self) { path in
                    HStack {
                        Image(systemName: "doc.fill")
                            .foregroundStyle(.secondary)
                        Text(AttachmentStorage.attachmentDisplayName(path: path))
                            .font(.callout)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button {
                            AttachmentStorage.openAttachment(path: path)
                        } label: {
                            Image(systemName: "arrow.up.forward.square")
                        }
                        .buttonStyle(.plain)
                        .help(String(localized: "template.workLog.attachments.open", defaultValue: "파일 열기"))
                        Button {
                            removeAttachment(path)
                        } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.plain)
                        .disabled(!isEditing)
                    }
                    .padding(.vertical, 4)
                    Divider()
                }
                Button {
                    addAttachment()
                } label: {
                    Label(String(localized: "template.workLog.attachments.add", defaultValue: "파일 추가"),
                          systemImage: "paperclip")
                }
                .buttonStyle(.borderless)
                .disabled(!isEditing)
            }
            .padding(.vertical, 4)
        }
    }

    private func addAttachment() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let path = AttachmentStorage.saveAttachment(from: url) {
                attachmentPaths.append(path)
            }
        }
    }

    private func removeAttachment(_ path: String) {
        AttachmentStorage.removeAttachment(path: path)
        attachmentPaths.removeAll { $0 == path }
    }
}
