import SwiftData
import SwiftUI

struct ExhibitionAddWindowView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var name = ""
    @State private var startDate = Date()
    @State private var endDate = Date()
    @State private var venue = ""
    @State private var introduction = ""
    @State private var introductionRTF = ""
    @State private var exhibitItems = ""
    @State private var exhibitItemsRTF = ""
    @State private var organizer = ""
    @State private var supervisor = ""
    @State private var contact = ""
    @State private var homepage = ""

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "exhibitions.add", defaultValue: "행사 추가"))
                .font(.title2.weight(.semibold))

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    textField(String(localized: "exhibitions.name", defaultValue: "행사명"), text: $name)

                    NoteTemplateSection(title: String(localized: "exhibitions.schedule", defaultValue: "일정")) {
                        HStack(spacing: 8) {
                            DatePicker(String(localized: "export.startDate"), selection: $startDate, displayedComponents: .date)
                                .labelsHidden()
                            Text("–")
                                .foregroundStyle(.secondary)
                            DatePicker(String(localized: "export.endDate"), selection: $endDate, displayedComponents: .date)
                                .labelsHidden()
                        }
                    }

                    textField(String(localized: "exhibitions.venue", defaultValue: "장소"), text: $venue)

                    let introductionTitle = String(localized: "exhibitions.introduction", defaultValue: "행사소개")
                    NoteTemplateSection(title: introductionTitle) {
                        NoteMemoEditor(text: $introduction, rtf: $introductionRTF, accessibilityTitle: introductionTitle)
                            .frame(height: 112)
                    }

                    let itemsTitle = String(localized: "exhibitions.exhibitItems", defaultValue: "전시품목")
                    NoteTemplateSection(title: itemsTitle) {
                        NoteMemoEditor(text: $exhibitItems, rtf: $exhibitItemsRTF, accessibilityTitle: itemsTitle)
                            .frame(height: 112)
                    }

                    textField(String(localized: "exhibitions.organizer", defaultValue: "주최"), text: $organizer)
                    textField(String(localized: "exhibitions.supervisor", defaultValue: "주관"), text: $supervisor)
                    textField(String(localized: "exhibitions.contact", defaultValue: "연락처"), text: $contact)
                    textField(String(localized: "exhibitions.homepage", defaultValue: "홈페이지"), text: $homepage)
                }
                .padding(.bottom, 4)
            }
            .multilineTextAlignment(.leading)

            Divider()

            HStack {
                Spacer()
                Button(String(localized: "action.cancel"), role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button(String(localized: "action.add", defaultValue: "추가")) {
                    addPreset()
                }
                .disabled(!canSave)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 620)
        .onChange(of: startDate) { _, newValue in
            if endDate < newValue {
                endDate = newValue
            }
        }
    }

    private func textField(_ title: String, text: Binding<String>) -> some View {
        NoteTemplateSection(title: title) {
            TextField("", text: text)
                .textFieldStyle(.plain)
                .accessibilityLabel(title)
                .padding(.vertical, 4)
        }
    }

    private func addPreset() {
        let preset = ExhibitionPreset(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            startDate: startDate,
            endDate: max(endDate, startDate),
            venue: venue.trimmingCharacters(in: .whitespacesAndNewlines),
            organizer: organizer.trimmingCharacters(in: .whitespacesAndNewlines),
            field: exhibitItems,
            introduction: introduction,
            exhibitItems: exhibitItems,
            supervisor: supervisor.trimmingCharacters(in: .whitespacesAndNewlines),
            contact: contact.trimmingCharacters(in: .whitespacesAndNewlines),
            homepage: homepage.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        preset.introductionRTFData = introductionRTF
        preset.exhibitItemsRTFData = exhibitItemsRTF
        context.insert(preset)
        try? context.save()
        Task { await CalendarReminderSyncService.shared.syncEvent(for: preset) }
        dismiss()
    }
}
