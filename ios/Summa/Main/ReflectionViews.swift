import SwiftUI
import SwiftData
import SummaCore

/// The name of the victories collection, in one place.
enum Colosseum {
    static let title = "Your Colosseum"
}

// MARK: - Entry point

/// The journal button in the lower-left corner of the daily screen: a dark seal with a gold rim
/// and a pale flame rising behind it. With Reduce Motion the flame is a still glow.
struct JournalButton: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let action: () -> Void

    @State private var slow = false
    @State private var quick = false

    private var flameCore: Color { theme.isDark ? .white : Color(hex: "#FFF6DC") }

    var body: some View {
        Button {
            Haptics.select()
            action()
        } label: {
            ZStack {
                flame(width: 58, height: 82, lift: -12, blur: 9, low: 0.45, high: 0.85, on: slow)
                flame(width: 36, height: 60, lift: -14, blur: 5, low: 0.35, high: 0.95, on: quick)
                Circle()
                    .fill(LinearGradient(colors: [theme.surfaceRaised, theme.surface], startPoint: .top, endPoint: .bottom))
                    .overlay(Circle().strokeBorder(
                        AngularGradient(colors: [theme.gold, flameCore, theme.gold, theme.gold.opacity(0.5), theme.gold], center: .center),
                        lineWidth: 1.6))
                    .shadow(color: .black.opacity(theme.isDark ? 0.5 : 0.18), radius: 6, y: 3)
                    .frame(width: 60, height: 60)
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(theme.gold)
            }
            .frame(width: 72, height: 84, alignment: .bottom)
            .contentShape(Rectangle())
        }
        .buttonStyle(JournalPressStyle())
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.9).repeatForever(autoreverses: true)) { slow = true }
            withAnimation(.easeInOut(duration: 1.15).repeatForever(autoreverses: true)) { quick = true }
        }
        .accessibilityLabel("Daily reflection")
        .accessibilityHint("Write a reflection or talk with Summa about today")
        .accessibilityIdentifier("journal.open")
    }

    private func flame(width: CGFloat, height: CGFloat, lift: CGFloat, blur: CGFloat, low: Double, high: Double, on: Bool) -> some View {
        Ellipse()
            .fill(RadialGradient(colors: [flameCore, theme.gold.opacity(0.55), .clear], center: UnitPoint(x: 0.5, y: 0.72),
                                 startRadius: 1, endRadius: height * 0.62))
            .frame(width: width, height: height)
            .scaleEffect(x: on ? 0.9 : 1.04, y: on ? 1.1 : 0.93, anchor: .bottom)
            .offset(x: on ? 1.5 : -1.5, y: lift)
            .blur(radius: blur)
            .opacity(reduceMotion ? (low + high) / 2 : (on ? high : low))
            .allowsHitTesting(false)
    }
}

