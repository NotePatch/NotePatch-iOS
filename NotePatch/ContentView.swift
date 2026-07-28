import PhotosUI
import QuickLook
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ContentView: View {
    @StateObject private var model = NotePatchViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if model.session == nil {
                AuthScreen(model: model)
            } else {
                WorkbenchScreen(model: model)
            }
        }
        .task {
            await model.restoreIfNeeded()
        }
        .onChange(of: scenePhase, initial: true) { _, newPhase in
            model.handleScenePhase(newPhase)
        }
        .sheet(item: $model.downloadedPreview) { preview in
            if preview.isImage {
                ImagePreview(url: preview.url)
            } else {
                QuickLookPreview(url: preview.url)
            }
        }
    }

}

// MARK: - Auth Screen

private struct AuthScreen: View {
    @ObservedObject var model: NotePatchViewModel
    @State private var appear = false

    var body: some View {
        ZStack {
            NPColors.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: NPSpacing.section) {
                    // Hero section
                    VStack(spacing: 16) {
                        NotePatchLogoImage(height: 56)
                            .scaleEffect(appear ? 1 : 0.80)
                            .opacity(appear ? 1 : 0)

                        VStack(spacing: NPSpacing.small) {
                            Text("NotePatch")
                                .npTitle()
                            Text("Scan, organize, and process your study documents")
                                .npCaption()
                                .lineSpacing(2)
                        }
                        .opacity(appear ? 1 : 0)
                        .offset(y: appear ? 0 : 12)
                    }
                    .padding(.top, NPSpacing.large)

                    // Form card
                    VStack(spacing: NPSpacing.item) {
                        VStack(spacing: 10) {
                            AuthField(title: "API Address", systemImage: "network") {
                                TextField("https://5mbps.me:8443/notepatch/1", text: $model.apiBaseURLText)
                                    .textInputAutocapitalization(.never)
                                    .keyboardType(.URL)
                                    .accessibilityIdentifier("apiAddressField")
                            }

                            Divider().background(NPColors.interactive.opacity(0.4))

                            AuthField(title: "Email", systemImage: "envelope") {
                                TextField("name@example.com", text: $model.emailText)
                                    .textInputAutocapitalization(.never)
                                    .keyboardType(.emailAddress)
                                    .textContentType(.username)
                                    .accessibilityIdentifier("emailField")
                            }

                            Divider().background(NPColors.interactive.opacity(0.4))

                            AuthField(title: "Password", systemImage: "lock") {
                                SecureField("Enter password", text: $model.passwordText)
                                    .textContentType(.password)
                                    .accessibilityIdentifier("passwordField")
                            }

                            Divider().background(NPColors.interactive.opacity(0.4))

                            AuthField(title: "Full Name", systemImage: "person") {
                                TextField("Enter when registering", text: $model.fullNameText)
                                    .textContentType(.name)
                            }
                        }
                        .modifier(NPCardModifier())
                        .accessibilityIdentifier("authFormCard")
                    }

                    // Login button
                    Button {
                        model.authenticate(register: false)
                    } label: {
                        HStack {
                            Spacer()
                            if model.isBusy {
                                ProgressView()
                                    .tint(NPColors.surface)
                            } else {
                                Label("Sign In", systemImage: "arrow.right")
                                    .font(.body.weight(.semibold))
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(NPPrimaryButtonStyle())
                    .disabled(model.isBusy)
                    .accessibilityIdentifier("loginButton")

                    // Secondary buttons
                    HStack(spacing: NPSpacing.medium) {
                        Button {
                            model.authenticate(register: true)
                        } label: {
                            Label("Create Account", systemImage: "person.badge.plus")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(NPSecondaryButtonStyle())
                        .disabled(model.isBusy)

                        Button {
                            model.checkAPIConnection()
                        } label: {
                            Label("Test Connection", systemImage: "wave.3.right")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(NPSecondaryButtonStyle())
                        .disabled(model.isBusy)
                    }

                    StatusPanel(isBusy: model.isBusy, statusMessage: model.statusMessage, errorMessage: model.errorMessage)
                }
                .frame(maxWidth: 520)
                .opacity(appear ? 1 : 0)
                .offset(y: appear ? 0 : 16)
                .padding(.horizontal, NPSpacing.outer)
                .padding(.bottom, NPSpacing.xxxl)
            }
        }
        .disabled(model.isBusy)
        .onAppear {
            withAnimation(.npCardEntry) { appear = true }
        }
    }
}

private struct AuthField<Field: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let field: Field

    var body: some View {
        HStack(spacing: NPSpacing.medium) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(NPColors.textSecondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(localized(title))
                    .npCaption()
                    .foregroundStyle(NPColors.textSecondary)
                field
                    .npBody()
            }
        }
        .frame(minHeight: 48)
    }
}

// MARK: - Workbench Screen

private struct WorkbenchScreen: View {
    @ObservedObject var model: NotePatchViewModel
    @State private var isUploadPresented = false

    var body: some View {
        VStack(spacing: 0) {
            StatusBanner(
                isBusy: model.isBusy || model.isConversationMutating || model.isAIPreferenceUpdating || model.isHomeworkLoading || model.isStudyNoteSaving,
                statusMessage: model.statusMessage,
                errorMessage: model.errorMessage,
                onDismiss: model.dismissStatusBanner
            )

            // Content area — all tabs kept alive, only selected one visible
            ZStack {
                DocumentsTab(model: model)
                    .opacity(model.selectedTab == .documents ? 1 : 0)
                    .disabled(model.selectedTab != .documents)

                NotesTab(model: model)
                    .opacity(model.selectedTab == .notes ? 1 : 0)
                    .disabled(model.selectedTab != .notes)

                OpenClawChatTab(
                    model: model,
                    chatState: model.openClawState,
                    composerState: model.openClawComposerState
                )
                    .opacity(model.selectedTab == .openClaw ? 1 : 0)
                    .disabled(model.selectedTab != .openClaw)

                ProfileTab(model: model)
                    .opacity(model.selectedTab == .profile ? 1 : 0)
                    .disabled(model.selectedTab != .profile)
            }
        }
        .background(NPColors.background)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            FloatingTabBar(
                selectedTab: $model.selectedTab,
                onUpload: { isUploadPresented = true }
            )
            .onChange(of: model.selectedTab) { _, newTab in
                if newTab != .openClaw { dismissActiveKeyboard() }
            }
        }
        .fullScreenCover(isPresented: $isUploadPresented) {
            UploadScreen(model: model, isPresented: $isUploadPresented)
        }
        .onAppear {
            model.ensureContentForSelectedTabLoaded()
        }
    }
}

// MARK: - Floating Tab Bar (Liquid Glass)

private struct FloatingTabBar: View {
    @Binding var selectedTab: WorkbenchTab
    let onUpload: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(WorkbenchTab.allCases) { tab in
                TabBarButton(
                    icon: tab.iconName,
                    label: tab.title,
                    isSelected: selectedTab == tab,
                    action: {
                        selectedTab = tab
                    }
                )
                .frame(maxWidth: .infinity)
            }

            Spacer().frame(width: 6)

            // Upload action
            UploadFloatingButton(action: onUpload)
        }
        .frame(height: 64)
        .padding(.horizontal, 10)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(.white.opacity(0.25), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.04), radius: 16, x: 0, y: 2)
        .padding(.horizontal, 20)
        .padding(.bottom, 6)
    }
}

private struct TabBarButton: View {
    let icon: String
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .regular))
                Text(label)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(isSelected ? NPColors.brand : NPColors.textTertiary)
        }
        .buttonStyle(.plain)
    }
}

private struct UploadFloatingButton: View {
    let action: () -> Void
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundStyle(NPColors.brand)
                .frame(width: 52, height: 52)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                )
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.3), lineWidth: 0.5)
                }
                .shadow(
                    color: .black.opacity(0.04),
                    radius: 8,
                    x: 0,
                    y: 2
                )
                .scaleEffect(isPressed ? 0.96 : 1.0)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Upload")
        .accessibilityIdentifier("uploadFAB")
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            withAnimation(Animation.npButton) { isPressed = pressing }
        }, perform: {})
    }
}

// MARK: - Notes Tab

private struct NotesTab: View {
    @ObservedObject var model: NotePatchViewModel
    @State private var readerItem: StudyNoteListItem?

    var body: some View {
        VStack(spacing: 0) {
            NotePatchLogoImage(height: 64)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, NPSpacing.outer)
                .padding(.top, NPSpacing.item)
                .padding(.bottom, NPSpacing.xs)

            Text("Patch your knowledge together.")
                .font(.system(size: 13, weight: .regular, design: .default))
                .foregroundStyle(NPColors.textSecondary.opacity(0.7))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, NPSpacing.outer)
                .padding(.bottom, NPSpacing.item)

            HStack {
                if model.selectedNotesSection == .notes {
                    Spacer()
                    Button {
                        model.loadNotesOverview(allowOfflineNetwork: true)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(NPToolbarIconButtonStyle())
                    .disabled(model.isNotesLoading)
                    .accessibilityLabel(localizedFormat("accessibility.refresh_named", localized("notes.section.notes")))
                }
            }
            .frame(height: 48)
            .padding(.horizontal, NPSpacing.outer)

            Picker(localized("notes.section.picker"), selection: $model.selectedNotesSection) {
                ForEach(NotesSection.allCases) { section in
                    Text(section.title).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, NPSpacing.outer)
            .padding(.vertical, 10)
            .accessibilityIdentifier("notesSectionPicker")

            Group {
                if model.selectedNotesSection == .notes {
                    notesOverview
                } else {
                    LearningTab(model: model) { item in
                        model.openStudyNote(item)
                        readerItem = item
                    }
                }
            }
        }
        .sheet(item: $readerItem) { _ in
            NavigationStack {
                StudyNoteReader(model: model)
                    .onDisappear { model.closeStudyNoteReader() }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(localized("common.done")) {
                                readerItem = nil
                            }
                        }
                    }
            }
        }
        .onChange(of: model.selectedNotesSection) { _, _ in
            model.ensureContentForSelectedTabLoaded()
        }
    }

    private var notesOverview: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: NPSpacing.item) {
                if model.isNotesLoading && model.studyNoteGroups.isEmpty {
                    ProgressView(localized("notes.loading"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 36)
                } else if model.studyNoteGroups.isEmpty {
                    NPEmptyState(
                        systemImage: "note.text",
                        title: localized("notes.empty.title"),
                        message: localized("notes.empty.message")
                    )
                    .padding(.top, 56)
                } else {
                    ForEach(model.studyNoteGroups) { group in
                        VStack(alignment: .leading, spacing: NPSpacing.small) {
                            Text(group.learningUnit.title)
                                .npSubheading()
                            HStack(spacing: 6) {
                                Image(systemName: noteStateIcon(group.generationState))
                                Text(noteStateTitle(group.generationState))
                            }
                            .font(.caption.weight(.medium))
                            .foregroundStyle(group.generationState == .generating ? NPColors.brand : NPColors.textSecondary)
                            let details = [group.learningUnit.subject, group.learningUnit.gradeLevel, group.learningUnit.topic]
                                .compactMap { $0?.isEmpty == false ? $0 : nil }
                            if !details.isEmpty {
                                Text(details.joined(separator: " · "))
                                    .npCaption()
                            }
                            if group.notes.isEmpty {
                                Text(noteStateMessage(group.generationState))
                                    .npCaption()
                                    .padding(.vertical, NPSpacing.small)
                            }
                            ForEach(group.notes) { item in
                                Button {
                                    model.openStudyNote(item)
                                    readerItem = item
                                } label: {
                                    HStack(spacing: NPSpacing.medium) {
                                        Image(systemName: "note.text")
                                            .npHeading()
                                            .foregroundStyle(NPColors.brand)
                                            .frame(width: 28)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(item.note.title.isEmpty ? localized("Digital Notes") : item.note.title)
                                                .npBody().fontWeight(.medium)
                                                .foregroundStyle(NPColors.textPrimary)
                                                .lineLimit(2)
                                            Text(localizedFormat("note.version", String(item.note.versionNo)))
                                                .npCaption()
                                            Text(item.note.revisionOriginLabel)
                                                .npCaption()
                                            if let summary = item.note.editSummary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
                                                Text(summary)
                                                    .npCaption()
                                                    .lineLimit(1)
                                            }
                                        }
                                        Spacer(minLength: NPSpacing.small)
                                        Image(systemName: "chevron.right")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(NPColors.textSecondary.opacity(0.5))
                                    }
                                    .padding(NPSpacing.card)
                                    .modifier(NPCardModifier())
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("studyNoteRow-\(item.note.id)")
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, NPSpacing.outer)
            .padding(.vertical, NPSpacing.item)
        }
    }

    private func noteStateIcon(_ state: StudyNoteGenerationState) -> String {
        switch state {
        case .noKnowledge: return "tray"
        case .generating: return "hourglass"
        case .ready: return "checkmark.circle"
        case .unavailable: return "exclamationmark.circle"
        }
    }

    private func noteStateTitle(_ state: StudyNoteGenerationState) -> String {
        localized("note.generation.\(state.rawValue).title")
    }

    private func noteStateMessage(_ state: StudyNoteGenerationState) -> String {
        localized("note.generation.\(state.rawValue).message")
    }
}

// MARK: - Study Note Reader

private struct StudyNoteReader: View {
    @ObservedObject var model: NotePatchViewModel

    var body: some View {
        Group {
            if let item = model.selectedStudyNoteItem {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.note.title.isEmpty ? localized("Digital Notes") : item.note.title)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(NPColors.textPrimary)
                        Text("\(item.learningUnit.title) · \(localizedFormat("note.version", String(item.note.versionNo)))")
                            .npBody()
                            .foregroundStyle(NPColors.textSecondary)
                        Text(item.note.revisionOriginLabel)
                            .npCaption()
                        if let summary = item.note.editSummary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
                            Text(summary)
                                .npCaption()
                        }
                    }
                    .padding(.horizontal, NPSpacing.outer)
                    .padding(.top, NPSpacing.item)
                    .padding(.bottom, NPSpacing.small)

                    Divider().overlay(NPColors.divider)

                    if model.isStudyNoteLoading {
                        ProgressView(localized("note.reader.loading"))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let html = model.studyNoteHTML {
                        SafeHTMLNoteView(html: html)
                            .accessibilityIdentifier("studyNoteHTMLReader")
                    } else if let error = model.studyNoteReaderError {
                        VStack(spacing: 14) {
                            NPEmptyState(
                                systemImage: "exclamationmark.triangle",
                                title: localized("note.reader.open_failed"),
                                message: error
                            )
                            Button(localized("common.retry")) {
                                model.openStudyNote(item)
                            }
                            .buttonStyle(NPSecondaryButtonStyle())
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(NPSpacing.outer)
                    }
                }
                .accessibilityIdentifier("studyNoteReader")
                .navigationTitle(localized("note.reader.title"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        if model.canEditSelectedStudyNote {
                            Button(localized("common.edit")) {
                                model.beginStudyNoteEditing()
                            }
                            .disabled(model.isStudyNoteSaving)
                            .accessibilityIdentifier("editStudyNoteButton")
                        }
                    }
                }
            } else {
                NPEmptyState(
                    systemImage: "note.text",
                    title: localized("note.reader.closed.title"),
                    message: localized("note.reader.closed.message")
                )
                .padding(.horizontal, NPSpacing.outer)
                .accessibilityIdentifier("studyNoteReader")
            }
        }
        .sheet(isPresented: $model.isStudyNoteEditorPresented) {
            NavigationStack {
                StudyNoteEditor(model: model)
                    .onDisappear { model.cancelStudyNoteEditing() }
            }
        }
    }
}

