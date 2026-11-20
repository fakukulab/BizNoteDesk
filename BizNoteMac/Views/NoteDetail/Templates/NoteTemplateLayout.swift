import SwiftUI

struct NoteTemplateSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.callout.weight(.semibold))
            Divider()
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct NoteTaskBoard<Status: Hashable, Column: View>: View {
    let statuses: [Status]
    let title: (Status) -> String
    @ViewBuilder let column: (Status) -> Column

    var body: some View {
        ViewThatFits(in: .horizontal) {
            statusRow(statuses)
            if statuses.count == 4 {
                VStack(alignment: .leading, spacing: 8) {
                    statusRow(Array(statuses.prefix(2)))
                    Divider()
                    statusRow(Array(statuses.suffix(2)))
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(statuses, id: \.self) { status in
                    if status != statuses.first {
                        Divider()
                    }
                    statusColumn(status)
                }
            }
        }
        .padding(8)
    }

    private func statusRow(_ row: [Status]) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(row, id: \.self) { status in
                if status != row.first {
                    Divider()
                }
                statusColumn(status)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func statusColumn(_ status: Status) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title(status))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            column(status)
        }
        .frame(minWidth: 152, maxWidth: .infinity, alignment: .topLeading)
    }
}

struct NoteActionRow: View {
    @Binding var isCompleted: Bool
    @Binding var category: ExhibitionTemplateData.TaskItem.TaskCategory
    @Binding var title: String
    @Binding var dueDate: Date
    let assignees: [String]
    let detail: String
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    completionCheck
                    categoryPicker
                    NoteInlineDivider()
                    titleField
                    if !assignees.isEmpty {
                        NoteInlineDivider()
                        assigneeLabel
                    }
                    duePicker
                    removeButton
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        completionCheck
                        categoryPicker
                        NoteInlineDivider()
                        titleField
                        removeButton
                    }
                    HStack(spacing: 8) {
                        duePicker
                        if !assignees.isEmpty {
                            NoteInlineDivider()
                            assigneeLabel
                        }
                    }
                }
            }
            if !detail.isEmpty {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }

    private var completionCheck: some View {
        Toggle(WorkLogTemplateData.WorkItem.TaskStatus.done.localizedName, isOn: $isCompleted)
            .labelsHidden()
            .toggleStyle(.checkbox)
    }

    private var categoryPicker: some View {
        Picker(String(localized: "template.taskForm.category", defaultValue: "Category"), selection: $category) {
            ForEach(ExhibitionTemplateData.TaskItem.TaskCategory.selectableCases) { option in
                Label(option.localizedName, systemImage: option.systemImage).tag(option)
            }
        }
        .labelsHidden()
        .frame(width: 112)
    }

    private var titleField: some View {
        TextField(String(localized: "template.meeting.action.task"), text: $title)
            .textFieldStyle(.plain)
            .frame(minWidth: 80)
    }

    private var assigneeLabel: some View {
        Text(assignees.joined(separator: ", "))
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .frame(maxWidth: 120, alignment: .leading)
    }

    private var duePicker: some View {
        DatePicker(String(localized: "template.taskForm.due", defaultValue: "Due"), selection: $dueDate,
                   displayedComponents: [.date, .hourAndMinute])
            .labelsHidden()
    }

    private var removeButton: some View {
        Button(role: .destructive, action: onRemove) {
            Image(systemName: "minus.circle")
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "action.delete", defaultValue: "삭제"))
    }
}


struct NoteInlineDivider: View {
    var body: some View {
        Divider()
            .frame(height: 16)
            .accessibilityHidden(true)
    }
}