private struct JournalPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// "Capture this moment": write, or talk it through. Free accounts see what Pro adds instead.
struct CaptureSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var clock: TodayClock
    let plan: Plan

    private enum Route: Hashable { case write, talk, colosseum }
    @State private var path: [Route] = []
    @State private var paywall: PaywallContext? = nil

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Eyebrow("Day \(plan.dayNumber(today: clock.today)) · \(clock.today.formatted(.dateTime.month(.wide).day()))")
                        Text("Capture this moment")
                            .font(SummaFont.serif(34, relativeTo: .largeTitle))
                            .accessibilityAddTraits(.isHeader)
                    }
                    if store.isPro { options } else { upgrade }
                }
                .padding(20)
            }
            .marbleBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .write:
                    ReflectionEditor(plan: plan, dayNumber: plan.dayNumber(today: clock.today), onSaved: { dismiss() })
                case .talk:
                    CompanionChatView(plan: plan, onSaved: { dismiss() })
                case .colosseum:
                    ScrollView { ColosseumView(plan: plan).padding(20) }
                        .marbleBackground()
                        .foregroundStyle(theme.text)
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
        }
        .foregroundStyle(theme.text)
        .sheet(item: $paywall) { SummaProView(context: $0).environment(\.theme, theme) }
    }

    private var options: some View {
        VStack(spacing: 12) {
            option("square.and.pencil", "Write a reflection", "A private note for today, in your own words.", id: "capture.write") { path.append(.write) }
            option("bubble.left.and.text.bubble.right", "Talk to Summa", "Speak or type. Think the day through together. Nothing is saved unless you approve it.", id: "capture.talk") { path.append(.talk) }
            option("laurel.leading", Colosseum.title, "See your victories, or add a new one.", id: "capture.colosseum") { path.append(.colosseum) }
        }
    }

    private func option(_ symbol: String, _ title: String, _ detail: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol).font(.title3).foregroundStyle(theme.gold).frame(width: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(SummaFont.serif(22, relativeTo: .title3)).foregroundStyle(theme.text)
                    Text(detail).font(.footnote).foregroundStyle(theme.muted).multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote).foregroundStyle(theme.muted)
            }
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .card()
        .accessibilityIdentifier(id)
    }

    private var upgrade: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Daily reflections are part of Summa Pro.").font(.headline)
            VStack(alignment: .leading, spacing: 12) {
                benefit("square.and.pencil", "A private journal for every day of your 90")
                benefit("bubble.left.and.text.bubble.right", "Talk the day through with Summa")
                benefit("sparkle", "A gold mark on each day you reflected")
                benefit("laurel.leading", "Keep your biggest wins in \(Colosseum.title)")
            }
            Button("Unlock with Summa Pro") { paywall = .reflections }
                .buttonStyle(.summaPrimary)
                .accessibilityIdentifier("capture.unlock")
            Text("Your habits, heatmap, and the full 90-day program stay free.")
                .font(.footnote).foregroundStyle(theme.muted)
        }
        .card()
    }

    private func benefit(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).foregroundStyle(theme.gold).frame(width: 24)
            Text(text).font(.subheadline)
        }
    }
}

// MARK: - Writing

/// A plain page for one reflection. Used for new entries, edits, and reviewing a suggestion from Summa.
struct ReflectionEditor: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var clock: TodayClock
    let plan: Plan
    let dayNumber: Int
    var existing: Reflection? = nil
    var suggested: String? = nil
    var onSaved: () -> Void = {}

    @State private var text = ""
    @State private var message: String? = nil
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(existing == nil ? "Day \(dayNumber) · New reflection" : "Day \(dayNumber) · Edit reflection")
            if suggested != nil, existing == nil {
                Text("Suggested by Summa. Change anything, then save it if it is true to your day.")
                    .font(.footnote).foregroundStyle(theme.muted)
            }
            TextEditor(text: $text)
                .focused($focused)
                .scrollContentBackground(.hidden)
                .font(.body)
                .padding(12)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(theme.divider))
                .accessibilityLabel("Reflection")
                .accessibilityIdentifier("reflection.text")
            HStack {
                if let message { Text(message).font(.footnote).foregroundStyle(theme.muted) }
                Spacer()
                Text("\(text.count) / \(ReflectionRule.maxLength)")
                    .font(.caption).foregroundStyle(text.count > ReflectionRule.maxLength ? Color.red : theme.muted)
            }
        }
        .padding(20)
        .marbleBackground()
        .foregroundStyle(theme.text)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(!ReflectionRule.isSavable(text))
                    .accessibilityIdentifier("reflection.save")
            }
        }
        .onAppear {
            if text.isEmpty { text = existing?.text ?? suggested ?? "" }
            focused = true
        }
    }

    private func save() {
        do {
            if let existing {
                try ReflectionStore.update(existing, text: text, in: context)
            } else {
                try ReflectionStore.add(text, to: plan, dayNumber: dayNumber, today: clock.today, fromCompanion: suggested != nil, in: context)
            }
            Haptics.commit()
            onSaved()
            dismiss()
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? "That could not be saved."
        }
    }
}

// MARK: - Reflections for one day

/// One saved reflection with its actions. Shared by the day sheet and anywhere else entries are listed.
struct ReflectionRow: View {
    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var context
    let plan: Plan
    let entry: Reflection

    @State private var editing = false
    @State private var confirmDelete = false
    @State private var confirmPromote = false
    @State private var note: String? = nil