// MARK: - Study Note Editor

private struct StudyNoteEditor: View {
    @ObservedObject var model: NotePatchViewModel
    @State private var editorCommand: HTMLNoteCommand?
    @State private var editorCommandToken = 0

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                LabeledField(title: localized("note.editor.title_field")) {
                    TextField(localized("note.editor.title_placeholder"), text: $model.studyNoteDraftTitle)
                        .accessibilityIdentifier("studyNoteEditorTitle")
                }

                richTextToolbar
            }
            .padding(.horizontal, NPSpacing.outer)
            .padding(.top, NPSpacing.small)

            if model.isStudyNoteEditorLoading {
                ProgressView(localized("note.editor.loading"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                RichHTMLNoteEditor(
                    html: $model.studyNoteDraftHTML,
                    command: editorCommand,
                    commandToken: editorCommandToken
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(NPColors.background)
                .clipShape(RoundedRectangle(cornerRadius: NPRadius.input, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: NPRadius.input, style: .continuous)
                        .stroke(NPColors.border, lineWidth: 1)
                )
                .padding(.horizontal, NPSpacing.outer)
                .padding(.vertical, NPSpacing.small)
                .accessibilityIdentifier("studyNoteEditorHTML")
            }

            VStack(alignment: .leading, spacing: 8) {
                LabeledField(title: localized("note.editor.summary_field")) {
                    TextField(localized("note.editor.summary_placeholder"), text: $model.studyNoteDraftSummary)
                        .accessibilityIdentifier("studyNoteEditorSummary")
                }
                Text(localized("note.editor.summary_optional"))
                    .npCaption()
                Text("\(model.studyNoteDraftHTML.count) / 2,000,000")
                    .npCaption()
                    .frame(maxWidth: .infinity, alignment: .trailing)

                if let error = model.studyNoteEditorError {
                    Text(error)
                        .npBody()
                        .foregroundStyle(NPColors.destructive)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(NPColors.destructive.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: NPRadius.button, style: .continuous))
                }
            }
            .padding(.horizontal, NPSpacing.outer)
            .padding(.bottom, NPSpacing.small)
        }
        .navigationTitle(localized("note.editor.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(localized("common.cancel")) {
                    model.cancelStudyNoteEditing()
                }
                .disabled(model.isStudyNoteSaving)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    model.saveStudyNoteRevision()
                } label: {
                    if model.isStudyNoteSaving {
                        ProgressView()
                    } else {
                        Text(localized("common.save"))
                    }
                }
                .disabled(model.isStudyNoteSaving || model.isStudyNoteEditorLoading)
                .accessibilityIdentifier("saveStudyNoteButton")
            }
        }
        .alert(localized("note.editor.conflict.title"), isPresented: $model.isStudyNoteConflictPending) {
            Button(localized("common.cancel"), role: .cancel) {
                model.isStudyNoteConflictPending = false
            }
            Button(localized("note.editor.conflict.continue")) {
                model.confirmStudyNoteConflictAndSave()
            }
        } message: {
            Text(localized("note.editor.conflict.message"))
        }
    }

    private var richTextToolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                editorButton(.undo, systemImage: "arrow.uturn.backward", label: "note.editor.undo")
                editorButton(.redo, systemImage: "arrow.uturn.forward", label: "note.editor.redo")
                Divider().frame(height: 24)
                editorButton(.bold, systemImage: "bold", label: "note.editor.bold")
                editorButton(.italic, systemImage: "italic", label: "note.editor.italic")
                editorButton(.heading2, systemImage: "textformat.size", label: "note.editor.heading")
                editorButton(.unorderedList, systemImage: "list.bullet", label: "note.editor.bullet_list")
                editorButton(.orderedList, systemImage: "list.number", label: "note.editor.numbered_list")
            }
        }
        .frame(height: 40)
    }

    private func editorButton(_ command: HTMLNoteCommand, systemImage: String, label: String) -> some View {
        Button {
            editorCommand = command
            editorCommandToken += 1
        } label: {
            Image(systemName: systemImage)
                .frame(width: 34, height: 34)
        }
        .buttonStyle(.plain)
        .background(NPColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: NPRadius.xs, style: .continuous))
        .accessibilityLabel(localized(label))
    }
}

// MARK: - Documents Tab

private struct DocumentsTab: View {
    @ObservedObject var model: NotePatchViewModel
    @State private var filtersExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            // Brand area
            NotePatchLogoImage(height: 64)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, NPSpacing.outer)
                .padding(.top, NPSpacing.item)
                .padding(.bottom, NPSpacing.xs)

            Text("Patch your knowledge together.")
                .font(.system(size: 13, weight: .regular, design: .default))
                .foregroundStyle(NPColors.textSecondary.opacity(0.7))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, NPSpacing.outer)
                .padding(.bottom, NPSpacing.item)

            // Segmented control
            Picker("Document view", selection: $model.selectedDocumentsSection) {
                ForEach(DocumentsSection.allCases) { section in
                    Text(section.title).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, NPSpacing.outer)
            .padding(.bottom, NPSpacing.large)

            if model.selectedDocumentsSection == .documents {
                documentList
            } else {
                TaskTab(model: model)
            }
        }
    }

    private var documentList: some View {
        ScrollView {
            VStack(spacing: NPSpacing.section) {
                // Filter —
                Button {
                    withAnimation(.npInteractive) { filtersExpanded.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "line.3.horizontal.decrease")
                            .font(.system(size: 12, weight: .medium))
                        Text(activeFilterSummary(status: model.statusFilter, documentKind: model.documentKindFilter, fileType: model.fileTypeFilter))
                            .lineLimit(1)
                        Image(systemName: filtersExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(NPColors.textSecondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(NPColors.surface)
                    .clipShape(Capsule())
                    .shadow(color: NPShadow.small.color, radius: NPShadow.small.radius, x: 0, y: NPShadow.small.y)
                }
                .buttonStyle(.plain)

                if filtersExpanded {
                    NPSection {
                        FilterPanel(model: model)
                    }
                }

                HStack {
                    Text("Documents")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(NPColors.textSecondary)
                        .textCase(.uppercase)
                    Spacer()
                    Text("\(model.documents.count)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(NPColors.textSecondary)
                        .padding(.horizontal, NPSpacing.small)
                        .padding(.vertical, 2)
                        .background(NPColors.interactive.opacity(0.4))
                        .clipShape(Capsule())
                }
                .padding(.top, 6)

                if model.documents.isEmpty {
                    NPEmptyState(systemImage: "doc", title: "No documents", message: "No documents yet. Upload an image, PDF, or file to get started.")
                } else {
                    LazyVStack(spacing: NPSpacing.medium) {
                        ForEach(model.documents) { document in
                            DocumentRow(
                                document: document,
                                artifacts: model.selectedArtifactDocumentId == document.id ? model.selectedArtifacts : [],
                                ocrArtifacts: model.selectedOcrDocumentId == document.id ? model.selectedOcrArtifacts : [],
                                isBusy: model.isBusy,
                                onDownload: { model.downloadAndPreview(document) },
                                onProcess: { model.startProcessing(document) },
                                onDelete: { model.deleteDocument(document) },
                                onArtifacts: { model.loadArtifacts(for: document) },
                                onOCR: { model.loadOcrArtifacts(for: document) },
                                onArtifactDownload: { model.downloadAndPreview($0) },
                                onOcrDownload: { model.downloadAndPreview($0) }
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, NPSpacing.outer)
            .padding(.top, 14)
            .padding(.bottom, NPSpacing.section)
        }
    }

}

// MARK: - Upload Screen (FAB entry point)

private struct UploadScreen: View {
    @ObservedObject var model: NotePatchViewModel
    @Binding var isPresented: Bool
    @State private var isShowingCamera = false
    @State private var isShowingPhotoLibrary = false
    @State private var isShowingFileImporter = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: NPSpacing.xxxl) {
                    // Hero
                    VStack(alignment: .leading, spacing: NPSpacing.small) {
                        Text("Upload")
                            .npTitle()
                        Text("Import your study materials.")
                            .npBody()
                            .foregroundStyle(NPColors.textSecondary)
                    }
                    .padding(.top, NPSpacing.xl)

                    // Upload options
                    VStack(spacing: NPSpacing.medium) {
                        UploadOptionCard(
                            icon: "doc.text.fill",
                            iconColor: NPColors.brand,
                            title: "Import PDF",
                            description: "Import PDF notes and worksheets."
                        ) {
                            isPresented = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                isShowingFileImporter = true
                            }
                        }

                        UploadOptionCard(
                            icon: "camera.fill",
                            iconColor: NPColors.brandDark,
                            title: "Scan Document",
                            description: "Use the camera to scan handwritten notes."
                        ) {
                            isPresented = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                isShowingCamera = true
                            }
                        }

                        UploadOptionCard(
                            icon: "photo.on.rectangle.fill",
                            iconColor: NPColors.brand,
                            title: "Import Photos",
                            description: "Choose images from the photo library."
                        ) {
                            isPresented = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                isShowingPhotoLibrary = true
                            }
                        }

                        UploadOptionCard(
                            icon: "folder.fill",
                            iconColor: NPColors.brandDark,
                            title: "Import Files",
                            description: "Browse Files and Cloud Storage."
                        ) {
                            isPresented = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                isShowingFileImporter = true
                            }
                        }
                    }
                }
                .padding(.horizontal, NPSpacing.outer)
                .padding(.bottom, NPSpacing.xxxl)
            }
            .background(NPColors.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        isPresented = false
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $isShowingFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                model.uploadPickedFiles(from: urls)
            }
        }
        .sheet(isPresented: $isShowingCamera) {
            CameraPicker { image in
                model.uploadCameraImage(image)
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $isShowingPhotoLibrary) {
            PhotoLibraryPicker(cacheDirectory: model.uploadCacheDirectory) { result in
                isShowingPhotoLibrary = false
                guard let result else { return }
                switch result {
                case .success(let files):
                    model.stageImportedUploadFiles(files)
                case .failure(let error):
                    model.errorMessage = friendlyError(error)
                }
            }
            .ignoresSafeArea()
        }
    }
}

private struct UploadOptionCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    let action: () -> Void
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: NPSpacing.large) {
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(iconColor)
                    .frame(width: 48, height: 48)
                    .background(iconColor.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: NPRadius.medium, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(localized(title))
                        .npSubheading()
                    Text(localized(description))
                        .npCallout()
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(NPColors.textTertiary)
            }
            .padding(NPSpacing.large)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NPColors.surfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: NPRadius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: NPRadius.card, style: .continuous)
                    .stroke(Color.white.opacity(0.70), lineWidth: 0.5)
            }
            .shadow(
                color: NPShadow.medium.color,
                radius: NPShadow.medium.radius,
                x: 0,
                y: NPShadow.medium.y
            )
            .scaleEffect(isPressed ? 0.985 : 1.0)
        }
        .buttonStyle(.plain)
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            withAnimation(Animation.npButton) { isPressed = pressing }
        }, perform: {})
    }
}

// MARK: - Upload Document Screen

private struct UploadDocumentScreen: View {
    @ObservedObject var model: NotePatchViewModel
    @State private var isShowingCamera = false
    @State private var isShowingPhotoLibrary = false
    @State private var isShowingFileImporter = false
    @State private var queuedPreview: DownloadedPreview?

