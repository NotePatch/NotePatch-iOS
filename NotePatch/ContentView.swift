import PhotosUI
import QuickLook
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ContentView: View {
    @StateObject private var model = NotePatchViewModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isShowingCamera = false
    @State private var isShowingFileImporter = false
    @State private var capturedCameraImage: UIImage?

    var body: some View {
        Group {
            if model.session == nil {
                AuthScreen(model: model)
            } else {
                WorkbenchScreen(
                    model: model,
                    selectedPhotoItem: $selectedPhotoItem,
                    onCameraUpload: { isShowingCamera = true },
                    onFileUpload: { isShowingFileImporter = true }
                )
            }
        }
        .task {
            await model.restoreIfNeeded()
        }
        .onChange(of: scenePhase) { _, newPhase in
            model.handleScenePhase(newPhase)
        }
        .onChange(of: selectedPhotoItem) { _, item in
            guard let item else {
                return
            }
            Task {
                await importPhoto(item)
                selectedPhotoItem = nil
            }
        }
        .fileImporter(isPresented: $isShowingFileImporter, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                model.uploadPickedFile(from: url)
            }
        }
        .sheet(isPresented: $isShowingCamera, onDismiss: stageCapturedImage) {
            CameraPicker { image in
                capturedCameraImage = image
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(item: $model.pendingUploadFile) { file in
            UploadPreviewScreen(
                file: file,
                documentKind: model.uploadDocumentKind,
                onCancel: model.discardPendingUpload,
                onUpload: model.confirmPendingUpload
            )
        }
        .sheet(item: $model.downloadedPreview) { preview in
            if preview.isImage {
                ImagePreview(url: preview.url)
            } else {
                QuickLookPreview(url: preview.url)
            }
        }
    }

    private func stageCapturedImage() {
        guard let image = capturedCameraImage else {
            return
        }
        capturedCameraImage = nil
        model.uploadCameraImage(image)
    }

    private func importPhoto(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                model.errorMessage = "无法读取选择的图片。"
                return
            }
            let type = item.supportedContentTypes.first
            let ext = type?.preferredFilenameExtension ?? "jpg"
            let mimeType = type?.preferredMIMEType ?? contentTypeForFilename("selected.\(ext)")
            let filename = "selected-\(Int(Date().timeIntervalSince1970 * 1000)).\(ext)"
            model.uploadPhotoData(data, suggestedFilename: filename, mimeType: mimeType)
        } catch {
            model.errorMessage = friendlyError(error)
        }
    }
}

private struct AuthScreen: View {
    @ObservedObject var model: NotePatchViewModel

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 28) {
                    VStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color.accentColor)
                                .frame(width: 72, height: 72)
                            Image(systemName: "doc.text.viewfinder")
                                .font(.system(size: 32, weight: .semibold))
                                .foregroundStyle(.white)
                        }

                        VStack(spacing: 6) {
                            Text("NotePatch")
                                .font(.largeTitle.weight(.bold))
                            Text("扫描、整理并处理你的学习文档")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    VStack(spacing: 18) {
                        VStack(spacing: 12) {
                            AuthField(title: "API 地址", systemImage: "network") {
                                TextField("http://192.168.100.123:8001", text: $model.apiBaseURLText)
                                    .textInputAutocapitalization(.never)
                                    .keyboardType(.URL)
                                    .accessibilityIdentifier("apiAddressField")
                            }

                            Divider()

                            AuthField(title: "邮箱", systemImage: "envelope") {
                                TextField("name@example.com", text: $model.emailText)
                                    .textInputAutocapitalization(.never)
                                    .keyboardType(.emailAddress)
                                    .textContentType(.username)
                                    .accessibilityIdentifier("emailField")
                            }

                            Divider()

                            AuthField(title: "密码", systemImage: "lock") {
                                SecureField("输入密码", text: $model.passwordText)
                                    .textContentType(.password)
                                    .accessibilityIdentifier("passwordField")
                            }

                            Divider()

                            AuthField(title: "姓名", systemImage: "person") {
                                TextField("注册时填写", text: $model.fullNameText)
                                    .textContentType(.name)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                        Button {
                            model.authenticate(register: false)
                        } label: {
                            HStack {
                                Spacer()
                                if model.isBusy {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Text("登录")
                                        .fontWeight(.semibold)
                                }
                                Spacer()
                            }
                            .frame(height: 48)
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.roundedRectangle(radius: 10))
                        .disabled(model.isBusy)
                        .accessibilityIdentifier("loginButton")

                        HStack(spacing: 12) {
                            Button {
                                model.authenticate(register: true)
                            } label: {
                                Label("创建账号", systemImage: "person.badge.plus")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .disabled(model.isBusy)

                            Button {
                                model.checkAPIConnection()
                            } label: {
                                Label("检测服务", systemImage: "wave.3.right")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .disabled(model.isBusy)
                        }

                        StatusPanel(isBusy: model.isBusy, statusMessage: model.statusMessage, errorMessage: model.errorMessage)
                    }
                    .frame(maxWidth: 520)
                }
                .padding(.horizontal, 20)
                .padding(.top, 44)
                .padding(.bottom, 32)
            }
        }
        .disabled(model.isBusy)
    }
}