    var body: some View {
        let promoted = ReflectionStore.isPromoted(entry)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(entry.createdAt.formatted(date: .omitted, time: .shortened))
                if entry.fromCompanion { Text("· with Summa") }
                if promoted { Label("In \(Colosseum.title)", systemImage: "laurel.leading").labelStyle(.titleAndIcon) }
            }
            .font(.caption).foregroundStyle(theme.muted)
            Text(entry.text).font(.body).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            HStack(spacing: 18) {
                Button("Edit") { editing = true }.accessibilityIdentifier("reflection.edit")
                if !promoted {
                    Button("Add to \(Colosseum.title)") { confirmPromote = true }.accessibilityIdentifier("reflection.promote")
                }
                Spacer()
                Button("Delete", role: .destructive) { confirmDelete = true }
                    .foregroundStyle(.red).accessibilityIdentifier("reflection.delete")
            }
            .font(.footnote.weight(.semibold)).tint(theme.gold).frame(minHeight: 36)
            if let note { Text(note).font(.footnote).foregroundStyle(theme.muted) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .sheet(isPresented: $editing) {
            NavigationStack {
                ReflectionEditor(plan: plan, dayNumber: entry.dayNumber, existing: entry)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { editing = false } } }
            }
            .environment(\.theme, theme)
        }
        .confirmationDialog("Delete this reflection?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete reflection", role: .destructive) { run { try ReflectionStore.delete(entry, in: context) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
        .confirmationDialog("Add this to \(Colosseum.title)?", isPresented: $confirmPromote, titleVisibility: .visible) {
            Button("Add as a victory") { run { try ReflectionStore.promote(entry, in: context); Haptics.commit() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The reflection stays where it is. Victories are private and are never shared with friends.")
        }
    }

    private func run(_ work: () throws -> Void) {
        do { try work() } catch { note = (error as? LocalizedError)?.errorDescription ?? "That did not work." }
    }
}

/// What happened on one day: the habit record, and the reflections written that day.
struct DayDetailSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var clock: TodayClock
    let plan: Plan
    let day: DayKey

    @State private var adding = false
    @State private var paywall: PaywallContext? = nil

    var body: some View {
        let dayNumber = plan.start.days(until: day) + 1
        let today = clock.today
        let summary = PlanProgress.day(day, timelines: plan.timelines, today: today)
        let entries = ReflectionStore.entries(for: plan, dayNumber: dayNumber)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Eyebrow("\(Stage.forDay(dayNumber).name) · \(summary.status.label)")
                        Text("Day \(dayNumber)").font(SummaFont.serif(34, relativeTo: .largeTitle)).accessibilityAddTraits(.isHeader)
                        Text(day.formatted(.dateTime.weekday(.wide).month(.wide).day().year()))
                            .font(.subheadline).foregroundStyle(theme.muted)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Eyebrow(summary.scheduled == 0 ? "Rest day" : "\(summary.completed) of \(summary.scheduled) done")
                        ForEach(plan.habits.sorted { $0.sortOrder < $1.sortOrder }) { habit in
                            let status = habit.timeline(planStart: plan.start).status(on: day, today: today)
                            HStack(spacing: 10) {
                                DayCell(status: status, accent: Color.accent(habit.colorHex), isToday: day == today).frame(width: 22, height: 22)
                                Text(habit.title).font(.subheadline)
                                Spacer()
                                Text(status.label).font(.footnote).foregroundStyle(theme.muted)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .card()

                    if store.isPro {
                        if !entries.isEmpty { Eyebrow(entries.count == 1 ? "Reflection" : "\(entries.count) reflections") }
                        ForEach(entries) { entry in ReflectionRow(plan: plan, entry: entry) }
                        if day <= today {
                            Button { adding = true } label: { Label("Add reflection", systemImage: "plus") }
                                .buttonStyle(.summaSecondary)
                                .accessibilityIdentifier("day.addReflection")
                        }
                    } else {
                        Button { paywall = .reflections } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "book.closed").foregroundStyle(theme.gold)
                                Text("Reflections are part of Summa Pro").font(.footnote).foregroundStyle(theme.muted)
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(theme.muted)
                            }
                            .frame(minHeight: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("day.reflectionsLocked")
                    }
                }
                .padding(20)
            }
            .marbleBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("day.done") } }
        }
        .foregroundStyle(theme.text)
        .sheet(isPresented: $adding) {
            NavigationStack {
                ReflectionEditor(plan: plan, dayNumber: dayNumber)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { adding = false } } }
            }
            .environment(\.theme, theme)
        }
        .sheet(item: $paywall) { SummaProView(context: $0).environment(\.theme, theme) }
    }
}

// MARK: - Talk to Summa