    var body: some View {
        ScrollView {
            VStack(spacing: NPSpacing.section) {
                NPSection {
                    UploadPanel(
                        model: model,
                        onCameraUpload: { isShowingCamera = true },
                        onGalleryUpload: { isShowingPhotoLibrary = true },
                        onFileUpload: { isShowingFileImporter = true }
                    )
                }

                NPSection {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("Pending", systemImage: "tray.and.arrow.up")
                                .npSubheading()
                            Spacer()
                            Text(localizedFormat("upload.items_count", String(model.queuedUploadItems.count)))
                                .npCaption()
                        }

                        if model.queuedUploadItems.isEmpty {
                            NPEmptyState(
                                systemImage: "tray",
                                title: "No pending files",
                                message: "Selected files, photos, or camera captures will appear here."
                            )
                        } else {
                            LazyVStack(spacing: 10) {
                                ForEach(model.queuedUploadItems) { item in
                                    QueuedUploadRow(
                                        item: item,
                                        isBusy: model.isBusy,
                                        onToggle: { model.toggleQueuedUpload(item.id) },
                                        onPreview: { queuedPreview = DownloadedPreview(url: item.file.url, mimeType: item.file.mimeType) },
                                        onRemove: { model.removeQueuedUpload(item.id) }
                                    )
                                }
                            }

                            Button {
                                model.uploadSelectedQueuedFiles()
                            } label: {
                                Label(localizedFormat("upload.selected_count", String(model.queuedUploadItems.filter(\.isSelected).count)), systemImage: "arrow.up.circle.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(NPPrimaryButtonStyle())
                            .disabled(model.isBusy || !model.queuedUploadItems.contains(where: \.isSelected))
                            .accessibilityIdentifier("uploadSelectedQueueButton")
                        }
                    }
                }
            }
            .padding(.horizontal, NPSpacing.outer)
            .padding(.top, 14)
            .padding(.bottom, NPSpacing.section)
        }
        .background(NPColors.background.ignoresSafeArea())
        .fileImporter(isPresented: $isShowingFileImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                model.uploadPickedFiles(from: urls)
            }
        }
        .sheet(isPresented: $isShowingCamera) {
            CameraPicker { image in
                model.uploadCameraImage(image)
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $isShowingPhotoLibrary) {
            PhotoLibraryPicker(cacheDirectory: model.uploadCacheDirectory) { result in
                isShowingPhotoLibrary = false
                guard let result else { return }
                switch result {
                case .success(let files):
                    model.stageImportedUploadFiles(files)
                case .failure(let error):
                    model.errorMessage = friendlyError(error)
                }
            }
            .ignoresSafeArea()
        }
        .sheet(item: $queuedPreview) { preview in
            if preview.isImage {
                ImagePreview(url: preview.url)
            } else {
                QuickLookPreview(url: preview.url)
            }
        }
    }
}

private struct QueuedUploadRow: View {
    let item: QueuedUploadItem
    let isBusy: Bool
    let onToggle: () -> Void
    let onPreview: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: onToggle) {
                Image(systemName: item.isSelected ? "checkmark.circle.fill" : "circle")
                    .npHeading()
                    .foregroundStyle(item.isSelected ? NPColors.brand : NPColors.textSecondary)
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
            .accessibilityLabel(localizedFormat(
                item.isSelected ? "accessibility.deselect_file" : "accessibility.select_file",
                item.file.filename
            ))

            UploadThumbnailView(file: item.file, onPreview: onPreview)
                .disabled(isBusy)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.file.filename)
                    .npBody().fontWeight(.medium)
                    .foregroundStyle(NPColors.textPrimary)
                    .lineLimit(2)
                Text("\(documentKindLabel(item.documentKind)) · \(formatBytes(item.file.fileSize))")
                    .npCaption()
                queueStateView
            }

            Spacer(minLength: 0)

            Button(action: onPreview) {
                Image(systemName: "eye")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
            .accessibilityLabel(localizedFormat("accessibility.preview_file", item.file.filename))

            Button(role: .destructive, action: onRemove) {
                Image(systemName: "trash")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
            .accessibilityLabel(localizedFormat("accessibility.remove_file", item.file.filename))
        }
        .padding(NPSpacing.small)
        .background(NPColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: NPRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: NPRadius.card, style: .continuous)
                .stroke(NPColors.border, lineWidth: 1)
        }
    }

    @ViewBuilder
    private var queueStateView: some View {
        switch item.state {
        case .pending:
            EmptyView()
        case .uploading:
            Label("Uploading", systemImage: "arrow.up.circle")
                .npCaption()
                .foregroundStyle(NPColors.brand)
        case .failed(let message):
            Text(message)
                .npCaption()
                .foregroundStyle(NPColors.destructive)
                .lineLimit(2)
        }
    }
}

private struct UploadPanel: View {
    @ObservedObject var model: NotePatchViewModel
    let onCameraUpload: () -> Void
    let onGalleryUpload: () -> Void
    let onFileUpload: () -> Void
    @State private var isLearningInfoExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("Document type")

            ChoiceGrid(minimum: 76) {
                ForEach(["homework", "corrected_homework", "courseware", "note", "exam", "answer_key", "rubric", "other"], id: \.self) { kind in
                    ChoiceButton(text: documentKindLabel(kind), selected: model.uploadDocumentKind == kind, enabled: !model.isBusy) {
                        model.uploadDocumentKind = kind
                    }
                }
            }

            HStack(spacing: NPSpacing.small) {
                UploadSourceButton(title: "Camera", systemImage: "camera.fill", emphasized: true, enabled: !model.isBusy && UIImagePickerController.isSourceTypeAvailable(.camera), action: onCameraUpload)
                UploadSourceButton(title: "Photos", systemImage: "photo.on.rectangle", emphasized: false, enabled: !model.isBusy, action: onGalleryUpload)
                UploadSourceButton(title: "File", systemImage: "folder", emphasized: false, enabled: !model.isBusy, action: onFileUpload)
            }

            if let progress = model.uploadProgressPercent {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(model.uploadProgressLabel)
                        Spacer()
                        Text("\(progress)%")
                            .monospacedDigit()
                    }
                    .npCaption()
                    ProgressView(value: Double(progress), total: 100)
                }
                .padding(.top, 2)
            }

            DisclosureGroup("Learning info", isExpanded: $isLearningInfoExpanded) {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Learning unit", selection: $model.uploadLearningUnitId) {
                        Text("Auto-create or categorize").tag("")
                        ForEach(model.learningUnits) { unit in
                            Text(unit.title).tag(unit.id)
                        }
                    }
                    .pickerStyle(.menu)
                    if model.uploadLearningUnitId.isEmpty {
                        LabeledField(title: "Unit title") {
                            TextField("e.g. Scores & Ratios", text: $model.uploadLearningUnitTitle)
                        }
                    }
                    LabeledField(title: "Subject") {
                        TextField("e.g. Math", text: $model.uploadSubject)
                    }
                    HStack(spacing: 10) {
                        LabeledField(title: "Grade") {
                            TextField("Grade 7", text: $model.uploadGradeLevel)
                        }
                        LabeledField(title: "Topic") {
                            TextField("Ratios", text: $model.uploadTopic)
                        }
                    }
                }
                .padding(.top, NPSpacing.small)
            }
            .npBody().fontWeight(.medium)
            .foregroundStyle(NPColors.textPrimary)
        }
    }
}

private struct UploadSourceButton: View {
    let title: String
    let systemImage: String
    let emphasized: Bool
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            UploadSourceLabel(title: title, systemImage: systemImage)
        }
        .buttonStyle(UploadSourceButtonStyle(emphasized: emphasized))
        .disabled(!enabled)
    }
}

private struct UploadSourceLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 19, weight: .medium))
            Text(localized(title))
                .font(.caption.weight(.medium))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 62)
    }
}

private struct UploadSourceButtonStyle: ButtonStyle {
    let emphasized: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(emphasized ? .white : NPColors.brandDark)
            .background(
                RoundedRectangle(cornerRadius: NPRadius.button, style: .continuous)
                    .fill(emphasized ? NPColors.brand : NPColors.brandLight)
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.npInteractive, value: configuration.isPressed)
    }
}

private struct FilterPanel: View {
    @ObservedObject var model: NotePatchViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FilterChoices(
                label: "Status",
                values: ["", "created", "uploading", "uploaded", "processing", "ready", "failed"],
                selected: model.statusFilter,
                enabled: !model.isBusy,
                onChange: model.setStatusFilter
            )
            FilterChoices(
                label: "Type",
                values: ["", "homework", "corrected_homework", "courseware", "note", "exam", "answer_key", "rubric", "other"],
                selected: model.documentKindFilter,
                enabled: !model.isBusy,
                onChange: model.setDocumentKindFilter
            )
            FilterChoices(
                label: "File",
                values: ["", "image", "pdf", "docx", "pptx", "audio", "video", "other"],
                selected: model.fileTypeFilter,
                enabled: !model.isBusy,
                onChange: model.setFileTypeFilter
            )
        }
    }
}

private struct FilterChoices: View {
    let label: String
    let values: [String]
    let selected: String
    let enabled: Bool
    let onChange: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionLabel(label)
            ChoiceGrid(minimum: 72) {
                ForEach(values, id: \.self) { value in
                    ChoiceButton(text: filterChoiceLabel(value), selected: selected == value, enabled: enabled) {
                        onChange(value)
                    }
                }
            }
        }
    }
}

private struct DocumentRow: View {
    let document: LearningDocumentItem
    let artifacts: [DocumentArtifactItem]
    let ocrArtifacts: [OcrArtifactItem]
    let isBusy: Bool
    let onDownload: () -> Void
    let onProcess: () -> Void
    let onDelete: () -> Void
    let onArtifacts: () -> Void
    let onOCR: () -> Void
    let onArtifactDownload: (DocumentArtifactItem) -> Void
    let onOcrDownload: (OcrArtifactItem) -> Void
    @State private var detailsExpanded = false

