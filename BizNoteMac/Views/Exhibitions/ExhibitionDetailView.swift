import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

/// Shown in the rightmost detail column when an event is selected from the
/// 행사 리스트 — an editable detail view for registered exhibition details.
struct ExhibitionDetailView: View {
    @Bindable var preset: ExhibitionPreset
    @Environment(\.modelContext) private var context

    @State private var draft = ExhibitionDraft()
    @State private var isEditing = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ExhibitionHeaderEditor(
                        draft: $draft,
                        isEditing: isEditing,
                        logoImage: logoImage,
                        onUploadLogo: uploadLogo,
                        onRemoveLogo: removeLogo
                    )

                    ExhibitionBodyEditor(draft: $draft, isEditing: isEditing)
                }
                .padding(20)
            }

            Divider()

            ExhibitionActionBar(
                isEditing: isEditing,
                canSave: isEditing && draft != ExhibitionDraft(preset: preset),
                onEdit: beginEditing,
                onSave: saveDraft,
                onCancel: cancelEditing
            )
        }
        .navigationTitle(draft.name.isEmpty ? String(localized: "note.untitled") : draft.name)
        .onAppear {
            loadDraft()
        }
        .onChange(of: preset.id) { _, _ in
            loadDraft()
            isEditing = false
        }
    }

    private var logoImage: NSImage? {
        if draft.logoImagePath == preset.logoImagePath {
            return AttachmentStorage.exhibitionLogo(for: preset)
        }
        return AttachmentStorage.loadExhibitionLogo(path: draft.logoImagePath)
    }

    private func beginEditing() {
        loadDraft()
        isEditing = true
    }

    private func cancelEditing() {
        let currentPath = draft.logoImagePath
        let savedPath = preset.logoImagePath
        if currentPath != savedPath {
            AttachmentStorage.removeExhibitionLogo(path: currentPath)
        }
        loadDraft()
        isEditing = false
    }

    private func loadDraft() {
        draft = ExhibitionDraft(preset: preset)
    }

    /// Clicking the image box works with or without Edit mode. Outside Edit
    /// mode the change is saved right away; in Edit mode it waits for Save.
    private func uploadLogo() {
        let wasEditing = isEditing
        if !wasEditing { loadDraft() }

        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff]

        guard panel.runModal() == .OK,
              let url = panel.url,
              let image = NSImage(contentsOf: url),
              let squareImage = image.centeredSquareImage(),
              // A fresh file name per upload, so a new logo never overwrites the
              // saved one before the user presses Save (or Cancel).
              let savedPath = AttachmentStorage.saveExhibitionLogo(squareImage, id: UUID()) else {
            return
        }

        if draft.logoImagePath != preset.logoImagePath {
            AttachmentStorage.removeExhibitionLogo(path: draft.logoImagePath)
        }
        draft.logoImagePath = savedPath
        if !wasEditing { saveDraft() }
    }

    private func removeLogo() {
        let wasEditing = isEditing
        if !wasEditing { loadDraft() }

        if draft.logoImagePath != preset.logoImagePath {
            AttachmentStorage.removeExhibitionLogo(path: draft.logoImagePath)
        }
        draft.logoImagePath = ""
        if !wasEditing { saveDraft() }
    }

    private func saveDraft() {
        let previousLogoPath = preset.logoImagePath

        preset.name = draft.name
        preset.startDate = draft.startDate
        preset.endDate = draft.endDate
        preset.venue = draft.venue
        preset.organizer = draft.organizer
        preset.field = draft.exhibitItems
        preset.introduction = draft.introduction
        preset.exhibitItems = draft.exhibitItems
        preset.introductionRTFData = draft.introductionRTF
        preset.exhibitItemsRTFData = draft.exhibitItemsRTF
        preset.supervisor = draft.supervisor
        preset.contact = draft.contact
        preset.homepage = draft.homepage
        preset.logoImagePath = draft.logoImagePath

        if previousLogoPath != draft.logoImagePath {
            preset.logoImageData = AttachmentStorage.exhibitionLogoData(path: draft.logoImagePath)
            AttachmentStorage.removeExhibitionLogo(path: previousLogoPath)
        }

        try? context.save()
        Task { await CalendarReminderSyncService.shared.syncEvent(for: preset) }
        isEditing = false
        loadDraft()
    }
}

