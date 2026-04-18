import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

struct ContentView: View {
    @StateObject private var vm: TodoListViewModel
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @AppStorage("iCloudSyncEnabled") private var iCloudSyncEnabled = false
    
    @State private var showImporter = false
    @State private var showArchiveExporter = false
    @State private var showArchiveImporter = false
    @State private var showArchivePrompt = false
    @State private var archiveDocument: TodoTextDocument?
    @State private var showExporter = false
    @State private var showSettings = false
    @State private var showOnboarding = false
    @State private var openImporterAfterOnboarding = false
    @State private var didRunInitialSetup = false
    @State private var alertText: String?
    @State private var editingTask: TodoTask?
    @State private var exportDocument: TodoTextDocument?
    
    @Environment(\.scenePhase) private var scenePhase

    @MainActor
    init() {
        _vm = StateObject(wrappedValue: TodoListViewModel())
    }

    @MainActor
    init(viewModel: TodoListViewModel) {
        _vm = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Text("Sort")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Sort", selection: $vm.sort) {
                        Text("Priority").tag(TodoListViewModel.Sort.priority)
                        Text("Due").tag(TodoListViewModel.Sort.dueDate)
                    }
                    .pickerStyle(.menu)
                    .fixedSize()
                    Spacer()
                    Text("Group")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Group", selection: $vm.grouping) {
                        Text("None").tag(TodoListViewModel.Grouping.none)
                        Text("Priority").tag(TodoListViewModel.Grouping.priority)
                        Text("Due").tag(TodoListViewModel.Grouping.dueDate)
                        Text("Project").tag(TodoListViewModel.Grouping.project)
                        Text("Context").tag(TodoListViewModel.Grouping.context)
                    }
                    .pickerStyle(.menu)
                    .fixedSize()
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 8)

                List {
                    if vm.grouping == .none {
                        ForEach(vm.visibleTasks) { task in
                            TaskRowView(task: task, vm: vm) {
                                editingTask = task
                            }
                        }
                        .onDelete(perform: vm.deleteVisible)
                    } else {
                        ForEach(vm.groupedTasks, id: \.key) { group in
                            Section(group.key) {
                                ForEach(group.tasks) { task in
                                    TaskRowView(task: task, vm: vm) {
                                        editingTask = task
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollDismissesKeyboard(.interactively)
                .onTapGesture {
                    dismissKeyboard()
                }

                AddTaskView(vm: vm, alertText: $alertText)

                Text("File: \(vmStoreFileName) • \(vm.visibleTasks.count) / \(vm.tasks.count)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)
            }
            .navigationTitle("Tasks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(item: $editingTask) { task in
                EditTaskSheet(
                    task: task,
                    projects: vm.allProjects,
                    contexts: vm.allContexts,
                    onSave: { newRaw in
                        if vm.update(task, with: newRaw) {
                            return nil
                        }
                        return "Invalid todo.txt line. Check priority/date/order."
                    },
                    onDismiss: {
                        editingTask = nil
                    }
                )
            }
            .sheet(isPresented: $showOnboarding, onDismiss: {
            if openImporterAfterOnboarding {
                openImporterAfterOnboarding = false
                showImporter = true
            }
        }) {
                FirstLaunchSheet(
                    onUseLocal: {
                        vm.clearExternalURL()
                        vm.seedStarterTasksIfNeeded()
                        hasSeenOnboarding = true
                        showOnboarding = false
                    },
                    onImportExistingFile: {
                        hasSeenOnboarding = true
                        showOnboarding = false
                        openImporterAfterOnboarding = true
                    }
                )
            }
            .sheet(isPresented: $showSettings) {
                SettingsSheet(
                    currentFileURL: TodoFileStore.shared.fileURL(),
                    onImportFile: { url in
                        iCloudSyncEnabled = false
                        vm.setExternalURL(url)
                        if TodoFileStore.shared.needsArchiveBookmark {
                            showArchivePrompt = true
                        }
                        showSettings = false
                    },
                    onUseLocalFile: {
                        iCloudSyncEnabled = false
                        vm.clearExternalURL()
                        showSettings = false
                    },
                    onExportFile: {
                        exportCurrentFile()
                        showSettings = false
                    },
                    onArchiveNow: {
                        archiveNow()
                    },
                    onICloudSyncChanged: { enabled in
                        setICloudSync(enabled)
                    }
                )
            }
        }
        .onAppear {
            runInitialSetupIfNeeded()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                vm.load()
            }
        }
        .fileExporter(
            isPresented: $showExporter,
            document: exportDocument,
            contentType: .plainText,
            defaultFilename: "todo.txt"
        ) { result in
            if case .failure(let error) = result {
                alertText = error.localizedDescription
            }
            exportDocument = nil
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [UTType.plainText],
            allowsMultipleSelection: false
        ) { (result: Result<[URL], Error>) in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                guard url.pathExtension.lowercased() == "txt" else {
                    alertText = "Please choose a .txt file."
                    return
                }
                iCloudSyncEnabled = false
                vm.setExternalURL(url)
                if TodoFileStore.shared.needsArchiveBookmark {
                    showArchivePrompt = true
                }
            case .failure(let error):
                alertText = error.localizedDescription
            }
        }
        .fileExporter(
            isPresented: $showArchiveExporter,
            document: archiveDocument,
            contentType: .plainText,
            defaultFilename: "done.txt"
        ) { result in
            switch result {
            case .success(let url):
                TodoFileStore.shared.setExternalArchiveURL(url)
            case .failure(let error):
                alertText = error.localizedDescription
            }
            archiveDocument = nil
        }
        .fileImporter(
            isPresented: $showArchiveImporter,
            allowedContentTypes: [UTType.plainText],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                TodoFileStore.shared.setExternalArchiveURL(url)
            } else if case .failure(let error) = result {
                alertText = error.localizedDescription
            }
        }
        .alert(
            "Link done.txt",
            isPresented: $showArchivePrompt
        ) {
            Button("Select Existing done.txt") {
                showArchiveImporter = true
            }
            Button("Create New done.txt") {
                archiveDocument = TodoTextDocument(text: "")
                showArchiveExporter = true
            }
            Button("Skip", role: .cancel) {}
        } message: {
            Text("Would you like to link a done.txt file for archiving completed tasks? You can select an existing one or create a new one. If you skip, archived tasks will be stored locally in the app.")
        }
        .alert(
            "Notice",
            isPresented: Binding(
                get: { alertText != nil },
                set: { if !$0 { alertText = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertText ?? "")
        }
        .alert(
            "Error",
            isPresented: Binding(
                get: { vm.lastError != nil },
                set: { if !$0 { vm.lastError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(vm.lastError ?? "")
        }
    }

    private var vmStoreFileName: String {
        TodoFileStore.shared.fileURL().lastPathComponent
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func runInitialSetupIfNeeded() {
        guard !didRunInitialSetup else { return }
        didRunInitialSetup = true

        if iCloudSyncEnabled {
            setICloudSync(true)
        } else {
            TodoFileStore.shared.ensureFileExistsForUI()
        }

        if !hasSeenOnboarding {
            showOnboarding = true
        }
    }

    private func exportCurrentFile() {
        let url = TodoFileStore.shared.fileURL()
        let content: String = (try? coordinatedRead(url: url) { readURL in
            try String(contentsOf: readURL, encoding: .utf8)
        }) ?? ""
        exportDocument = TodoTextDocument(text: content)
        showExporter = true
    }

    private func archiveNow() {
        let count = vm.archiveCompleted()
        if count > 0 {
            alertText = "Archived \(count) completed task\(count == 1 ? "" : "s") to done.txt."
        } else if vm.lastError == nil {
            alertText = "No completed tasks to archive."
        }
    }

    private func setICloudSync(_ enabled: Bool) {
        if enabled {
            do {
                try vm.enableICloudSync()
                iCloudSyncEnabled = true
            } catch {
                iCloudSyncEnabled = false
                alertText = error.localizedDescription
            }
        } else {
            iCloudSyncEnabled = false
            vm.clearExternalURL()
        }
    }
}

// MARK: - Extracted Subviews

struct TaskRowView: View {
    let task: TodoTask
    @ObservedObject var vm: TodoListViewModel
    let onEdit: () -> Void
    
    @AppStorage("archivingEnabled") private var archivingEnabled = true
    @AppStorage("autoArchiveOnComplete") private var autoArchiveOnComplete = false

    var body: some View {
        coloredTaskText
            .frame(maxWidth: .infinity, alignment: .leading)
        .font(.body.monospaced())
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                vm.deleteTask(task)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            Button(action: onEdit) {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.blue)
        }
        .contextMenu {
            Button {
                handleToggle()
            } label: {
                Label(task.completed ? "Uncomplete" : "Complete",
                      systemImage: task.completed ? "arrow.uturn.backward" : "checkmark")
            }
            Button(action: onEdit) {
                Label("Edit", systemImage: "pencil")
            }
            Button(role: .destructive) {
                vm.deleteTask(task)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var coloredTaskText: Text {
        if task.completed {
            return Text(TodoParser.serialize(task))
                .foregroundStyle(.secondary)
        }

        var parts: [Text] = []

        if let priority = task.priority {
            parts.append(Text("(\(String(priority)))").foregroundStyle(.orange))
        }

        if let creationDate = task.creationDate {
            parts.append(Text(TodoParser.dateFormatter.string(from: creationDate)).foregroundStyle(.gray))
        }

        if !task.baseDescription.isEmpty {
            parts.append(Text(task.baseDescription).foregroundStyle(.primary))
        }

        for project in task.projects {
            parts.append(Text("+\(project)").foregroundStyle(.blue))
        }

        for context in task.contexts {
            parts.append(Text("@\(context)").foregroundStyle(.purple))
        }

        for (key, value) in task.extras.sorted(by: { $0.key < $1.key }) {
            let color: Color = {
                if key == "due", let dueDate = TodoParser.dateFormatter.date(from: value) {
                    let today = Calendar.current.startOfDay(for: Date())
                    return dueDate <= today ? .red : .orange
                }
                return .orange
            }()
            parts.append(Text("\(key):\(value)").foregroundStyle(color))
        }

        return parts.enumerated().reduce(Text("")) { result, item in
            item.offset == 0 ? item.element : result + Text(" ") + item.element
        }
    }

    private func handleToggle() {
        let justCompleted = vm.toggle(task)
        if archivingEnabled, autoArchiveOnComplete, justCompleted {
            _ = vm.archiveCompleted()
        }
    }
}

struct AddTaskView: View {
    @ObservedObject var vm: TodoListViewModel
    @Binding var alertText: String?
    
    @AppStorage("defaultPriority") private var defaultPriorityRaw = ""
    @AppStorage("autoCreationDate") private var autoCreationDate = true
    @State private var newLine = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            SuggestionBarView(text: $newLine, projects: vm.allProjects, contexts: vm.allContexts)

            HStack(spacing: 10) {
                TextField("(A) 2025-08-11 Your task +Project @context due:2025-09-01", text: $newLine)
                    .focused($isInputFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .font(.body.monospaced())
                    .onSubmit(commitNew)
                Button {
                    if newLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        isInputFocused = true
                    } else {
                        commitNew()
                    }
                } label: {
                    Image(systemName: "plus")
                        .imageScale(.large)
                        .font(.title3.weight(.bold))
                }
                .accessibilityLabel("Add task")
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
    }

    private func commitNew() {
        let line = newLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else {
            isInputFocused = true
            return
        }

        var lineToAdd = lineWithDefaultPriorityIfNeeded(line)
        lineToAdd = lineWithCreationDateIfNeeded(lineToAdd)
        if let errorMessage = vm.add(lineToAdd) {
            alertText = errorMessage
        } else {
            newLine = ""
        }
    }

    private func lineWithDefaultPriorityIfNeeded(_ line: String) -> String {
        guard let parsed = try? TodoParser.parse(line: line) else { return line }
        guard !parsed.completed, parsed.priority == nil else { return line }
        guard defaultPriorityRaw.count == 1 else { return line }
        return "(\(defaultPriorityRaw)) \(line)"
    }

    private func lineWithCreationDateIfNeeded(_ line: String) -> String {
        guard autoCreationDate else { return line }
        guard let parsed = try? TodoParser.parse(line: line) else { return line }
        guard !parsed.completed, parsed.creationDate == nil else { return line }

        let today = TodoParser.dateFormatter.string(from: Date())

        // Insert the date after the priority if present, otherwise at the start.
        if let priority = parsed.priority {
            return "(\(priority)) \(today) \(line.dropFirst(4))"
        } else {
            return "\(today) \(line)"
        }
    }
}
// MARK: - Autocomplete Suggestion Bar

struct SuggestionBarView: View {
    @Binding var text: String
    let projects: [String]
    let contexts: [String]

    private var activeToken: String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        // Find the last whitespace-separated token
        let tokens = trimmed.split(separator: " ", omittingEmptySubsequences: false)
        guard let last = tokens.last else { return nil }
        let token = String(last)
        if token.hasPrefix("+") || token.hasPrefix("@") {
            return token
        }
        return nil
    }

    private var suggestions: [String] {
        guard let token = activeToken else { return [] }
        let prefix = token.prefix(1) // "+" or "@"
        let partial = String(token.dropFirst()).lowercased()

        let candidates: [String]
        if prefix == "+" {
            candidates = projects
        } else {
            candidates = contexts
        }

        let filtered = candidates.filter { name in
            let lower = name.lowercased()
            // Show all if user just typed the prefix character, otherwise filter
            return partial.isEmpty || lower.hasPrefix(partial)
        }

        // Return full tags (e.g. "+Family"), excluding exact matches
        return filtered.compactMap { name in
            let full = "\(prefix)\(name)"
            if full.lowercased() == token.lowercased() { return nil }
            return full
        }
    }

    var body: some View {
        if !suggestions.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button {
                            accept(suggestion)
                        } label: {
                            Text(suggestion)
                                .font(.footnote.monospaced())
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .controlSize(.small)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
            }
        }
    }

    private func accept(_ suggestion: String) {
        // Replace the last token with the suggestion
        guard activeToken != nil else { return }
        // Find the range of the last token by finding the last space
        if let lastSpaceIndex = text.lastIndex(of: " ") {
            let afterSpace = text.index(after: lastSpaceIndex)
            text.replaceSubrange(afterSpace..., with: suggestion + " ")
        } else {
            // The entire text is the token
            text = suggestion + " "
        }
    }
}

// MARK: - File Export Document

struct TodoTextDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }

    let text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents {
            text = String(data: data, encoding: .utf8) ?? ""
        } else {
            text = ""
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