    var body: some View {
        NPSection {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(document.title ?? document.originalFilename)
                            .npSubheading()
                            .lineLimit(2)
                        Text("\(documentKindLabel(document.documentKind)) · \(fileTypeLabel(document.fileType))")
                            .npCaption()
                            .lineLimit(1)
                        Text("\(formatBytes(document.fileSize)) · \(compactDateTime(document.createdAt))")
                            .npCaption()
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    NPStatusChip(text: statusLabel(document.status), variant: statusChipVariant(document.status))
                }

                HStack(spacing: NPSpacing.small) {
                    Button(action: onProcess) {
                        Label(processTitle, systemImage: "wand.and.stars")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(NPDocumentPrimaryButtonStyle())
                    .disabled(isBusy || !canProcess)

                    Button(action: onDownload) {
                        Image(systemName: "arrow.down.to.line")
                    }
                    .buttonStyle(NPDocumentIconButtonStyle())
                    .disabled(isBusy || document.status == "deleted")
                    .accessibilityLabel("Download")

                    Menu {
                        Button(action: onOCR) {
                            Label("OCR Results", systemImage: "text.viewfinder")
                        }
                        .disabled(isBusy || document.status != "ready")
                        Button(action: onArtifacts) {
                            Label("Artifacts", systemImage: "tray.full")
                        }
                        Button {
                            detailsExpanded.toggle()
                        } label: {
                            Label(detailsExpanded ? "Hide details" : "View details", systemImage: "info.circle")
                        }
                        Divider()
                        Button(role: .destructive, action: onDelete) {
                            Label("Delete document", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .buttonStyle(NPDocumentIconButtonStyle())
                    .disabled(isBusy)
                    .accessibilityLabel("More actions")
                }

                if detailsExpanded {
                    Divider().background(NPColors.interactive.opacity(0.4))
                    DetailText("mime: \(document.mimeType ?? "unknown")")
                    if let sha256 = document.sha256 {
                        DetailText("sha256: \(sha256)")
                    }
                    DetailText("updated: \(document.updatedAt)")
                }

                if !artifacts.isEmpty {
                    Divider().background(NPColors.interactive.opacity(0.4))
                    SectionLabel("Artifacts")
                    ForEach(artifacts) { artifact in
                        HStack(alignment: .firstTextBaseline, spacing: NPSpacing.small) {
                            DetailText(
                                [
                                    artifactTypeLabel(artifact.artifactType),
                                    artifact.mimeType,
                                    formatBytes(artifact.fileSize),
                                    artifact.metadataProcessor.map { "processor=\($0)" }
                                ].compactMap { $0 }.joined(separator: " · ")
                            )
                            Spacer(minLength: 0)
                            IconButton(systemImage: "arrow.down.circle", accessibilityLabel: "Download artifact", enabled: !isBusy) {
                                onArtifactDownload(artifact)
                            }
                        }
                        if let metadataText = artifact.metadataText {
                            DetailText("metadata: \(metadataText)", lineLimit: 2)
                        }
                    }
                }

                if !ocrArtifacts.isEmpty {
                    Divider().background(NPColors.interactive.opacity(0.4))
                    VStack(alignment: .leading, spacing: NPSpacing.small) {
                        SectionLabel("OCR Results")
                        ForEach(ocrArtifacts) { artifact in
                            HStack(alignment: .firstTextBaseline, spacing: NPSpacing.small) {
                                DetailText(
                                    [
                                        artifactTypeLabel(artifact.artifactType),
                                        artifact.mimeType,
                                        formatBytes(artifact.fileSize),
                                        compactDateTime(artifact.createdAt)
                                    ].compactMap { $0 }.joined(separator: " · ")
                                )
                                Spacer(minLength: 0)
                                IconButton(systemImage: "arrow.down.circle", accessibilityLabel: "Download OCR result", enabled: !isBusy && artifact.downloadURL?.isEmpty == false) {
                                    onOcrDownload(artifact)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var processTitle: String {
        document.status == "ready" || document.status == "failed" ? "Reprocess" : "Process"
    }

    private var canProcess: Bool {
        document.status == "uploaded" || document.status == "ready" || document.status == "failed"
    }
}

private struct TaskTab: View {
    @ObservedObject var model: NotePatchViewModel

    var body: some View {
        ScrollView {
            TaskPanel(
                activeTask: model.activeTask,
                events: model.taskEvents,
                canRetryDocumentPurge: model.canRetryDocumentPurge,
                onRetryDocumentPurge: model.retryDocumentPurge
            )
                .padding(.horizontal, NPSpacing.outer)
                .padding(.top, 14)
                .padding(.bottom, NPSpacing.section)
        }
    }
}

private struct TaskPanel: View {
    let activeTask: TaskItem?
    let events: [TaskEventItem]
    let canRetryDocumentPurge: Bool
    let onRetryDocumentPurge: () -> Void
    @State private var resultExpanded = false
    @State private var eventsExpanded = false

    var body: some View {
        NPSection {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Active task", systemImage: "clock.arrow.circlepath")
                        .npSubheading()
                        .foregroundStyle(NPColors.textPrimary)
                    Spacer()
                    if let activeTask {
                        NPStatusChip(text: taskStatusLabel(activeTask), variant: taskStatusChipVariant(activeTask))
                    }
                }

                if let activeTask {
                    VStack(alignment: .leading, spacing: NPSpacing.small) {
                        HStack {
                            Text(taskTypeLabel(activeTask.taskType))
                                .npBody().fontWeight(.medium)
                                .foregroundStyle(NPColors.textPrimary)
                                .lineLimit(1)
                            Spacer()
                            Text("\(activeTask.progress.clamped(to: 0...100))%")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(NPColors.textSecondary)
                        }
                        ProgressView(value: Double(activeTask.progress.clamped(to: 0...100)), total: 100)
                    }
                    HStack(spacing: NPSpacing.item) {
                        if let startedAt = activeTask.startedAt {
                            TaskTime(label: "Started", value: compactDateTime(startedAt))
                        }
                        if let finishedAt = activeTask.finishedAt {
                            TaskTime(label: "Completed", value: compactDateTime(finishedAt))
                        }
                        if let cancelRequestedAt = activeTask.cancelRequestedAt {
                            TaskTime(label: "Cancel requested", value: compactDateTime(cancelRequestedAt))
                        }
                    }
                    if let taskMessage = terminalMessage(for: activeTask) {
                        let isCancelled = activeTask.status == "cancelled"
                        let msgColor: Color = isCancelled ? NPColors.warning : NPColors.destructive
                        Label(taskMessage, systemImage: "exclamationmark.triangle.fill")
                            .npBody()
                            .foregroundStyle(msgColor)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(msgColor.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: NPRadius.button, style: .continuous))
                    }
                    if let resultText = activeTask.resultText {
                        DisclosureGroup("Task result", isExpanded: $resultExpanded) {
                            DetailText(resultText, lineLimit: nil)
                                .padding(.top, 6)
                        }
                        .npBody().fontWeight(.medium)
                    }
                    if canRetryDocumentPurge {
                        Button(action: onRetryDocumentPurge) {
                            Label("Retry cleanup", systemImage: "arrow.clockwise")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(NPPrimaryButtonStyle())
                        .accessibilityIdentifier("retryDocumentPurgeButton")
                    }
                } else {
                    NPEmptyState(
                        systemImage: "checkmark.circle",
                        title: "No active tasks",
                        message: "Progress will appear here after processing documents or asking AI Co-pilot."
                    )
                }

                if !events.isEmpty {
                    Divider().background(NPColors.interactive.opacity(0.4))
                    HStack {
                        SectionLabel("Event log")
                        Spacer()
                        Button(eventsExpanded ? "Collapse" : "View all") {
                            eventsExpanded.toggle()
                        }
                        .npCaption()
                    }

                    ForEach(visibleEvents) { event in
                        HStack(alignment: .top, spacing: NPSpacing.small) {
                            Circle()
                                .fill(event.level == "error" ? NPColors.destructive : NPColors.textSecondary.opacity(0.5))
                                .frame(width: 6, height: 6)
                                .padding(.top, 5)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(event.progress.map { "\($0)% · " } ?? "")\(event.message)")
                                    .npCaption()
                                    .foregroundStyle(event.level == "error" ? NPColors.destructive : NPColors.textPrimary)
                                    .lineLimit(eventsExpanded ? 3 : 1)
                                if eventsExpanded, let dataText = event.dataText {
                                    DetailText(dataText, lineLimit: 2)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var visibleEvents: [TaskEventItem] {
        if eventsExpanded {
            return events
        }
        let recent = Array(events.suffix(4))
        if let latestError = events.last(where: { $0.level == "error" }),
           !recent.contains(latestError) {
            return [latestError] + recent.suffix(3)
        }
        return recent
    }

    private func terminalMessage(for task: TaskItem) -> String? {
        if task.status == "cancelled" {
            return events.last(where: { $0.eventType.contains("cancel") })?.message
                ?? events.last(where: { $0.level == "error" })?.message
                ?? events.last?.message
                ?? task.errorMessage
                ?? "Task cancelled."
        }
        return task.errorMessage
    }
}

private struct TaskTime: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .npCaption()
                .foregroundStyle(NPColors.textSecondary)
            Text(value)
                .npCaption()
                .foregroundStyle(NPColors.textPrimary)
                .lineLimit(1)
        }
    }
}

// MARK: - OpenClaw Chat Tab

private struct OpenClawChatTab: View {
    let model: NotePatchViewModel
    @ObservedObject var chatState: OpenClawViewState
    @ObservedObject var composerState: OpenClawComposerState
    @State private var isRenaming = false
    @State private var titleDraft = ""
    @State private var isComposerFocused = false
    @State private var isShowingAIPhotoLibrary = false
    @State private var isShowingAIFileImporter = false

    var body: some View {
        VStack(spacing: 0) {
            // ——— Brand Hero ———
            ScrollView {
                VStack(spacing: 0) {
                    NotePatchLogoImage(height: 64)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, NPSpacing.outer)
                        .padding(.top, NPSpacing.item)
                        .padding(.bottom, NPSpacing.xs)

                    Text("Patch your knowledge together.")
                        .font(.system(size: 13, weight: .regular, design: .default))
                        .foregroundStyle(NPColors.textSecondary.opacity(0.7))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, NPSpacing.outer)
                        .padding(.bottom, NPSpacing.item)

                    // ——— Conversation header ———
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(chatState.selectedConversation?.title ?? localized("New conversation"))
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(NPColors.textPrimary)
                                .lineLimit(1)
                                .accessibilityIdentifier("openClawTab")
                            Text(chatState.selectedConversation == nil
                                 ? localized("chat.ai.auto_saved_after_first_message")
                                 : localized("chat.ai.saved_session"))
                                .font(.system(size: 12, weight: .regular))
                                .foregroundStyle(NPColors.textSecondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Menu {
                            Button {
                                dismissComposer()
                                model.startNewConversation()
                            } label: {
                                Label("New conversation", systemImage: "square.and.pencil")
                            }
                            if let conversation = chatState.selectedConversation {
                                Button {
                                    dismissComposer()
                                    titleDraft = conversation.title
                                    isRenaming = true
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    dismissComposer()
                                    model.deleteCurrentConversation()
                                } label: {
                                    Label("Delete conversation", systemImage: "trash")
                                }
                            }
                            if !chatState.conversations.isEmpty {
                                Divider()
                                ForEach(chatState.conversations) { conversation in
                                    Button {
                                        dismissComposer()
                                        model.selectConversation(conversation.id)
                                    } label: {
                                        Label(conversation.title, systemImage: conversation.id == chatState.selectedConversationId ? "checkmark" : "bubble.left")
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(NPColors.textSecondary)
                                .frame(width: 40, height: 40)
                                .background(NPColors.interactive.opacity(0.4))
                                .clipShape(Circle())
                        }
                        .disabled(chatState.isHistoryLoading || chatState.isConversationMutating)
                        .accessibilityLabel("Conversation actions")
                    }
                    .padding(.horizontal, NPSpacing.outer)
                    .padding(.vertical, 14)
                    .background(NPColors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: NPRadius.card, style: .continuous))
                    .modifier(NPCardShadow())
                    .padding(.horizontal, NPSpacing.outer)
                    .padding(.bottom, NPSpacing.large)

                    // ——— Welcome card ———
                    if chatState.messages.isEmpty {
                        NPSection {
                            VStack(spacing: NPSpacing.small) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 28, weight: .light))
                                    .foregroundStyle(NPColors.brand)
                                    .padding(.bottom, NPSpacing.xs)
                                Text("How can NotePatch AI help today?")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(NPColors.textPrimary)
                                Text("Organize ideas, summarize notes, and analyze your documents with Markdown support.")
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundStyle(NPColors.textSecondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, NPSpacing.xs)
                        }
                        .padding(.horizontal, NPSpacing.outer)
                    }

                    // ——— Messages ———
                    ScrollViewReader { proxy in
                        LazyVStack(spacing: NPSpacing.medium) {
                            ForEach(chatState.messages) { message in
                                OpenClawMessageBubble(message: message)
                                    .id(message.id)
                            }
                        }
                        .padding(.horizontal, NPSpacing.outer)
                        .padding(.vertical, 14)
                        .onChange(of: chatState.messages.count) { _, _ in
                            if let last = chatState.messages.last {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    proxy.scrollTo(last.id, anchor: .bottom)
                                }
                            }
                        }
                    }
                    .accessibilityIdentifier("openClawMessages")
                }
            }

            // ——— Composer bar ———
            VStack(spacing: 0) {
                Divider().background(NPColors.interactive.opacity(0.4))
                composer
                    .padding(.horizontal, NPSpacing.outer)
                    .padding(.vertical, 10)
                    .animation(.npInteractive, value: isComposerExpanded)
            }
            .background(.thinMaterial)
        }
        .onDisappear { dismissComposer() }
        .fileImporter(
            isPresented: $isShowingAIFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                addAIFileAttachments(urls)
            } else if case .failure(let error) = result {
                model.errorMessage = friendlyError(error)
            }
        }
        .sheet(isPresented: $isShowingAIPhotoLibrary) {
            PhotoLibraryPicker(cacheDirectory: aiAttachmentCacheDirectory) { result in
                isShowingAIPhotoLibrary = false
                guard let result else { return }
                switch result {
                case .success(let files):
                    composerState.attachments.append(contentsOf: files)
                case .failure(let error):
                    model.errorMessage = friendlyError(error)
                }
            }
            .ignoresSafeArea()
        }
        .alert("Rename conversation", isPresented: $isRenaming) {
            TextField("Conversation title", text: $titleDraft)
            Button("Cancel", role: .cancel) {}
            Button("Save") { model.renameCurrentConversation(to: titleDraft) }
                .disabled(
                    chatState.isConversationMutating ||
                    titleDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    titleDraft.trimmingCharacters(in: .whitespacesAndNewlines).count > 160
                )
        }
    }

    private func dismissComposer() {
        isComposerFocused = false
        dismissActiveKeyboard()
    }

    private func dismissKeyboardIfNeeded(
        startLocation: CGPoint,
        location: CGPoint,
        translation: CGSize,
        scrollBottomY: CGFloat
    ) {
        guard translation.height > 12,
              translation.height > abs(translation.width),
              startLocation.y < scrollBottomY,
              location.y >= scrollBottomY + composerState.measuredTextHeight else {
            return
        }
        dismissComposer()
    }

    private var isComposerExpanded: Bool {
        isComposerFocused || !composerState.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var composer: some View {
        let expanded = isComposerExpanded
        let composerHeight = expanded ? max(92, composerState.measuredTextHeight + 62) : 44

        return VStack(spacing: NPSpacing.small) {
            if !composerState.attachments.isEmpty {
                aiAttachmentStrip
            }

            GeometryReader { geometry in
                let textHorizontalInset = expanded ? NPSpacing.small : 54
                let textViewWidth = max(0, geometry.size.width)

                ZStack(alignment: .topLeading) {
                    if expanded {
                        RoundedRectangle(cornerRadius: NPRadius.sheet, style: .continuous)
                            .fill(NPColors.surface)
                            .modifier(NPCardShadow())
                    }

                    Text("Ask AI Co-pilot")
                        .foregroundStyle(NPColors.textSecondary)
                        .padding(.leading, expanded ? NPSpacing.outer : 54)
                        .padding(.trailing, expanded ? NPSpacing.outer : 54)
                        .padding(.top, expanded ? 19 : 11)
                        .opacity(composerState.text.isEmpty ? 1 : 0)
                        .allowsHitTesting(false)

                    AdaptiveComposerTextView(
                        text: $composerState.text,
                        isFocused: Binding(
                            get: { isComposerFocused },
                            set: { isComposerFocused = $0 }
                        ),
                        height: $composerState.measuredTextHeight,
                        availableWidth: textViewWidth,
                        horizontalInset: textHorizontalInset,
                        maximumLines: expanded ? 7 : 1
                    )
                    .frame(
                        width: textViewWidth,
                        height: expanded ? composerState.measuredTextHeight : 44
                    )
                    .padding(.top, expanded ? NPSpacing.small : 0)
                    .padding(.bottom, expanded ? 46 : 0)
                    .disabled(chatState.isSending)

                    HStack(spacing: 10) {
                        composerAttachmentButton
                        Spacer(minLength: 0)
                        composerSendButton
                    }
                    .padding(.horizontal, expanded ? NPSpacing.small : 0)
                    .frame(height: 38)
                    .padding(.bottom, expanded ? NPSpacing.small : 0)
                    .frame(maxHeight: .infinity, alignment: expanded ? .bottom : .center)
                }
                .frame(
                    width: geometry.size.width,
                    height: composerHeight,
                    alignment: .topLeading
                )
            }
            .frame(height: composerHeight)
        }
    }

    private var composerAttachmentButton: some View {
        Menu {
            Button {
                dismissComposer()
                isShowingAIPhotoLibrary = true
            } label: {
                Label("Choose photo", systemImage: "photo.on.rectangle")
            }
            Button {
                dismissComposer()
                isShowingAIFileImporter = true
            } label: {
                Label("Choose file", systemImage: "folder")
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 38, height: 38)
        }
        .foregroundStyle(NPColors.textSecondary)
        .accessibilityLabel("Add attachment")
        .accessibilityIdentifier("openClawAttachmentButton")
        .disabled(chatState.isSending)
    }

    private var aiAttachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: NPSpacing.small) {
                ForEach(composerState.attachments) { file in
                    AIComposerAttachmentChip(file: file) {
                        removeAIDraftAttachment(file)
                    }
                }
            }
            .padding(.horizontal, 1)
        }
        .frame(height: 46)
    }

    private func addAIFileAttachments(_ urls: [URL]) {
        let cacheDirectory = aiAttachmentCacheDirectory
        Task {
            let outcomes = await FileImportService.shared.importFiles(
                urls,
                fallbackPrefix: "ai-attachment",
                cacheDirectory: cacheDirectory
            )
            composerState.attachments.append(contentsOf: outcomes.compactMap(\.file))
            if let message = outcomes.compactMap(\.errorMessage).first {
                model.errorMessage = message
            }
        }
    }

    private func removeAIDraftAttachment(_ file: LocalUploadFile) {
        composerState.removeAttachment(file)
        UploadThumbnailCache.shared.remove(file: file)
        Task.detached(priority: .utility) {
            try? FileManager.default.removeItem(at: file.url)
        }
    }

    private var aiAttachmentCacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
    }

    private var composerSendButton: some View {
        let canSend = !chatState.isSending && !composerState.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        return Button {
            dismissComposer()
            if model.startOpenClawChat(prompt: composerState.text) {
                composerState.clearDraft(removeAttachmentFiles: true)
            }
        } label: {
            Image(systemName: "arrow.up")
                .font(.system(size: 16, weight: .bold))
                .frame(width: 38, height: 38)
        }
        .buttonStyle(.plain)
        .foregroundStyle(canSend ? NPColors.surface : NPColors.textSecondary)
        .background {
            Circle()
                .fill(canSend ? NPColors.brand : NPColors.textSecondary.opacity(0.18))
        }
        .clipShape(Circle())
        .frame(width: 38, height: 38)
        .contentShape(Circle())
        .disabled(!canSend)
        .accessibilityLabel("Send")
        .accessibilityIdentifier("openClawSendButton")
    }
}

private struct AIComposerAttachmentChip: View {
    let file: LocalUploadFile
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 7) {
            attachmentIcon

            Text(file.filename)
                .npCaption()
                .lineLimit(1)
                .frame(maxWidth: 128, alignment: .leading)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundStyle(NPColors.textSecondary)
            .accessibilityLabel(localizedFormat("accessibility.remove_file", file.filename))
        }
        .padding(.leading, 7)
        .padding(.trailing, 4)
        .frame(height: 40)
        .background(NPColors.surface)
        .clipShape(Capsule())
        .overlay {
            Capsule().stroke(NPColors.border, lineWidth: 1)
        }
    }

    @ViewBuilder
    private var attachmentIcon: some View {
        UploadThumbnailImage(
            file: file,
            size: CGSize(width: 30, height: 30),
            cornerRadius: 6
        )
    }
}

private func dismissActiveKeyboard() {
    UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap { $0.windows }
        .first { $0.isKeyWindow }?
        .endEditing(true)
}

// MARK: - Learning Tab

private struct LearningTab: View {
    @ObservedObject var model: NotePatchViewModel
    let onOpenNote: (StudyNoteListItem) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Picker("Learning view", selection: $model.selectedLearningSection) {
                ForEach(LearningSection.allCases) { section in
                    Text(section.title).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, NPSpacing.outer)
            .padding(.top, NPSpacing.xs)
            .padding(.bottom, 12)
            .accessibilityIdentifier("reviewSectionPicker")

            ScrollView {
                Group {
                    switch model.selectedLearningSection {
                    case .units:
                        LearningUnitsSection(model: model, onOpenNote: onOpenNote)
                    case .search:
                        KnowledgeSearchSection(model: model)
                    case .grading:
                        HomeworkGradingSection(model: model)
                    case .flashcards:
                        FlashcardsSection(model: model)
                    }
                }
                .padding(.horizontal, NPSpacing.outer)
                .padding(.bottom, NPSpacing.section)
            }
        }
        .onChange(of: model.selectedLearningSection) { _, section in
            if section == .flashcards {
                model.ensureFlashcardsLoaded()
            }
        }
    }
}

private struct LearningUnitsSection: View {
    @ObservedObject var model: NotePatchViewModel
    let onOpenNote: (StudyNoteListItem) -> Void

    var body: some View {
        LazyVStack(alignment: .leading, spacing: NPSpacing.item) {
            LearningSectionHeader(title: "Learning units", subtitle: "Auto-organized results from your workspace", isLoading: model.isLearningLoading) {
                model.loadLearningUnits(allowOfflineNetwork: true)
            }
            if model.isLearningLoading && model.learningUnits.isEmpty {
                ProgressView("Loading learning units...")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
            } else if model.learningUnits.isEmpty {
                LearningEmptyState()
            } else {
                ForEach(model.learningUnits) { unit in
                    Button { model.selectLearningUnit(unit.id) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(unit.title).npSubheading().lineLimit(2)
                                Spacer()
                                if unit.id == model.selectedLearningUnitId {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(NPColors.brand)
                                }
                            }
                            let details = [unit.subject, unit.gradeLevel, unit.topic].compactMap { $0?.isEmpty == false ? $0 : nil }
                            if !details.isEmpty {
                                Text(details.joined(separator: " · ")).npCaption()
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .modifier(NPCardModifier())
                    }
                    .buttonStyle(.plain)
                }
            }
            if model.selectedLearningUnitId != nil {
                Text(localized("Digital Notes")).npSubheading().padding(.top, 6)
                if model.studyNotes.isEmpty {
                    Text(localized("notes.unit.empty"))
                        .npBody()
                        .foregroundStyle(NPColors.textSecondary)
                } else {
                    ForEach(model.studyNotes) { note in
                        HStack(spacing: NPSpacing.medium) {
                            Image(systemName: "note.text").foregroundStyle(NPColors.brand)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(note.title.isEmpty ? localized("Digital Notes") : note.title).npBody().fontWeight(.medium).lineLimit(2)
                                Text(localizedFormat("note.version", String(note.versionNo))).npCaption()
                            }
                            Spacer()
                            Button {
                                guard let unit = model.learningUnits.first(where: { $0.id == model.selectedLearningUnitId }) else {
                                    return
                                }
                                onOpenNote(StudyNoteListItem(learningUnit: unit, note: note))
                            } label: {
                                Image(systemName: "eye")
                            }
                                .buttonStyle(NPSecondaryButtonStyle())
                                .accessibilityLabel(localized("note.preview"))
                        }
                        .modifier(NPCardModifier())
                    }
                }
            }
        }
    }
}

private struct FlashcardsSection: View {
    @ObservedObject var model: NotePatchViewModel