private struct ExhibitionDraft: Equatable {
    var name = ""
    var startDate = Date()
    var endDate = Date()
    var venue = ""
    var organizer = ""
    var introduction = ""
    var introductionRTF = ""
    var exhibitItems = ""
    var exhibitItemsRTF = ""
    var supervisor = ""
    var contact = ""
    var homepage = ""
    var logoImagePath = ""

    init() { }

    init(preset: ExhibitionPreset) {
        name = preset.name
        startDate = preset.startDate
        endDate = preset.endDate
        venue = preset.venue
        organizer = preset.organizer
        introduction = preset.introduction
        introductionRTF = preset.introductionRTFData
        exhibitItems = preset.exhibitItems
        exhibitItemsRTF = preset.exhibitItemsRTFData
        supervisor = preset.supervisor
        contact = preset.contact
        homepage = preset.homepage
        logoImagePath = preset.logoImagePath
    }
}

private struct ExhibitionHeaderEditor: View {
    @Binding var draft: ExhibitionDraft
    let isEditing: Bool
    let logoImage: NSImage?
    let onUploadLogo: () -> Void
    let onRemoveLogo: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            ExhibitionImageEditor(
                image: logoImage,
                hasImage: logoImage != nil || !draft.logoImagePath.isEmpty,
                onUpload: onUploadLogo,
                onRemove: onRemoveLogo
            )

            VStack(alignment: .leading, spacing: 12) {
                ExhibitionTextFieldRow(
                    title: String(localized: "exhibitions.name", defaultValue: "행사명"),
                    text: $draft.name,
                    isEditing: isEditing
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "exhibitions.schedule", defaultValue: "일정"))
                        .font(.callout.weight(.semibold))
                    HStack(spacing: 8) {
                        DatePicker("", selection: $draft.startDate, displayedComponents: .date)
                            .labelsHidden()
                            .disabled(!isEditing)
                        Text("-")
                            .foregroundStyle(.secondary)
                        DatePicker("", selection: $draft.endDate, displayedComponents: .date)
                            .labelsHidden()
                            .disabled(!isEditing)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                ExhibitionTextFieldRow(
                    title: String(localized: "exhibitions.venue", defaultValue: "장소"),
                    text: $draft.venue,
                    isEditing: isEditing
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .macGroupSurface()
    }
}

/// The event image box. Clicking it uploads an image when there is none, or
/// opens a menu to replace or delete the current one (also on right-click).
private struct ExhibitionImageEditor: View {
    let image: NSImage?
    let hasImage: Bool
    let onUpload: () -> Void
    let onRemove: () -> Void

    @State private var isHovering = false

    private var uploadTitle: String {
        hasImage
            ? String(localized: "exhibitions.image.replace", defaultValue: "이미지 교체")
            : String(localized: "exhibitions.image.upload", defaultValue: "이미지 업로드")
    }

    private var removeTitle: String {
        String(localized: "exhibitions.image.remove", defaultValue: "이미지 삭제")
    }

    var body: some View {
        Button {
            if hasImage {
                showImageMenu()
            } else {
                onUpload()
            }
        } label: {
            imageBox
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .contextMenu {
            Button(uploadTitle, systemImage: "photo.badge.plus", action: onUpload)
            if hasImage {
                Button(removeTitle, systemImage: "trash", role: .destructive, action: onRemove)
            }
        }
        .help(hasImage
              ? String(localized: "exhibitions.image.help.change", defaultValue: "클릭해서 이미지 교체 또는 삭제")
              : String(localized: "exhibitions.image.help.upload", defaultValue: "클릭해서 이미지 업로드"))
        .accessibilityLabel(String(localized: "exhibitions.image.empty", defaultValue: "행사 이미지"))
        .frame(width: 180, alignment: .leading)
    }

    private var imageBox: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.08))

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 180, height: 180)
                    .clipped()
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 26))
                        .foregroundStyle(.secondary)
                    Text(String(localized: "exhibitions.image.empty", defaultValue: "행사 이미지"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            if isHovering && image != nil {
                Color.black.opacity(0.35)
                Label(String(localized: "exhibitions.image.change", defaultValue: "이미지 변경"), systemImage: "photo.badge.plus")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 180, height: 180)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isHovering ? Color.accentColor.opacity(0.6) : Color.secondary.opacity(0.18), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8))
    }

    private func showImageMenu() {
        let menu = NSMenu()
        menu.addItem(ClosureMenuItem(title: uploadTitle, systemImage: "photo.badge.plus", handler: onUpload))
        menu.addItem(ClosureMenuItem(title: removeTitle, systemImage: "trash", handler: onRemove))
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}