private struct AuthField<Field: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let field: Field

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                field
                    .font(.body)
            }
        }
        .frame(minHeight: 48)
    }
}

private struct WorkbenchScreen: View {
    @ObservedObject var model: NotePatchViewModel
    @Binding var selectedPhotoItem: PhotosPickerItem?
    let onCameraUpload: () -> Void
    let onFileUpload: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            CompactTopBar(model: model)
            StatusBanner(isBusy: model.isBusy, statusMessage: model.statusMessage, errorMessage: model.errorMessage)

            TabView(selection: $model.selectedTab) {
                DocumentsTab(
                    model: model,
                    selectedPhotoItem: $selectedPhotoItem,
                    onCameraUpload: onCameraUpload,
                    onFileUpload: onFileUpload
                )
                .tag(WorkbenchTab.documents)
                .tabItem { Label(WorkbenchTab.documents.title, systemImage: WorkbenchTab.documents.iconName) }

                TaskTab(model: model)
                    .tag(WorkbenchTab.tasks)
                    .tabItem { Label(WorkbenchTab.tasks.title, systemImage: WorkbenchTab.tasks.iconName) }

                OpenClawChatTab(model: model)
                    .tag(WorkbenchTab.openClaw)
                    .tabItem { Label(WorkbenchTab.openClaw.title, systemImage: WorkbenchTab.openClaw.iconName) }

                LearningTab(model: model)
                    .tag(WorkbenchTab.learning)
                    .tabItem { Label(WorkbenchTab.learning.title, systemImage: WorkbenchTab.learning.iconName) }

                SettingsTab(model: model)
                    .tag(WorkbenchTab.settings)
                    .tabItem { Label(WorkbenchTab.settings.title, systemImage: WorkbenchTab.settings.iconName) }
            }
            .accessibilityIdentifier("workbenchTabs")
        }
        .background(Color(.systemGroupedBackground))
    }
}

private struct CompactTopBar: View {
    @ObservedObject var model: NotePatchViewModel

    var body: some View {
        let workspaceName = model.workspaces.first(where: { $0.id == model.selectedWorkspaceId })?.name
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.accentColor)
                    .frame(width: 38, height: 38)
                Image(systemName: "doc.text.viewfinder")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("NotePatch")
                    .font(.headline)
                Text(workspaceName ?? "未选择个人空间")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .accessibilityIdentifier("personalWorkspaceName")
            }
            Spacer(minLength: 8)
            Button {
                model.refreshCurrentWorkspace()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .disabled(model.isBusy || model.selectedWorkspaceId == nil)
            .accessibilityLabel("刷新个人空间")

            Text(accountInitial)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 34, height: 34)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(Circle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground))
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityIdentifier("workbenchTopBar")
    }

    private var accountInitial: String {
        let account = model.session?.fullName?.isEmpty == false ? model.session?.fullName : model.session?.email
        return account?.trimmingCharacters(in: .whitespacesAndNewlines).first.map(String.init)?.uppercased() ?? "N"
    }
}

private struct DocumentsTab: View {
    @ObservedObject var model: NotePatchViewModel
    @Binding var selectedPhotoItem: PhotosPickerItem?
    let onCameraUpload: () -> Void
    let onFileUpload: () -> Void
    @State private var uploadExpanded = true
    @State private var filtersExpanded = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                CollapsibleSection(
                    title: "上传文档",
                    summary: model.uploadProgressPercent.map { "\(model.uploadProgressLabel) · \($0)%" } ?? documentKindLabel(model.uploadDocumentKind),
                    expanded: $uploadExpanded
                ) {
                    UploadPanel(
                        model: model,
                        selectedPhotoItem: $selectedPhotoItem,
                        onCameraUpload: onCameraUpload,
                        onFileUpload: onFileUpload
                    )
                }

