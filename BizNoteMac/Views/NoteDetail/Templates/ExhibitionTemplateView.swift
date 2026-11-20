import SwiftUI
import SwiftData
import Contacts

struct ExhibitionTemplateView: View {
    @Binding var data: ExhibitionTemplateData
    let businessCards: [BusinessCard]
    @Query(sort: \ExhibitionPreset.startDate, order: .reverse) private var presets: [ExhibitionPreset]
    @State private var showPresetPicker = false
    @State private var showTaskForm = false
    @AppStorage("general.enableTaskSections") private var enableTaskSections: Bool = true

    static let worldCountryNames: [String] = {
        let locale = Locale.current
        let names = Locale.Region.isoRegions.compactMap { locale.localizedString(forRegionCode: $0.identifier) }
        return Array(Set(names)).sorted()
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                TextField(String(localized: "template.exhibition.name", defaultValue: "행사 이름"), text: $data.exhibitionName)
                    .textFieldStyle(.plain)
                Button(String(localized: "template.exhibition.loadPreset", defaultValue: "행사 조회")) {
                    showPresetPicker = true
                }
                .frame(minWidth: 96)
            }

            Divider()

            HStack {
                Text(String(localized: "template.exhibition.eventDate", defaultValue: "행사 일자"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                DatePicker("", selection: $data.eventStartDate, displayedComponents: .date)
                    .labelsHidden()
                Text("–")
                DatePicker("", selection: $data.eventEndDate, displayedComponents: .date)
                    .labelsHidden()
            }

            Divider()

            TextField(String(localized: "template.exhibition.venue"), text: $data.venue)
                .textFieldStyle(.plain)

            Divider()

            TextField(String(localized: "template.exhibition.organizer"), text: $data.organizer)
                .textFieldStyle(.plain)

            Divider()

            HStack {
                Text(String(localized: "template.exhibition.participationType", defaultValue: "참가 형태"))
                    .font(.callout.weight(.semibold))
                Picker("", selection: $data.participationType) {
                    ForEach(ExhibitionTemplateData.ParticipationType.allCases) { t in
                        Text(t.localizedName).tag(t)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)
            }

            if data.participationType == .visitor {
                visitedBoothsSection
            } else {
                contactsSection
            }

            if enableTaskSections {
                NoteTemplateSection(title: String(localized: "template.exhibition.followUpTasks", defaultValue: "후속업무")) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach($data.tasks) { $task in
                            taskRow($task)
                            Divider()
                        }
                        if showTaskForm {
                            TaskFormView(
                                assigneeSuggestions: assigneeOptions,
                                onSave: { result in
                                    addTask(from: result)
                                    showTaskForm = false
                                },
                                onCancel: { showTaskForm = false }
                            )
                        } else {
                            Button {
                                showTaskForm = true
                            } label: {
                                Label(String(localized: "template.exhibition.followUpTasks", defaultValue: "후속업무"), systemImage: "plus")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }
            }
        }
        .sheet(isPresented: $showPresetPicker) {
            ExhibitionPresetListSheet(
                presets: presets,
                onSelect: { preset in
                    applyPreset(preset)
                    showPresetPicker = false
                },
                onCancel: { showPresetPicker = false }
            )
        }
    }

    private var assigneeOptions: [String] {
        let names = data.participationType == .visitor
            ? data.visitedBooths.map(\.contactPerson)
            : data.contacts.map(\.name)
        return Array(Set(names.filter { !$0.isEmpty })).sorted()
    }

    private func taskRow(_ item: Binding<ExhibitionTemplateData.TaskItem>) -> some View {
        let id = item.wrappedValue.id
        return NoteActionRow(
            isCompleted: item.isCompleted,
            category: item.category,
            title: item.title,
            dueDate: item.dueDate,
            assignees: item.wrappedValue.assignees,
            detail: item.wrappedValue.detail
        ) {
            data.tasks.removeAll { $0.id == id }
        }
    }

    private func addTask(from result: TaskFormResult) {
        var task = ExhibitionTemplateData.TaskItem()
        task.title = result.description
        task.detail = result.detail
        task.category = result.category
        task.assignees = result.assignees
        task.dueDate = result.dueDate
        data.tasks.append(task)
    }

    private var visitedBoothsSection: some View {
        NoteTemplateSection(title: String(localized: "template.exhibition.booths")) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach($data.visitedBooths) { $booth in
                    boothRow($booth)
                    Divider()
                }
                Button {
                    data.visitedBooths.append(.init())
                } label: {
                    Label(String(localized: "template.exhibition.person.add", defaultValue: "사람"), systemImage: "plus")
                }
                .buttonStyle(.borderless)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func boothRow(_ booth: Binding<ExhibitionTemplateData.VisitedBooth>) -> some View {
        VStack(spacing: 8) {
            HStack {
                TextField(String(localized: "template.meeting.participants.name", defaultValue: "이름"),
                          text: booth.contactPerson)
                    .textFieldStyle(.plain)
                    .padding(.vertical, 2)
                NoteInlineDivider()
                TextField(String(localized: "card.field.jobTitle", defaultValue: "직급"),
                          text: booth.jobTitle)
                    .textFieldStyle(.plain)
                    .padding(.vertical, 2)
                NoteInlineDivider()
                TextField(String(localized: "template.exhibition.visitedBooth.company", defaultValue: "회사"),
                          text: booth.companyName)
                    .textFieldStyle(.plain)
                    .padding(.vertical, 2)
                CardLinkButton(cards: businessCards, onSelect: { card in applyCard(card, toBooth: booth) })
                ContactPickerButton(onSelect: { contact in applyContact(contact, toBooth: booth) },
                                    title: String(localized: "contacts.import.short", defaultValue: "주소록"))
                Button {
                    data.visitedBooths.removeAll { $0.id == booth.wrappedValue.id }
                } label: { Image(systemName: "minus.circle") }
                .buttonStyle(.plain)
            }
            Divider()
            HStack {
                TextField(String(localized: "template.exhibition.booth.contactPhone", defaultValue: "연락처"),
                          text: booth.contactPhone)
                    .textFieldStyle(.plain)
                NoteInlineDivider()
                TextField(String(localized: "template.exhibition.booth.contactEmail", defaultValue: "이메일"),
                          text: booth.contactEmail)
                    .textFieldStyle(.plain)
            }
            Divider()
            HStack(alignment: .top, spacing: 8) {
                Text(String(localized: "template.exhibition.contact.memo", defaultValue: "메모"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .leading)
                AutoHeightTextEditor(text: booth.notes, minHeight: 22)
                    .scrollContentBackground(.hidden)
            }
        }
        .padding(.vertical, 4)
    }

    private var contactsSection: some View {
        NoteTemplateSection(title: String(localized: "template.exhibition.contacts", defaultValue: "만난 사람")) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach($data.contacts) { $contact in
                    VStack(spacing: 8) {
                        HStack {
                            TextField(String(localized: "template.meeting.participants.name", defaultValue: "이름"),
                                      text: $contact.name)
                                .textFieldStyle(.plain)
                                .padding(.vertical, 2)
                            NoteInlineDivider()
                            TextField(String(localized: "card.field.jobTitle", defaultValue: "직급"),
                                      text: $contact.jobTitle)
                                .textFieldStyle(.plain)
                                .padding(.vertical, 2)
                            Picker(String(localized: "template.exhibition.contact.country", defaultValue: "국가"),
                                   selection: $contact.country) {
                                Text(String(localized: "settings.iCloud.destination.none", defaultValue: "선택 안 함")).tag("")
                                ForEach(Self.worldCountryNames, id: \.self) { name in
                                    Text(name).tag(name)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: .infinity)
                            CardLinkButton(cards: businessCards, onSelect: { card in applyCard(card, toContact: $contact) })
                            ContactPickerButton(onSelect: { c in applyContact(c, toContact: $contact) },
                                                title: String(localized: "contacts.import.short", defaultValue: "주소록"))
                            Button {
                                data.contacts.removeAll { $0.id == contact.id }
                            } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.plain)
                        }
                        Divider()
                        TextField(String(localized: "template.exhibition.booth.company", defaultValue: "회사명"),
                                  text: $contact.company)
                            .textFieldStyle(.plain)
                        Divider()
                        HStack {
                            TextField(String(localized: "template.exhibition.booth.contactPhone", defaultValue: "연락처"),
                                      text: $contact.phone)
                                .textFieldStyle(.plain)
                            NoteInlineDivider()
                            TextField(String(localized: "template.exhibition.booth.contactEmail", defaultValue: "이메일"),
                                      text: $contact.email)
                                .textFieldStyle(.plain)
                        }
                        Divider()
                        HStack(alignment: .top, spacing: 8) {
                            Text(String(localized: "template.exhibition.contact.memo", defaultValue: "메모"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 40, alignment: .leading)
                            AutoHeightTextEditor(text: $contact.memo, minHeight: 22)
                                .scrollContentBackground(.hidden)
                        }
                    }
                    .padding(.vertical, 4)
                    Divider()
                }
                Button {
                    data.contacts.append(.init())
                } label: {
                    Label(String(localized: "template.exhibition.person.add", defaultValue: "사람"), systemImage: "plus")
                }
                .buttonStyle(.borderless)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    private func applyPreset(_ preset: ExhibitionPreset) {
        data.exhibitionName = preset.name
        data.eventStartDate = preset.startDate
        data.eventEndDate = preset.endDate
        data.venue = preset.venue
        data.organizer = preset.organizer
        data.participatingDate = preset.startDate
        data.presetID = preset.id
    }

    private func applyContact(_ contact: CNContact, toBooth booth: Binding<ExhibitionTemplateData.VisitedBooth>) {
        booth.wrappedValue.contactPerson = contact.displayName
        booth.wrappedValue.companyName = contact.organizationName
        booth.wrappedValue.jobTitle = contact.jobTitle
        booth.wrappedValue.contactPhone = contact.primaryPhone
        booth.wrappedValue.contactEmail = contact.primaryEmail
    }

    private func applyContact(_ contact: CNContact, toContact target: Binding<ExhibitionTemplateData.Contact>) {
        target.wrappedValue.name = contact.displayName
        target.wrappedValue.company = contact.organizationName
        target.wrappedValue.jobTitle = contact.jobTitle
        target.wrappedValue.phone = contact.primaryPhone
        target.wrappedValue.email = contact.primaryEmail
    }

    private func applyCard(_ card: BusinessCard, toBooth booth: Binding<ExhibitionTemplateData.VisitedBooth>) {
        booth.wrappedValue.contactPerson = card.name
        booth.wrappedValue.companyName = card.company
        booth.wrappedValue.jobTitle = card.jobTitle
        booth.wrappedValue.contactPhone = card.phone
        booth.wrappedValue.contactEmail = card.email
        booth.wrappedValue.linkedCardID = card.id
    }

    private func applyCard(_ card: BusinessCard, toContact target: Binding<ExhibitionTemplateData.Contact>) {
        target.wrappedValue.name = card.name
        target.wrappedValue.company = card.company
        target.wrappedValue.jobTitle = card.jobTitle
        target.wrappedValue.phone = card.phone
        target.wrappedValue.email = card.email
        target.wrappedValue.linkedCardID = card.id
    }
}

/// A separate window (sheet) listing the registered events, shown when
/// the event-name field's 행사 조회 button is clicked.
private struct ExhibitionPresetListSheet: View {
    let presets: [ExhibitionPreset]
    var onSelect: (ExhibitionPreset) -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(String(localized: "template.exhibition.loadPreset", defaultValue: "행사 조회"))
                    .font(.headline)
                Spacer()
                Button(String(localized: "action.cancel"), action: onCancel)
                    .buttonStyle(.plain)
            }
            .padding(12)

            Divider()

            if presets.isEmpty {
                Text(String(localized: "template.exhibition.noPresets", defaultValue: "등록된 행사가 없습니다"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(presets) { preset in
                    Button {
                        onSelect(preset)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(preset.name).font(.callout.weight(.semibold))
                            Text(preset.dateRangeDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.inset)
            }
        }
        .frame(width: 360, height: 420)
    }
}