    var body: some View {
        LazyVStack(alignment: .leading, spacing: NPSpacing.item) {
            LearningSectionHeader(
                title: localized("flashcards.title"),
                subtitle: localized("flashcards.subtitle"),
                isLoading: model.isFlashcardsLoading
            ) {
                model.ensureFlashcardsLoaded(force: true)
            }

            if model.learningUnits.isEmpty {
                NPEmptyState(
                    systemImage: "rectangle.stack",
                    title: localized("flashcards.no_units.title"),
                    message: localized("flashcards.no_units.message")
                )
            } else {
                HStack(spacing: NPSpacing.medium) {
                    HStack {
                        Text(localized("flashcards.learning_unit"))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(NPColors.textSecondary)
                            .lineLimit(1)
                        Spacer(minLength: NPSpacing.xs)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(NPColors.textSecondary.opacity(0.6))
                    }
                    .padding(.horizontal, NPSpacing.medium)
                    .padding(.vertical, 9)
                    .background(NPColors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: NPRadius.small, style: .continuous))
                    .shadow(color: NPShadow.small.color, radius: NPShadow.small.radius, x: 0, y: NPShadow.small.y)
                    .overlay {
                        Picker(
                            localized("flashcards.learning_unit"),
                            selection: Binding(
                                get: { model.selectedFlashcardLearningUnitId },
                                set: { model.selectFlashcardLearningUnit($0) }
                            )
                        ) {
                            ForEach(model.learningUnits) { unit in
                                Text(unit.title).tag(unit.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .opacity(0.02)
                        .accessibilityIdentifier("flashcardLearningUnitPicker")
                    }

                    HStack {
                        Text(localized("flashcards.deck"))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(NPColors.textSecondary)
                            .lineLimit(1)
                        Spacer(minLength: NPSpacing.xs)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(NPColors.textSecondary.opacity(0.6))
                    }
                    .padding(.horizontal, NPSpacing.medium)
                    .padding(.vertical, 9)
                    .background(NPColors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: NPRadius.small, style: .continuous))
                    .shadow(color: NPShadow.small.color, radius: NPShadow.small.radius, x: 0, y: NPShadow.small.y)
                    .overlay {
                        Picker(
                            localized("flashcards.deck"),
                            selection: Binding(
                                get: { model.selectedFlashcardDeckId ?? "" },
                                set: { model.selectFlashcardDeck($0) }
                            )
                        ) {
                            ForEach(model.flashcardDecks) { deck in
                                Text(localizedFormat("flashcards.deck_version", String(deck.versionNo)))
                                    .tag(deck.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .opacity(0.02)
                        .accessibilityIdentifier("flashcardDeckPicker")
                    }
                }

                if model.isFlashcardsLoading && model.flashcardDeckDetail == nil {
                    ProgressView(localized("flashcards.loading"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 36)
                } else if let error = model.flashcardError {
                    VStack(spacing: NPSpacing.small) {
                        NPEmptyState(
                            systemImage: "exclamationmark.triangle",
                            title: localized("flashcards.load_failed"),
                            message: error
                        )
                        Button(localized("common.retry")) {
                            model.ensureFlashcardsLoaded(force: true)
                        }
                        .buttonStyle(NPSecondaryButtonStyle())
                    }
                    .frame(maxWidth: .infinity)
                } else if let card = model.currentFlashcard,
                          let detail = model.flashcardDeckDetail {
                    flashcard(card, detail: detail)
                    priorityDetails(card)
                } else {
                    NPEmptyState(
                        systemImage: "rectangle.stack",
                        title: localized("flashcards.empty.title"),
                        message: localized("flashcards.empty.message")
                    )
                }
            }
        }
        .accessibilityIdentifier("flashcardsSection")
    }

    private func flashcard(_ card: Flashcard, detail: FlashcardDeckDetail) -> some View {
        VStack(spacing: NPSpacing.item) {
            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                    model.flipCurrentFlashcard()
                }
            } label: {
                VStack(spacing: 14) {
                    Text(model.isFlashcardShowingBack ? localized("flashcards.back") : localized("flashcards.front"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(NPColors.brand)
                    Text(model.isFlashcardShowingBack ? card.back : card.front)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(NPColors.textPrimary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                    Text(localized("flashcards.tap_to_flip"))
                        .npCaption()
                }
                .frame(maxWidth: .infinity, minHeight: 220)
                .padding(NPSpacing.card)
                .modifier(NPCardModifier())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("flashcardCard")

            HStack(spacing: NPSpacing.item) {
                Button { model.showPreviousFlashcard() } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(NPSecondaryButtonStyle())
                .disabled(model.flashcardIndex == 0)
                .accessibilityLabel(localized("flashcards.previous"))

                Spacer()
                Text(localizedFormat(
                    "flashcards.progress",
                    String(model.flashcardIndex + 1),
                    String(detail.cards.count)
                ))
                .npCaption()
                Spacer()

                Button { model.showNextFlashcard() } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(NPSecondaryButtonStyle())
                .disabled(model.flashcardIndex + 1 >= detail.cards.count)
                .accessibilityLabel(localized("flashcards.next"))
            }
        }
    }

    private func priorityDetails(_ card: Flashcard) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(card.priorityFactors.keys.sorted(), id: \.self) { key in
                    if let value = card.priorityFactors[key] {
                        HStack(alignment: .firstTextBaseline) {
                            Text(priorityFactorLabel(key))
                                .foregroundStyle(NPColors.textSecondary)
                            Spacer(minLength: 12)
                            Text(value.displayString)
                                .foregroundStyle(NPColors.textPrimary)
                        }
                        .npBody()
                    }
                }
                if let difficulty = card.difficulty?.trimmingCharacters(in: .whitespacesAndNewlines), !difficulty.isEmpty {
                    HStack {
                        Text(localized("flashcards.difficulty"))
                            .foregroundStyle(NPColors.textSecondary)
                        Spacer()
                        Text(difficulty)
                    }
                    .npBody()
                }
            }
            .padding(.top, 10)
        } label: {
            Text(localizedFormat("flashcards.priority", String(format: "%.4f", card.priorityScore)))
                .npBody().fontWeight(.medium)
                .foregroundStyle(NPColors.textPrimary)
        }
        .modifier(NPCardModifier())
    }

    private func priorityFactorLabel(_ key: String) -> String {
        switch key {
        case "base": return localized("flashcards.factor.base")
        case "error_pressure": return localized("flashcards.factor.error_pressure")
        case "success_pressure": return localized("flashcards.factor.success_pressure")
        case "recent_correct_streak": return localized("flashcards.factor.correct_streak")
        default: return key
        }
    }
}

private struct LearningSectionHeader: View {
    let title: String
    let subtitle: String
    let isLoading: Bool
    let onRefresh: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(localized(title)).npHeading()
                Text(localized(subtitle)).npCaption()
            }
            Spacer()
            Button(action: onRefresh) { Image(systemName: "arrow.clockwise") }
                .buttonStyle(NPToolbarIconButtonStyle())
                .disabled(isLoading)
                .accessibilityLabel(localizedFormat("accessibility.refresh_named", localized(title)))
        }
    }
}

private struct KnowledgeSearchSection: View {
    @ObservedObject var model: NotePatchViewModel

    var body: some View {
        LazyVStack(alignment: .leading, spacing: NPSpacing.item) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Knowledge search").npHeading()
                Text("Search through your workspace materials").npCaption()
            }