                CollapsibleSection(
                    title: "筛选",
                    summary: activeFilterSummary(status: model.statusFilter, documentKind: model.documentKindFilter, fileType: model.fileTypeFilter),
                    expanded: $filtersExpanded
                ) {
                    FilterPanel(model: model)
                }

                HStack {
                    Text("文档列表")
                        .font(.headline)
                    Spacer()
                    Text("\(model.documents.count) 个")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if model.documents.isEmpty {
                    EmptyText("暂无文档，先上传图片、PDF 或文件。")
                } else {
                    LazyVStack(spacing: 10) {
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
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 24)
        }
        .accessibilityIdentifier("documentsTab")
    }
}

private struct UploadPanel: View {
    @ObservedObject var model: NotePatchViewModel
    @Binding var selectedPhotoItem: PhotosPickerItem?
    let onCameraUpload: () -> Void
    let onFileUpload: () -> Void
    @State private var isLearningInfoExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("文档类型")

            ChoiceGrid(minimum: 76) {
                ForEach(["homework", "corrected_homework", "courseware", "note", "exam", "other"], id: \.self) { kind in
                    ChoiceButton(text: documentKindLabel(kind), selected: model.uploadDocumentKind == kind, enabled: !model.isBusy) {
                        model.uploadDocumentKind = kind
                    }
                }
            }

            HStack(spacing: 8) {
                UploadSourceButton(title: "拍照", systemImage: "camera.fill", emphasized: true, enabled: !model.isBusy && UIImagePickerController.isSourceTypeAvailable(.camera), action: onCameraUpload)
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    UploadSourceLabel(title: "相册", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(UploadSourceButtonStyle(emphasized: false))
                .disabled(model.isBusy)
                UploadSourceButton(title: "文件", systemImage: "folder", emphasized: false, enabled: !model.isBusy, action: onFileUpload)
            }

            if let progress = model.uploadProgressPercent {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(model.uploadProgressLabel)
                        Spacer()
                        Text("\(progress)%")
                            .monospacedDigit()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    ProgressView(value: Double(progress), total: 100)
                }
                .padding(.top, 2)
            }

