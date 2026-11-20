import SwiftUI
import SwiftData

struct ExportSheetView: View {
    enum Kind: String, CaseIterable, Identifiable {
        case notes, businessCards, all
        var id: String { rawValue }
        var localized: String {
            switch self {
            case .notes:         return String(localized: "export.kind.notes")
            case .businessCards: return String(localized: "export.kind.cards")
            case .all:           return String(localized: "export.kind.all", defaultValue: "모두")
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @Query private var allNotes: [Note]
    @Query private var allCards: [BusinessCard]
    @Query(sort: \CustomCategory.createdAt) private var customCategories: [CustomCategory]

    @State private var kind: Kind = .notes
    @State private var categoryFilter: NoteCategorySelection? = nil
    @State private var startDate: Date = Calendar.current.date(byAdding: .month, value: -3, to: Date()) ?? Date()
    @State private var endDate: Date = Date()
    @AppStorage("export.openAfterSave") private var openAfterSave: Bool = true
    @AppStorage("export.cardFormat") private var cardFormatRaw: String = SpreadsheetFormat.xlsx.rawValue

    private var cardFormat: SpreadsheetFormat {
        SpreadsheetFormat(rawValue: cardFormatRaw) ?? .xlsx
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "export.title"))
                .font(.title2.weight(.semibold))

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Picker(String(localized: "export.targetLabel", defaultValue: "대상"), selection: $kind) {
                        ForEach(Kind.allCases) { kind in
                            Text(kind.localized).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)

                    if kind != .businessCards {
                        Picker(String(localized: "export.noteListLabel", defaultValue: "노트목록"), selection: $categoryFilter) {
                            Text(String(localized: "export.category.all")).tag(NoteCategorySelection?.none)
                            ForEach(NoteCategory.allCases) { category in
                                Text(category.localizedName).tag(NoteCategorySelection?.some(.builtin(category)))
                            }
                            ForEach(customCategories) { category in
                                Text(category.name).tag(NoteCategorySelection?.some(.custom(category)))
                            }
                        }
                    }

                    if kind != .notes {
                        Picker(String(localized: "export.cardFormat", defaultValue: "명함 파일 형식"), selection: $cardFormatRaw) {
                            ForEach(SpreadsheetFormat.allCases) { format in
                                Text(format.localizedName).tag(format.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }

            GroupBox(String(localized: "export.periodLabel", defaultValue: "기간")) {
                HStack(spacing: 16) {
                    DatePicker(String(localized: "export.startDate"),
                               selection: $startDate, displayedComponents: .date)
                    DatePicker(String(localized: "export.endDate"),
                               selection: $endDate, displayedComponents: .date)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }

            Toggle(String(localized: "export.openAfterSave"), isOn: $openAfterSave)
                .toggleStyle(.checkbox)

            HStack {
                Text(String(localized: "export.count") + ": \(filteredCount)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(String(localized: "action.cancel"), role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "export.run")) {
                    performExport()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(filteredCount == 0)
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private var filteredNotes: [Note] {
        allNotes.filter { note in
            let inRange = note.updatedAt >= startOfDay(startDate) && note.updatedAt <= endOfDay(endDate)
            let matches: Bool = {
                guard let categoryFilter else { return true }
                switch categoryFilter {
                case .builtin(let c): return !note.isCustomCategory && note.category == c
                case .custom(let c):  return note.isCustomCategory && note.customCategory?.id == c.id
                }
            }()
            return inRange && matches
        }
    }

    private var filteredCards: [BusinessCard] {
        allCards.filter { $0.createdAt >= startOfDay(startDate) && $0.createdAt <= endOfDay(endDate) }
    }

    private var filteredCount: Int {
        switch kind {
        case .notes:         return filteredNotes.count
        case .businessCards: return filteredCards.count
        case .all:           return filteredNotes.count + filteredCards.count
        }
    }

    private func performExport() {
        switch kind {
        case .notes:
            PDFExportService.exportNotes(filteredNotes, openAfter: openAfterSave)
        case .businessCards:
            ExcelExportService.exportBusinessCards(filteredCards, format: cardFormat, openAfter: openAfterSave)
        case .all:
            PDFExportService.exportNotes(filteredNotes, openAfter: openAfterSave)
            ExcelExportService.exportBusinessCards(filteredCards, format: cardFormat, openAfter: openAfterSave)
        }
    }

    private func startOfDay(_ d: Date) -> Date {
        Calendar.current.startOfDay(for: d)
    }
    private func endOfDay(_ d: Date) -> Date {
        Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: d) ?? d
    }
}
