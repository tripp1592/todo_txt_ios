import SwiftUI
import UniformTypeIdentifiers
import UserNotifications
#if os(iOS)
import UIKit
#endif

struct SettingsSheet: View {
    private enum NotificationPermissionState {
        case unknown
        case notDetermined
        case denied
        case authorized
        case provisional
        case ephemeral

        var description: String {
            switch self {
            case .unknown: return "Checking status"
            case .notDetermined: return "Not enabled"
            case .denied: return "Disabled in Settings"
            case .authorized: return "Alerts and badges enabled"
            case .provisional: return "Provisionally allowed"
            case .ephemeral: return "Temporarily allowed"
            }
        }
    }

    @AppStorage("defaultPriority") private var defaultPriorityRaw = ""
    @AppStorage("autoCreationDate") private var autoCreationDate = true
    @AppStorage("archivingEnabled") private var archivingEnabled = true
    @AppStorage("autoArchiveOnComplete") private var autoArchiveOnComplete = false
    @AppStorage("iCloudSyncEnabled") private var iCloudSyncEnabled = false
    @Environment(\.openURL) private var openURL
    @State private var notificationPermissionState: NotificationPermissionState = .unknown
    @State private var showUserGuide = false
    @State private var showImporter = false

    let currentFileURL: URL
    let onImportFile: (URL) -> Void
    let onUseLocalFile: () -> Void
    let onExportFile: () -> Void
    let onArchiveNow: () -> Void
    let onICloudSyncChanged: (Bool) -> Void

    private var currentFileLocation: String {
        let path = currentFileURL.path

        // Check if it's the app's internal documents directory
        if let appDocuments = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
           path.hasPrefix(appDocuments.path) {
            return "App Storage"
        }

        // Use the stored provider display name if available (e.g. "Dropbox")
        if let providerName = TodoFileStore.shared.externalProviderName {
            return providerName
        }

        // Check for iCloud ubiquity container
        if path.contains("ubiquity") || path.contains("iCloud") {
            return "iCloud Drive"
        }

        return "External File"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("User Guide") {
                        showUserGuide = true
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("File")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(currentFileURL.path)
                            .font(.caption.monospaced())
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                        LabeledContent("Location", value: currentFileLocation)
                    }
                    .padding(.vertical, 2)
                    Toggle("Sync with iCloud Drive", isOn: $iCloudSyncEnabled)
                        .onChange(of: iCloudSyncEnabled) { _, enabled in
                            onICloudSyncChanged(enabled)
                        }
                    Button("Import a TODO.txt File") {
                        showImporter = true
                    }
                    Button("Create New TODO.txt File", action: onUseLocalFile)
                    Button("Export TODO.txt Copy", action: onExportFile)
                } header: {
                    Text("File")
                } footer: {
                    Text("Import sets the selected file as your default. All changes are saved directly to it.")
                }

                Section("Tasks") {
                    Picker("Default Priority", selection: $defaultPriorityRaw) {
                        Text("None").tag("")
                        Text("A – Highest").tag("A")
                        Text("B – High").tag("B")
                        Text("C – Normal").tag("C")
                        Text("D – Low").tag("D")
                        Text("E – Lowest").tag("E")
                    }
                    Toggle("Add Creation Date Automatically", isOn: $autoCreationDate)
                    Toggle("Archive Completed to done.txt", isOn: $archivingEnabled)
                    if archivingEnabled {
                        Toggle("Auto Archive on Complete", isOn: $autoArchiveOnComplete)
                        Button("Archive Now", action: onArchiveNow)
                    }
                }

                Section("Notifications") {
                    LabeledContent("Status", value: notificationPermissionState.description)
                    if notificationPermissionState == .notDetermined {
                        Button("Enable Alerts and Badges") {
                            requestNotificationPermissions()
                        }
                    } else {
                        Button("Open Notification Settings") {
                            openNotificationSettings()
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                refreshNotificationPermissionState()
            }
            .sheet(isPresented: $showUserGuide) {
                TodoTxtGuideSheet()
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [UTType.plainText],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    onImportFile(url)
                }
            }
        }
    }

    private func refreshNotificationPermissionState() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let state: NotificationPermissionState
            switch settings.authorizationStatus {
            case .notDetermined: state = .notDetermined
            case .denied: state = .denied
            case .authorized: state = .authorized
            case .provisional: state = .provisional
            case .ephemeral: state = .ephemeral
            @unknown default: state = .unknown
            }

            DispatchQueue.main.async {
                notificationPermissionState = state
            }
        }
    }

    private func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge]) { _, _ in
            refreshNotificationPermissionState()
        }
    }

    private func openNotificationSettings() {
#if os(iOS)
        guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
        openURL(url)
#endif
    }
}