            DisclosureGroup("学习信息", isExpanded: $isLearningInfoExpanded) {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("学习单元", selection: $model.uploadLearningUnitId) {
                        Text("自动创建或归类").tag("")
                        ForEach(model.learningUnits) { unit in
                            Text(unit.title).tag(unit.id)
                        }
                    }
                    .pickerStyle(.menu)
                    if model.uploadLearningUnitId.isEmpty {
                        LabeledField(title: "学习单元标题") {
                            TextField("例如：分数与比例", text: $model.uploadLearningUnitTitle)
                        }
                    }
                    LabeledField(title: "学科") {
                        TextField("例如：数学", text: $model.uploadSubject)
                    }
                    HStack(spacing: 10) {
                        LabeledField(title: "年级") {
                            TextField("七年级", text: $model.uploadGradeLevel)
                        }
                        LabeledField(title: "主题") {
                            TextField("比例", text: $model.uploadTopic)
                        }
                    }
                }
                .padding(.top, 8)
            }
            .font(.subheadline.weight(.medium))
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
            Text(title)
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
            .foregroundStyle(emphasized ? Color.white : Color.accentColor)
            .background(emphasized ? Color.accentColor : Color.accentColor.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

private struct FilterPanel: View {
    @ObservedObject var model: NotePatchViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FilterChoices(
                label: "状态",
                values: ["", "created", "uploading", "uploaded", "processing", "ready", "failed"],
                selected: model.statusFilter,
                enabled: !model.isBusy,
                onChange: model.setStatusFilter
            )
            FilterChoices(
                label: "类型",
                values: ["", "homework", "courseware", "note", "exam", "other"],
                selected: model.documentKindFilter,
                enabled: !model.isBusy,
                onChange: model.setDocumentKindFilter
            )
            FilterChoices(
                label: "文件",
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
        SectionContainer(background: Color(.secondarySystemGroupedBackground)) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(document.title ?? document.originalFilename)
                            .font(.body.weight(.semibold))
                            .lineLimit(2)
                        Text("\(documentKindLabel(document.documentKind)) · \(fileTypeLabel(document.fileType))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text("\(formatBytes(document.fileSize)) · \(compactDateTime(document.createdAt))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    StatusPill(text: statusLabel(document.status), color: statusColor(document.status))
                }

                HStack(spacing: 8) {
                    Button(action: onProcess) {
                        Label(processTitle, systemImage: "wand.and.stars")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isBusy || document.status == "deleted")

                    Button(action: onDownload) {
                        Image(systemName: "arrow.down.to.line")
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isBusy || document.status == "deleted")
                    .accessibilityLabel("下载")

                    Menu {
                        Button(action: onOCR) {
                            Label("OCR 结果", systemImage: "text.viewfinder")
                        }
                        .disabled(isBusy || document.status != "ready")
                        Button(action: onArtifacts) {
                            Label("处理产物", systemImage: "tray.full")
                        }
                        Button {
                            detailsExpanded.toggle()
                        } label: {
                            Label(detailsExpanded ? "收起详情" : "查看详情", systemImage: "info.circle")
                        }
                        Divider()
                        Button(role: .destructive, action: onDelete) {
                            Label("删除文档", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isBusy)
                    .accessibilityLabel("更多操作")
                }

                if detailsExpanded {
                    Divider()
                    DetailText("mime: \(document.mimeType ?? "unknown")")
                    if let sha256 = document.sha256 {
                        DetailText("sha256: \(sha256)")
                    }
                    DetailText("updated: \(document.updatedAt)")
                }

                if !artifacts.isEmpty {
                    Divider()
                    SectionLabel("处理产物")
                    ForEach(artifacts) { artifact in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            DetailText(
                                [
                                    artifactTypeLabel(artifact.artifactType),
                                    artifact.mimeType,
                                    formatBytes(artifact.fileSize),
                                    artifact.metadataProcessor.map { "processor=\($0)" }
                                ].compactMap { $0 }.joined(separator: " · ")
                            )
                            Spacer(minLength: 0)
                            IconButton(systemImage: "arrow.down.circle", accessibilityLabel: "下载处理产物", enabled: !isBusy) {
                                onArtifactDownload(artifact)
                            }
                        }
                        if let metadataText = artifact.metadataText {
                            DetailText("metadata: \(metadataText)", lineLimit: 2)
                        }
                    }
                }

                if !ocrArtifacts.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel("OCR 结果")
                        ForEach(ocrArtifacts) { artifact in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                DetailText(
                                    [
                                        artifactTypeLabel(artifact.artifactType),
                                        artifact.mimeType,
                                        formatBytes(artifact.fileSize),
                                        compactDateTime(artifact.createdAt)
                                    ].compactMap { $0 }.joined(separator: " · ")
                                )
                                Spacer(minLength: 0)
                                IconButton(systemImage: "arrow.down.circle", accessibilityLabel: "下载 OCR 结果", enabled: !isBusy && artifact.downloadURL?.isEmpty == false) {
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
        document.status == "ready" || document.status == "failed" ? "重处理" : "处理"
    }
}

private struct TaskTab: View {
    @ObservedObject var model: NotePatchViewModel

    var body: some View {
        ScrollView {
            TaskPanel(activeTask: model.activeTask, events: model.taskEvents)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 24)
        }
        .accessibilityIdentifier("tasksTab")
    }
}

private struct TaskPanel: View {
    let activeTask: TaskItem?
    let events: [TaskEventItem]
    @State private var resultExpanded = false
    @State private var eventsExpanded = false

    var body: some View {
        SectionContainer {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("当前任务", systemImage: "clock.arrow.circlepath")
                        .font(.headline)
                    Spacer()
                    if let activeTask {
                        StatusPill(text: statusLabel(activeTask.status), color: statusColor(activeTask.status))
                    }
                }

                if let activeTask {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(taskTypeLabel(activeTask.taskType))
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                            Spacer()
                            Text("\(activeTask.progress.clamped(to: 0...100))%")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        ProgressView(value: Double(activeTask.progress.clamped(to: 0...100)), total: 100)
                    }
                    HStack(spacing: 16) {
                        if let startedAt = activeTask.startedAt {
                            TaskTime(label: "开始", value: compactDateTime(startedAt))
                        }
                        if let finishedAt = activeTask.finishedAt {
                            TaskTime(label: "完成", value: compactDateTime(finishedAt))
                        }
                    }
                    if let errorMessage = activeTask.errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.red)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    if let resultText = activeTask.resultText {
                        DisclosureGroup("任务结果", isExpanded: $resultExpanded) {
                            DetailText(resultText, lineLimit: nil)
                                .padding(.top, 6)
                        }
                        .font(.subheadline.weight(.medium))
                    }
                } else {
                    EmptyState(
                        systemImage: "checkmark.circle",
                        title: "暂无进行中的任务",
                        message: "处理文档或向 OpenClaw 提问后，进度会显示在这里。"
                    )
                }

                if !events.isEmpty {
                    Divider()
                    HStack {
                        SectionLabel("事件日志")
                        Spacer()
                        Button(eventsExpanded ? "收起" : "查看全部") {
                            eventsExpanded.toggle()
                        }
                        .font(.caption)
                    }

                    ForEach(visibleEvents) { event in
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(event.level == "error" ? Color.red : Color.secondary.opacity(0.5))
                                .frame(width: 6, height: 6)
                                .padding(.top, 5)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(event.progress.map { "\($0)% · " } ?? "")\(event.message)")
                                    .font(.caption)
                                    .foregroundStyle(event.level == "error" ? .red : .primary)
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
}

private struct TaskTime: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .lineLimit(1)
        }
    }
}

private struct OpenClawChatTab: View {
    @ObservedObject var model: NotePatchViewModel
    @State private var isRenaming = false
    @State private var titleDraft = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.selectedConversation?.title ?? "新对话")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(model.selectedConversation == nil ? "发送第一条消息后自动保存" : "已保存的 AI 会话")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Menu {
                    Button { model.startNewConversation() } label: {
                        Label("新建对话", systemImage: "square.and.pencil")
                    }
                    if let conversation = model.selectedConversation {
                        Button {
                            titleDraft = conversation.title
                            isRenaming = true
                        } label: {
                            Label("重命名", systemImage: "pencil")
                        }
                        Button(role: .destructive) { model.deleteCurrentConversation() } label: {
                            Label("删除当前对话", systemImage: "trash")
                        }
                    }
                    if !model.conversations.isEmpty {
                        Divider()
                        ForEach(model.conversations) { conversation in
                            Button { model.selectConversation(conversation.id) } label: {
                                Label(conversation.title, systemImage: conversation.id == model.selectedConversationId ? "checkmark" : "bubble.left")
                            }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .frame(width: 36, height: 36)
                }
                .accessibilityLabel("会话操作")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemGroupedBackground))

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(model.openClawMessages) { message in
                            OpenClawMessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .onChange(of: model.openClawMessages.count) {
                    if let last = model.openClawMessages.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            VStack(spacing: 0) {
                Divider()
                HStack(alignment: .bottom, spacing: 10) {
                    TextField("问 OpenClaw", text: $model.openClawInput, axis: .vertical)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color(.tertiarySystemFill))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .lineLimit(1...4)
                        .disabled(model.isOpenClawSending)
                    Button {
                        model.startOpenClawChat()
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 15, weight: .bold))
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.circle)
                    .disabled(model.isOpenClawSending || model.openClawInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("发送")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemGroupedBackground))
            }
        }
        .accessibilityIdentifier("openClawTab")
        .task { model.loadChatHistory() }
        .alert("重命名对话", isPresented: $isRenaming) {
            TextField("对话标题", text: $titleDraft)
            Button("取消", role: .cancel) {}
            Button("保存") { model.renameCurrentConversation(to: titleDraft) }
        }
    }
}

