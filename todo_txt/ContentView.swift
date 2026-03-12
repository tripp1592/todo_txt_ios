import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

struct ContentView: View {
    @StateObject private var vm: TodoListViewModel
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @AppStorage("defaultPriority") private var defaultPriorityRaw = ""
    @AppStorage("autoArchiveOnComplete") private var autoArchiveOnComplete = false
    @AppStorage("iCloudSyncEnabled") private var iCloudSyncEnabled = false
    @State private var newLine = ""
    @State private var showImporter = false
    @State private var showSettings = false
    @State private var showOnboarding = false
    @State private var openImporterAfterOnboarding = false
    @State private var didRunInitialSetup = false
    @State private var alertText: String?
    @State private var editingTask: TodoTask?
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
                        Text("Newest").tag(TodoListViewModel.Sort.newestDate)
                        Text("Text").tag(TodoListViewModel.Sort.text)
                    }
                    .pickerStyle(.menu)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 8)

                List {
                    ForEach(vm.visibleTasks) { task in
                        HStack(spacing: 10) {
                            Image(systemName: task.completed ? "checkmark.square.fill" : "square")
                                .frame(width: 28, alignment: .leading)
                                .foregroundStyle(task.completed ? .green : .secondary)

                            Text(canonicalDisplayLine(for: task))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .foregroundStyle(task.completed ? .secondary : .primary)
                        }
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
                            Button {
                                editingTask = task
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                        .contextMenu {
                            Button {
                                handleToggle(task)
                            } label: {
                                Label(task.completed ? "Uncomplete" : "Complete",
                                      systemImage: task.completed ? "arrow.uturn.backward" : "checkmark")
                            }
                            Button {
                                editingTask = task
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                vm.deleteTask(task)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    .onDelete(perform: vm.deleteVisible)
                }
                .listStyle(.plain)

                HStack(spacing: 10) {
                    TextField("(A) 2025-08-11 Your task +Project @context due:2025-09-01", text: $newLine)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .font(.body.monospaced())
                        .onSubmit(commitNew)
                    Button(action: { commitNew() }) {
                        Image(systemName: "plus")
                            .imageScale(.large)
                            .font(.title3.weight(.bold))
                    }
                    .accessibilityLabel("Add task")
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.horizontal)
                .padding(.vertical, 10)

                Text("File: \(vmStoreFileName) • \(vm.visibleTasks.count) / \(vm.tasks.count)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)
            }
            .navigationTitle("Tasks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showImporter = true
                    } label: {
                        Label("Choose File", systemImage: "folder")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    ShareLink(item: TodoFileStore.shared.fileURL()) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
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
            .sheet(isPresented: $showOnboarding) {
                FirstLaunchSheet(
                    onUseLocal: {
                        vm.clearExternalURL()
                        vm.seedStarterTasksIfNeeded()
                        hasSeenOnboarding = true
                        showOnboarding = false
                    },
                    onImportExistingFile: {
                        openImporterAfterOnboarding = true
                        hasSeenOnboarding = true
                        showOnboarding = false
                    }
                )
            }
            .sheet(isPresented: $showSettings) {
                SettingsSheet(
                    currentFileName: vmStoreFileName,
                    onChooseFile: {
                        iCloudSyncEnabled = false
                        showSettings = false
                        showImporter = true
                    },
                    onUseLocalFile: {
                        iCloudSyncEnabled = false
                        vm.clearExternalURL()
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
                vm.updateBadgeCount()
            }
        }
        .onChange(of: showOnboarding) { _, isShowing in
            guard !isShowing, openImporterAfterOnboarding else { return }
            openImporterAfterOnboarding = false
            showImporter = true
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
            case .failure(let error):
                alertText = error.localizedDescription
            }
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

    private func canonicalDisplayLine(for task: TodoTask) -> String {
        TodoParser.serialize(task)
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

    private func handleToggle(_ task: TodoTask) {
        let justCompleted = vm.toggle(task)
        if autoArchiveOnComplete, justCompleted {
            _ = vm.archiveCompleted()
        }
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

    private func commitNew() {
        let line = newLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return }

        let lineToAdd = lineWithDefaultPriorityIfNeeded(line)
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
}
