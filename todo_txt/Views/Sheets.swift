import SwiftUI
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
    @AppStorage("autoArchiveOnComplete") private var autoArchiveOnComplete = false
    @AppStorage("iCloudSyncEnabled") private var iCloudSyncEnabled = false
    @Environment(\.openURL) private var openURL
    @State private var notificationPermissionState: NotificationPermissionState = .unknown
    @State private var showUserGuide = false

    let currentFileName: String
    let onChooseFile: () -> Void
    let onUseLocalFile: () -> Void
    let onArchiveNow: () -> Void
    let onICloudSyncChanged: (Bool) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("File") {
                    LabeledContent("Current", value: currentFileName)
                    Toggle("Sync with iCloud Drive", isOn: $iCloudSyncEnabled)
                        .onChange(of: iCloudSyncEnabled) { _, enabled in
                            onICloudSyncChanged(enabled)
                        }
                    Button("Create New .txt File", action: onUseLocalFile)
                    Button("Choose .txt File", action: onChooseFile)
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
                    Toggle("Auto Archive Completed", isOn: $autoArchiveOnComplete)
                    Button("Archive Now", action: onArchiveNow)
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

                Section("Help") {
                    Button("User Guide") {
                        showUserGuide = true
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
                    Label("Swipe left on a task to edit. Swipe right to delete.", systemImage: "hand.draw")
                    Label("Use the sort menu to order tasks by priority, date, or text.", systemImage: "arrow.up.arrow.down")
                    Label("Archive moves completed tasks from todo.txt to done.txt.", systemImage: "archivebox")
                    Label("Choose any .txt file from Files, or sync with iCloud Drive.", systemImage: "folder")
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
    static func editableTaskText(for task: TodoTask) -> String {
        var bodyTokens: [String] = []

        if !task.baseDescription.isEmpty {
            bodyTokens.append(task.baseDescription)
        }
        bodyTokens.append(contentsOf: task.projects.map { "+\($0)" })
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
        dueDateText: String,
        thresholdDateText: String
    ) -> String {
        let editableBody = taskText.trimmingCharacters(in: .whitespacesAndNewlines)
        let (description, projects, contexts, parsedExtras) = TodoParser.parseRest(editableBody)
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

        var bodyTokens: [String] = []
        if !description.isEmpty {
            bodyTokens.append(description)
        }
        bodyTokens.append(contentsOf: projects.map { "+\($0)" })
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
    let onSave: (String) -> String?
    let onDismiss: () -> Void

    @State private var priorityRaw = ""
    @State private var taskText = ""
    @State private var dueDateText = ""
    @State private var thresholdDateText = ""
    @State private var activeDateField: DateField?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
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

    private func composedRawLine() -> String {
        TaskEditFormatter.composedRawLine(
            task: task,
            taskText: taskText,
            priorityRaw: priorityRaw,
            dueDateText: dueDateText,
            thresholdDateText: thresholdDateText
        )
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
