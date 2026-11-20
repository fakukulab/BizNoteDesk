import SwiftUI
import Contacts

struct MeetingMinutesTemplateView: View {
    @Binding var data: MeetingMinutesTemplateData
    let businessCards: [BusinessCard]
    @State private var showLocationPicker = false
    @State private var showTaskForm = false
    @AppStorage("general.enableTaskSections") private var enableTaskSections: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Toggle(String(localized: "template.meeting.online", defaultValue: "온라인"),
                       isOn: $data.isOnlineMeeting)
                    .fixedSize()
                NoteInlineDivider()
                if data.isOnlineMeeting {
                    TextField(String(localized: "template.meeting.onlineLink", defaultValue: "회의 링크 (Zoom, Teams 등)"),
                              text: $data.onlineLink)
                        .textFieldStyle(.plain)
                        .padding(.vertical, 2)
                } else {
                    TextField(String(localized: "template.meeting.location"), text: $data.location)
                        .textFieldStyle(.plain)
                        .padding(.vertical, 2)
                    Button(String(localized: "location.picker.title", defaultValue: "위치찾기")) {
                        showLocationPicker = true
                    }
                    .frame(minWidth: 96)
                }
            }

            if data.isOnlineMeeting {
                Divider()
                LabeledContent(String(localized: "task.category.call")) {
                    TextField(String(localized: "template.meeting.onlinePhone", defaultValue: "통화 번호"),
                              text: $data.onlinePhone)
                        .textFieldStyle(.plain)
                }
            }

            NoteTemplateSection(title: String(localized: "template.meeting.participants")) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach($data.participants) { $person in
                        participantRow($person)
                        Divider()
                    }
                    Button {
                        data.participants.append(.init())
                    } label: {
                        Label(String(localized: "template.meeting.participant.add.short",
                                     defaultValue: "참석자"), systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }

            NoteTemplateSection(title: String(localized: "template.meeting.agenda")) {
                AutoHeightTextEditor(text: $data.agenda, minHeight: 60)
                    .scrollContentBackground(.hidden)
            }

            NoteTemplateSection(title: String(localized: "template.meeting.discussion")) {
                ListEditorView(items: $data.discussionPoints,
                               placeholder: String(localized: "template.meeting.discussion.placeholder"),
                               addTitle: String(localized: "template.meeting.discussion.add", defaultValue: "논의사항"))
            }

            NoteTemplateSection(title: String(localized: "template.meeting.decisions")) {
                ListEditorView(items: $data.decisions,
                               placeholder: String(localized: "template.meeting.decisions.placeholder"),
                               addTitle: String(localized: "template.meeting.decisions.add", defaultValue: "결정사항"))
            }

            if enableTaskSections {
                NoteTemplateSection(title: String(localized: "template.meeting.actionItems")) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach($data.actionItems) { $item in
                            actionItemRow($item)
                            Divider()
                        }
                        if showTaskForm {
                            TaskFormView(
                                assigneeSuggestions: participantNames,
                                onSave: { result in
                                    addActionItem(from: result)
                                    showTaskForm = false
                                },
                                onCancel: { showTaskForm = false }
                            )
                        } else {
                            Button {
                                showTaskForm = true
                            } label: {
                                Label(String(localized: "template.workLog.item.add", defaultValue: "업무"), systemImage: "plus")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }
            }
        }
        .sheet(isPresented: $showLocationPicker) {
            LocationPickerSheet(
                initialName: data.location,
                onConfirm: { name, lat, lon in
                    data.location = name
                    data.locationLatitude = lat
                    data.locationLongitude = lon
                    showLocationPicker = false
                },
                onCancel: { showLocationPicker = false }
            )
        }
    }

    private var participantNames: [String] {
        let names = data.participants.map(\.name).filter { !$0.isEmpty }
        return Array(Set(names)).sorted()
    }

    private func actionItemRow(_ item: Binding<MeetingMinutesTemplateData.ActionItem>) -> some View {
        let id = item.wrappedValue.id
        return NoteActionRow(
            isCompleted: item.isCompleted,
            category: item.category,
            title: item.task,
            dueDate: item.dueDate,
            assignees: item.wrappedValue.assignees,
            detail: item.wrappedValue.detail
        ) {
            data.actionItems.removeAll { $0.id == id }
        }
    }

    private func addActionItem(from result: TaskFormResult) {
        var item = MeetingMinutesTemplateData.ActionItem()
        item.task = result.description
        item.detail = result.detail
        item.category = result.category
        item.assignees = result.assignees
        item.dueDate = result.dueDate
        data.actionItems.append(item)
    }

    @ViewBuilder
    private func participantRow(_ person: Binding<MeetingMinutesTemplateData.Participant>) -> some View {
        HStack {
            TextField(String(localized: "template.meeting.participants.name", defaultValue: "이름"),
                      text: person.name)
                .textFieldStyle(.plain)
                .padding(.vertical, 2)
            NoteInlineDivider()
            TextField(String(localized: "card.field.jobTitle", defaultValue: "직급"),
                      text: person.jobTitle)
                .textFieldStyle(.plain)
                .padding(.vertical, 2)
            NoteInlineDivider()
            TextField(String(localized: "template.meeting.participants.company", defaultValue: "소속"),
                      text: person.company)
                .textFieldStyle(.plain)
                .padding(.vertical, 2)
            CardLinkButton(cards: businessCards, onSelect: { card in applyCard(card, to: person) })
            ContactPickerButton(onSelect: { contact in applyContact(contact, to: person) },
                                title: String(localized: "contacts.import.short", defaultValue: "주소록"))
            Button {
                data.participants.removeAll { $0.id == person.wrappedValue.id }
            } label: { Image(systemName: "minus.circle") }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    private func applyContact(_ contact: CNContact, to person: Binding<MeetingMinutesTemplateData.Participant>) {
        person.wrappedValue.name = contact.displayName
        person.wrappedValue.company = contact.organizationName
        person.wrappedValue.jobTitle = contact.jobTitle
        person.wrappedValue.phone = contact.primaryPhone
        person.wrappedValue.email = contact.primaryEmail
    }

    private func applyCard(_ card: BusinessCard, to person: Binding<MeetingMinutesTemplateData.Participant>) {
        person.wrappedValue.name = card.name
        person.wrappedValue.company = card.company
        person.wrappedValue.jobTitle = card.jobTitle
        person.wrappedValue.phone = card.phone
        person.wrappedValue.email = card.email
        person.wrappedValue.linkedCardID = card.id
    }
}

struct ListEditorView: View {
    @Binding var items: [String]
    let placeholder: String
    let addTitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items.indices, id: \.self) { i in
                HStack {
                    Text("•").foregroundStyle(.secondary)
                    TextField(placeholder, text: Binding(
                        get: { items.indices.contains(i) ? items[i] : "" },
                        set: { if items.indices.contains(i) { items[i] = $0 } }
                    ))
                    .textFieldStyle(.plain)
                    .padding(.vertical, 2)
                    Button {
                        if items.indices.contains(i) { items.remove(at: i) }
                    } label: { Image(systemName: "minus.circle") }
                    .buttonStyle(.plain)
                }
                Divider()
            }
            Button {
                items.append("")
            } label: {
                Label(addTitle, systemImage: "plus")
            }
            .buttonStyle(.borderless)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}
