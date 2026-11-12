import SwiftUI
import SummaCore

/// Edits one habit: action, minimum version, schedule, color, and reminder.
/// Used for drafts before the plan starts and for saved habits afterwards.
struct HabitEditorView: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    let heading: String
    @State var draft: HabitDraft
    @State var reminderOn: Bool
    var scheduleNote: String?
    let onSave: (HabitDraft, Bool) -> Void

    @State private var reminderDenied = false

    private let symbols = ["sun.max", "figure.walk", "book", "pencil.line", "moon", "scope", "drop", "leaf", "dumbbell", "laurel.leading", "music.note", "fork.knife"]

    private var isValid: Bool {
        !draft.title.trimmed.isEmpty && !draft.action.trimmed.isEmpty && !draft.minimumVersion.trimmed.isEmpty && !draft.weekdays.isEmpty
    }

    private var reminderDate: Binding<Date> {
        Binding(
            get: {
                let reminder = draft.reminder ?? ReminderDraft(hour: 8, minute: 0)
                return Calendar.current.date(from: DateComponents(hour: reminder.hour, minute: reminder.minute)) ?? Date()
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                draft.reminder = ReminderDraft(hour: parts.hour ?? 8, minute: parts.minute ?? 0)
            })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    field("Name", text: $draft.title, placeholder: "Read daily", id: "editor.title")
                    field("The action", text: $draft.action, placeholder: "Read two pages after breakfast", id: "editor.action",
                          note: "Concrete enough to put on a calendar.")
                    field("Target", text: $draft.target, placeholder: "2 pages", id: "editor.target",
                          note: "The measurable amount for one day.")
                    field("Minimum version", text: $draft.minimumVersion, placeholder: "Read one page", id: "editor.minimum",
                          note: "What still counts on a difficult day.")

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Schedule").font(.subheadline.weight(.semibold))
                        WeekdayPicker(weekdays: $draft.weekdays, accent: Color.accent(draft.colorHex))
                        Text(scheduleNote ?? "Days you leave off are rest days. They never break a streak.")
                            .font(.footnote).foregroundStyle(theme.muted)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Color").font(.subheadline.weight(.semibold))
                        FlowLayout(spacing: 12) {
                            ForEach(HabitPalette.all) { entry in
                                Button {
                                    Haptics.select()
                                    draft.colorHex = entry.hex
                                } label: {
                                    Circle()
                                        .fill(Color(hex: entry.hex))
                                        .frame(width: 44, height: 44)
                                        .overlay(Circle().strokeBorder(theme.text, lineWidth: draft.colorHex == entry.hex ? 2.5 : 0).padding(-4))
                                        .overlay {
                                            if draft.colorHex == entry.hex {
                                                Image(systemName: "checkmark").font(.footnote.weight(.bold)).foregroundStyle(.black)
                                            }
                                        }
                                        .padding(4)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(entry.name)
                                .accessibilityAddTraits(draft.colorHex == entry.hex ? .isSelected : [])
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Symbol").font(.subheadline.weight(.semibold))
                        FlowLayout(spacing: 10) {
                            ForEach(symbols, id: \.self) { symbol in
                                Button {
                                    draft.symbol = symbol
                                } label: {
                                    Image(systemName: symbol)
                                        .font(.body)
                                        .foregroundStyle(draft.symbol == symbol ? theme.onGold : theme.text)
                                        .frame(width: 44, height: 44)
                                        .background(draft.symbol == symbol ? Color.accent(draft.colorHex) : theme.surface,
                                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(theme.divider))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(symbol.replacingOccurrences(of: ".", with: " "))
                                .accessibilityAddTraits(draft.symbol == symbol ? .isSelected : [])
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(isOn: Binding(get: { reminderOn }, set: { setReminder($0) })) {
                            Text("Reminder").font(.subheadline.weight(.semibold))
                        }
                        .tint(theme.gold)
                        .accessibilityIdentifier("editor.reminder")
                        if reminderOn {
                            DatePicker("Time", selection: reminderDate, displayedComponents: .hourAndMinute)
                        } else if let reminder = draft.reminder {
                            Text("Suggested: \(Reminders.timeString(hour: reminder.hour, minute: reminder.minute)) on scheduled days.")
                                .font(.footnote).foregroundStyle(theme.muted)
                        }
                        if reminderDenied {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Notifications are off for Summa, so this reminder cannot be delivered. Everything else works without them.")
                                    .font(.footnote).foregroundStyle(theme.muted)
                                Button("Open Settings") { Reminders.openSystemSettings() }
                                    .font(.footnote.weight(.semibold)).foregroundStyle(theme.gold).frame(minHeight: 44)
                            }
                        }
                    }
                    .card()
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .marbleBackground()
            .navigationTitle(heading)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(draft, reminderOn)
                        dismiss()
                    }
                    .disabled(!isValid)
                    .accessibilityIdentifier("editor.save")
                }
            }
        }
        .foregroundStyle(theme.text)
    }

    private func setReminder(_ on: Bool) {
        guard on else {
            reminderOn = false
            return
        }
        if draft.reminder == nil { draft.reminder = ReminderDraft(hour: 8, minute: 0) }
        // Notification permission is requested here, at the moment a reminder is turned on.
        Task { @MainActor in
            let allowed = await Reminders.requestIfNeeded()
            reminderOn = allowed
            reminderDenied = !allowed
        }
    }

    private func field(_ label: String, text: Binding<String>, placeholder: String, id: String, note: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.subheadline.weight(.semibold))
            TextField(placeholder, text: text, axis: .vertical)
                .lineLimit(1...3)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(minHeight: 48)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(theme.divider))
                .accessibilityLabel(label)
                .accessibilityIdentifier(id)
            if let note { Text(note).font(.footnote).foregroundStyle(theme.muted) }
        }
    }
}