private struct LearningTab: View {
    @ObservedObject var model: NotePatchViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("学习单元")
                            .font(.title3.weight(.semibold))
                        Text("个人空间中的自动整理结果")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { model.loadLearningUnits() } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.isLearningLoading)
                    .accessibilityLabel("刷新学习单元")
                }

                if model.isLearningLoading && model.learningUnits.isEmpty {
                    ProgressView("正在加载学习单元...")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 28)
                } else if model.learningUnits.isEmpty {
                    ContentUnavailableView("暂无学习单元", systemImage: "book.closed", description: Text("上传并处理文档后，学习结果会显示在这里。"))
                } else {
                    ForEach(model.learningUnits) { unit in
                        Button { model.selectLearningUnit(unit.id) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(unit.title)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                    Spacer()
                                    if unit.id == model.selectedLearningUnitId {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                                let details = [unit.subject, unit.gradeLevel, unit.topic].compactMap { $0?.isEmpty == false ? $0 : nil }
                                if !details.isEmpty {
                                    Text(details.joined(separator: " · "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color(.secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }

                if model.selectedLearningUnitId != nil {
                    Text("电子笔记")
                        .font(.headline)
                        .padding(.top, 4)
                    if model.studyNotes.isEmpty {
                        Text("该学习单元暂无笔记版本。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.studyNotes) { note in
                            HStack(spacing: 12) {
                                Image(systemName: "note.text")
                                    .foregroundStyle(Color.accentColor)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(note.title.isEmpty ? "电子笔记" : note.title)
                                        .font(.subheadline.weight(.medium))
                                        .lineLimit(2)
                                    Text("版本 \(note.versionNo)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button { model.downloadAndPreview(note) } label: {
                                    Image(systemName: "eye")
                                }
                                .buttonStyle(.bordered)
                                .disabled(note.preferredDownloadURL == nil)
                                .accessibilityLabel("预览笔记")
                            }
                            .padding(12)
                            .background(Color(.secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .task { model.loadLearningUnits() }
        .accessibilityIdentifier("learningTab")
    }
}

private struct OpenClawMessageBubble: View {
    let message: OpenClawChatMessage

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 28)
            }
            VStack(alignment: .leading, spacing: 8) {
                if message.role == .assistant {
                    Label("OpenClaw", systemImage: "sparkles")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.accentColor)
                }
                if message.status == .sending {
                    Text("思考中...")
                        .fontWeight(.medium)
                    ProgressView(value: Double(message.progress ?? 0), total: 100)
                } else if message.role == .assistant {
                    LightweightMarkdownText(markdown: message.content, color: foregroundColor)
                } else {
                    Text(message.content)
                        .foregroundStyle(foregroundColor)
                }
                if let errorEvent = message.events.last(where: { $0.level == "error" }) {
                    Text("错误事件：\(errorEvent.message)")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(3)
                }
            }
            .padding(12)
            .frame(maxWidth: message.role == .system ? .infinity : 320, alignment: .leading)
            .background(backgroundColor)
            .foregroundStyle(foregroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            if message.role != .user {
                Spacer(minLength: 28)
            }
        }
    }

    private var backgroundColor: Color {
        if message.status == .error {
            return Color(.systemRed).opacity(0.14)
        }
        switch message.role {
        case .user:
            return Color.accentColor
        case .system:
            return Color(.tertiarySystemFill)
        case .assistant:
            return Color(.secondarySystemGroupedBackground)
        }
    }

    private var foregroundColor: Color {
        if message.role == .user {
            return .white
        }
        return .primary
    }
}

private struct SettingsTab: View {
    @ObservedObject var model: NotePatchViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                SectionContainer {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("服务器", systemImage: "server.rack")
                            .font(.headline)

                        LabeledField(title: "API 地址") {
                            TextField("API 地址", text: $model.apiBaseURLText)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.URL)
                        }
                        LabeledField(title: "tusd 上传地址") {
                            TextField("tusd 地址", text: $model.tusBaseURLText)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.URL)
                        }

                        Button {
                            model.saveServerURLs()
                        } label: {
                            Label("保存服务器设置", systemImage: "checkmark")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isBusy)

                        HStack(spacing: 8) {
                            Button {
                                model.checkAPIConnection()
                            } label: {
                                Label("检测 API", systemImage: "network")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .disabled(model.isBusy)

                            Button {
                                model.checkTUSConnection()
                            } label: {
                                Label("检测 tusd", systemImage: "arrow.up.circle")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .disabled(model.isBusy)
                        }
                    }
                }

                WorkspaceManagementSection(model: model)

                SectionContainer {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("AI", systemImage: "sparkles")
                            .font(.headline)
                        Toggle("AI 使用历史", isOn: Binding(
                            get: { model.aiHistoryEnabled },
                            set: { model.updateAIHistoryEnabled($0) }
                        ))
                        .disabled(model.isBusy)
                        Text("关闭后，新的 OpenClaw 对话不保留到历史记录。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                SectionContainer {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("账号", systemImage: "person.crop.circle")
                            .font(.headline)
                        HStack(spacing: 12) {
                            Image(systemName: "person.fill")
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 42, height: 42)
                                .background(Color.accentColor.opacity(0.10))
                                .clipShape(Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.session?.fullName?.isEmpty == false ? model.session?.fullName ?? "" : "NotePatch 用户")
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                                Text(model.session?.email ?? "")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Text("登录有效期至 \(compactDateTime(model.session?.expiresAt ?? ""))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Button(role: .destructive) {
                            model.logout()
                        } label: {
                            Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .disabled(model.isBusy)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 24)
        }
        .accessibilityIdentifier("settingsTab")
    }
}

private struct WorkspaceManagementSection: View {
    @ObservedObject var model: NotePatchViewModel

    var body: some View {
        let selected = model.workspaces.first(where: { $0.id == model.selectedWorkspaceId })
        SectionContainer {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("个人空间", systemImage: "person.crop.square")
                        .font(.headline)
                    Spacer()
                    Button {
                        model.refreshCurrentWorkspace()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .disabled(model.isBusy || model.selectedWorkspaceId == nil)
                    .accessibilityLabel("刷新个人空间")
                }
                if let selected {
                    HStack(spacing: 10) {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(.orange)
                            .frame(width: 34, height: 34)
                            .background(Color.orange.opacity(0.10))
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(selected.name)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                            Text("当前使用的个人空间")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("暂无个人空间，可尝试恢复。")
                        .foregroundStyle(.secondary)
                }
                Button {
                    model.recoverPersonalWorkspace()
                } label: {
                    Label("恢复个人空间", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(model.isBusy)
            }
        }
    }
}

private struct LightweightMarkdownText: View {
    let markdown: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(parseMarkdownBlocks(markdown)) { block in
                switch block.type {
                case .heading:
                    Text(block.text)
                        .font(block.level == 1 ? .title3.weight(.semibold) : .subheadline.weight(.semibold))
                        .foregroundStyle(color)
                case .bullet:
                    MarkdownInlineText(text: "• \(block.text)", color: color)
                case .ordered:
                    MarkdownInlineText(text: "1. \(block.text)", color: color)
                case .quote:
                    HStack(spacing: 8) {
                        StatusStripe(color: .accentColor)
                            .frame(height: 38)
                        MarkdownInlineText(text: block.text, color: .primary)
                    }
                    .padding(8)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                case .code:
                    Text(block.text)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Color(.systemBackground))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color(.label))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                case .paragraph:
                    MarkdownInlineText(text: block.text, color: color)
                }
            }
        }
    }
}

private struct MarkdownInlineText: View {
    let text: String
    let color: Color

    var body: some View {
        parseMarkdownInline(text).reduce(Text("")) { partial, token in
            partial + styledText(token)
        }
        .foregroundStyle(color)
    }

    private func styledText(_ token: MarkdownInlineToken) -> Text {
        switch token.type {
        case .text:
            return Text(token.text)
        case .bold:
            return Text(token.text).fontWeight(.bold)
        case .code:
            return Text(token.text).font(.system(.body, design: .monospaced))
        case .link:
            return Text(token.text).underline().foregroundColor(.accentColor)
        }
    }
}

private struct CollapsibleSection<Content: View>: View {
    let title: String
    let summary: String
    @Binding var expanded: Bool
    @ViewBuilder let content: Content

    var body: some View {
        SectionContainer {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.headline)
                        Text(summary.isEmpty ? "全部" : summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button {
                        expanded.toggle()
                    } label: {
                        Label(expanded ? "收起" : "展开", systemImage: expanded ? "chevron.up" : "chevron.down")
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

private struct SectionContainer<Content: View>: View {
    var background: Color = Color(.secondarySystemGroupedBackground)
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(.separator).opacity(0.16), lineWidth: 0.5)
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
        Text(text)
            .font(.subheadline.weight(.semibold))
    }
}

private struct LabeledField<Field: View>: View {
    let title: String
    @ViewBuilder let field: Field

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            field
                .padding(.horizontal, 11)
                .frame(height: 42)
                .background(Color(.tertiarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

private struct StatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
            .fixedSize()
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
        .foregroundStyle(Color.accentColor)
        .disabled(!enabled)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct ChoiceButton: View {
    let text: String
    let selected: Bool
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        if selected {
            Button(action: action) {
                label
            }
            .buttonStyle(.borderedProminent)
            .disabled(!enabled)
        } else {
            Button(action: action) {
                label
            }
            .buttonStyle(.bordered)
            .disabled(!enabled)
        }
    }

    private var label: some View {
        Text(text)
            .font(.subheadline)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .frame(maxWidth: .infinity)
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
            Label(title, systemImage: systemImage)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .buttonStyle(.borderless)
        .disabled(!enabled)
    }
}

private struct StatusStripe: View {
    let color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(color)
            .frame(width: 4)
    }
}

private struct StatusBanner: View {
    let isBusy: Bool
    let statusMessage: String
    let errorMessage: String?

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
                            .font(.caption)
                            .lineLimit(2)
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .lineLimit(3)
                    }
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(errorMessage == nil ? Color.primary : Color.red)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(errorMessage == nil ? Color(.tertiarySystemFill) : Color(.systemRed).opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }

    private var shouldShowStatus: Bool {
        statusMessage.isEmpty == false && (
            isBusy ||
            statusMessage.contains("连接正常") ||
            statusMessage.contains("已保存") ||
            statusMessage.contains("已创建") ||
            statusMessage.contains("完成") ||
            statusMessage.contains("已下载") ||
            statusMessage.contains("已删除") ||
            statusMessage.contains("artifacts") ||
            statusMessage.contains("OCR") ||
            statusMessage.contains("在线状态")
        )
    }

    private var isWarning: Bool {
        errorMessage != nil || statusMessage.contains("失败") || statusMessage.contains("重试")
    }

    private var bannerIcon: String {
        isWarning ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
    }

    private var bannerColor: Color {
        if errorMessage != nil {
            return .red
        }
        return isWarning ? .orange : .accentColor
    }
}

private struct AppHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title2.weight(.semibold))
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

private struct StatusPanel: View {
    let isBusy: Bool
    let statusMessage: String
    let errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if isBusy {
                ProgressView()
            }
            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct EmptyText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        EmptyState(systemImage: "doc", title: "暂无文档", message: text)
    }
}

private struct EmptyState: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.subheadline.weight(.medium))
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
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
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(lineLimit)
    }
}