            NPSection {
                VStack(alignment: .leading, spacing: 12) {
                    LabeledField(title: "Search query") {
                        TextField("e.g. What does the slope of a linear function mean?", text: $model.knowledgeQuery)
                            .accessibilityIdentifier("knowledgeQueryField")
                    }
                    Picker("Learning unit", selection: $model.knowledgeLearningUnitId) {
                        Text("All units").tag("")
                        ForEach(model.learningUnits) { unit in Text(unit.title).tag(unit.id) }
                    }
                    .pickerStyle(.menu)
                    LabeledField(title: "Subject (optional)") {
                        TextField("e.g. math", text: $model.knowledgeSubject)
                    }
                    Stepper("Results: \(model.knowledgeLimit)", value: $model.knowledgeLimit, in: 1...20)
                    Button { model.searchKnowledge() } label: {
                        Label("Search", systemImage: "magnifyingglass")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(NPPrimaryButtonStyle())
                    .disabled(model.isKnowledgeSearching || model.knowledgeQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("knowledgeSearchButton")
                }
            }

            if model.isKnowledgeSearching {
                ProgressView("Searching knowledge base...").frame(maxWidth: .infinity).padding(.vertical, NPSpacing.large)
            } else if model.hasSearchedKnowledge && model.knowledgeResults.isEmpty {
                NPEmptyState(systemImage: "magnifyingglass", title: "No matches found", message: "Try different keywords, unit, or subject.")
            } else if !model.knowledgeResults.isEmpty {
                HStack {
                    Text("Search results").npSubheading()
                    Spacer()
                    Text(localizedFormat("knowledge.results_count", String(model.knowledgeResults.count))).npCaption()
                }
                ForEach(model.knowledgeResults) { item in
                    NPSection {
                        VStack(alignment: .leading, spacing: NPSpacing.small) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(item.metadataTitle ?? item.sourceType ?? localized("Knowledge snippet"))
                                    .npSubheading()
                                    .foregroundStyle(NPColors.textPrimary)
                                    .lineLimit(2)
                                Spacer()
                                Text(String(format: "%.4f", item.score))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(NPColors.textSecondary)
                            }
                            Text(item.content).npBody().textSelection(.enabled).foregroundStyle(NPColors.textPrimary)
                            let details = [item.subject, item.gradeLevel, item.sourceType, item.pageReferences.map { "Page \($0)" }].compactMap { $0 }
                            if !details.isEmpty {
                                Text(details.joined(separator: " · ")).npCaption()
                            }
                            if item.documentId != nil {
                                Button { model.previewKnowledgeSource(item) } label: {
                                    Label("Preview source", systemImage: "doc.text.magnifyingglass")
                                }
                                .buttonStyle(NPSecondaryButtonStyle())
                                .disabled(model.isBusy)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct HomeworkGradingSection: View {
    @ObservedObject var model: NotePatchViewModel
    @State private var isCreatingHomework = false
    @State private var selectedReferenceDocumentId = ""

    var body: some View {
        LazyVStack(alignment: .leading, spacing: NPSpacing.item) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Homework grading").npHeading()
                    Text("Configure grading rules, references, and start grading").npCaption()
                }
                Spacer()
                Button { isCreatingHomework = true } label: { Image(systemName: "plus") }
                    .buttonStyle(NPToolbarIconButtonStyle())
                    .disabled(model.homeworkDocumentCandidates.isEmpty)
                    .accessibilityLabel("Create homework")
                Button { model.loadLearningDashboard(allowOfflineNetwork: true) } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(NPToolbarIconButtonStyle())
                    .disabled(model.isHomeworkLoading)
                    .accessibilityLabel(localized("accessibility.refresh_homework"))
            }

            if model.isHomeworkLoading && model.homeworks.isEmpty {
                ProgressView("Loading homework...").frame(maxWidth: .infinity).padding(.vertical, NPSpacing.xl)
            } else if model.homeworks.isEmpty {
                NPEmptyState(systemImage: "checklist", title: "No homework yet", message: model.homeworkDocumentCandidates.isEmpty ? "Upload and process a homework document first." : "Tap + to create a linked homework.")
            } else {
                Picker("Current homework", selection: Binding(
                    get: { model.selectedHomeworkId ?? "" },
                    set: { if !$0.isEmpty { model.selectHomework($0) } }
                )) {
                    Text("Select homework").tag("")
                    ForEach(model.homeworks) { homework in Text(homework.title).tag(homework.id) }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("homeworkPicker")
            }

            if let homework = model.selectedHomework {
                homeworkEditor(homework)
            }
        }
        .sheet(isPresented: $isCreatingHomework) {
            HomeworkCreateSheet(model: model, isPresented: $isCreatingHomework)
        }
    }

    private func homeworkEditor(_ homework: HomeworkItem) -> some View {
        VStack(alignment: .leading, spacing: NPSpacing.item) {
            NPSection {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(homework.title).npSubheading()
                            Text([statusLabel(homework.status), homework.dueAt.map(compactDateTime)].compactMap { $0 }.joined(separator: " · "))
                                .npCaption()
                        }
                        Spacer()
                        NPStatusChip(text: statusLabel(homework.status), variant: statusChipVariant(homework.status))
                    }
                    SectionLabel("Grading rubric")
                    TextEditor(text: $model.homeworkRubricText)
                        .frame(height: 92)
                        .padding(6)
                        .npInputField()
                    LabeledField(title: "Max score") {
                        TextField("100", text: $model.homeworkMaxScoreText)
                            .keyboardType(.decimalPad)
                    }
                    if model.isGradingConfigDirty {
                        Label("Unsaved changes", systemImage: "exclamationmark.circle")
                            .npCaption()
                            .foregroundStyle(NPColors.warning)
                            .accessibilityIdentifier("gradingConfigUnsavedLabel")
                    }
                    Button { model.saveGradingConfig() } label: {
                        Label("Save grading config", systemImage: "checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(NPPrimaryButtonStyle())
                    .disabled(model.isHomeworkLoading || !model.isGradingConfigDirty)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Grading references").npSubheading()
                if model.homeworkReferences.isEmpty {
                    Text("No answer key or rubric.").npBody().foregroundStyle(NPColors.textSecondary)
                } else {
                    ForEach(model.homeworkReferences) { reference in
                        HStack(spacing: 10) {
                            Image(systemName: reference.referenceType == "answer_key" ? "checkmark.square" : "list.clipboard")
                                .foregroundStyle(NPColors.brand)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(referenceDocumentName(reference.documentId)).npBody().fontWeight(.medium).lineLimit(2)
                                Text(documentKindLabel(reference.referenceType)).npCaption()
                            }
                            Spacer()
                            Button(role: .destructive) { model.deleteHomeworkReference(reference) } label: { Image(systemName: "trash") }
                                .disabled(model.isHomeworkLoading)
                                .accessibilityLabel(localized("accessibility.remove_reference"))
                        }
                        .modifier(NPCardModifier())
                    }
                }
                if model.referenceDocumentCandidates.isEmpty {
                    Text("No reference documents available. Upload and process an Answer Key or Rubric first.")
                        .npCaption()
                } else {
                    Picker("Add reference", selection: $selectedReferenceDocumentId) {
                        Text("Select reference").tag("")
                        ForEach(model.referenceDocumentCandidates) { document in
                            Text("\(documentKindLabel(document.documentKind)) · \(document.title ?? document.originalFilename)").tag(document.id)
                        }
                    }
                    .pickerStyle(.menu)
                    Button {
                        model.addHomeworkReference(documentId: selectedReferenceDocumentId)
                        selectedReferenceDocumentId = ""
                    } label: {
                        Label("Add grading reference", systemImage: "plus")
                    }
                    .buttonStyle(NPSecondaryButtonStyle())
                    .disabled(selectedReferenceDocumentId.isEmpty || model.isHomeworkLoading)
                }
            }

            if let mode = model.gradingModeLabel {
                HStack {
                    Text(mode).npSubheading().foregroundStyle(NPColors.textPrimary)
                    if let confidence = model.gradingConfidence {
                        Text(localizedFormat("grading.confidence", String(format: "%.4f", confidence))).npCaption()
                    }
                }
            }
            Button { model.gradeSelectedHomework() } label: {
                Label("Start grading", systemImage: "checkmark.seal")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(NPPrimaryButtonStyle())
            .disabled(model.isHomeworkLoading)
            .accessibilityIdentifier("gradeHomeworkButton")
        }
    }

    private func referenceDocumentName(_ documentId: String) -> String {
        model.gradingDocuments.first(where: { $0.id == documentId })?.title
            ?? model.gradingDocuments.first(where: { $0.id == documentId })?.originalFilename
            ?? documentId
    }
}

private struct HomeworkCreateSheet: View {
    @ObservedObject var model: NotePatchViewModel
    @Binding var isPresented: Bool
    @State private var documentId = ""
    @State private var title = ""
    @State private var description = ""
    @State private var hasDueDate = false
    @State private var dueAt = Date()
    @State private var rubricText = ""
    @State private var maxScoreText = "100"

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Homework document")) {
                    Picker("Document", selection: $documentId) {
                        Text("Select").tag("")
                        ForEach(model.homeworkDocumentCandidates) { document in
                            Text(document.title ?? document.originalFilename).tag(document.id)
                        }
                    }
                    .onChange(of: documentId) { _, newValue in
                        if title.isEmpty, let document = model.homeworkDocumentCandidates.first(where: { $0.id == newValue }) {
                            title = document.title ?? document.originalFilename
                        }
                    }
                    TextField("Homework title", text: $title)
                    TextField("Description (optional)", text: $description)
                }
                Section(header: Text("Due date")) {
                    Toggle("Set due date", isOn: $hasDueDate)
                    if hasDueDate { DatePicker("Due date", selection: $dueAt) }
                }
                Section(header: Text("Grading config")) {
                    TextEditor(text: $rubricText).frame(height: 90)
                    TextField("Max score", text: $maxScoreText).keyboardType(.decimalPad)
                }
            }
            .navigationTitle("Create homework")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { isPresented = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        if model.createHomework(
                            documentId: documentId,
                            title: title,
                            description: description,
                            dueAt: hasDueDate ? dueAt : nil,
                            rubricText: rubricText,
                            maxScoreText: maxScoreText
                        ) {
                            isPresented = false
                        }
                    }
                    .disabled(documentId.isEmpty || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .onAppear {
            if documentId.isEmpty, let document = model.homeworkDocumentCandidates.first {
                documentId = document.id
                title = document.title ?? document.originalFilename
            }
        }
        .accessibilityIdentifier("homeworkCreateSheet")
    }
}

private struct LearningEmptyState: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "book.closed")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(NPColors.textSecondary.opacity(0.5))
            Text("No learning units yet")
                .npSubheading()
            Text("Learning results will appear here after processing documents.")
                .npCaption()
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
        .padding(.vertical, NPSpacing.xxxl)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - OpenClaw Message Bubble

private struct OpenClawMessageBubble: View {
    let message: OpenClawChatMessage

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 28)
            }
            VStack(alignment: .leading, spacing: NPSpacing.small) {
                if message.role == .assistant {
                    Label("OpenClaw", systemImage: "sparkles")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(NPColors.brand)
                }
                if message.status == .sending {
                    Text("Thinking...")
                        .font(.body.weight(.medium))
                        .foregroundStyle(NPColors.textPrimary)
                    ProgressView(value: Double(message.progress ?? 0), total: 100)
                } else if message.role == .assistant {
                    LightweightMarkdownText(markdown: message.content, color: foregroundColor)
                } else {
                    Text(message.content)
                        .foregroundStyle(foregroundColor)
                }
                if let errorEvent = message.events.last(where: { $0.level == "error" }) {
                    Text(localizedFormat("chat.error_event", errorEvent.message))
                        .npCaption()
                        .foregroundStyle(NPColors.destructive)
                        .lineLimit(3)
                }
                if message.sourceStatus == "partially_unavailable" {
                    Label("Some source materials removed", systemImage: "exclamationmark.triangle")
                        .npCaption()
                        .foregroundStyle(NPColors.warning)
                } else if message.sourceStatus == "unavailable" {
                    Label("Source materials removed", systemImage: "exclamationmark.triangle.fill")
                        .npCaption()
                        .foregroundStyle(NPColors.warning)
                } else if !message.citations.isEmpty {
                    Text(localizedFormat("chat.citing_sources", String(message.citations.count)))
                        .npCaption()
                }
            }
            .padding(NPSpacing.card)
            .frame(maxWidth: message.role == .system ? .infinity : 320, alignment: .leading)
            .background(bubbleBackground)
            .clipShape(RoundedRectangle(cornerRadius: NPRadius.card, style: .continuous))
            .overlay {
                if message.role != .user {
                    RoundedRectangle(cornerRadius: NPRadius.card, style: .continuous)
                        .stroke(NPColors.border, lineWidth: 1)
                }
            }
            if message.role != .user {
                Spacer(minLength: 28)
            }
        }
    }

    private var bubbleBackground: Color {
        if message.status == .error {
            return NPColors.destructive.opacity(0.1)
        }
        switch message.role {
        case .user:
            return NPColors.aiUserBubble
        case .system, .assistant:
            return NPColors.surface
        }
    }

    private var foregroundColor: Color {
        if message.role == .user {
            return NPColors.textPrimary
        }
        return NPColors.textPrimary
    }
}

// MARK: - Profile Tab