/// NSMenuItem that runs a closure. The closure runs after the menu closes so it
/// can open other modal UI (like the file picker).
private final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, systemImage: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
        image = NSImage(systemSymbolName: systemImage, accessibilityDescription: nil)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func run() {
        DispatchQueue.main.async(execute: handler)
    }
}

private struct ExhibitionBodyEditor: View {
    @Binding var draft: ExhibitionDraft
    let isEditing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            richField(String(localized: "exhibitions.introduction", defaultValue: "행사소개"),
                      text: $draft.introduction, rtf: $draft.introductionRTF)
            richField(String(localized: "exhibitions.exhibitItems", defaultValue: "전시품목"),
                      text: $draft.exhibitItems, rtf: $draft.exhibitItemsRTF)

            ExhibitionTextFieldRow(
                title: String(localized: "exhibitions.organizer", defaultValue: "주최"),
                text: $draft.organizer,
                isEditing: isEditing
            )

            ExhibitionTextFieldRow(
                title: String(localized: "exhibitions.supervisor", defaultValue: "주관"),
                text: $draft.supervisor,
                isEditing: isEditing
            )

            ExhibitionTextFieldRow(
                title: String(localized: "exhibitions.contact", defaultValue: "연락처"),
                text: $draft.contact,
                isEditing: isEditing
            )

            HomepageEditorRow(
                homepage: $draft.homepage,
                isEditing: isEditing
            )
        }
    }

    private func richField(_ title: String, text: Binding<String>, rtf: Binding<String>) -> some View {
        NoteTemplateSection(title: title) {
            if isEditing {
                NoteMemoEditor(text: text, rtf: rtf, accessibilityTitle: title)
                    .frame(height: 120)
            } else {
                Text(AttributedString(NoteMemoEditor.displayText(text.wrappedValue, rtf: rtf.wrappedValue)))
                    .textSelection(.enabled)
                    .frame(minHeight: 32, alignment: .topLeading)
            }
        }
    }
}