private func statusColor(_ status: String) -> Color {
    switch status {
    case "failed", "cancelled", "deleted":
        return .red
    case "created", "uploading", "uploaded", "processing", "queued", "running":
        return .orange
    case "ready", "succeeded", "completed":
        return .accentColor
    default:
        return .gray
    }
}

private func taskTypeLabel(_ taskType: String) -> String {
    switch taskType {
    case "process_document", "document_process":
        return "文档处理"
    case "openclaw", "openclaw_task":
        return "OpenClaw"
    default:
        return taskType.replacingOccurrences(of: "_", with: " ")
    }
}

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

private struct UploadPreviewScreen: View {
    let file: LocalUploadFile
    let documentKind: String
    let onCancel: () -> Void
    let onUpload: () -> Void

    var body: some View {
        NavigationStack {
            preview
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(previewBackground)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    uploadControls
                }
                .navigationTitle("上传预览")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(Color.black, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbarColorScheme(.dark, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(action: onCancel) {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel("取消上传")
                    }
                }
        }
        .accessibilityIdentifier("uploadPreviewScreen")
    }

    @ViewBuilder
    private var preview: some View {
        switch previewKind {
        case .image:
            if UIImage(contentsOfFile: file.url.path) != nil {
                ZoomableImagePreview(url: file.url)
            } else {
                UnsupportedUploadPreview(file: file, message: "无法读取所选图片")
            }
        case .quickLook:
            QuickLookPreview(url: file.url)
        case .unsupported:
            UnsupportedUploadPreview(file: file, message: "此格式不支持预览，但仍可正常上传")
        }
    }