private struct ProfileTab: View {
    @ObservedObject var model: NotePatchViewModel
    @EnvironmentObject private var localization: AppLocalization

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // ——— Brand Hero ———
                NotePatchLogoImage(height: 100)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, NPSpacing.outer)
                    .padding(.top, NPSpacing.item)
                    .padding(.bottom, NPSpacing.xs)

                Text("Patch your knowledge together.")
                    .font(.system(size: 13, weight: .regular, design: .default))
                    .foregroundStyle(NPColors.textSecondary.opacity(0.7))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, NPSpacing.outer)
                    .padding(.bottom, NPSpacing.item)

                // ——— Profile Card ———
                NPSection {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 14) {
                            Circle()
                                .fill(NPColors.brandLight)
                                .frame(width: 48, height: 48)
                                .overlay(
                                    Text(accountInitial)
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundStyle(NPColors.brandDark)
                                )
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.session?.fullName?.isEmpty == false ? model.session?.fullName ?? "" : localized("account.default_user"))
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(NPColors.textPrimary)
                                    .lineLimit(1)
                                Text(model.session?.email ?? "")
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundStyle(NPColors.textSecondary)
                                    .lineLimit(1)
                            }
                        }
                        Text(localizedFormat("account.session_valid_until", compactDateTime(model.session?.expiresAt ?? "")))
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(NPColors.textSecondary.opacity(0.75))
                    }
                }

                // ——— Workspace ———
                WorkspaceManagementSection(model: model)

                // ——— Preferences ———
                languageSection

                // ——— AI ———
                aiSection

                // ——— Server ———
                serverSection

                // ——— Sign Out ———
                Button(role: .destructive) {
                    model.logout()
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(NPSecondaryButtonStyle())
                .foregroundStyle(NPColors.destructive)
                .disabled(model.isBusy)
                .padding(.bottom, NPSpacing.xl)
            }
            .padding(.horizontal, NPSpacing.outer)
            .padding(.top, NPSpacing.small)
            .padding(.bottom, NPSpacing.xxxl)
        }
    }

    private var accountInitial: String {
        let account = model.session?.fullName?.isEmpty == false ? model.session?.fullName : model.session?.email
        return account?.trimmingCharacters(in: .whitespacesAndNewlines).first.map(String.init)?.uppercased() ?? "N"
    }

    private var languageSection: some View {
        NPSection {
            VStack(alignment: .leading, spacing: NPSpacing.small) {
                Label("Language", systemImage: "globe")
                    .npSubheading()
                Picker("Language", selection: Binding(
                    get: { localization.language },
                    set: { localization.select($0) }
                )) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .accessibilityIdentifier("appLanguagePicker")
                Text("Changes apply immediately throughout NotePatch.")
                    .npCaption()
            }
        }
    }

    private var aiSection: some View {
        NPSection {
            VStack(alignment: .leading, spacing: NPSpacing.small) {
                Label("AI", systemImage: "sparkles")
                    .npSubheading()
                Toggle("AI history", isOn: Binding(
                    get: { model.aiHistoryEnabled },
                    set: { model.updateAIHistoryEnabled($0) }
                ))
                .disabled(model.isBusy || model.isAIPreferenceUpdating)
                Text("Session records are retained, but future requests won't include history context.")
                    .npCaption()
            }
        }
    }

    private var serverSection: some View {
        NPSection {
            VStack(alignment: .leading, spacing: 14) {
                Label("Server", systemImage: "server.rack")
                    .npSubheading()

                LabeledField(title: "API address") {
                    TextField("API address", text: $model.apiBaseURLText)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                }
                LabeledField(title: "TUSD upload address") {
                    TextField("TUSD address", text: $model.tusBaseURLText)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                }

                Button {
                    model.saveServerURLs()
                } label: {
                    Label("Save server settings", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(NPPrimaryButtonStyle())
                .disabled(model.isBusy)

                HStack(spacing: NPSpacing.small) {
                    Button {
                        model.checkAPIConnection()
                    } label: {
                        Label("Test API", systemImage: "network")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(NPSecondaryButtonStyle())
                    .disabled(model.isBusy)

                    Button {
                        model.checkTUSConnection()
                    } label: {
                        Label("Test TUSD", systemImage: "arrow.up.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(NPSecondaryButtonStyle())
                    .disabled(model.isBusy)
                }
            }
        }
    }
}

private struct WorkspaceManagementSection: View {
    @ObservedObject var model: NotePatchViewModel

    var body: some View {
        let selected = model.workspaces.first(where: { $0.id == model.selectedWorkspaceId })
        NPSection {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Workspace", systemImage: "person.crop.square")
                        .npSubheading()
                    Spacer()
                    Button {
                        model.refreshCurrentWorkspace()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .disabled(model.isBusy || model.selectedWorkspaceId == nil)
                    .accessibilityLabel("Refresh workspace")
                }
                if let selected {
                    HStack(spacing: 10) {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(NPColors.warning)
                            .frame(width: 34, height: 34)
                            .background(NPColors.warning.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: NPRadius.button, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(selected.name)
                                .npBody().fontWeight(.medium)
                                .foregroundStyle(NPColors.textPrimary)
                                .lineLimit(1)
                            Text("Active workspace")
                                .npCaption()
                        }
                    }
                } else {
                    Text("No workspaces. Try restoring.")
                        .foregroundStyle(NPColors.textSecondary)
                }
                Button {
                    model.recoverPersonalWorkspace()
                } label: {
                    Label("Restore workspace", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(NPSecondaryButtonStyle())
                .disabled(model.isBusy)
            }
        }
    }
}

// MARK: - Markdown Rendering

private struct LightweightMarkdownText: View {
    let markdown: String
    let color: Color
    @StateObject private var renderer = MarkdownRenderState()

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(renderer.blocks) { block in
                switch block.type {
                case .heading:
                    Text(block.text)
                        .font(block.level == 1 ? .title3.weight(.semibold) : .subheadline.weight(.semibold))
                        .foregroundStyle(color)
                case .bullet:
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text("•")
                        MarkdownInlineText(tokens: block.inlineTokens, color: color)
                    }
                case .ordered:
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text("1.")
                        MarkdownInlineText(tokens: block.inlineTokens, color: color)
                    }
                case .quote:
                    HStack(spacing: NPSpacing.small) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(NPColors.brand)
                            .frame(width: 4)
                            .frame(height: 38)
                        MarkdownInlineText(tokens: block.inlineTokens, color: NPColors.textPrimary)
                    }
                    .padding(NPSpacing.small)
                    .background(NPColors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: NPRadius.input, style: .continuous))
                case .code:
                    Text(block.text)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(NPColors.surface)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color.black.opacity(0.65))
                        .clipShape(RoundedRectangle(cornerRadius: NPRadius.xs))
                case .paragraph:
                    MarkdownInlineText(tokens: block.inlineTokens, color: color)
                }
            }
        }
        .task(id: markdown) {
            renderer.load(markdown)
        }
    }
}

private struct MarkdownInlineText: View {
    let tokens: [MarkdownInlineToken]
    let color: Color

    var body: some View {
        tokens.reduce(Text("")) { partial, token in
            partial + styledText(token)
        }
        .foregroundStyle(color)
    }

    private func styledText(_ token: MarkdownInlineToken) -> Text {
        switch token.type {
        case .text:
            return Text(token.text)
        case .bold:
            return Text(token.text).bold()
        case .code:
            return Text(token.text).font(.system(.body, design: .monospaced))
        case .link:
            return Text(token.text).underline().foregroundStyle(NPColors.brand)
        }
    }
}

// MARK: - Reusable Building Blocks

private struct CollapsibleSection<Content: View>: View {
    let title: String
    let summary: String
    @Binding var expanded: Bool
    @ViewBuilder let content: Content

    var body: some View {
        NPSection {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(localized(title))
                            .npSubheading()
                        Text(summary.isEmpty ? localized("filter.all") : summary)
                            .npCaption()
                            .lineLimit(1)
                    }
                    Spacer()
                    Button {
                        withAnimation(.npInteractive) { expanded.toggle() }
                    } label: {
                        Label(expanded ? "Collapse" : "Expand", systemImage: expanded ? "chevron.up" : "chevron.down")
                    }
                    .buttonStyle(.borderless)
                }
                if expanded {
                    content
                }
            }
        }
    }
}

private struct ChoiceGrid<Content: View>: View {
    var minimum: CGFloat = 92
    @ViewBuilder let content: Content

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: minimum), spacing: 8)], alignment: .leading, spacing: 8) {
            content
        }
    }
}

private struct SectionLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(localized(text))
            .npSubheading()
    }
}

private struct LabeledField<Field: View>: View {
    let title: String
    @ViewBuilder let field: Field

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(localized(title))
                .npCaption()
            field
                .padding(.horizontal, 11)
                .frame(height: 42)
                .npInputField()
        }
    }
}

private struct IconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .foregroundStyle(NPColors.brand)
        .disabled(!enabled)
        .accessibilityLabel(localized(accessibilityLabel))
    }
}

private struct ChoiceButton: View {
    let text: String
    let selected: Bool
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            label
        }
        .buttonStyle(ChoiceChipButtonStyle(selected: selected))
        .disabled(!enabled)
    }

    private var label: some View {
        Text(localized(text))
            .npBody()
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .frame(maxWidth: .infinity)
    }
}

private struct ChoiceChipButtonStyle: ButtonStyle {
    let selected: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .regular))
            .foregroundStyle(selected ? NPColors.brandDark : NPColors.brandDark)
            .frame(height: 38)
            .padding(.horizontal, NPSpacing.medium)
            .background {
                Capsule(style: .continuous)
                    .fill(selected ? NPColors.brandLight.opacity(0.6) : NPColors.interactive)
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(selected ? NPColors.brand : NPColors.border, lineWidth: selected ? 1 : 0.5)
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(isEnabled ? 1.0 : 0.5)
            .animation(Animation.npInteractive, value: configuration.isPressed)
    }
}

private struct TextButton: View {
    let title: String
    let systemImage: String
    let enabled: Bool
    let action: () -> Void

    init(_ title: String, systemImage: String, enabled: Bool, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.enabled = enabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Label(localized(title), systemImage: systemImage)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .buttonStyle(.borderless)
        .disabled(!enabled)
    }
}

private struct DetailText: View {
    let text: String
    let lineLimit: Int?

    init(_ text: String, lineLimit: Int? = 2) {
        self.text = text
        self.lineLimit = lineLimit
    }

    var body: some View {
        Text(localized(text))
            .npCaption()
            .lineLimit(lineLimit)
    }
}

// MARK: - Status Banner

private struct StatusBanner: View {
    let isBusy: Bool
    let statusMessage: String
    let errorMessage: String?
    let onDismiss: () -> Void

    var body: some View {
        if shouldShowStatus || errorMessage != nil {
            HStack(alignment: .top, spacing: 10) {
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.top, 1)
                } else {
                    Image(systemName: bannerIcon)
                        .foregroundStyle(bannerColor)
                }
                VStack(alignment: .leading, spacing: 3) {
                    if shouldShowStatus {
                        Text(statusMessage)
                            .npCaption()
                            .lineLimit(2)
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .npCaption()
                            .lineLimit(3)
                    }
                }
                Spacer(minLength: 0)
                if errorMessage != nil {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.bold))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(NPColors.textSecondary)
                    .accessibilityLabel(localized("common.dismiss"))
                }
            }
            .foregroundStyle(NPColors.textPrimary)
            .padding(.horizontal, NPSpacing.medium)
            .padding(.vertical, NPSpacing.small)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(bannerBg)
            .clipShape(RoundedRectangle(cornerRadius: NPRadius.button, style: .continuous))
            .shadow(color: NPShadow.small.color, radius: NPShadow.small.radius, x: 0, y: NPShadow.small.y)
            .padding(.horizontal, NPSpacing.outer)
            .padding(.top, NPSpacing.small)
            .accessibilityIdentifier("globalStatusBanner")
        }
    }

    private var shouldShowStatus: Bool {
        !statusMessage.isEmpty
    }

    private var isWarning: Bool {
        errorMessage != nil
    }

    private var bannerIcon: String {
        isWarning ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
    }

    private var bannerColor: Color {
        if errorMessage != nil {
            return NPColors.destructive
        }
        return isWarning ? NPColors.warning : NPColors.brand
    }

    private var bannerBg: Color {
        if errorMessage != nil {
            return NPColors.destructive.opacity(0.12)
        }
        return isWarning ? NPColors.warning.opacity(0.15) : NPColors.brandLight.opacity(0.5)
    }
}

private struct StatusPanel: View {
    let isBusy: Bool
    let statusMessage: String
    let errorMessage: String?

    var body: some View {
        if hasContent {
            VStack(alignment: .leading, spacing: 7) {
                if isBusy {
                    HStack(spacing: NPSpacing.small) {
                        ProgressView()
                        Text("Processing...")
                            .npBody()
                            .foregroundStyle(NPColors.textSecondary)
                    }
                }
                if !statusMessage.isEmpty && !isBusy {
                    Text(statusMessage)
                        .npCaption()
                }
                if let errorMessage {
                    Text(errorMessage)
                        .npCaption()
                        .foregroundStyle(NPColors.destructive)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(NPSpacing.medium)
            .background(errorMessage != nil ? NPColors.destructive.opacity(0.1) : NPColors.brandLight.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: NPRadius.medium, style: .continuous))
            .shadow(color: NPShadow.small.color, radius: NPShadow.small.radius, x: 0, y: NPShadow.small.y)
        }
    }

    private var hasContent: Bool {
        isBusy || !statusMessage.isEmpty || errorMessage != nil
    }
}

// MARK: - Helper: NotePatch Brand Logo Image
// Renders the embroidered wordmark on a fully transparent background.
// Blends naturally with any page color (paper warm tones or surface whites).

private struct NotePatchLogoImage: View {
    var height: CGFloat
    var body: some View {
        Image("NotePatchLogo")
            .resizable()
            .renderingMode(.original)
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(height: height)
    }
}

// MARK: - Helper: Status Color / Variant Mapping

private func colorForStatus(_ status: String) -> Color {
    switch status {
    case "failed", "cancelled", "deleted":
        return NPColors.destructive
    case "created", "uploading", "uploaded", "processing", "queued", "running":
        return NPColors.warning
    case "ready", "succeeded", "completed":
        return NPColors.brand
    default:
        return NPColors.textSecondary
    }
}

private func statusChipVariant(_ status: String) -> NPStatusChip.NPStatusChipVariant {
    switch status {
    case "failed", "cancelled", "deleted":
        return .destructive
    case "created", "uploading", "uploaded", "processing", "queued", "running":
        return .warning
    case "ready", "succeeded", "completed":
        return .brand
    default:
        return .neutral
    }
}

private func taskStatusChipVariant(_ task: TaskItem) -> NPStatusChip.NPStatusChipVariant {
    if task.cancelRequestedAt != nil && !["succeeded", "failed", "cancelled"].contains(task.status) {
        return .warning
    }
    return statusChipVariant(task.status)
}

private func statusColor(_ status: String) -> Color {
    return colorForStatus(status)
}

private func taskStatusLabel(_ task: TaskItem) -> String {
    if task.cancelRequestedAt != nil && !["succeeded", "failed", "cancelled"].contains(task.status) {
        return localized("task.status.cancelling")
    }
    return statusLabel(task.status)
}

private func taskStatusColor(_ task: TaskItem) -> Color {
    if task.cancelRequestedAt != nil && !["succeeded", "failed", "cancelled"].contains(task.status) {
        return NPColors.warning
    }
    return colorForStatus(task.status)
}

private func taskTypeLabel(_ taskType: String) -> String {
    switch taskType {
    case "purge_document":
        return localized("task.type.document_cleanup")
    case "process_document", "document_process":
        return localized("task.type.document_processing")
    case "openclaw", "openclaw_task":
        return "OpenClaw"
    default:
        return taskType.replacingOccurrences(of: "_", with: " ")
    }
}

// MARK: - Chat Scroll Pan Observer

private struct ChatScrollPanValue {
    let startLocation: CGPoint
    let location: CGPoint
    let translation: CGSize
    let scrollBottomY: CGFloat
}

private struct ChatScrollPanObserver: UIViewRepresentable {
    let onPan: (ChatScrollPanValue) -> Void