/// A conversation about the day. It is held in memory and gone when this screen closes.
struct CompanionChatView: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var clock: TodayClock
    let plan: Plan
    var purpose: Companion.Purpose = .reflection
    var onSaved: () -> Void = {}

    @StateObject private var dictation = SpeechDictation()
    @State private var proposedCategory: VictoryCategory? = nil
    @State private var turns: [Companion.Turn] = []
    @State private var draft = ""
    @State private var textBeforeDictation = ""
    @State private var waiting = false
    @State private var notice: String? = nil
    @State private var proposal: String? = nil
    @State private var reviewing: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        bubble(.assistant, opening)
                        ForEach(turns) { turn in bubble(turn.role, turn.text).id(turn.id) }
                        if waiting { Text("Summa is thinking…").font(.footnote).foregroundStyle(theme.muted).id("waiting") }
                        if let proposal { proposalCard(proposal).id("proposal") }
                        if let notice { Text(notice).font(.footnote).foregroundStyle(theme.muted).id("notice") }
                    }
                    .padding(20)
                }
                .onChange(of: turns.count) { _, _ in withAnimation { proxy.scrollTo(turns.last?.id, anchor: .bottom) } }
                .onChange(of: proposal) { _, value in if value != nil { withAnimation { proxy.scrollTo("proposal", anchor: .bottom) } } }
            }
            composer
        }
        .marbleBackground()
        .foregroundStyle(theme.text)
        .navigationTitle("Talk to Summa")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if !Companion.isConnected { notice = Companion.Failure.notConnected.errorDescription } }
        .onDisappear { dictation.stop() }
        .onChange(of: dictation.transcript) { _, transcript in
            guard dictation.isRecording || !transcript.isEmpty else { return }
            draft = [textBeforeDictation, transcript].filter { !$0.isEmpty }.joined(separator: " ")
        }
        .onChange(of: dictation.isRecording) { _, recording in
            // Recording ended on its own and nothing was heard: say so, rather than leaving silence unexplained.
            if !recording, dictation.transcript.isEmpty, dictation.access == .granted, draft.trimmed == textBeforeDictation {
                notice = "Nothing was heard. Check the microphone and try again, or type instead."
            } else if !recording, dictation.access == .unavailable {
                notice = "Dictation is not available on this device right now. You can type instead."
            }
        }
        .sheet(item: Binding(get: { reviewing.map(ReviewText.init) }, set: { reviewing = $0?.text })) { review in
            NavigationStack {
                Group {
                    if purpose == .victory {
                        VictoryEditor(plan: plan, suggested: review.text, suggestedCategory: proposedCategory, onSaved: onSaved)
                    } else {
                        ReflectionEditor(plan: plan, dayNumber: plan.dayNumber(today: clock.today), suggested: review.text, onSaved: onSaved)
                    }
                }
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { reviewing = nil } } }
            }
            .environment(\.theme, theme)
        }
    }

    private struct ReviewText: Identifiable { let text: String; var id: String { text } }

    private var opening: String {
        let name = plan.userName.trimmed
        let greeting = name.isEmpty ? "Hello" : "Hello, \(name)"
        if purpose == .victory { return "\(greeting). Tell me about the win you want to remember. What happened, and what did it take?" }
        return "\(greeting). How did today go? Tell me about a win, a hard moment, or whatever is on your mind."
    }

    private func bubble(_ role: Companion.Turn.Role, _ text: String) -> some View {
        Text(text)
            .font(.body)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(role == .user ? theme.gold.opacity(0.16) : theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(role == .user ? theme.gold.opacity(0.35) : theme.divider))
            .frame(maxWidth: .infinity, alignment: role == .user ? .trailing : .leading)
            .padding(role == .user ? .leading : .trailing, 36)
            .accessibilityLabel((role == .user ? "You: " : "Summa: ") + text)
    }

    private func proposalCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(purpose == .victory ? "A victory for \(Colosseum.title)" : "A reflection you could keep")
            if purpose == .victory, let proposedCategory {
                HStack(spacing: 8) {
                    VictoryEmblem(category: proposedCategory, size: 26)
                    Text(proposedCategory.title).font(.footnote.weight(.semibold)).foregroundStyle(theme.gold)
                }
            }
            Text(text).font(SummaFont.serifItalic(19, relativeTo: .body)).fixedSize(horizontal: false, vertical: true)
            Text("Not saved yet. Review it first.").font(.footnote).foregroundStyle(theme.muted)
            HStack(spacing: 12) {
                Button("Review and save") { reviewing = text }.buttonStyle(.summaPrimary).accessibilityIdentifier("companion.review")
                Button("Not now") { proposal = nil }.buttonStyle(.summaSecondary).accessibilityIdentifier("companion.dismiss")
            }
        }
        .card()
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField(dictation.isRecording ? "Listening…" : "Say what is on your mind", text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .padding(.horizontal, 14).padding(.vertical, 11)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(dictation.isRecording ? theme.gold : theme.divider))
                .accessibilityIdentifier("companion.input")
            if dictation.access != .denied && dictation.access != .unavailable {
                Button {
                    Task {
                        // Microphone access is asked for only when the person chooses to speak.
                        if dictation.access == .undetermined { await dictation.requestAccess() }
                        if dictation.access == .granted {
                            if !dictation.isRecording { textBeforeDictation = draft.trimmed }
                            dictation.toggle()
                        }
                        // Say why when speaking cannot start, instead of the button quietly disappearing.
                        if dictation.access == .denied {
                            notice = "Microphone or speech recognition access is off for Summa. Turn both on in the Settings app, or type instead."
                        } else if dictation.access == .unavailable {
                            notice = "Dictation is not available on this device right now. You can type instead."
                        }
                    }
                } label: {
                    Image(systemName: dictation.isRecording ? "stop.fill" : "mic.fill")
                        .foregroundStyle(dictation.isRecording ? theme.onGold : theme.gold)
                        .frame(width: 44, height: 44)
                        .background(dictation.isRecording ? theme.gold : theme.gold.opacity(0.14), in: Circle())
                }
                .accessibilityLabel(dictation.isRecording ? "Stop dictation" : "Start dictation")
            }
            Button { send() } label: {
                Image(systemName: "arrow.up").font(.body.weight(.semibold)).foregroundStyle(theme.onGold)
                    .frame(width: 44, height: 44).background(theme.gold, in: Circle())
            }
            .disabled(draft.trimmed.isEmpty || waiting || !Companion.isConnected)
            .opacity(draft.trimmed.isEmpty || waiting || !Companion.isConnected ? 0.4 : 1)
            .accessibilityLabel("Send")
            .accessibilityIdentifier("companion.send")
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(theme.background.opacity(0.94))
    }

    private func send() {
        let text = draft.trimmed
        guard !text.isEmpty, !waiting else { return }
        dictation.stop()
        draft = ""
        textBeforeDictation = ""
        notice = nil
        turns.append(Companion.Turn(role: .user, text: text))
        waiting = true
        Task { @MainActor in
            defer { waiting = false }
            do {
                let reply = try await Companion.send(turns, purpose: purpose, plan: plan, today: clock.today)
                turns.append(Companion.Turn(role: .assistant, text: reply.reply))
                if let suggestion = reply.draft {
                    proposal = suggestion
                    proposedCategory = reply.category ?? VictoryCategory.classify(suggestion)
                }
                let left = CompanionLimit.remaining(usedToday: Companion.usedToday(clock.today))
                if left <= 5 { notice = left == 0 ? Companion.Failure.dailyLimit.errorDescription : "\(left) messages left today." }
            } catch {
                notice = (error as? LocalizedError)?.errorDescription ?? Companion.Failure.unavailable.errorDescription
            }
        }
    }
}

