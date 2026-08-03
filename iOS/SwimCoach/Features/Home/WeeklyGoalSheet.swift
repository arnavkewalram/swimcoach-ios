import SwiftUI
import SwiftData

/// Editorial stepper sheet for the weekly session goal. Zero means off.
/// Edits the goal for the active swimmer scope — "" is Everyone. Below the
/// stepper, an opt-in reminder row arms a weekly nudge notification for
/// the same scope (GoalReminderPlanner decides fire date and copy).
struct WeeklyGoalSheet: View {
    @AppStorage("activeSwimmer") private var activeSwimmer: String = ""
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var draft: Int = 0
    @State private var reminderEnabled = false
    @State private var reminderWeekday = GoalReminderStore.Settings.initial.weekday
    @State private var reminderTime = Date()
    @State private var showDeniedHint = false

    private static let maxGoal = 14

    private var scopeName: String {
        activeSwimmer.isEmpty ? "Everyone" : activeSwimmer
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DS.background.ignoresSafeArea()

                VStack(spacing: 24) {
                    Text("Sessions per week to aim for. Two or three is plenty for steady technique work.")
                        .font(.footnote)
                        .lineSpacing(3)
                        .foregroundStyle(DS.inkSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.top, 24)

                    HStack(spacing: 28) {
                        stepButton("minus", enabled: draft > 0) { draft -= 1 }
                        Text(draft == 0 ? "OFF" : "\(draft)")
                            .font(.grotesk(44, .bold))
                            .foregroundStyle(draft == 0 ? DS.inkTertiary : DS.ink)
                            .frame(minWidth: 96)
                            .contentTransition(.numericText())
                            .animation(.snappy(duration: 0.18), value: draft)
                        stepButton("plus", enabled: draft < Self.maxGoal) { draft += 1 }
                    }
                    .accessibilityElement(children: .contain)

                    reminderSection
                        .padding(.horizontal, 28)

                    Spacer()
                }
            }
            .navigationTitle("Weekly Goal — \(scopeName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        Text("Weekly Goal")
                            .font(.grotesk(17, .medium))
                            .foregroundStyle(DS.ink)
                        Text("— \(scopeName)")
                            .font(.grotesk(17, .medium))
                            .foregroundStyle(DS.accent)
                            .lineLimit(1)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Weekly goal for \(scopeName)")
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(DS.inkSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                        dismiss()
                    }
                    .foregroundStyle(DS.accent)
                    .font(.callout.weight(.semibold))
                }
            }
        }
        .presentationDetents([.height(reminderEnabled ? 452 : 372)])
        .presentationBackground(DS.background)
        .onAppear { load() }
    }

    // MARK: - Reminder row

    @ViewBuilder
    private var reminderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Reminder")

            Toggle(isOn: reminderToggleBinding) {
                Text("Remind me")
                    .font(.grotesk(15, .medium))
                    .foregroundStyle(DS.ink)
            }
            .tint(DS.accent)
            .accessibilityHint("Sends a weekly notification if the goal isn't met")

            if reminderEnabled {
                HStack(spacing: 12) {
                    Picker("Reminder day", selection: $reminderWeekday) {
                        ForEach(1...7, id: \.self) { day in
                            Text(Calendar.current.weekdaySymbols[day - 1]).tag(day)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(DS.accent)
                    .labelsHidden()

                    DatePicker("Reminder time", selection: $reminderTime,
                               displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .tint(DS.accent)

                    Spacer()
                }
                .transition(.opacity)
            }

            if showDeniedHint {
                Text("ENABLE NOTIFICATIONS IN SETTINGS")
                    .font(.custom(GroteskWeight.medium.postScriptName, size: 10))
                    .tracking(1.2)
                    .foregroundStyle(DS.severityModerate)
            }
        }
        // No goal means nothing to remind about — the block stays visible
        // but inert until the stepper leaves OFF.
        .opacity(draft == 0 ? 0.4 : 1)
        .disabled(draft == 0)
        .animation(.snappy(duration: 0.18), value: reminderEnabled)
        .animation(.snappy(duration: 0.18), value: showDeniedHint)
    }

    /// Turning the toggle on requests full notification authorization the
    /// first time; on denial the toggle stays off and the Settings hint
    /// appears instead of failing silently.
    private var reminderToggleBinding: Binding<Bool> {
        Binding(
            get: { reminderEnabled },
            set: { isOn in
                guard isOn else {
                    reminderEnabled = false
                    return
                }
                Task { @MainActor in
                    if await GoalReminderScheduler().requestAuthorization() {
                        reminderEnabled = true
                        showDeniedHint = false
                    } else {
                        reminderEnabled = false
                        showDeniedHint = true
                    }
                }
            })
    }

    // MARK: - Load / save

    private func load() {
        draft = WeeklyGoalStore().goal(for: activeSwimmer)
        let settings = GoalReminderStore().settings(for: activeSwimmer)
        reminderEnabled = settings.isEnabled
        reminderWeekday = settings.weekday
        reminderTime = Calendar.current.date(
            bySettingHour: settings.hour, minute: settings.minute, second: 0,
            of: Date()) ?? Date()
        // Permission revoked in Settings since enabling? Reflect reality.
        if settings.isEnabled {
            Task { @MainActor in
                if await GoalReminderScheduler().isDenied() {
                    reminderEnabled = false
                    showDeniedHint = true
                }
            }
        }
    }

    private func save() {
        WeeklyGoalStore().setGoal(draft, for: activeSwimmer)
        let time = Calendar.current.dateComponents([.hour, .minute],
                                                   from: reminderTime)
        GoalReminderStore().setSettings(
            GoalReminderStore.Settings(isEnabled: reminderEnabled,
                                       weekday: reminderWeekday,
                                       hour: time.hour ?? 17,
                                       minute: time.minute ?? 0),
            for: activeSwimmer)
        GoalReminder.reschedule(context: modelContext)
    }

    private func stepButton(_ icon: String, enabled: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title3.weight(.medium))
                .foregroundStyle(enabled ? DS.ink : DS.inkTertiary)
                .frame(width: 52, height: 52)
                .overlay(Circle().stroke(enabled ? DS.borderBold : DS.border, lineWidth: 1))
                .contentShape(Circle())
        }
        .disabled(!enabled)
        .accessibilityLabel(icon == "plus" ? "Increase goal" : "Decrease goal")
    }
}