struct TodoTxtGuideSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("One line in your todo.txt file equals one task. That's it. Just type what you need to do.")
                    Text("Everything below is optional. A task can be as simple as:")
                    Text("Buy milk")
                        .font(.body.monospaced())
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Basics")
                } footer: {
                    Text("All formatting — priority, dates, projects, contexts — is completely optional. Use only what helps you.")
                }

                Section("Priority") {
                    Text("Add a letter in parentheses at the very start to set importance. The app offers five levels:")
                    VStack(alignment: .leading, spacing: 4) {
                        Text("(A) Highest")
                        Text("(B) High")
                        Text("(C) Normal — the default/average level")
                        Text("(D) Low")
                        Text("(E) Lowest")
                    }
                    .font(.body.monospaced())
                    .foregroundStyle(.secondary)
                    Text("(A) Call Mom")
                        .font(.body.monospaced())
                        .foregroundStyle(.secondary)
                    Text("(C) Schedule dentist appointment")
                        .font(.body.monospaced())
                        .foregroundStyle(.secondary)
                    Text("Pick up groceries")
                        .font(.body.monospaced())
                        .foregroundStyle(.secondary)
                    Text("Priority is optional. Tasks without one are treated as lowest priority when sorting. Letters F\u{2013}Z are also valid if typed manually.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Creation Date") {
                    Text("A date in YYYY-MM-DD format can appear right after the priority (or first if there's no priority).")
                    Text("(A) 2026-03-11 Call Mom")
                        .font(.body.monospaced())
                        .foregroundStyle(.secondary)
                    Text("2026-03-11 Buy milk")
                        .font(.body.monospaced())
                        .foregroundStyle(.secondary)
                    Text("Creation dates are optional. They help you see how long a task has been on your list.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Projects & Contexts") {
                    Text("Tag tasks with +Project to group by project, and @context for where or how you'll do it.")
                    Text("Call Mom +Family @phone")
                        .font(.body.monospaced())
                        .foregroundStyle(.secondary)
                    Text("Schedule pickup +GarageSale @phone")
                        .font(.body.monospaced())
                        .foregroundStyle(.secondary)
                    Text("Research flights +Vacation @computer")
                        .font(.body.monospaced())
                        .foregroundStyle(.secondary)
                    Text("Projects and contexts are optional. A task can have zero, one, or many of each. They can appear anywhere in the task text.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Completing Tasks") {
                    Text("A completed task starts with a lowercase x followed by the completion date.")
                    Text("x 2026-03-11 Call Mom")
                        .font(.body.monospaced())
                        .foregroundStyle(.secondary)
                    Text("x 2026-03-11 2026-03-10 Buy milk")
                        .font(.body.monospaced())
                        .foregroundStyle(.secondary)
                    Text("The second date above is the original creation date. This lets you see how long a task took.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Text("Use key:value pairs anywhere in the task for additional data. The app recognizes these two tags:")

                    VStack(alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("due:")
                                .font(.body.monospaced().bold())
                            Text("Due date. When the task needs to be finished. Shows as a date picker when editing.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Divider()
                        VStack(alignment: .leading, spacing: 2) {
                            Text("t:")
                                .font(.body.monospaced().bold())
                            Text("Threshold (start) date. When you can start working on the task. Shows as a date picker when editing.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)

                    Text("(A) Submit report due:2026-03-20")
                        .font(.body.monospaced())
                        .foregroundStyle(.secondary)
                    Text("Start taxes t:2026-04-01")
                        .font(.body.monospaced())
                        .foregroundStyle(.secondary)
                    Text("You can also add your own custom tags like note:reminder or link:url. The app will preserve them, but they won't get special handling.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Meta Tags")
                }

                Section("Using This App") {
                    Label("Type a task in the text field at the bottom and tap + to add it.", systemImage: "plus")
                    Label("Long press a task to mark it complete, edit, or delete.", systemImage: "hand.tap")
                    Label("Swipe right on a task to edit. Swipe left to delete.", systemImage: "hand.draw")
                    Label("Use the sort menu to order tasks by priority, date, or text.", systemImage: "arrow.up.arrow.down")
                    Label("Creation dates are added automatically by default. You can turn this off in Settings.", systemImage: "calendar.badge.plus")
                    Label("Archiving is optional. When enabled, completed tasks move from todo.txt to done.txt.", systemImage: "archivebox")
                    Label("Import a todo.txt from Dropbox, iCloud, or other providers in Settings. Export a copy anytime.", systemImage: "folder")
                    Label("When importing from an external provider, you can also link a done.txt for archiving.", systemImage: "doc.on.doc")
                }

                Section("Full Example") {
                    Group {
                        Text("(A) 2026-03-11 Call Mom +Family @phone")
                        Text("(B) Schedule Goodwill pickup +GarageSale @phone")
                        Text("Post signs around the neighborhood +GarageSale")
                        Text("Buy milk @errands due:2026-03-12")
                        Text("x 2026-03-11 2026-03-10 File taxes +Finance @computer")
                    }
                    .font(.body.monospaced())
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("User Guide")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct FirstLaunchSheet: View {
    let onUseLocal: () -> Void
    let onImportExistingFile: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Choose how to start")
                    .font(.headline)
                Text("You can start with a local `todo.txt` in this app, or import your existing file.")
                    .foregroundStyle(.secondary)
                Button(action: onUseLocal) {
                    Label("Start with local todo.txt", systemImage: "doc.text")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button(action: onImportExistingFile) {
                    Label("Import existing .txt file", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Spacer()
            }
            .padding()
            .navigationTitle("Welcome")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

enum TaskEditFormatter {
    /// Returns the editable text for the task body, **excluding** project tags.
    /// Projects are managed separately in the edit sheet.
    static func editableTaskText(for task: TodoTask) -> String {
        var bodyTokens: [String] = []

        if !task.baseDescription.isEmpty {
            bodyTokens.append(task.baseDescription)
        }
        // Projects are intentionally omitted — they are managed via the Projects picker.
        bodyTokens.append(contentsOf: task.contexts.map { "@\($0)" })
        bodyTokens.append(contentsOf: task.extras
            .filter { $0.key != "due" && $0.key != "t" }
            .sorted { $0.key < $1.key }
            .map { "\($0.key):\($0.value)" })

        return bodyTokens.joined(separator: " ")
    }

    static func composedRawLine(
        task: TodoTask,
        taskText: String,
        priorityRaw: String,
        selectedProjects: [String],
        dueDateText: String,
        thresholdDateText: String
    ) -> String {
        let editableBody = taskText
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let (description, textProjects, contexts, parsedExtras) = TodoParser.parseRest(editableBody)
        var parts: [String] = []

        if task.completed {
            parts.append("x")
            parts.append(TodoParser.dateFormatter.string(from: task.completionDate ?? Date()))
            if let creationDate = task.creationDate {
                parts.append(TodoParser.dateFormatter.string(from: creationDate))
            }
        } else {
            if priorityRaw.count == 1 {
                parts.append("(\(priorityRaw))")
            }
            if let creationDate = task.creationDate {
                parts.append(TodoParser.dateFormatter.string(from: creationDate))
            }
        }

        // Merge projects from the picker and any typed in the text field
        let allProjects = Set(selectedProjects).union(textProjects)

        var bodyTokens: [String] = []
        if !description.isEmpty {
            bodyTokens.append(description)
        }
        bodyTokens.append(contentsOf: allProjects.sorted().map { "+\($0)" })
        bodyTokens.append(contentsOf: contexts.map { "@\($0)" })

        var extras = parsedExtras
        extras.removeValue(forKey: "due")
        extras.removeValue(forKey: "t")

        let due = dueDateText.trimmingCharacters(in: .whitespacesAndNewlines)
        let threshold = thresholdDateText.trimmingCharacters(in: .whitespacesAndNewlines)

        if !due.isEmpty {
            extras["due"] = due
        }
        if !threshold.isEmpty {
            extras["t"] = threshold
        }

        bodyTokens.append(contentsOf: extras.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" })
        parts.append(bodyTokens.joined(separator: " "))

        return parts.joined(separator: " ")
    }
}

struct EditTaskSheet: View {
    private enum DateField: Identifiable {
        case due
        case threshold

        var id: String {
            switch self {
            case .due: return "due"
            case .threshold: return "threshold"
            }
        }
    }

    let task: TodoTask
    let projects: [String]
    let contexts: [String]
    let onSave: (String) -> String?
    let onDismiss: () -> Void

    @State private var priorityRaw = ""
    @State private var taskText = ""
    @State private var selectedProjects: Set<String> = []
    @State private var newProjectName = ""
    @State private var dueDateText = ""
    @State private var thresholdDateText = ""
    @State private var activeDateField: DateField?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    SuggestionBarView(text: $taskText, projects: projects, contexts: contexts)
                    TextField("Task", text: $taskText, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                }

                Section("Priority") {
                    Picker("Priority", selection: $priorityRaw) {
                        Text("None").tag("")
                        Text("A – Highest").tag("A")
                        Text("B – High").tag("B")
                        Text("C – Normal").tag("C")
                        Text("D – Low").tag("D")
                        Text("E – Lowest").tag("E")
                    }
                }

                Section("Projects") {
                    let allProjects = allAvailableProjects
                    if !allProjects.isEmpty {
                        FlowLayout(spacing: 8) {
                            ForEach(allProjects, id: \.self) { project in
                                Button {
                                    if selectedProjects.contains(project) {
                                        selectedProjects.remove(project)
                                    } else {
                                        selectedProjects.insert(project)
                                    }
                                } label: {
                                    Text("+\(project)")
                                        .font(.subheadline.monospaced())
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(selectedProjects.contains(project) ? Color.blue : Color(.systemGray5))
                                        .foregroundStyle(selectedProjects.contains(project) ? .white : .primary)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    HStack {
                        TextField("New project name", text: $newProjectName)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                        Button {
                            addNewProject()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                        .disabled(newProjectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                Section("Dates") {
                    Button {
                        activeDateField = .due
                    } label: {
                        LabeledContent("Due", value: dueDateText.isEmpty ? "Not set" : dueDateText)
                    }
                    .foregroundStyle(.primary)

                    Button {
                        activeDateField = .threshold
                    } label: {
                        LabeledContent("Threshold", value: thresholdDateText.isEmpty ? "Not set" : thresholdDateText)
                    }
                    .foregroundStyle(.primary)
                }

                if let error {
                    Section {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Edit Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onDismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let message = validateDates() {
                            error = message
                            return
                        }

                        let rawLine = composedRawLine()
                        if let message = onSave(rawLine) {
                            error = message
                        } else {
                            onDismiss()
                        }
                    }
                }
            }
            .onAppear {
                guard taskText.isEmpty else { return }
                taskText = TaskEditFormatter.editableTaskText(for: task)
                priorityRaw = task.priority.map(String.init) ?? ""
                selectedProjects = Set(task.projects)
                dueDateText = task.extras["due"] ?? ""
                thresholdDateText = task.extras["t"] ?? ""
            }
            .sheet(item: $activeDateField) { field in
                switch field {
                case .due:
                    DateSelectionSheet(
                        title: "Due Date",
                        initialDateText: dueDateText,
                        onSave: { selectedDate in
                            dueDateText = selectedDate
                        },
                        onClear: {
                            dueDateText = ""
                        }
                    )
                case .threshold:
                    DateSelectionSheet(
                        title: "Threshold Date",
                        initialDateText: thresholdDateText,
                        onSave: { selectedDate in
                            thresholdDateText = selectedDate
                        },
                        onClear: {
                            thresholdDateText = ""
                        }
                    )
                }
            }
        }
    }

    private func validateDates() -> String? {
        let due = dueDateText.trimmingCharacters(in: .whitespacesAndNewlines)
        let threshold = thresholdDateText.trimmingCharacters(in: .whitespacesAndNewlines)

        if !due.isEmpty, TodoParser.dateFormatter.date(from: due) == nil {
            return "Due date must use YYYY-MM-DD."
        }
        if !threshold.isEmpty, TodoParser.dateFormatter.date(from: threshold) == nil {
            return "Threshold date must use YYYY-MM-DD."
        }

        return nil
    }

    /// All known projects plus any the user has selected (in case they were removed from other tasks).
    private var allAvailableProjects: [String] {
        let combined = Set(projects).union(selectedProjects)
        return combined.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func addNewProject() {
        let name = newProjectName.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
        guard !name.isEmpty else { return }
        // Strip leading + if the user typed it
        let clean = name.hasPrefix("+") ? String(name.dropFirst()) : name
        guard !clean.isEmpty else { return }
        selectedProjects.insert(clean)
        newProjectName = ""
    }

    private func composedRawLine() -> String {
        TaskEditFormatter.composedRawLine(
            task: task,
            taskText: taskText,
            priorityRaw: priorityRaw,
            selectedProjects: Array(selectedProjects),
            dueDateText: dueDateText,
            thresholdDateText: thresholdDateText
        )
    }
}

// MARK: - Flow Layout for wrapping chips

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

struct DateSelectionSheet: View {
    let title: String
    let initialDateText: String
    let onSave: (String) -> Void
    let onClear: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedDate = Date()

    var body: some View {
        NavigationStack {
            VStack {
                DatePicker("", selection: $selectedDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .padding(.horizontal)
                Spacer()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear") {
                        onClear()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave(TodoParser.dateFormatter.string(from: selectedDate))
                        dismiss()
                    }
                }
            }
            .onAppear {
                if let parsedDate = TodoParser.dateFormatter.date(from: initialDateText) {
                    selectedDate = parsedDate
                }
            }
        }
    }
}
