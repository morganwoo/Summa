import SwiftUI
import SummaCore

/// Single- or multi-select options with room for a custom answer.
struct ChoiceInput: View {
    @Environment(\.theme) private var theme
    let options: [String]
    let isMultiple: Bool
    let allowsCustom: Bool
    @Binding var selection: [String]
    var onSinglePick: (() -> Void)?

    @State private var custom = ""
    @FocusState private var customFocused: Bool

    private var customValues: [String] { selection.filter { !options.contains($0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FlowLayout(spacing: 10) {
                ForEach(options, id: \.self) { option in
                    Chip(title: option, isSelected: selection.contains(option)) { toggle(option) }
                        .accessibilityIdentifier("option.\(option)")
                }
                ForEach(customValues, id: \.self) { value in
                    Chip(title: value, isSelected: true) { selection.removeAll { $0 == value } }
                }
            }
            if allowsCustom {
                HStack(spacing: 10) {
                    TextField("Something else", text: $custom)
                        .focused($customFocused)
                        .submitLabel(.done)
                        .onSubmit(addCustom)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 48)
                        .background(theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(theme.divider))
                    if !custom.trimmed.isEmpty {
                        Button("Add", action: addCustom)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(theme.gold)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                }
            }
        }
    }

    private func toggle(_ option: String) {
        Haptics.select()
        if isMultiple {
            if selection.contains(option) { selection.removeAll { $0 == option } } else { selection.append(option) }
        } else {
            selection = [option]
            onSinglePick?()
        }
    }

    private func addCustom() {
        let value = custom.trimmed
        guard !value.isEmpty else { return }
        if isMultiple {
            if !selection.contains(value) { selection.append(value) }
        } else {
            selection = [value]
        }
        custom = ""
    }
}

/// Optional body details. Every field can be left empty.
struct BodyDetailsInput: View {
    @Environment(\.theme) private var theme
    @Binding var values: [String]

    private struct Field {
        let label: String
        let placeholder: String
        let numeric: Bool
    }

    private let fields = [
        Field(label: "Age", placeholder: "e.g. 34", numeric: true),
        Field(label: "Height", placeholder: "e.g. 178 cm or 5 ft 10", numeric: false),
        Field(label: "Weight", placeholder: "e.g. 80 kg or 176 lb", numeric: false),
    ]
    private let genders = ["Woman", "Man", "Non-binary"]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(fields, id: \.label) { field in
                VStack(alignment: .leading, spacing: 6) {
                    Text(field.label).font(.subheadline.weight(.medium))
                    TextField(field.placeholder, text: binding(field.label))
                        .keyboardType(field.numeric ? .numberPad : .default)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 48)
                        .background(theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(theme.divider))
                        .accessibilityLabel("\(field.label), optional")
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Gender").font(.subheadline.weight(.medium))
                FlowLayout(spacing: 10) {
                    ForEach(genders, id: \.self) { gender in
                        Chip(title: gender, isSelected: value("Gender") == gender) {
                            set("Gender", value("Gender") == gender ? "" : gender)
                        }
                    }
                }
            }
        }
    }

    private func value(_ label: String) -> String {
        let prefix = "\(label): "
        return values.first(where: { $0.hasPrefix(prefix) }).map { String($0.dropFirst(prefix.count)) } ?? ""
    }

    private func set(_ label: String, _ newValue: String) {
        var next = values.filter { !$0.hasPrefix("\(label): ") }
        if !newValue.isEmpty { next.append("\(label): \(newValue)") }
        values = next
    }

    private func binding(_ label: String) -> Binding<String> {
        Binding(get: { value(label) }, set: { set(label, $0) })
    }
}

