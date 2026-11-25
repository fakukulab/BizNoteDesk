import SwiftUI
import SwiftData
import AppKit

/// Shown in the detail column when a card is selected in the "명함 관리"
/// smart folder — displays the scanned image alongside an editable form so
/// the extracted fields can be corrected after the fact.
struct BusinessCardDetailView: View {
    @Bindable var card: BusinessCard
    @Environment(\.modelContext) private var context

    private var image: NSImage? {
        if let data = card.imageData, let image = NSImage(data: data) {
            return image
        }
        return AttachmentStorage.cardImageData(path: card.imagePath, id: card.id).flatMap(NSImage.init(data:))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))
                }

                Form {
                    Section {
                        LabeledContent(String(localized: "card.field.name")) {
                            cardField($card.name)
                        }
                        LabeledContent(String(localized: "card.field.company")) {
                            cardField($card.company)
                        }
                        LabeledContent(String(localized: "card.field.department")) {
                            cardField($card.department)
                        }
                        LabeledContent(String(localized: "card.field.jobTitle")) {
                            cardField($card.jobTitle)
                        }
                    }
                    Section {
                        LabeledContent(String(localized: "card.field.email")) {
                            cardField($card.email)
                        }
                        LabeledContent(String(localized: "card.field.phone")) {
                            cardField($card.phone)
                        }
                        LabeledContent(String(localized: "card.field.officePhone")) {
                            cardField($card.officePhone)
                        }
                    }
                    Section {
                        LabeledContent(String(localized: "card.field.website")) {
                            cardField($card.website)
                        }
                        LabeledContent(String(localized: "card.field.memo")) {
                            TextEditor(text: $card.memo)
                                .frame(minHeight: 60)
                                .macEditorField()
                                .multilineTextAlignment(.leading)
                        }
                    }
                    if let note = card.note {
                        Section {
                            LabeledContent(String(localized: "cardDetail.note", defaultValue: "연결된 노트")) {
                                Text(note.title.isEmpty ? String(localized: "note.untitled") : note.title)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
            }
            .padding(24)
        }
        .navigationTitle(card.name.isEmpty ? String(localized: "note.untitled") : card.name)
        .onChange(of: card.name) { _, _ in save() }
        .onChange(of: card.company) { _, _ in save() }
        .onChange(of: card.department) { _, _ in save() }
        .onChange(of: card.jobTitle) { _, _ in save() }
        .onChange(of: card.email) { _, _ in save() }
        .onChange(of: card.phone) { _, _ in save() }
        .onChange(of: card.officePhone) { _, _ in save() }
        .onChange(of: card.website) { _, _ in save() }
        .onChange(of: card.memo) { _, _ in save() }
    }

    private func cardField(_ text: Binding<String>) -> some View {
        TextField("", text: text)
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.leading)
    }

    private func save() {
        try? context.save()
    }
}