// MARK: - Your Colosseum

/// The emblem for a kind of victory, drawn in gold: swords, caduceus, abacus, scroll, or coin pouch.
struct VictoryEmblem: View {
    @Environment(\.theme) private var theme
    let category: VictoryCategory
    var size: CGFloat = 44

    private var asset: String {
        switch category {
        case .physical: return "Victory-swords"
        case .science: return "Victory-caduceus"
        case .reckoning: return "Victory-abacus"
        case .letters: return "Victory-scroll"
        case .wealth: return "Victory-pouch"
        }
    }

    var body: some View {
        Image(asset)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .foregroundStyle(theme.gold)
            .accessibilityLabel(category.emblemName)
    }
}

/// Writing a victory, or reviewing one Summa suggested. The emblem follows the words until the person picks one.
struct VictoryEditor: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var clock: TodayClock
    let plan: Plan
    var suggested: String? = nil
    var suggestedCategory: VictoryCategory? = nil
    var onSaved: () -> Void = {}

    @State private var text = ""
    @State private var chosen: VictoryCategory? = nil
    @State private var message: String? = nil
    @FocusState private var focused: Bool

    private var category: VictoryCategory { chosen ?? VictoryCategory.classify(text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow("Day \(plan.dayNumber(today: clock.today)) · New victory")
            if suggested != nil {
                Text("Suggested by Summa. Change anything, then save it if it is true.")
                    .font(.footnote).foregroundStyle(theme.muted)
            }
            TextEditor(text: $text)
                .focused($focused)
                .scrollContentBackground(.hidden)
                .font(.body)
                .padding(12)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(theme.divider))
                .accessibilityLabel("Victory")
                .accessibilityIdentifier("victory.text")
            Eyebrow("Emblem")
            HStack(spacing: 8) {
                ForEach(VictoryCategory.allCases, id: \.self) { option in
                    Button { chosen = option; Haptics.select() } label: {
                        VStack(spacing: 4) {
                            VictoryEmblem(category: option, size: 30)
                            Text(option.title).font(.caption2).foregroundStyle(theme.muted).lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity, minHeight: 62)
                        .background(theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(category == option ? theme.gold : theme.divider, lineWidth: category == option ? 1.6 : 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(option.title), \(option.emblemName)")
                    .accessibilityAddTraits(category == option ? .isSelected : [])
                }
            }
            if let message { Text(message).font(.footnote).foregroundStyle(theme.muted) }
        }
        .padding(20)
        .marbleBackground()
        .foregroundStyle(theme.text)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }.disabled(!ReflectionRule.isSavable(text)).accessibilityIdentifier("victory.save")
            }
        }
        .onAppear {
            if text.isEmpty { text = suggested ?? "" }
            if chosen == nil { chosen = suggestedCategory }
            focused = true
        }
    }

    private func save() {
        do {
            try ReflectionStore.addVictory(text, category: category, to: plan, today: clock.today, in: context)
            Haptics.commit()
            onSaved()
            dismiss()
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? "That could not be saved."
        }
    }
}