/// The illustrative 90-day arc with markers at days 7, 14, 21, 66, and 90.
struct ArcChart: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn: CGFloat = 0

    private struct Marker {
        let day: Int
        let label: String
    }

    private let markers = [
        Marker(day: 7, label: "Getting started"), Marker(day: 14, label: "Still choosing it"),
        Marker(day: 21, label: "Finding footing"), Marker(day: 66, label: "Rhythm"), Marker(day: 90, label: "Yours"),
    ]

    /// A gentle S-curve. Purely illustrative; it is not fitted to any data.
    private func height(_ day: Double) -> Double {
        let t = day / 90
        let smooth = t * t * (3 - 2 * t)
        return 0.06 + 0.9 * smooth * (0.55 + 0.45 * t)
    }

    private func point(_ day: Double, in size: CGSize) -> CGPoint {
        let x = 8 + (Double(size.width) - 16) * day / 90
        let y = Double(size.height) - 26 - (Double(size.height) - 52) * height(day)
        return CGPoint(x: x, y: y)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { proxy in
                let size = proxy.size
                ZStack(alignment: .topLeading) {
                    Path { path in
                        path.move(to: CGPoint(x: 8, y: size.height - 26))
                        path.addLine(to: CGPoint(x: size.width - 8, y: size.height - 26))
                    }
                    .stroke(theme.divider, lineWidth: 1)

                    Path { path in
                        path.move(to: point(0, in: size))
                        for day in stride(from: 1.0, through: 90.0, by: 1.0) { path.addLine(to: point(day, in: size)) }
                    }
                    .trim(from: 0, to: drawn)
                    .stroke(theme.gold, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                    ForEach(markers, id: \.day) { marker in
                        let p = point(Double(marker.day), in: size)
                        let visible = drawn >= CGFloat(marker.day) / 90 - 0.02
                        Circle()
                            .fill(theme.background)
                            .overlay(Circle().strokeBorder(theme.gold, lineWidth: 2))
                            .frame(width: 12, height: 12)
                            .position(p)
                            .opacity(visible ? 1 : 0)
                        Text("\(marker.day)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(theme.muted)
                            .position(x: p.x, y: size.height - 10)
                    }
                }
            }
            .frame(height: 210)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(markers, id: \.day) { marker in
                    HStack(spacing: 10) {
                        Text("Day \(marker.day)").font(.footnote.weight(.semibold)).foregroundStyle(theme.gold).frame(width: 58, alignment: .leading)
                        Text(marker.label).font(.footnote).foregroundStyle(theme.muted)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Illustrative arc with reflection points at day 7, getting started; day 14, still choosing it; day 21, finding footing; day 66, rhythm; and day 90, yours.")
        }
        .card()
        .onAppear {
            if reduceMotion { drawn = 1 } else { withAnimation(.easeInOut(duration: 2.2)) { drawn = 1 } }
        }
    }
}

/// Says what to fix in a username, or confirms that it is valid.
struct UsernameStatus: View {
    @Environment(\.theme) private var theme
    let text: String

    var body: some View {
        if !text.trimmed.isEmpty {
            let problem = UsernameRule.problem(with: text)
            Label(problem ?? "@\(UsernameRule.normalized(text)) looks good.", systemImage: problem == nil ? "checkmark.circle" : "exclamationmark.circle")
                .font(.footnote)
                .foregroundStyle(problem == nil ? theme.gold : theme.muted)
                .accessibilityIdentifier("username.status")
        }
    }
}

/// Renders the right control for a question. Shared by the guided path and the talk path's cards.
struct QuestionInput: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var onboarding: OnboardingStore
    let question: Question
    /// The talk path collects custom answers in its own input bar.
    var showsCustomField = true
    var onSinglePick: (() -> Void)?
    @FocusState private var focused: Bool

    var body: some View {
        switch question.kind {
        case .shortText(let placeholder):
            TextField(placeholder, text: onboarding.textBinding(for: question.id))
                .font(.title3)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($focused)
                .padding(.horizontal, 16)
                .frame(minHeight: 56)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(theme.divider))
                .accessibilityIdentifier("onboarding.textField")
        case .username:
            VStack(alignment: .leading, spacing: 8) {
                TextField("username", text: onboarding.textBinding(for: question.id))
                    .font(.title3)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .submitLabel(.done)
                    .focused($focused)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 56)
                    .background(theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(theme.divider))
                    .accessibilityLabel("Username")
                    .accessibilityIdentifier("onboarding.textField")
                UsernameStatus(text: onboarding.answers.text(.username))
            }
        case .longText(let placeholder):
            TextField(placeholder, text: onboarding.textBinding(for: question.id), axis: .vertical)
                .lineLimit(4...10)
                .focused($focused)
                .padding(16)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(theme.divider))
                .accessibilityIdentifier("onboarding.textField")
        case .single(let options):
            ChoiceInput(options: options, isMultiple: false, allowsCustom: false,
                        selection: onboarding.binding(for: question.id), onSinglePick: onSinglePick)
        case .multi(let options, let allowsCustom):
            ChoiceInput(options: options, isMultiple: true, allowsCustom: allowsCustom && showsCustomField,
                        selection: onboarding.binding(for: question.id))
        case .weekdays:
            WeekdayPicker(weekdays: Binding(
                get: { onboarding.answers.weekdays },
                set: { days in onboarding.answers.set(.days, days.map { String($0) }) }))
        case .arc:
            ArcChart()
        case .body:
            BodyDetailsInput(values: onboarding.binding(for: .body))
        }
    }
}