    private var previewKind: UploadPreviewKind {
        file.previewKind(canQuickLookPreview: QLPreviewController.canPreview(file.url as NSURL))
    }

    private var previewBackground: Color {
        previewKind == .image ? .black : Color(.systemGroupedBackground)
    }

    private var uploadControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(file.filename)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .accessibilityIdentifier("uploadPreviewFilename")
                Text(fileDetails)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 10) {
                Button(action: onCancel) {
                    Text("取消")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("cancelPendingUploadButton")

                Button(action: onUpload) {
                    Label("上传", systemImage: "arrow.up.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("confirmPendingUploadButton")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(.regularMaterial)
        .overlay(alignment: .top) { Divider() }
    }

    private var fileDetails: String {
        [
            documentKindLabel(documentKind),
            file.mimeType ?? "未知类型",
            formatBytes(file.fileSize)
        ].joined(separator: " · ")
    }
}

private struct UnsupportedUploadPreview: View {
    let file: LocalUploadFile
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.questionmark")
                .font(.system(size: 54, weight: .light))
                .foregroundStyle(Color.accentColor)
            Text(file.filename)
                .font(.headline)
                .multilineTextAlignment(.center)
                .lineLimit(3)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

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

private struct ImagePreview: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(12)
            } else {
                Text("无法预览图片")
                    .foregroundStyle(.white)
            }
            Button {
                dismiss()
            } label: {
                Label("关闭", systemImage: "xmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .font(.title)
                    .foregroundStyle(.white)
                    .padding(18)
            }
        }
    }
}

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}

#Preview {
    ContentView()
}