    func makeUIView(context: Context) -> ObserverView {
        let view = ObserverView()
        view.onPan = onPan
        return view
    }

    func updateUIView(_ view: ObserverView, context: Context) {
        view.onPan = onPan
        view.attachIfNeeded()
    }

    final class ObserverView: UIView {
        var onPan: ((ChatScrollPanValue) -> Void)?
        private weak var observedScrollView: UIScrollView?
        private weak var observedPanGesture: UIPanGestureRecognizer?
        private var startLocation: CGPoint?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                self?.attachIfNeeded()
            }
        }

        deinit {
            observedPanGesture?.removeTarget(self, action: #selector(handlePan))
        }

        func attachIfNeeded() {
            var candidate = superview
            while let view = candidate, !(view is UIScrollView) {
                candidate = view.superview
            }
            guard let scrollView = candidate as? UIScrollView,
                  observedScrollView !== scrollView else {
                return
            }

            observedPanGesture?.removeTarget(self, action: #selector(handlePan))
            observedScrollView = scrollView
            observedPanGesture = scrollView.panGestureRecognizer
            scrollView.panGestureRecognizer.addTarget(self, action: #selector(handlePan))
        }

        @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
            guard let scrollView = observedScrollView else { return }
            let location = recognizer.location(in: nil)

            switch recognizer.state {
            case .began:
                startLocation = location
            case .changed, .ended:
                guard let startLocation else { return }
                let translation = recognizer.translation(in: nil)
                onPan?(
                    ChatScrollPanValue(
                        startLocation: startLocation,
                        location: location,
                        translation: CGSize(width: translation.x, height: translation.y),
                        scrollBottomY: scrollView.convert(scrollView.bounds, to: nil).maxY
                    )
                )
                if recognizer.state == .ended {
                    self.startLocation = nil
                }
            case .cancelled, .failed:
                startLocation = nil
            default:
                break
            }
        }
    }
}

// MARK: - Adaptive Composer Text View

private struct AdaptiveComposerTextView: UIViewRepresentable {
    @Environment(\.sizeCategory) private var sizeCategory
    @Binding var text: String
    @Binding var isFocused: Bool
    @Binding var height: CGFloat
    let availableWidth: CGFloat
    let horizontalInset: CGFloat
    let maximumLines: Int

    func makeUIView(context: Context) -> ComposerTextViewContainer {
        let container = ComposerTextViewContainer()
        let textView = container.textView
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.textColor = .label
        textView.textContainerInset = UIEdgeInsets(
            top: 9,
            left: horizontalInset,
            bottom: 9,
            right: horizontalInset
        )
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.widthTracksTextView = true
        textView.textContainer.heightTracksTextView = false
        textView.textContainer.lineBreakMode = .byWordWrapping
        textView.showsVerticalScrollIndicator = true
        textView.showsHorizontalScrollIndicator = false
        textView.alwaysBounceVertical = false
        textView.alwaysBounceHorizontal = false
        textView.isScrollEnabled = false
        textView.accessibilityLabel = localized("Ask AI Co-pilot")
        textView.accessibilityIdentifier = "openClawComposerTextView"
        return container
    }

    func updateUIView(_ container: ComposerTextViewContainer, context: Context) {
        let textView = container.textView
        context.coordinator.update(parent: self)
        textView.accessibilityLabel = localized("Ask AI Co-pilot")
        let normalizedHorizontalInset = max(0, horizontalInset)
        let didChangeInsets =
            abs(textView.textContainerInset.left - normalizedHorizontalInset) > 0.5 ||
            abs(textView.textContainerInset.right - normalizedHorizontalInset) > 0.5
        if didChangeInsets {
            textView.textContainerInset.left = normalizedHorizontalInset
            textView.textContainerInset.right = normalizedHorizontalInset
        }
        let didReplaceText = textView.text != text
        if textView.text != text {
            textView.text = text
        }
        if isFocused, !textView.isFirstResponder {
            textView.becomeFirstResponder()
        } else if !isFocused, textView.isFirstResponder {
            textView.resignFirstResponder()
        }
        context.coordinator.updateHeight(for: textView, force: didReplaceText || didChangeInsets)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        private var parent: AdaptiveComposerTextView
        private var lastMeasuredText: String?
        private var lastMeasuredWidth: CGFloat = 0
        private var lastMaximumLines = 0
        private var lastSizeCategory: ContentSizeCategory?

        init(parent: AdaptiveComposerTextView) {
            self.parent = parent
        }

        func update(parent: AdaptiveComposerTextView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            updateHeight(for: textView)
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.isFocused = true
        }

        func textViewDidEndEditing(_ textView: UITextView) {}

        func updateHeight(for textView: UITextView, force: Bool = false) {
            let width = parent.availableWidth
            guard width.isFinite, width >= ComposerTextLayout.minimumMeasurementWidth else {
                return
            }
            guard force ||
                    lastMeasuredText != textView.text ||
                    abs(lastMeasuredWidth - width) > 0.5 ||
                    lastMaximumLines != parent.maximumLines ||
                    lastSizeCategory != parent.sizeCategory else {
                return
            }
            let trace = NPPerformanceTrace.begin("ComposerMeasure")
            defer { NPPerformanceTrace.end("ComposerMeasure", id: trace) }
            lastMeasuredText = textView.text
            lastMeasuredWidth = width
            lastMaximumLines = parent.maximumLines
            lastSizeCategory = parent.sizeCategory

            guard let measurement = ComposerTextLayout.measure(
                textView: textView,
                availableWidth: width,
                maximumLines: parent.maximumLines
            ) else {
                return
            }
            textView.isScrollEnabled = measurement.requiresScrolling

            if measurement.requiresScrolling {
                textView.scrollRangeToVisible(textView.selectedRange)
            } else if textView.contentOffset.y != 0 {
                textView.setContentOffset(.zero, animated: false)
            }

            if abs(parent.height - measurement.height) > 0.5 {
                let measuredText = textView.text
                let measuredWidth = width
                let measuredMaximumLines = parent.maximumLines
                let measuredHeight = measurement.height
                DispatchQueue.main.async { [weak self] in
                    guard let self,
                          self.lastMeasuredText == measuredText,
                          abs(self.lastMeasuredWidth - measuredWidth) <= 0.5,
                          self.lastMaximumLines == measuredMaximumLines else {
                        return
                    }
                    self.parent.height = measuredHeight
                }
            }
        }
    }
}

private final class ComposerTextViewContainer: UIView {
    let textView = UITextView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        textView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textView)
        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textView.topAnchor.constraint(equalTo: topAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

struct ComposerTextMeasurement: Equatable {
    let height: CGFloat
    let requiresScrolling: Bool
}

enum ComposerTextLayout {
    static let minimumMeasurementWidth: CGFloat = 44

    static func measure(
        textView: UITextView,
        availableWidth: CGFloat,
        maximumLines: Int
    ) -> ComposerTextMeasurement? {
        guard availableWidth.isFinite, availableWidth >= minimumMeasurementWidth else {
            return nil
        }

        let lineHeight = textView.font?.lineHeight
            ?? UIFont.preferredFont(forTextStyle: .body).lineHeight
        let verticalInsets = textView.textContainerInset.top + textView.textContainerInset.bottom
        let minimumHeight = max(44, ceil(lineHeight + verticalInsets))
        let maximumHeight = max(
            minimumHeight,
            ceil(lineHeight * CGFloat(max(1, maximumLines)) + verticalInsets)
        )
        let fittingHeight = textView.sizeThatFits(
            CGSize(width: availableWidth, height: CGFloat.greatestFiniteMagnitude)
        ).height

        return ComposerTextMeasurement(
            height: min(max(fittingHeight, minimumHeight), maximumHeight),
            requiresScrolling: fittingHeight > maximumHeight + 0.5
        )
    }
}

// MARK: - Photo Library Picker

private struct PhotoLibraryPicker: UIViewControllerRepresentable {
    let cacheDirectory: URL
    let onComplete: (Result<[LocalUploadFile], Error>?) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 0
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(cacheDirectory: cacheDirectory, onComplete: onComplete)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let cacheDirectory: URL
        let onComplete: (Result<[LocalUploadFile], Error>?) -> Void

        init(cacheDirectory: URL, onComplete: @escaping (Result<[LocalUploadFile], Error>?) -> Void) {
            self.cacheDirectory = cacheDirectory
            self.onComplete = onComplete
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard !results.isEmpty else {
                onComplete(nil)
                return
            }
            let group = DispatchGroup()
            let lock = NSLock()
            var selections = Array<LocalUploadFile?>(repeating: nil, count: results.count)
            var firstError: Error?

            for (index, result) in results.enumerated() {
                let provider = result.itemProvider
                guard let typeIdentifier = provider.registeredTypeIdentifiers.first(where: {
                    UTType($0)?.conforms(to: .image) == true
                }) else {
                    firstError = firstError ?? LearningBackendError("Unable to identify the selected image format.")
                    continue
                }
                group.enter()
                provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { temporaryURL, error in
                    defer { group.leave() }
                    do {
                        if let error { throw error }
                        guard let temporaryURL else {
                            throw LearningBackendError("Unable to read the selected image.")
                        }
                        let type = UTType(typeIdentifier)
                        let fileExtension = type?.preferredFilenameExtension ?? "jpg"
                        let suggestedName = provider.suggestedName?.trimmingCharacters(in: .whitespacesAndNewlines)
                        let filename = suggestedName?.isEmpty == false
                            ? ((suggestedName! as NSString).pathExtension.isEmpty ? "\(suggestedName!).\(fileExtension)" : suggestedName!)
                            : "selected-\(Int(Date().timeIntervalSince1970 * 1000))-\(index).\(fileExtension)"
                        let file = try copyFileToUploadCache(
                            sourceURL: temporaryURL,
                            fallbackPrefix: "selected-photo",
                            cacheDirectory: self.cacheDirectory,
                            suggestedMimeType: type?.preferredMIMEType ?? contentTypeForFilename(filename),
                            suggestedFilename: filename
                        )
                        lock.lock()
                        selections[index] = file
                        lock.unlock()
                    } catch {
                        lock.lock()
                        firstError = firstError ?? error
                        lock.unlock()
                    }
                }
            }
            group.notify(queue: .main) {
                let loaded = selections.compactMap { $0 }
                if loaded.isEmpty, let firstError {
                    self.onComplete(.failure(firstError))
                } else {
                    self.onComplete(.success(loaded))
                }
            }
        }
    }
}

// MARK: - Camera Picker

private struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onImage: onImage, dismiss: dismiss)
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onImage: (UIImage) -> Void
        let dismiss: DismissAction

        init(onImage: @escaping (UIImage) -> Void, dismiss: DismissAction) {
            self.onImage = onImage
            self.dismiss = dismiss
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                onImage(image)
            }
            dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}

// MARK: - Quick Look Preview

private struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        controller.reloadData()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            1
        }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}

// MARK: - Zoomable Image Preview

private struct ZoomableImagePreview: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.backgroundColor = .black
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 5
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.bouncesZoom = true
        scrollView.addSubview(context.coordinator.imageView)

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)
        context.coordinator.scrollView = scrollView
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        if context.coordinator.loadedURL != url {
            context.coordinator.loadedURL = url
            context.coordinator.imageView.image = UIImage(contentsOfFile: url.path)
            scrollView.setZoomScale(1, animated: false)
        }
        DispatchQueue.main.async {
            context.coordinator.layoutImage(in: scrollView)
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var scrollView: UIScrollView?
        var loadedURL: URL?
        let imageView: UIImageView = {
            let view = UIImageView()
            view.contentMode = .scaleAspectFit
            view.isUserInteractionEnabled = true
            return view
        }()

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerImage(in: scrollView)
        }

        func layoutImage(in scrollView: UIScrollView) {
            guard let image = imageView.image, scrollView.bounds.width > 0, scrollView.bounds.height > 0 else {
                return
            }
            let widthScale = scrollView.bounds.width / image.size.width
            let heightScale = scrollView.bounds.height / image.size.height
            let scale = min(widthScale, heightScale)
            let fittedSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            if scrollView.zoomScale == 1 {
                imageView.frame = CGRect(origin: .zero, size: fittedSize)
            }
            scrollView.contentSize = imageView.frame.size
            centerImage(in: scrollView)
        }

        @objc func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard let scrollView else {
                return
            }
            if scrollView.zoomScale > 1 {
                scrollView.setZoomScale(1, animated: true)
                layoutImage(in: scrollView)
                return
            }
            let point = recognizer.location(in: imageView)
            let zoomScale = min(2.5, scrollView.maximumZoomScale)
            let size = CGSize(width: scrollView.bounds.width / zoomScale, height: scrollView.bounds.height / zoomScale)
            let rect = CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height)
            scrollView.zoom(to: rect, animated: true)
        }

        private func centerImage(in scrollView: UIScrollView) {
            let horizontalInset = max(0, (scrollView.bounds.width - scrollView.contentSize.width) / 2)
            let verticalInset = max(0, (scrollView.bounds.height - scrollView.contentSize.height) / 2)
            scrollView.contentInset = UIEdgeInsets(top: verticalInset, left: horizontalInset, bottom: verticalInset, right: horizontalInset)
        }
    }
}

// MARK: - Image Preview

private struct ImagePreview: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if UIImage(contentsOfFile: url.path) != nil {
                ZoomableImagePreview(url: url)
                    .ignoresSafeArea()
            } else {
                Text("Cannot preview image")
                    .foregroundStyle(NPColors.surface)
            }
            Button {
                dismiss()
            } label: {
                Label("Close", systemImage: "xmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .font(.title)
                    .foregroundStyle(NPColors.surface)
                    .padding(18)
            }
        }
    }
}

// MARK: - Utility

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}

// MARK: - Preview

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
#endif