/// Victories the person chose to keep, each under its emblem. Private; never part of Friends.
struct ColosseumView: View {
    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var store: Store
    let plan: Plan

    private enum Adding: String, Identifiable { case write, talk; var id: String { rawValue } }
    @State private var adding: Adding? = nil
    @State private var removing: Victory? = nil
    @State private var paywall: PaywallContext? = nil

    var body: some View {
        let victories = ReflectionStore.victories(for: plan)
        VStack(alignment: .leading, spacing: 18) {
            ColosseumCrest(count: victories.count)
            if !store.isPro {
                VStack(alignment: .leading, spacing: 12) {
                    Text("\(Colosseum.title) is part of Summa Pro.").font(.headline)
                    Text("Anything you saved before is kept and returns when Pro is active.").font(.footnote).foregroundStyle(theme.muted)
                    Button("Unlock with Summa Pro") { paywall = .reflections }.buttonStyle(.summaPrimary)
                }
                .card()
            } else {
                HStack(spacing: 12) {
                    Button { adding = .write } label: { Label("Write a victory", systemImage: "square.and.pencil") }
                        .buttonStyle(.summaPrimary).accessibilityIdentifier("colosseum.write")
                    Button { adding = .talk } label: { Label("Tell Summa", systemImage: "mic") }
                        .buttonStyle(.summaSecondary).accessibilityIdentifier("colosseum.talk")
                }
                if victories.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("The arena is empty.").font(SummaFont.serif(24, relativeTo: .title3))
                        Text("Write a victory, tell Summa about one by voice or text, or add a reflection from any day on your heatmap.")
                            .font(.subheadline).foregroundStyle(theme.muted)
                    }
                    .card()
                }
                // Newest first; each keeps the number it earned when it entered the arena.
                ForEach(Array(victories.enumerated()), id: \.element.id) { index, victory in
                    card(victory, ordinal: victories.count - index)
                }
            }
        }
        .sheet(item: $adding) { mode in
            NavigationStack {
                Group {
                    if mode == .write {
                        VictoryEditor(plan: plan)
                    } else {
                        CompanionChatView(plan: plan, purpose: .victory, onSaved: { adding = nil })
                    }
                }
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { adding = nil } } }
            }
            .environment(\.theme, theme)
        }
        .sheet(item: $paywall) { SummaProView(context: $0).environment(\.theme, theme) }
        .confirmationDialog("Remove this victory?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            Button("Remove victory", role: .destructive) {
                if let removing { try? ReflectionStore.delete(removing, in: context) }
                removing = nil
            }
            Button("Cancel", role: .cancel) { removing = nil }
        } message: {
            Text("If it came from a reflection, the reflection is kept.")
        }
    }

    private func card(_ victory: Victory, ordinal: Int) -> some View {
        let kind = victory.kind
        let date = (DayKey(victory.day) ?? plan.start).formatted(.dateTime.month(.abbreviated).day().year())
        return VStack(spacing: 14) {
            // The emblem sits in a medallion between two laurel branches.
            HStack(spacing: 10) {
                Image(systemName: "laurel.leading").font(.system(size: 34, weight: .light))
                VictoryEmblem(category: kind, size: 40)
                    .padding(13)
                    .background(RadialGradient(colors: [gilt.glow.opacity(0.30), gilt.glow.opacity(0.04)], center: .center, startRadius: 2, endRadius: 40), in: Circle())
                    .overlay(Circle().strokeBorder(gilt.line, lineWidth: 1.4))
                    .overlay(Circle().inset(by: 4).strokeBorder(theme.gold.opacity(0.35), lineWidth: 0.6))
                Image(systemName: "laurel.trailing").font(.system(size: 34, weight: .light))
            }
            .foregroundStyle(gilt.line)
            .accessibilityHidden(true)

            Text("VICTORIA  \(RomanNumeral.string(ordinal))")
                .font(SummaFont.roman(15)).tracking(4).foregroundStyle(gilt.line)
                .accessibilityLabel("Victory \(ordinal), \(kind.title)")

            Text("“\(victory.text)”")
                .font(SummaFont.serifItalic(24, relativeTo: .title3))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            GiltRule()

            Text("\(kind.title.uppercased())  ·  DAY \(RomanNumeral.string(victory.dayNumber))  ·  \(date.uppercased())")
                .font(.caption2.weight(.medium)).tracking(1.8).foregroundStyle(theme.muted)
                .multilineTextAlignment(.center)
                .accessibilityLabel("\(kind.title), day \(victory.dayNumber), \(date)")

            HStack(spacing: 18) {
                Menu("Change emblem") {
                    ForEach(VictoryCategory.allCases, id: \.self) { option in
                        Button("\(option.title) (\(option.emblemName))") { try? ReflectionStore.setCategory(option, for: victory, in: context) }
                    }
                }
                Spacer()
                Button("Remove", role: .destructive) { removing = victory }.foregroundStyle(.red.opacity(0.85))
            }
            .font(.footnote.weight(.semibold)).tint(theme.gold).frame(minHeight: 36)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 22).padding(.top, 26).padding(.bottom, 12)
        .modifier(GiltFrame())
        .accessibilityElement(children: .contain)
    }

    private var gilt: Gilt { Gilt(theme: theme) }
}

