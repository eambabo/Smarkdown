import SwiftUI

// MARK: - Time estimate unit

enum TimeEstimateUnit: String, CaseIterable {
    case minutes, hours, days

    var label: String {
        switch self {
        case .minutes: return "min"
        case .hours:   return "hr"
        case .days:    return "day"
        }
    }

    func toMinutes(_ value: Int) -> Int {
        switch self {
        case .minutes: return value
        case .hours:   return value * 60
        case .days:    return value * 1440
        }
    }

    /// Chooses the largest unit that divides evenly, so 120 min → 2 hr.
    static func fromMinutes(_ minutes: Int) -> (value: Int, unit: TimeEstimateUnit) {
        if minutes >= 1440, minutes % 1440 == 0 { return (minutes / 1440, .days) }
        if minutes >= 60,   minutes % 60   == 0 { return (minutes / 60,   .hours) }
        return (minutes, .minutes)
    }
}

// MARK: - Tasks list

struct TasksView: View {
    let editorViewModel: EditorViewModel

    @State private var showCompleted = false
    @State private var expandedTaskID: UUID? = nil

    private var displayedTasks: [Classification] {
        editorViewModel.allTasks.filter {
            showCompleted || $0.status == .active
        }
    }

    var body: some View {
        Group {
            if displayedTasks.isEmpty {
                if showCompleted {
                    ContentUnavailableView(
                        "No Tasks",
                        systemImage: "checklist",
                        description: Text("Start a line with **/t** followed by your task and press Return.")
                    )
                } else {
                    ContentUnavailableView(
                        "No Active Tasks",
                        systemImage: "checklist",
                        description: Text("All tasks are done, or start one with **/t** on a new line.")
                    )
                }
            } else {
                List {
                    ForEach(displayedTasks) { task in
                        TaskRowView(
                            task: task,
                            isExpanded: expandedTaskID == task.id,
                            editorViewModel: editorViewModel,
                            onToggleExpand: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    expandedTaskID = expandedTaskID == task.id ? nil : task.id
                                }
                            },
                            onNavigate: {
                                editorViewModel.openDocumentFromTask(task)
                            }
                        )
                        .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
                    }
                }
                .listStyle(.plain)
            }
        }
        .safeAreaInset(edge: .bottom) {
            Toggle("Show completed & archived", isOn: $showCompleted)
                .toggleStyle(.switch)
                .controlSize(.small)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial)
        }
    }
}

// MARK: - Task row

private struct TaskRowView: View {
    let task: Classification
    let isExpanded: Bool
    let editorViewModel: EditorViewModel
    let onToggleExpand: () -> Void
    let onNavigate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Main row ──────────────────────────────────────────
            HStack(alignment: .top, spacing: 6) {

                // Expand chevron
                Button(action: onToggleExpand) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 14, height: 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 3)

                // Task text + metadata — tappable to navigate
                VStack(alignment: .leading, spacing: 3) {
                    Text(task.contentText)
                        .font(.body)
                        .lineLimit(isExpanded ? nil : 2)
                        .strikethrough(task.status != .active, color: .secondary)
                        .foregroundStyle(task.status == .active ? Color.primary : Color.secondary)

                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 6, height: 6)
                        Text(task.documentName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(task.createdAt, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture(perform: onNavigate)

                // Action buttons (active tasks only)
                if task.status == .active {
                    Button {
                        editorViewModel.updateTaskStatus(task.id, status: .completed)
                    } label: {
                        Image(systemName: "checkmark.circle")
                            .foregroundStyle(.green)
                    }
                    .buttonStyle(.plain)
                    .help("Mark complete")

                    Button {
                        editorViewModel.updateTaskStatus(task.id, status: .archived)
                    } label: {
                        Image(systemName: "xmark.circle")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Archive")
                }
            }
            .padding(.vertical, 8)

            // ── Detail panel (slide-in) ───────────────────────────
            if isExpanded {
                Divider()
                    .padding(.leading, 20)
                TaskDetailPanel(task: task, editorViewModel: editorViewModel)
                    .padding(.leading, 20)
                    .padding(.bottom, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - Task detail panel

private struct TaskDetailPanel: View {
    let task: Classification
    let editorViewModel: EditorViewModel

    @State private var hasDueDate   = false
    @State private var dueDate      = Date()
    @State private var estText      = ""
    @State private var estUnit      = TimeEstimateUnit.minutes
    @State private var detailsText  = ""
    @State private var loaded       = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            // Due date
            HStack(spacing: 8) {
                Toggle("Due date", isOn: $hasDueDate)
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                    .labelsHidden()
                Text("Due date")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if hasDueDate {
                    DatePicker(
                        "",
                        selection: $dueDate,
                        displayedComponents: .date
                    )
                    .labelsHidden()
                    .controlSize(.small)
                }
            }

            // Time estimate
            HStack(spacing: 6) {
                Text("Estimate")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .leading)
                TextField("—", text: $estText)
                    .frame(width: 44)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                Picker("", selection: $estUnit) {
                    ForEach(TimeEstimateUnit.allCases, id: \.self) { unit in
                        Text(unit.label).tag(unit)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 60)
                .controlSize(.small)
            }

            // Notes
            VStack(alignment: .leading, spacing: 4) {
                Text("Notes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $detailsText)
                    .font(.callout)
                    .frame(minHeight: 56, maxHeight: 120)
                    .scrollContentBackground(.hidden)
                    .padding(4)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    )
            }
        }
        .padding(.top, 8)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let d = editorViewModel.fetchTaskDetail(for: task.id) {
                hasDueDate  = d.dueDate != nil
                dueDate     = d.dueDate ?? Date()
                detailsText = d.details
                if let mins = d.estimatedMinutes {
                    let (val, unit) = TimeEstimateUnit.fromMinutes(mins)
                    estText = "\(val)"
                    estUnit = unit
                }
            }
        }
        .onChange(of: hasDueDate)  { _, _ in save() }
        .onChange(of: dueDate)     { _, _ in save() }
        .onChange(of: estText)     { _, _ in save() }
        .onChange(of: estUnit)     { _, _ in save() }
        .onChange(of: detailsText) { _, _ in save() }
    }

    private func save() {
        guard loaded else { return }
        let minutes: Int? = {
            guard let v = Int(estText), v > 0 else { return nil }
            return estUnit.toMinutes(v)
        }()
        let detail = TaskDetail(
            taskID: task.id,
            dueDate: hasDueDate ? dueDate : nil,
            estimatedMinutes: minutes,
            details: detailsText
        )
        editorViewModel.upsertTaskDetail(detail)
    }
}