/// One labeled value on the exhibition page, in the same box as the note's
/// free memo field. Every value uses `ExhibitionTextView`, so all text is left
/// aligned with the same 1.2 line spacing.
private struct ExhibitionTextFieldRow: View {
    let title: String
    @Binding var text: String
    let isEditing: Bool
    var singleLine: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.callout.weight(.semibold))
            ExhibitionTextBox(text: $text, isEditing: isEditing, singleLine: singleLine)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ExhibitionTextBox: View {
    @Binding var text: String
    let isEditing: Bool
    var singleLine: Bool = true

    var body: some View {
        Group {
            if isEditing {
                textView
                    .macInputSurface()
            } else {
                textView
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var textView: some View {
        ExhibitionTextView(
            text: $text,
            isEditable: isEditing,
            singleLine: singleLine,
            minimumLines: singleLine ? 1 : 2
        )
    }
}

/// Plain-text view for exhibition values: left aligned, line spacing 1.2
/// (1.2 × the font's normal single line height, like "1.2 lines" in Pages),
/// grows with its text instead of scrolling, editable only in Edit mode.
private struct ExhibitionTextView: NSViewRepresentable {
    @Binding var text: String
    var isEditable: Bool
    var singleLine: Bool
    var minimumLines: Int

    static let lineHeightMultiple: CGFloat = 1.2
    static let inset = NSSize(width: 4, height: 4)
    static var font: NSFont { .preferredFont(forTextStyle: .body) }

    static var paragraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = .left
        style.lineHeightMultiple = lineHeightMultiple
        return style
    }

    static var attributes: [NSAttributedString.Key: Any] {
        [.font: font, .paragraphStyle: paragraphStyle, .foregroundColor: NSColor.labelColor]
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSTextView {
        let textView = FrameTrackingTextView(usingTextLayoutManager: false)
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = false
        textView.textContainerInset = Self.inset
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.lineFragmentPadding = 0
        textView.font = Self.font
        textView.alignment = .left
        textView.defaultParagraphStyle = Self.paragraphStyle
        textView.typingAttributes = Self.attributes
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        setText(text, in: textView)
        textView.isEditable = isEditable
        textView.isSelectable = true
        return textView
    }

    func updateNSView(_ textView: NSTextView, context: Context) {
        context.coordinator.parent = self
        if textView.string != text {
            setText(text, in: textView)
        }
        if textView.isEditable != isEditable {
            if !isEditable, textView.window?.firstResponder === textView {
                textView.window?.makeFirstResponder(nil)
            }
            textView.isEditable = isEditable
        }
    }

    /// Measures with a separate scratch layout, never the live text view:
    /// SwiftUI probes several widths (some tiny) while laying out, and
    /// resizing the live text container for those probes left the text
    /// wrapping at a few characters and spilling out of its box.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView textView: NSTextView, context: Context) -> CGSize? {
        let width = max(proposal.width ?? 320, 40)
        let textHeight = Self.measuredTextHeight(textView.string, width: width - Self.inset.width * 2)
        let lineHeight = Self.measuredTextHeight("", width: .greatestFiniteMagnitude)
        let height = max(textHeight, lineHeight * CGFloat(minimumLines))
        return CGSize(width: width, height: ceil(height + Self.inset.height * 2))
    }

    static func measuredTextHeight(_ string: String, width: CGFloat) -> CGFloat {
        let storage = NSTextStorage(string: string.isEmpty ? " " : string, attributes: attributes)
        let layoutManager = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: max(width, 1), height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: container)
        return ceil(layoutManager.usedRect(for: container).height)
    }

    /// Keeps the text wrapping width equal to the view's real width.
    final class FrameTrackingTextView: NSTextView {
        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            textContainer?.containerSize = NSSize(
                width: max(newSize.width - textContainerInset.width * 2, 1),
                height: .greatestFiniteMagnitude
            )
        }
    }

    private func setText(_ string: String, in textView: NSTextView) {
        textView.textStorage?.setAttributedString(NSAttributedString(string: string, attributes: Self.attributes))
        textView.typingAttributes = Self.attributes
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ExhibitionTextView

        init(parent: ExhibitionTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            var string = textView.string
            if parent.singleLine, string.contains(where: \.isNewline) {
                string = string.components(separatedBy: .newlines).joined(separator: " ")
                parent.setText(string, in: textView)
            }
            parent.text = string
        }

        /// Return / Tab move to the next field in single-line values instead
        /// of inserting a line break or tab character.
        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.insertTab(_:)) {
                textView.window?.selectNextKeyView(nil)
                return true
            }
            if selector == #selector(NSResponder.insertBacktab(_:)) {
                textView.window?.selectPreviousKeyView(nil)
                return true
            }
            if parent.singleLine, selector == #selector(NSResponder.insertNewline(_:)) {
                textView.window?.makeFirstResponder(nil)
                return true
            }
            return false
        }
    }
}

private struct HomepageEditorRow: View {
    @Binding var homepage: String
    let isEditing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "exhibitions.homepage", defaultValue: "홈페이지"))
                .font(.callout.weight(.semibold))
            HStack(alignment: .center, spacing: 8) {
                ExhibitionTextBox(text: $homepage, isEditing: isEditing)

                Link(destination: homepageURL ?? URL(string: "about:blank")!) {
                    Label(String(localized: "exhibitions.homepage.open", defaultValue: "열기"), systemImage: "safari")
                }
                .disabled(homepageURL == nil)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var homepageURL: URL? {
        let trimmed = homepage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed), url.scheme != nil {
            return url
        }
        return URL(string: "https://\(trimmed)")
    }
}

private struct ExhibitionActionBar: View {
    let isEditing: Bool
    let canSave: Bool
    let onEdit: () -> Void
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Spacer()

            Button(action: onEdit) {
                Label(String(localized: "action.edit", defaultValue: "수정"), systemImage: "pencil")
            }
            .disabled(isEditing)

            Button(action: onSave) {
                Label(String(localized: "action.save", defaultValue: "저장"), systemImage: "checkmark")
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(!canSave)

            Button(role: .cancel, action: onCancel) {
                Label(String(localized: "action.cancel", defaultValue: "취소"), systemImage: "xmark")
            }
            .keyboardShortcut(.cancelAction)
            .disabled(!isEditing)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }
}