// MARK: - Gilding

/// The Colosseum's gold: a burnished gradient for lines, and a paler tone for light and glow.
struct Gilt {
    let theme: Theme

    var stops: [Color] {
        theme.isDark ? [Color(hex: "#8A6A24"), Color(hex: "#F7E3A1"), Color(hex: "#DCAF61"), Color(hex: "#FFF4CF"), Color(hex: "#A67C2A")]
                     : [Color(hex: "#6B4F12"), Color(hex: "#C9A24A"), Color(hex: "#7E5F17"), Color(hex: "#DDBE6C"), Color(hex: "#6B4F12")]
    }
    var glow: Color { theme.isDark ? Color(hex: "#F6D98A") : Color(hex: "#C9A24A") }
    var line: LinearGradient { LinearGradient(colors: stops, startPoint: .topLeading, endPoint: .bottomTrailing) }
}

/// A fine rule with a diamond at its centre, like the divider on an inscription.
struct GiltRule: View {
    @Environment(\.theme) private var theme

    var body: some View {
        let gilt = Gilt(theme: theme)
        HStack(spacing: 10) {
            LinearGradient(colors: [.clear, gilt.glow.opacity(0.8)], startPoint: .leading, endPoint: .trailing).frame(height: 0.8)
            Rectangle().fill(gilt.line).frame(width: 6, height: 6).rotationEffect(.degrees(45))
            LinearGradient(colors: [gilt.glow.opacity(0.8), .clear], startPoint: .leading, endPoint: .trailing).frame(height: 0.8)
        }
        .frame(maxWidth: 220)
        .accessibilityHidden(true)
    }
}

