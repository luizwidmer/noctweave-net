import NoctwebLabCore
import SwiftUI
import UniformTypeIdentifiers

private enum WebsiteEditorMode: String, CaseIterable, Identifiable {
    case design
    case code
    case preview

    var id: Self { self }

    var title: String {
        rawValue.capitalized
    }

    var systemImage: String {
        switch self {
        case .design: "square.grid.2x2"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .preview: "play.rectangle"
        }
    }
}

private enum PreviewViewport: String, CaseIterable, Identifiable {
    case desktop
    case tablet
    case mobile

    var id: Self { self }

    var title: String {
        rawValue.capitalized
    }

    var systemImage: String {
        switch self {
        case .desktop: "desktopcomputer"
        case .tablet: "ipad"
        case .mobile: "iphone"
        }
    }

    var width: CGFloat {
        switch self {
        case .desktop: 1_200
        case .tablet: 768
        case .mobile: 390
        }
    }
}

private enum EditorPathPrompt {
    case newFile
    case renameFile(id: UUID, path: String)

    var title: String {
        switch self {
        case .newFile: "New Website File"
        case .renameFile: "Rename Website File"
        }
    }

    var message: String {
        switch self {
        case .newFile:
            "Use a relative path inside the website bundle."
        case .renameFile:
            "References inside HTML, CSS, and JavaScript are not rewritten."
        }
    }
}

private enum EditorDestructiveAction {
    case replaceBuild(URL)
    case deleteBlock(id: UUID, name: String)
    case deleteFile(id: UUID, path: String)

    var title: String {
        switch self {
        case .replaceBuild:
            "Replace the current website project?"
        case let .deleteBlock(_, name):
            "Delete \(name)?"
        case let .deleteFile(_, path):
            "Delete \(path)?"
        }
    }

    var message: String {
        switch self {
        case .replaceBuild:
            "The selected build folder will replace every current website file and leave visual block mode. This cannot be undone."
        case .deleteBlock:
            "The block and its generated HTML will be removed from this local draft."
        case .deleteFile:
            "The file will be removed from this local website bundle. References to it are not rewritten."
        }
    }
}

struct WebsiteProjectEditorView: View {
    @EnvironmentObject private var model: AppModel

    let site: SiteProject

    @State private var mode: WebsiteEditorMode = .design
    @State private var selectedBlockID: UUID?
    @State private var selectedFileID: UUID?
    @State private var viewport: PreviewViewport = .desktop
    @State private var reloadToken = UUID()
    @State private var previewRefreshTask: Task<Void, Never>?
    @State private var sourceSaveTask: Task<Void, Never>?
    @State private var sourceDraft = ""
    @State private var sourceDraftFileID: UUID?
    @State private var sourceSaveStatus = "Saved locally"
    @State private var showsDesignInspector = false
    @State private var showingImporter = false
    @State private var pathPrompt: EditorPathPrompt?
    @State private var destructiveAction: EditorDestructiveAction?
    @State private var pathDraft = ""
    @FocusState private var focusedSourceFileID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            editorToolbar
            Divider()

