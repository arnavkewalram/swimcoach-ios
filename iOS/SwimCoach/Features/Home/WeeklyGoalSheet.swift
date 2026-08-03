import SwiftUI

/// Editorial stepper sheet for the weekly session goal. Zero means off.
/// Edits the goal for the active swimmer scope — "" is Everyone.
struct WeeklyGoalSheet: View {
    @AppStorage("activeSwimmer") private var activeSwimmer: String = ""
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Int = 0

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
                        WeeklyGoalStore().setGoal(draft, for: activeSwimmer)
                        dismiss()
                    }
                    .foregroundStyle(DS.accent)
                    .font(.callout.weight(.semibold))
                }
            }
        }
        .presentationDetents([.height(280)])
        .presentationBackground(DS.background)
        .onAppear { draft = WeeklyGoalStore().goal(for: activeSwimmer) }
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