/// The frame around a victory: a burnished double border with a jewel at each corner, a warm light
/// from above, and a slow glint that travels around the edge. With Reduce Motion the glint is still.
struct GiltFrame: ViewModifier {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var turn = false

    func body(content: Content) -> some View {
        let gilt = Gilt(theme: theme)
        let outer = RoundedRectangle(cornerRadius: 22, style: .continuous)
        let inner = RoundedRectangle(cornerRadius: 16, style: .continuous)
        content
            .background {
                ZStack {
                    outer.fill(LinearGradient(colors: [theme.surfaceRaised, theme.surface], startPoint: .top, endPoint: .bottom))
                    // Light falling from above, as if the tablet stood under an oculus.
                    outer.fill(RadialGradient(colors: [gilt.glow.opacity(theme.isDark ? 0.16 : 0.20), .clear],
                                              center: UnitPoint(x: 0.5, y: 0), startRadius: 4, endRadius: 240))
                }
            }
            .overlay(outer.strokeBorder(gilt.line, lineWidth: 1.6))
            .overlay {
                // The travelling glint: a bright arc, masked to the border.
                Rectangle()
                    .fill(AngularGradient(stops: [.init(color: .clear, location: 0), .init(color: .clear, location: 0.80),
                                                  .init(color: .white.opacity(theme.isDark ? 0.95 : 0.85), location: 0.90),
                                                  .init(color: .clear, location: 1)], center: .center))
                    .scaleEffect(3)
                    .rotationEffect(.degrees(reduceMotion ? 300 : (turn ? 360 : 0)))
                    .mask(outer.strokeBorder(lineWidth: 1.8))
                    .blendMode(theme.isDark ? .plusLighter : .normal)
                    .allowsHitTesting(false)
            }
            .clipShape(outer)
            .overlay(inner.inset(by: 0).strokeBorder(gilt.glow.opacity(0.42), lineWidth: 0.7).padding(6))
            .overlay(alignment: .topLeading) { jewel(gilt).padding(10) }
            .overlay(alignment: .topTrailing) { jewel(gilt).padding(10) }
            .overlay(alignment: .bottomLeading) { jewel(gilt).padding(10) }
            .overlay(alignment: .bottomTrailing) { jewel(gilt).padding(10) }
            .shadow(color: gilt.glow.opacity(theme.isDark ? 0.16 : 0.22), radius: 14, y: 4)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 7).repeatForever(autoreverses: false)) { turn = true }
            }
    }

    private func jewel(_ gilt: Gilt) -> some View {
        Rectangle().fill(gilt.line).frame(width: 5, height: 5).rotationEffect(.degrees(45)).accessibilityHidden(true)
    }
}

/// The crest at the top of the Colosseum: laurels, the name in Roman capitals, and the tally of victories.
struct ColosseumCrest: View {
    @Environment(\.theme) private var theme
    let count: Int

    var body: some View {
        let gilt = Gilt(theme: theme)
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                Image(systemName: "laurel.leading")
                Text(count > 0 ? RomanNumeral.string(count) : "·")
                    .font(SummaFont.roman(34, relativeTo: .largeTitle))
                    .minimumScaleFactor(0.6).lineLimit(1)
                Image(systemName: "laurel.trailing")
            }
            .font(.system(size: 44, weight: .ultraLight))
            .foregroundStyle(gilt.line)
            .shadow(color: gilt.glow.opacity(theme.isDark ? 0.45 : 0.2), radius: 10)
            .accessibilityHidden(true)

            Text(Colosseum.title.uppercased())
                .font(SummaFont.roman(20, relativeTo: .title3)).tracking(5)
                .foregroundStyle(gilt.line)
                .accessibilityAddTraits(.isHeader)
                .accessibilityLabel("\(Colosseum.title), \(count) \(count == 1 ? "victory" : "victories")")
            GiltRule()
            Text(count == 0 ? "What you conquer is written here." : "Veni. Vidi. Vici.")
                .font(SummaFont.serifItalic(19, relativeTo: .body)).foregroundStyle(theme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
    }
}