            Group {
                switch mode {
                case .design:
                    designWorkspace
                case .code:
                    codeWorkspace
                case .preview:
                    websitePreview(showViewportControls: true)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            resetSelectionForCurrentSite()
        }
        .onChange(of: site.id) {
            flushSourceDraft()
            resetSelectionForCurrentSite()
        }
        .onChange(of: site.resolvedFiles.count) {
            repairFileSelection()
        }
        .onChange(of: selectedFileID) {
            loadSelectedSourceDraft()
        }
        .onChange(of: focusedSourceFileID) {
            if focusedSourceFileID == nil {
                flushSourceDraft()
            }
        }
        .onDisappear {
            previewRefreshTask?.cancel()
            flushSourceDraft()
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                guard let url = urls.first else { return }
                destructiveAction = .replaceBuild(url)
            case let .failure(error):
                model.reportOperationError(
                    "The website folder could not be opened: \(error.localizedDescription)"
                )
            }
        }
        .alert(
            pathPrompt?.title ?? "Website File",
            isPresented: pathPromptBinding,
            presenting: pathPrompt
        ) { prompt in
            TextField("scripts/app.js", text: $pathDraft)
            Button("Cancel", role: .cancel) {
                pathPrompt = nil
            }
            switch prompt {
            case .newFile:
                Button("Create") {
                    let requestedPath = pathDraft
                    model.addSourceFile(path: requestedPath)
                    if let created = model.selectedSite?.resolvedFiles.first(
                        where: {
                            $0.path.caseInsensitiveCompare(requestedPath) ==
                                .orderedSame
                        }
                    ) {
                        selectedFileID = created.id
                    }
                    pathPrompt = nil
                    refreshPreview()
                }
            case let .renameFile(fileID, _):
                Button("Rename") {
                    model.renameSourceFile(fileID, path: pathDraft)
                    pathPrompt = nil
                    refreshPreview()
                }
            }
        } message: { prompt in
            Text(prompt.message)
        }
        .confirmationDialog(
            destructiveAction?.title ?? "Confirm project change",
            isPresented: destructiveActionBinding,
            titleVisibility: .visible,
            presenting: destructiveAction
        ) { action in
            switch action {
            case let .replaceBuild(url):
                Button("Replace Project Files", role: .destructive) {
                    importBuild(at: url)
                }
            case let .deleteBlock(blockID, _):
                Button("Delete Block", role: .destructive) {
                    performDeleteBlock(blockID)
                }
            case let .deleteFile(fileID, _):
                Button("Delete File", role: .destructive) {
                    performDeleteFile(fileID)
                }
            }
            Button("Cancel", role: .cancel) {
                destructiveAction = nil
            }
        } message: { action in
            Text(action.message)
        }
    }

    private var editorToolbar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                ForEach(WebsiteEditorMode.allCases) { editorMode in
                    Button {
                        mode = editorMode
                    } label: {
                        Label(editorMode.title, systemImage: editorMode.systemImage)
                            .font(.callout.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(mode == editorMode ? Color.white : Color.primary)
                    .background {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(mode == editorMode ? Color.accentColor : Color.clear)
                    }
                    .accessibilityLabel(editorMode.title)
                    .accessibilityValue(mode == editorMode ? "Selected" : "Not selected")
                }
            }
            .padding(4)
            .frame(width: 340)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.1))
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Editor mode")

            Spacer(minLength: 8)

            if mode == .design {
                Button {
                    showsDesignInspector.toggle()
                } label: {
                    Label(
                        showsDesignInspector ? "Done Editing" : "Edit Block",
                        systemImage: showsDesignInspector
                            ? "checkmark"
                            : "slider.horizontal.3"
                    )
                }
                .buttonStyle(.bordered)
                .tint(showsDesignInspector ? .accentColor : .secondary)
            }

            StatusPill(
                title: site.resolvedProjectKind.title,
                systemImage: site.resolvedProjectKind == .visual
                    ? "square.grid.2x2"
                    : "folder",
                color: site.resolvedProjectKind == .visual ? .accentColor : .blue
            )

            Menu {
                Button {
                    showingImporter = true
                } label: {
                    Label("Import Build Folder…", systemImage: "square.and.arrow.down")
                }

                Button {
                    pathDraft = ""
                    pathPrompt = .newFile
                    mode = .code
                } label: {
                    Label("New File…", systemImage: "doc.badge.plus")
                }
            } label: {
                Label("Project", systemImage: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Import an agent-built site or manage project files")
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 52)
        .background(.bar)
    }

    @ViewBuilder
    private var designWorkspace: some View {
        if site.resolvedProjectKind == .imported {
            ContentUnavailableView {
                Label("Imported Website", systemImage: "folder.badge.gearshape")
            } description: {
                Text(
                    "This project remains ordinary HTML, CSS, JavaScript, and assets. Use Code for exact files or Preview to run the verified build; visual blocks are not imposed on imported code."
                )
            } actions: {
                HStack {
                    Button("Open Code") {
                        mode = .code
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Preview Website") {
                        mode = .preview
                    }
                }
            }
            .padding(24)
        } else {
            VStack(spacing: 0) {
                compactBlockNavigator
                Divider()
                GeometryReader { proxy in
                    if showsDesignInspector && proxy.size.width >= 760 {
                        HSplitView {
                            designCanvas
                                .frame(minWidth: 420)
                            blockInspector
                                .frame(
                                    minWidth: 300,
                                    idealWidth: 330,
                                    maxWidth: 380
                                )
                        }
                    } else if showsDesignInspector {
                        blockInspector
                    } else {
                        designCanvas
                    }
                }
            }
        }
    }

    private var blockNavigator: some View {
        VStack(spacing: 0) {
            paneHeader("Page Structure", systemImage: "square.3.layers.3d") {
                addBlockMenu
            }
            Divider()

            List(selection: $selectedBlockID) {
                ForEach(Array(site.resolvedBlocks.enumerated()), id: \.element.id) {
                    index,
                    block in
                    blockRow(block, index: index)
                        .tag(Optional(block.id))
                        .contextMenu {
                            blockActions(block)
                        }
                }
            }
            .listStyle(.sidebar)

            Divider()
            Text("Blocks generate normal index.html, styles.css, and app.js files.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
        }
        .background(.regularMaterial)
    }

    private var compactBlockNavigator: some View {
        HStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(Array(site.resolvedBlocks.enumerated()), id: \.element.id) {
                        index,
                        block in
                        Button {
                            selectedBlockID = block.id
                            showsDesignInspector = true
                        } label: {
                            Label(
                                block.heading.isEmpty
                                    ? "\(block.kind.title) \(index + 1)"
                                    : block.heading,
                                systemImage: block.kind.systemImage
                            )
                            .lineLimit(1)
                        }
                        .buttonStyle(.bordered)
                        .tint(
                            selectedBlockID == block.id
                                ? Color.accentColor
                                : Color.secondary
                        )
                    }
                }
            }
            addBlockMenu
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 50)
        .background(.regularMaterial)
    }

    private func blockRow(_ block: SiteBlock, index: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: block.kind.systemImage)
                .frame(width: 20)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(
                    block.heading.isEmpty
                        ? "\(block.kind.title) \(index + 1)"
                        : block.heading
                )
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                Text(block.kind.title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var addBlockMenu: some View {
        Menu {
            ForEach(SiteBlockKind.allCases) { kind in
                Button {
                    model.addBlock(kind)
                    selectedBlockID = model.selectedSite?.resolvedBlocks.last?.id
                    refreshPreview()
                } label: {
                    Label(kind.title, systemImage: kind.systemImage)
                }
            }
        } label: {
            Image(systemName: "plus")
        }
        .menuStyle(.borderlessButton)
        .help("Add a page block")
    }

    @ViewBuilder
    private func blockActions(_ block: SiteBlock) -> some View {
        let index = site.resolvedBlocks.firstIndex(where: { $0.id == block.id }) ?? 0
        Button("Move Up") {
            model.moveBlock(block.id, offset: -1)
            refreshPreview()
        }
        .disabled(index == 0)
        Button("Move Down") {
            model.moveBlock(block.id, offset: 1)
            refreshPreview()
        }
        .disabled(index >= site.resolvedBlocks.count - 1)
        Divider()
        Button("Delete Block", role: .destructive) {
            destructiveAction = .deleteBlock(
                id: block.id,
                name: block.heading.isEmpty ? block.kind.title : block.heading
            )
        }
        .disabled(site.resolvedBlocks.count <= 1)
    }

    private var blockInspector: some View {
        VStack(spacing: 0) {
            paneHeader("Edit Block", systemImage: "slider.horizontal.3") {
                Button {
                    showsDesignInspector = false
                } label: {
                    Label("Done", systemImage: "checkmark")
                }
                .buttonStyle(.borderless)
            }
            Divider()

            Group {
                if let block = selectedBlock {
                    ScrollView {
                        Form {
                        Section("Publication") {
                            Picker(
                                "Relay namespace",
                                selection: relayNamespaceBinding
                            ) {
                                ForEach(model.availableRelayNamespaces) { relay in
                                    Text(
                                        ".\(relay.namespaceSuffix ?? "unavailable") — \(relay.name)"
                                    )
                                    .tag(relay.relayNamespaceID ?? "")
                                }
                            }
                            .disabled(site.publishedEnvelope != nil)

                            TextField(
                                "Noctweb address",
                                text: siteStringBinding(\.address)
                            )
                            .font(.system(.body, design: .monospaced))
                            .disabled(site.publishedEnvelope != nil)

                            Text(
                                site.publishedEnvelope != nil
                        ? "This relay-scoped name is committed for this hosted revision. Host new revisions without changing it."
                                    : "Names use noct://site.relay-suffix/. The relay scopes registration; the publisher key controls updates."
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)

                            Picker(
                                "Publisher route policy",
                                selection: publisherRouteDirectiveBinding
                            ) {
                                ForEach(RouteDirective.allCases, id: \.self) { directive in
                                    Text(directive.title)
                                        .tag(directive)
                                }
                            }

                            Text("Open defers to the visitor unless federation or relay-operator policy has already decided. The publisher policy may change in a newly signed revision even after this address is finalized.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            LabeledContent("Publisher") {
                                Text(site.publisherID?.shortIdentifier ?? "Preparing…")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Section("Selected Block") {
                            Picker(
                                "Type",
                                selection: blockKindBinding(block.id)
                            ) {
                                ForEach(SiteBlockKind.allCases) { kind in
                                    Label(kind.title, systemImage: kind.systemImage)
                                        .tag(kind)
                                }
                            }

                            TextField(
                                "Eyebrow",
                                text: blockStringBinding(block.id, \.eyebrow)
                            )
                            TextField(
                                "Heading",
                                text: blockStringBinding(block.id, \.heading),
                                axis: .vertical
                            )
                            .lineLimit(1...3)

                            VStack(alignment: .leading, spacing: 7) {
                                Text("Body")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextEditor(
                                    text: blockStringBinding(block.id, \.body)
                                )
                                .frame(minHeight: 130)
                                .font(.body)
                                .padding(6)
                                .background(
                                    Color.secondary.opacity(0.08),
                                    in: RoundedRectangle(cornerRadius: 7)
                                )
                            }

                            if block.kind == .hero || block.kind == .callToAction {
                                TextField(
                                    "Button label",
                                    text: blockStringBinding(block.id, \.buttonLabel)
                                )
                                TextField(
                                    "Button link",
                                    text: blockStringBinding(block.id, \.buttonURL)
                                )
                                .font(.system(.body, design: .monospaced))
                            }
                        }

                        Section("Appearance") {
                            LabeledContent("Accent") {
                                HStack(spacing: 8) {
                                    ForEach(accentChoices, id: \.self) { hex in
                                        accentButton(hex)
                                    }
                                }
                            }
                        }

                        Section {
                            HStack {
                                Button {
                                    model.moveBlock(block.id, offset: -1)
                                    refreshPreview()
                                } label: {
                                    Label("Up", systemImage: "arrow.up")
                                }
                                .disabled(isFirstSelectedBlock)

                                Button {
                                    model.moveBlock(block.id, offset: 1)
                                    refreshPreview()
                                } label: {
                                    Label("Down", systemImage: "arrow.down")
                                }
                                .disabled(isLastSelectedBlock)

                                Spacer()

                                Button(role: .destructive) {
                                    destructiveAction = .deleteBlock(
                                        id: block.id,
                                        name: block.heading.isEmpty
                                            ? block.kind.title
                                            : block.heading
                                    )
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                .disabled(site.resolvedBlocks.count <= 1)
                            }
                        }
                    }
                        .formStyle(.grouped)
                        .padding(.bottom, 16)
                    }
                } else {
                    ContentUnavailableView(
                        "Select a Block",
                        systemImage: "square.dashed",
                        description: Text(
                            "Choose a page block to edit its content and layout."
                        )
                    )
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var designCanvas: some View {
        VStack(spacing: 0) {
            paneHeader("Live Canvas", systemImage: "macwindow") {
                Button {
                    mode = .preview
                } label: {
                    Label("Open Preview", systemImage: "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(.borderless)
            }
            Divider()
            websitePreview(showViewportControls: false)
        }
    }

    private var codeWorkspace: some View {
        GeometryReader { proxy in
            if proxy.size.width >= 700 {
                HSplitView {
                    fileNavigator
                        .frame(minWidth: 210, idealWidth: 240, maxWidth: 300)
                    sourceEditor
                        .frame(minWidth: 390)
                }
            } else {
                VStack(spacing: 0) {
                    compactFileNavigator
                    Divider()
                    sourceEditor
                }
            }
        }
    }

    private var fileNavigator: some View {
        VStack(spacing: 0) {
            paneHeader("Website Files", systemImage: "folder") {
                Button {
                    pathDraft = ""
                    pathPrompt = .newFile
                } label: {
                    Label("New", systemImage: "doc.badge.plus")
                }
                .buttonStyle(.borderless)
                .help("New website file")
            }
            Divider()

            List(selection: $selectedFileID) {
                ForEach(site.resolvedFiles) { file in
                    fileRow(file)
                        .tag(Optional(file.id))
                        .contextMenu {
                            fileActions(file)
                        }
                }
            }
            .listStyle(.sidebar)

            Divider()
            HStack {
                Text("\(site.resolvedFiles.count) files")
                Spacer()
                Text(ByteCountFormatter.string(
                    fromByteCount: Int64(site.resolvedFiles.reduce(0) { $0 + $1.bytes.count }),
                    countStyle: .file
                ))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(12)
        }
        .background(.regularMaterial)
    }

    private var compactFileNavigator: some View {
        HStack(spacing: 10) {
            Picker("Website file", selection: $selectedFileID) {
                ForEach(site.resolvedFiles) { file in
                    Text(file.path)
                        .tag(Optional(file.id))
                }
            }
            .labelsHidden()
            .frame(maxWidth: 360)

            Spacer()

            Button {
                pathDraft = ""
                pathPrompt = .newFile
            } label: {
                Image(systemName: "doc.badge.plus")
            }
            .help("New website file")
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 48)
        .background(.regularMaterial)
    }

    private func fileRow(_ file: SiteSourceFile) -> some View {
        HStack(spacing: 9) {
            Image(systemName: file.isText ? "doc.text" : "doc")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(file.path)
                    .font(.system(.subheadline, design: .monospaced))
                    .lineLimit(1)
                if file.path == site.resolvedEntryPath {
                    Text("Entry point")
                        .font(.caption2)
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private func fileActions(_ file: SiteSourceFile) -> some View {
        Button("Rename…") {
            selectedFileID = file.id
            pathDraft = file.path
            pathPrompt = .renameFile(id: file.id, path: file.path)
        }
        Button("Delete File", role: .destructive) {
            selectedFileID = file.id
            destructiveAction = .deleteFile(id: file.id, path: file.path)
        }
        .disabled(file.path == site.resolvedEntryPath)
    }

    private var sourceEditor: some View {
        Group {
            if let file = selectedFile {
                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(file.path)
                                .font(.system(.headline, design: .monospaced))
                                .lineLimit(1)
                            Text("\(file.mediaType) · \(file.bytes.count) bytes")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Label(
                            sourceSaveStatus,
                            systemImage: sourceSaveStatus == "Saving…"
                                ? "arrow.triangle.2.circlepath"
                                : "checkmark.circle"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        Button {
                            pathDraft = file.path
                            pathPrompt = .renameFile(
                                id: file.id,
                                path: file.path
                            )
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .help("Rename file")

                        Button(role: .destructive) {
                            destructiveAction = .deleteFile(
                                id: file.id,
                                path: file.path
                            )
                        } label: {
                            Image(systemName: "trash")
                        }
                        .disabled(file.path == site.resolvedEntryPath)
                        .help(
                            file.path == site.resolvedEntryPath
                                ? "The entry file cannot be deleted"
                                : "Delete file"
                        )
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 52)
                    .background(.bar)

                    Divider()

                    if file.isText, file.text != nil {
                        TextEditor(text: $sourceDraft)
                            .font(.system(.body, design: .monospaced))
                            .scrollContentBackground(.hidden)
                            .padding(12)
                            .background(Color(nsColor: .textBackgroundColor))
                            .focused($focusedSourceFileID, equals: file.id)
                            .onAppear {
                                loadSourceDraft(file)
                            }
                            .onChange(of: sourceDraft) {
                                scheduleSourceSave(fileID: file.id)
                            }
                    } else {
                        ContentUnavailableView {
                            Label("Binary Asset", systemImage: "doc.zipper")
                        } description: {
                            Text(
                                "\(file.path) is preserved byte-for-byte in the signed website bundle. Replace it by importing a new build folder."
                            )
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "No File Selected",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Choose a website file to inspect or edit.")
                )
            }
        }
    }

    private func websitePreview(showViewportControls: Bool) -> some View {
        VStack(spacing: 0) {
            if showViewportControls {
                HStack {
                    Label("Verified Preview", systemImage: "checkmark.shield")
                        .font(.headline)
                    Spacer()
                    Picker("Viewport", selection: $viewport) {
                        ForEach(PreviewViewport.allCases) { candidate in
                            Label(candidate.title, systemImage: candidate.systemImage)
                                .tag(candidate)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)

                    Button {
                        refreshPreview()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Reload website")
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 48)
                .background(.bar)
                Divider()
            }

            GeometryReader { proxy in
                let width = min(
                    viewport.width,
                    max(320, proxy.size.width - 44)
                )
                ScrollView([.horizontal, .vertical]) {
                    VStack(spacing: 0) {
                        HStack(spacing: 7) {
                            Circle().fill(.red.opacity(0.75)).frame(width: 8, height: 8)
                            Circle().fill(.yellow.opacity(0.75)).frame(width: 8, height: 8)
                            Circle().fill(.green.opacity(0.75)).frame(width: 8, height: 8)
                            Text(site.address)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: "checkmark.shield.fill")
                                .foregroundStyle(.green)
                                .help("Publisher-scoped verified preview")
                        }
                        .padding(.horizontal, 11)
                        .frame(height: 34)
                        .background(Color(nsColor: .windowBackgroundColor))

                        Divider()

                        if let bundle = try? WebsiteProjectBuilder.makeBundle(from: site) {
                            VerifiedWebsiteWebView(
                                bundle: bundle,
                                origin: site.publisherID ?? "",
                                reloadToken: reloadToken
                            )
                        } else {
                            ContentUnavailableView(
                                "Website Bundle Invalid",
                                systemImage: "exclamationmark.triangle",
                                description: Text(
                                    "Review the project files and entry point before previewing."
                                )
                            )
                        }
                    }
                    .frame(
                        width: width,
                        height: max(480, proxy.size.height - 44)
                    )
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.14), radius: 18, y: 8)
                    .padding(22)
                }
                .background(Color(nsColor: .underPageBackgroundColor))
            }
        }
    }

    private func paneHeader<Actions: View>(
        _ title: String,
        systemImage: String,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        HStack(spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            Spacer()
            actions()
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 46)
        .background(.bar)
    }

    private var selectedBlock: SiteBlock? {
        guard let selectedBlockID else { return nil }
        return site.resolvedBlocks.first(where: { $0.id == selectedBlockID })
    }

    private var selectedFile: SiteSourceFile? {
        guard let selectedFileID else { return nil }
        return (model.selectedSite?.resolvedFiles ?? site.resolvedFiles)
            .first(where: { $0.id == selectedFileID })
    }

    private var isFirstSelectedBlock: Bool {
        guard
            let selectedBlockID,
            let index = site.resolvedBlocks.firstIndex(where: { $0.id == selectedBlockID })
        else { return true }
        return index == 0
    }

    private var isLastSelectedBlock: Bool {
        guard
            let selectedBlockID,
            let index = site.resolvedBlocks.firstIndex(where: { $0.id == selectedBlockID })
        else { return true }
        return index == site.resolvedBlocks.count - 1
    }

    private func siteStringBinding(
        _ keyPath: WritableKeyPath<SiteProject, String>
    ) -> Binding<String> {
        Binding(
            get: { model.selectedSite?[keyPath: keyPath] ?? "" },
            set: { value in
                Task { @MainActor in
                    await Task.yield()
                    model.updateSelectedSite { $0[keyPath: keyPath] = value }
                    refreshPreview(debounced: true)
                }
            }
        )
    }

    private var relayNamespaceBinding: Binding<String> {
        Binding(
            get: { model.selectedSite?.relayNamespaceID ?? "" },
            set: { model.selectRelayNamespace($0) }
        )
    }

    private var publisherRouteDirectiveBinding: Binding<RouteDirective> {
        Binding(
            get: {
                model.selectedSite?.resolvedPublisherRouteDirective ?? .open
            },
            set: { model.setPublisherRouteDirective($0) }
        )
    }

    private func blockStringBinding(
        _ blockID: UUID,
        _ keyPath: WritableKeyPath<SiteBlock, String>
    ) -> Binding<String> {
        Binding(
            get: {
                model.selectedSite?.resolvedBlocks.first(
                    where: { $0.id == blockID }
                )?[keyPath: keyPath] ?? ""
            },
            set: { value in
                Task { @MainActor in
                    await Task.yield()
                    model.updateBlock(blockID) { $0[keyPath: keyPath] = value }
                    refreshPreview(debounced: true)
                }
            }
        )
    }

    private func blockKindBinding(_ blockID: UUID) -> Binding<SiteBlockKind> {
        Binding(
            get: {
                model.selectedSite?.resolvedBlocks.first(
                    where: { $0.id == blockID }
                )?.kind ?? .text
            },
            set: { kind in
                model.updateBlock(blockID) { $0.kind = kind }
                refreshPreview()
            }
        )
    }

    private func accentButton(_ hex: String) -> some View {
        Button {
            model.updateSelectedVisualSite { $0.accentHex = hex }
            refreshPreview()
        } label: {
            Circle()
                .fill(Color(hex: hex))
                .frame(width: 22, height: 22)
                .overlay {
                    if site.accentHex == hex {
                        Circle()
                            .stroke(.white, lineWidth: 2)
                            .padding(3)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Use accent \(hex)")
    }

    private func performDeleteBlock(_ blockID: UUID) {
        let blocks = site.resolvedBlocks
        guard
            blocks.count > 1,
            let index = blocks.firstIndex(where: { $0.id == blockID })
        else { return }
        model.deleteBlock(blockID)
        let remaining = model.selectedSite?.resolvedBlocks ?? []
        selectedBlockID = remaining.indices.contains(index)
            ? remaining[index].id
            : remaining.last?.id
        destructiveAction = nil
        refreshPreview()
    }

    private func performDeleteFile(_ fileID: UUID) {
        model.deleteSourceFile(fileID)
        destructiveAction = nil
        repairFileSelection()
        refreshPreview()
    }

    private func importBuild(at url: URL) {
        model.importWebsiteDirectory(url)
        destructiveAction = nil
        guard model.operationError == nil else { return }
        selectedFileID = model.selectedSite?.resolvedFiles.first(
            where: { $0.path == model.selectedSite?.resolvedEntryPath }
        )?.id
        mode = .code
        refreshPreview()
    }

    private func resetSelectionForCurrentSite() {
        mode = site.resolvedProjectKind == .visual ? .design : .code
        selectedBlockID = site.resolvedBlocks.first?.id
        selectedFileID = site.resolvedFiles.first(
            where: { $0.path == site.resolvedEntryPath }
        )?.id ?? site.resolvedFiles.first?.id
        loadSelectedSourceDraft()
        refreshPreview()
    }

    private func repairFileSelection() {
        let files = model.selectedSite?.resolvedFiles ?? site.resolvedFiles
        let entryPath =
            model.selectedSite?.resolvedEntryPath ?? site.resolvedEntryPath
        if let selectedFileID,
           files.contains(where: { $0.id == selectedFileID })
        {
            return
        }
        self.selectedFileID = files.first(
            where: { $0.path == entryPath }
        )?.id ?? files.first?.id
        loadSelectedSourceDraft()
    }

    private func loadSelectedSourceDraft() {
        guard let selectedFile else {
            sourceSaveTask?.cancel()
            sourceDraftFileID = nil
            sourceDraft = ""
            sourceSaveStatus = "Saved locally"
            return
        }
        loadSourceDraft(selectedFile)
    }

    private func loadSourceDraft(_ file: SiteSourceFile) {
        guard sourceDraftFileID != file.id else { return }
        sourceSaveTask?.cancel()
        sourceDraftFileID = file.id
        sourceDraft = file.text ?? ""
        sourceSaveStatus = "Saved locally"
    }

    private func scheduleSourceSave(fileID: UUID) {
        guard sourceDraftFileID == fileID else { return }
        let currentText = model.selectedSite?.resolvedFiles.first(
            where: { $0.id == fileID }
        )?.text
        guard currentText != sourceDraft else {
            sourceSaveStatus = "Saved locally"
            return
        }
        sourceSaveTask?.cancel()
        sourceSaveStatus = "Saving…"
        let value = sourceDraft
        sourceSaveTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(450))
            } catch {
                return
            }
            guard sourceDraftFileID == fileID else { return }
            model.updateSourceFile(fileID, text: value)
            sourceSaveStatus = "Saved locally"
            refreshPreview()
        }
    }

    private func flushSourceDraft() {
        sourceSaveTask?.cancel()
        guard let fileID = sourceDraftFileID else { return }
        let currentText = model.selectedSite?.resolvedFiles.first(
            where: { $0.id == fileID }
        )?.text
        guard currentText != sourceDraft else {
            sourceSaveStatus = "Saved locally"
            return
        }
        model.updateSourceFile(fileID, text: sourceDraft)
        sourceSaveStatus = "Saved locally"
        refreshPreview()
    }

    private func refreshPreview(debounced: Bool = false) {
        previewRefreshTask?.cancel()
        guard debounced else {
            reloadToken = UUID()
            return
        }
        previewRefreshTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return
            }
            reloadToken = UUID()
        }
    }

    private var pathPromptBinding: Binding<Bool> {
        Binding(
            get: { pathPrompt != nil },
            set: { if !$0 { pathPrompt = nil } }
        )
    }

    private var destructiveActionBinding: Binding<Bool> {
        Binding(
            get: { destructiveAction != nil },
            set: { if !$0 { destructiveAction = nil } }
        )
    }

    private let accentChoices = [
        "#7B61FF",
        "#5B9CFA",
        "#3DD5C5",
        "#62697A",
        "#1C2030",
    ]
}

private extension String {
    var shortIdentifier: String {
        guard count > 18 else { return self }
        return "\(prefix(10))…\(suffix(6))"
    }
}
