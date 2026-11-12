import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers
import SummaCore

enum JourneySheet: String, Identifiable {
    case reports, milestones, photos, graduation, chapters
    var id: String { rawValue }
}

/// Remembers the newest weekly report the person has opened.
enum ReportMemory {
    private static func key(_ plan: Plan) -> String { "summa.reportSeen.\(plan.id.uuidString)" }
    static func unseenWeek(for plan: Plan, today: DayKey) -> Int? {
        guard let latest = ReportBuilder.finishedWeeks(planStart: plan.start, today: today).first,
              latest > UserDefaults.standard.integer(forKey: key(plan)) else { return nil }
        return latest
    }
    static func markSeen(_ plan: Plan, today: DayKey) {
        if let latest = ReportBuilder.finishedWeeks(planStart: plan.start, today: today).first {
            UserDefaults.standard.set(latest, forKey: key(plan))
        }
    }
}

/// Entry points shown on the Plan tab.
struct JourneySection: View {
    @Environment(\.theme) private var theme
    let open: (JourneySheet) -> Void

    private let rows: [(JourneySheet, String, String, String)] = [
        (.reports, "doc.text", "Weekly reports", "What you kept and missed, week by week"),
        (.milestones, "flag", "Milestones", "Days 21, 66, and 90"),
        (.photos, "photo.on.rectangle", "Photo diary", "Private progress photos"),
        (.graduation, "laurel.leading", "Graduation", "Your day-90 result"),
        (.chapters, "books.vertical", "Chapters", "This and earlier 90 days"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<rows.count, id: \.self) { index in
                let row = rows[index]
                Button { open(row.0) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: row.1).foregroundStyle(theme.gold).frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.2).font(.headline).foregroundStyle(theme.text)
                            Text(row.3).font(.footnote).foregroundStyle(theme.muted)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote).foregroundStyle(theme.muted)
                    }
                    .frame(minHeight: 52)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("journey.\(row.0.rawValue)")
                if index < rows.count - 1 { Hairline() }
            }
        }
        .card(padding: 14)
    }
}

/// Presents one journey screen in a sheet with a Done button.
struct JourneyHost: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    let sheet: JourneySheet
    let plan: Plan

    var body: some View {
        NavigationStack {
            ScrollView {
                Group {
                    switch sheet {
                    case .reports: WeeklyReportsView(plan: plan)
                    case .milestones: MilestonesView(plan: plan)
                    case .photos: PhotoDiaryView(plan: plan)
                    case .graduation: GraduationView(plan: plan)
                    case .chapters: ChaptersView(current: plan)
                    }
                }
                .padding(20)
            }
            .marbleBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("journey.done")
                }
            }
        }
        .foregroundStyle(theme.text)
    }
}

private struct ScreenTitle: View {
    @Environment(\.theme) private var theme
    let eyebrow: String
    let title: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(eyebrow)
            Text(title).font(SummaFont.serif(34, relativeTo: .largeTitle)).fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: Weekly reports

struct WeeklyReportsView: View {
    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var clock: TodayClock
    let plan: Plan
    @State private var editing: Habit? = nil

    var body: some View {
        let weeks = ReportBuilder.finishedWeeks(planStart: plan.start, today: clock.today)
        let records = plan.records
        VStack(alignment: .leading, spacing: 18) {
            ScreenTitle(eyebrow: "Weekly reports", title: "The week, as it was.")
            if weeks.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your first report arrives after day 7.").font(.headline)
                    Text("Each report is built from what you actually checked in.").font(.footnote).foregroundStyle(theme.muted)
                }
                .card()
            }
            ForEach(weeks, id: \.self) { week in
                reportCard(ReportBuilder.report(week: week, habits: records, today: clock.today))
            }
        }
        .onAppear { ReportMemory.markSeen(plan, today: clock.today) }
        .sheet(item: $editing) { habit in
            HabitEditorView(heading: "Edit habit", draft: habit.asDraft(), reminderOn: habit.reminderEnabled,
                            otherRemindersOn: plan.activeHabits.filter { $0.reminderEnabled && $0.id != habit.id }.count,
                            scheduleNote: "A new schedule starts today. Earlier days keep the schedule they had.") { draft, reminderOn in
                PlanStore.update(habit, with: draft, reminderEnabled: reminderOn, today: clock.today, in: context)
            }
            .environment(\.theme, theme)
        }
    }

    private func reportCard(_ report: WeeklyReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow("Week \(report.week)", color: Stage.forDay((report.week - 1) * 7 + 1).color)
                Spacer()
                Text("\(report.range.lowerBound.formatted(.dateTime.month(.abbreviated).day())) – \(report.range.upperBound.formatted(.dateTime.month(.abbreviated).day()))")
                    .font(.caption).foregroundStyle(theme.muted)
            }
            if let percent = report.percent {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(percent)%").font(SummaFont.serif(48, relativeTo: .largeTitle))
                    if let change = report.change {
                        Text(change == 0 ? "same as last week" : "\(change > 0 ? "up" : "down") \(abs(change)) from last week")
                            .font(.footnote).foregroundStyle(theme.muted)
                    }
                }
                Text("\(report.scheduled) scheduled · \(report.completed) completed · \(report.missed) missed").font(.subheadline)
                if let strongest = report.strongest { line("Strongest", strongest) }
                if let weakest = report.weakest { line("Needs attention", weakest) }
            }
            Hairline()
            ForEach(report.suggestions, id: \.self) { suggestion in
                Text(suggestion).font(.footnote).foregroundStyle(theme.muted).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(plan.activeHabits.filter { report.habitsToReview.contains($0.id) }) { habit in
                Button("Review “\(habit.title)”") { editing = habit }
                    .font(.subheadline.weight(.semibold)).foregroundStyle(theme.gold).frame(minHeight: 44)
            }
        }
        .card()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("report.week.\(report.week)")
    }

    private func line(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.footnote).foregroundStyle(theme.muted)
            Spacer()
            Text(value).font(.footnote.weight(.semibold))
        }
    }
}

// MARK: Milestones

struct MilestonesView: View {
    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var clock: TodayClock
    let plan: Plan
    @State private var sharing: Int? = nil

    var body: some View {
        let day = plan.dayNumber(today: clock.today)
        let finished = plan.isFinished(today: clock.today)
        VStack(alignment: .leading, spacing: 18) {
            ScreenTitle(eyebrow: "Milestones", title: "Proof you can point to.")
            Text("Written from your objective. Rewrite each one so it names something you can measure.")
                .font(.footnote).foregroundStyle(theme.muted)
            ForEach(plan.sortedMilestones) { milestone in
                let arrived = finished || day >= milestone.day
                VStack(alignment: .leading, spacing: 12) {
                    Eyebrow("Day \(milestone.day) · \(Stage.forDay(milestone.day).name)", color: Stage.forDay(milestone.day).color)
                    TextField("What will be true on day \(milestone.day)?", text: Binding(
                        get: { milestone.text },
                        set: { milestone.text = String($0.prefix(400)); try? context.save() }), axis: .vertical)
                        .lineLimit(2...6)
                        .accessibilityLabel("Milestone for day \(milestone.day)")
                    Toggle("Reached", isOn: Binding(get: { milestone.reached }, set: { milestone.reached = $0; try? context.save() }))
                        .tint(theme.gold)
                        .disabled(!arrived)
                    if arrived {
                        MilestonePhotoRow(plan: plan, milestoneDay: milestone.day)
                        Button { sharing = milestone.day } label: { Label("Create a card to share", systemImage: "square.and.arrow.up") }
                            .buttonStyle(.summaSecondary)
                            .accessibilityIdentifier("milestone.share.\(milestone.day)")
                    } else {
                        Text("Opens on day \(milestone.day).").font(.footnote).foregroundStyle(theme.muted)
                    }
                }
                .card()
            }
        }
        .onAppear { PlanStore.ensureMilestones(for: plan, in: context) }
        .sheet(item: Binding(get: { sharing.map { IdentifiedInt(value: $0) } }, set: { sharing = $0?.value })) { item in
            ShareCardSheet(plan: plan, day: item.value).environment(\.theme, theme)
        }
    }
}

struct IdentifiedInt: Identifiable {
    let value: Int
    var id: Int { value }
}

/// Adds or shows the optional photo for one milestone.
private struct MilestonePhotoRow: View {
    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var clock: TodayClock
    let plan: Plan
    let milestoneDay: Int
    @State private var picked: PhotosPickerItem? = nil
    @State private var working = false
    @State private var problem: String? = nil

    var body: some View {
        let photo = plan.sortedPhotos.last { $0.milestoneDay == milestoneDay }
        VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 12) {
            if let photo, let image = PhotoStore.image(photo.fileName) {
                Image(uiImage: image).resizable().scaledToFill().frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityLabel("Milestone photo")
            }
            PhotosPicker(selection: $picked, matching: .images) {
                Label(photo == nil ? "Add a private photo" : "Replace photo", systemImage: "camera")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(theme.gold).frame(minHeight: 44)
            }
        }
        .overlay(alignment: .trailing) { if working { ProgressView().tint(theme.gold) } }
        .onChange(of: picked) { _, item in
            guard let item else { return }
            working = true
            problem = nil
            Task { @MainActor in
                // The old photo is removed only once the new one is safely stored.
                problem = await PhotoImport.add(item, milestoneDay: milestoneDay, replacing: photo, to: plan, today: clock.today, in: context)
                working = false
                picked = nil
            }
        }
        if let problem {
            Text(problem).font(.footnote).foregroundStyle(theme.muted).accessibilityIdentifier("milestone.photoProblem")
        }
        }
    }
}

/// Loads a picked photo and stores it. Returns a sentence to show when it could not be done.
@MainActor
enum PhotoImport {
    /// Some library items only load as an image type, not as plain data.
    private struct PickedImage: Transferable {
        let data: Data
        static var transferRepresentation: some TransferRepresentation {
            DataRepresentation(importedContentType: .image) { PickedImage(data: $0) }
        }
    }

    static func add(_ item: PhotosPickerItem, milestoneDay: Int?, replacing old: ProgressPhoto? = nil, to plan: Plan, today: DayKey,
                    in context: ModelContext) async -> String? {
        var data = try? await item.loadTransferable(type: Data.self)
        if data == nil { data = (try? await item.loadTransferable(type: PickedImage.self))?.data }
        guard let data else {
            return "That photo could not be loaded. If it is stored in iCloud, open it in Photos first so it downloads, or choose another."
        }
        guard PlanStore.addPhoto(data, milestoneDay: milestoneDay, to: plan, today: today, in: context) else {
            return "That photo could not be saved. Choose a different image, or check that the device has free space."
        }
        if let old { PlanStore.deletePhoto(old, in: context) }
        Haptics.commit()
        return nil
    }
}

// MARK: Photo diary

struct PhotoDiaryView: View {
    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var clock: TodayClock
    let plan: Plan
    @State private var picked: PhotosPickerItem? = nil
    @State private var deleting: ProgressPhoto? = nil
    @State private var working = false
    @State private var problem: String? = nil

    var body: some View {
        let photos = plan.sortedPhotos
        VStack(alignment: .leading, spacing: 18) {
            ScreenTitle(eyebrow: "Photo diary", title: "For your eyes.")
            Text("Photos are optional and private. They are stored only on this device and are never shared unless you add one to a card yourself.")
                .font(.footnote).foregroundStyle(theme.muted)
            PhotosPicker(selection: $picked, matching: .images) {
                Label("Add a photo", systemImage: "plus")
                    .font(.headline).foregroundStyle(theme.text).frame(maxWidth: .infinity, minHeight: 52)
                    .background(theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(theme.divider))
            }
            .accessibilityIdentifier("photos.add")
            .disabled(working)
            if working {
                HStack(spacing: 10) { ProgressView().tint(theme.gold); Text("Saving photo…").font(.footnote).foregroundStyle(theme.muted) }
            }
            if let problem {
                Text(problem).font(.footnote).foregroundStyle(theme.muted).card().accessibilityIdentifier("photos.problem")
            }
            if photos.isEmpty {
                Text("No photos yet.").font(.subheadline).foregroundStyle(theme.muted).card()
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(photos) { photo in
                    VStack(alignment: .leading, spacing: 6) {
                        Color.black.aspectRatio(1, contentMode: .fit)
                            .overlay {
                                if let image = PhotoStore.image(photo.fileName) { Image(uiImage: image).resizable().scaledToFill() }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .accessibilityLabel("Progress photo, \(caption(photo))")
                        HStack {
                            Text(caption(photo)).font(.caption).foregroundStyle(theme.muted)
                            Spacer()
                            Button { deleting = photo } label: { Image(systemName: "trash").frame(width: 44, height: 44) }
                                .buttonStyle(.plain).foregroundStyle(theme.muted)
                                .accessibilityLabel("Delete photo from \(caption(photo))")
                        }
                    }
                }
            }
        }
        .onChange(of: picked) { _, item in
            guard let item else { return }
            working = true
            problem = nil
            Task { @MainActor in
                problem = await PhotoImport.add(item, milestoneDay: nil, to: plan, today: clock.today, in: context)
                working = false
                picked = nil
            }
        }
        .confirmationDialog("Delete this photo?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let photo = deleting { PlanStore.deletePhoto(photo, in: context) }
                deleting = nil
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: {
            Text("It is removed from this device and cannot be recovered.")
        }
    }

    private func caption(_ photo: ProgressPhoto) -> String {
        let day = DayKey(photo.day).map { plan.start.days(until: $0) + 1 } ?? 0
        return photo.milestoneDay.map { "Day \($0) milestone" } ?? "Day \(day)"
    }
}

// MARK: Share cards

/// A milestone card with real statistics. Always dark, so it looks the same wherever it is posted.
struct ShareCard: View {
    let day: Int
    let percent: Int?
    let completed: Int
    let streak: Int
    let photo: UIImage?

    var body: some View {
        let stage = Stage.forDay(day)
        let gold = Color(hex: "#DCAF61")
        let ivory = Color(hex: "#EEEBE4")
        VStack(spacing: 14) {
            Text("SUMMA").font(SummaFont.roman(15)).tracking(5).foregroundStyle(gold)
            if let photo {
                Image(uiImage: photo).resizable().scaledToFill().frame(width: 150, height: 150)
                    .clipShape(Circle()).overlay(Circle().strokeBorder(gold.opacity(0.6), lineWidth: 1))
            } else {
                LaurelWreath(size: 84, weight: .light).foregroundStyle(gold)
            }
            Text("Day \(day)").font(SummaFont.serif(54)).foregroundStyle(ivory)
            HStack(spacing: 7) {
                Circle().fill(stage.color).frame(width: 8, height: 8)
                Text(stage.name.uppercased()).font(.system(size: 12, weight: .semibold)).tracking(2).foregroundStyle(ivory)
            }
            HStack(spacing: 22) {
                stat(percent.map { "\($0)%" } ?? "—", "complete", ivory)
                stat("\(completed)", "activities", ivory)
                stat("\(streak)", "best streak", ivory)
            }
            .padding(.top, 6)
        }
        .padding(28)
        .frame(width: 340, height: 440)
        .background(LinearGradient(colors: [Color(hex: "#040404"), Color(hex: "#15130F"), Color(hex: "#040404")], startPoint: .topLeading, endPoint: .bottomTrailing))
        .overlay(Rectangle().strokeBorder(gold.opacity(0.45), lineWidth: 1).padding(10))
    }

    private func stat(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(SummaFont.serif(28)).foregroundStyle(color)
            Text(label).font(.system(size: 11)).foregroundStyle(color.opacity(0.7))
        }
    }
}

struct ShareCardSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    let plan: Plan
    let day: Int
    @State private var includePhoto = false

    var body: some View {
        let through = plan.start.adding(day - 1)
        let timelines = plan.timelines
        let overall = PlanProgress.completion(timelines: timelines, today: through)
        let streak = timelines.map { HabitMetrics.compute($0, today: through).longestStreak }.max() ?? 0
        let photoFile = plan.sortedPhotos.last { $0.milestoneDay == day }?.fileName
        let photo = includePhoto ? photoFile.flatMap { PhotoStore.image($0) } : nil
        let card = ShareCard(day: day, percent: overall.percent, completed: overall.completed, streak: streak, photo: photo)
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    card.accessibilityElement(children: .ignore)
                        .accessibilityLabel("Day \(day) card: \(overall.percent ?? 0) percent complete, \(overall.completed) activities, best streak \(streak)")
                    if photoFile != nil {
                        Toggle("Include my day \(day) photo", isOn: $includePhoto).tint(theme.gold)
                    }
                    Text("The card shows statistics only. Nothing is posted for you: you choose where it goes.")
                        .font(.footnote).foregroundStyle(theme.muted)
                    if let image = Rendering.image(of: card) {
                        ShareLink(item: Image(uiImage: image), preview: SharePreview("Summa, day \(day)", image: Image(uiImage: image))) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.summaPrimary)
                        .accessibilityIdentifier("card.share")
                    }
                }
                .padding(20)
            }
            .marbleBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .foregroundStyle(theme.text)
    }
}

@MainActor
enum Rendering {
    static func image<V: View>(of view: V) -> UIImage? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        return renderer.uiImage
    }
}

// MARK: Graduation

struct GraduationView: View {
    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var clock: TodayClock
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var onboarding: OnboardingStore
    @AppStorage("summa.newChapter") private var startingNewChapter = false
    let plan: Plan

    @State private var paywall: PaywallContext? = nil
    @State private var showCertificate = false
    @State private var showReel = false
    @State private var sharing = false
    @State private var confirmContinue = false

    var body: some View {
        let timelines = plan.timelines
        let due = Graduation.isDue(timelines: timelines, planStart: plan.start, today: clock.today)
        let result = Graduation.evaluate(timelines: timelines)
        VStack(alignment: .leading, spacing: 18) {
            GraduationRingView(result: result, stage: plan.stage(today: clock.today), day: plan.dayNumber(today: clock.today),
                               finished: plan.isFinished(today: clock.today))
            if !due {
                notYet(timelines)
            } else if result.eligible {
                graduated(result)
            } else {
                summary(result)
            }
            if due {
                report(result)
                next
            }
        }
        .onAppear {
            if due, !plan.graduationSeen {
                plan.graduationSeen = true
                try? context.save()
            }
        }
        .sheet(item: $paywall) { SummaProView(context: $0).environment(\.theme, theme) }
        .sheet(isPresented: $showCertificate) { CertificateSheet(plan: plan, result: result).environment(\.theme, theme) }
        .sheet(isPresented: $sharing) { ShareCardSheet(plan: plan, day: 90).environment(\.theme, theme) }
        .fullScreenCover(isPresented: $showReel) { HighlightReel(plan: plan, result: result).environment(\.theme, theme) }
        .confirmationDialog("Continue with the same habits?", isPresented: $confirmContinue, titleVisibility: .visible) {
            Button("Start the next 90 days") {
                PlanStore.continueChapter(from: plan, today: clock.today, in: context)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("A new chapter begins today with your current habits. This chapter and its record are kept under Chapters.")
        }
    }

    private func notYet(_ timelines: [HabitTimeline]) -> some View {
        let soFar = PlanProgress.completion(timelines: timelines, today: clock.today)
        return VStack(alignment: .leading, spacing: 12) {
            ScreenTitle(eyebrow: "Graduation", title: "Decided on day 90.")
            Text("Graduation needs at least \(Graduation.threshold)% of every scheduled activity across the full 90 days.").font(.body)
            if let percent = soFar.percent {
                Text("So far: \(percent)% (\(soFar.completed) of \(soFar.scheduled)).").font(.headline)
                    .accessibilityIdentifier("graduation.sofar")
            }
            Text("Day \(plan.dayNumber(today: clock.today)) of \(HabitTimeline.planLength).").font(.footnote).foregroundStyle(theme.muted)
        }
        .card()
    }

    private func graduated(_ result: GraduationResult) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            LaurelWreath(size: 70, weight: .regular).foregroundStyle(theme.gold).accessibilityHidden(true)
            ScreenTitle(eyebrow: "Summa Graduation", title: plan.userName.isEmpty ? "You graduated." : "\(plan.userName), you graduated.")
            Text("\(result.percent)% of \(result.scheduled) scheduled activities across 90 days. The requirement is \(Graduation.threshold)%.")
                .font(.body)
            Button { store.isPro ? (showCertificate = true) : (paywall = .graduation) } label: {
                Label(store.isPro ? "Graduation certificate" : "Graduation certificate · Pro", systemImage: "seal")
            }
            .buttonStyle(.summaPrimary)
            .accessibilityIdentifier("graduation.certificate")
            Button { store.isPro ? (showReel = true) : (paywall = .graduation) } label: {
                Label(store.isPro ? "Highlight reel" : "Highlight reel · Pro", systemImage: "play.rectangle")
            }
            .buttonStyle(.summaSecondary)
            if !store.isPro {
                Text("Your graduation is yours on any plan. The certificate and reel are part of Summa Pro.")
                    .font(.footnote).foregroundStyle(theme.muted)
            }
        }
        .card()
        .accessibilityIdentifier("graduation.graduated")
    }

    private func summary(_ result: GraduationResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ScreenTitle(eyebrow: "Your 90 days", title: "The record stands.")
            Text("You completed \(result.completed) of \(result.scheduled) scheduled activities: \(result.percent)%.").font(.body)
            Text("Official graduation needs \(Graduation.threshold)%, so this chapter closes without it. Everything you did is kept.")
                .font(.footnote).foregroundStyle(theme.muted)
        }
        .card()
        .accessibilityIdentifier("graduation.summary")
    }

    private func report(_ result: GraduationResult) -> some View {
        let photos = plan.sortedPhotos
        return VStack(alignment: .leading, spacing: 14) {
            Eyebrow("Transformation report")
            HStack(spacing: 24) {
                figure("\(result.percent)%", "completion")
                figure("\(result.completed)", "activities completed")
            }
            Hairline()
            ForEach(plan.sortedMilestones) { milestone in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: milestone.reached ? "checkmark.circle.fill" : "circle").foregroundStyle(milestone.reached ? theme.gold : theme.muted)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Day \(milestone.day)").font(.caption.weight(.semibold)).foregroundStyle(theme.muted)
                        Text(milestone.text).font(.footnote).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            if !photos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(photos) { photo in
                            if let image = PhotoStore.image(photo.fileName) {
                                Image(uiImage: image).resizable().scaledToFill().frame(width: 84, height: 84)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                        }
                    }
                }
                .accessibilityLabel("\(photos.count) progress photos")
            }
            Button { sharing = true } label: { Label("Share a day 90 card", systemImage: "square.and.arrow.up") }
                .buttonStyle(.summaSecondary)
        }
        .card()
    }

    private func figure(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(SummaFont.serif(44, relativeTo: .largeTitle))
            Text(label).font(.footnote).foregroundStyle(theme.muted)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var next: some View {
        if plan.isFinished(today: clock.today) {
            VStack(alignment: .leading, spacing: 12) {
                Eyebrow("What next")
                Button("Start a new chapter with new goals") {
                    let previous = plan.answers
                    onboarding.reset()
                    onboarding.answers.set(.name, text: previous.name)
                    onboarding.answers.set(.username, text: previous.username)
                    onboarding.stage = .choosePath
                    startingNewChapter = true
                }
                .buttonStyle(.summaPrimary)
                .disabled(DevSandbox.isActive) // the developer preview never starts a real chapter
                .accessibilityIdentifier("graduation.newChapter")
                Button("Continue with the same habits") { confirmContinue = true }
                    .buttonStyle(.summaSecondary)
                    .accessibilityIdentifier("graduation.continue")
                Text("Either way, this chapter, its reports, photos, and achievements are kept.")
                    .font(.footnote).foregroundStyle(theme.muted)
            }
            .card()
        } else {
            Text("New chapters open tomorrow, once day 90 has ended.").font(.footnote).foregroundStyle(theme.muted)
        }
    }
}

/// The Pro graduation certificate, shareable as an image.
private struct CertificateSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    let plan: Plan
    let result: GraduationResult

    private var certificate: some View {
        let gold = Color(hex: "#DCAF61")
        let ivory = Color(hex: "#EEEBE4")
        return VStack(spacing: 12) {
            Text("SUMMA").font(SummaFont.roman(15)).tracking(5).foregroundStyle(gold)
            LaurelWreath(size: 92, weight: .regular).foregroundStyle(gold)
            Text("Certificate of Graduation").font(SummaFont.serif(30)).foregroundStyle(ivory)
            Text("awarded to").font(.system(size: 12)).foregroundStyle(ivory.opacity(0.7))
            Text(plan.userName.isEmpty ? "A Summa graduate" : plan.userName).font(SummaFont.serifItalic(34)).foregroundStyle(gold)
            Text("for completing \(result.percent)% of \(result.scheduled) scheduled practices across ninety days")
                .font(.system(size: 13)).multilineTextAlignment(.center).foregroundStyle(ivory)
            Text("\(plan.start.formatted(.dateTime.month(.wide).day().year())) – \(plan.end.formatted(.dateTime.month(.wide).day().year()))")
                .font(.system(size: 11)).foregroundStyle(ivory.opacity(0.7))
            Text("Chapter \(plan.chapter)").font(.system(size: 11, weight: .semibold)).tracking(2).foregroundStyle(gold)
        }
        .padding(30)
        .frame(width: 340, height: 460)
        .background(LinearGradient(colors: [Color(hex: "#040404"), Color(hex: "#17140E"), Color(hex: "#040404")], startPoint: .top, endPoint: .bottom))
        .overlay(Rectangle().strokeBorder(gold.opacity(0.6), lineWidth: 1).padding(10))
        .overlay(Rectangle().strokeBorder(gold.opacity(0.3), lineWidth: 1).padding(15))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    certificate.accessibilityElement(children: .ignore)
                        .accessibilityLabel("Certificate of graduation for \(plan.userName), \(result.percent) percent across ninety days")
                    if let image = Rendering.image(of: certificate) {
                        ShareLink(item: Image(uiImage: image), preview: SharePreview("Summa graduation certificate", image: Image(uiImage: image))) {
                            Label("Share or save", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.summaPrimary)
                    }
                }
                .padding(20)
            }
            .marbleBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .foregroundStyle(theme.text)
    }
}

/// A short, full-screen look back: numbers, milestones, and photos, one at a time.
private struct HighlightReel: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let plan: Plan
    let result: GraduationResult
    @State private var index = 0

    private enum Slide { case title, number(String, String), text(String, String), photo(UIImage, String) }

    private var slides: [Slide] {
        var all: [Slide] = [.title, .number("\(result.percent)%", "of everything you scheduled"), .number("\(result.completed)", "practices completed")]
        for milestone in plan.sortedMilestones where milestone.reached { all.append(.text("Day \(milestone.day)", milestone.text)) }
        for photo in plan.sortedPhotos {
            if let image = PhotoStore.image(photo.fileName) {
                let day = DayKey(photo.day).map { plan.start.days(until: $0) + 1 } ?? 0
                all.append(.photo(image, "Day \(day)"))
            }
        }
        all.append(.text("Ninety days", "The act is the record."))
        return all
    }

    var body: some View {
        let all = slides
        let current = all[min(index, all.count - 1)]
        ZStack {
            Color.black.ignoresSafeArea()
            Group {
                switch current {
                case .title:
                    VStack(spacing: 16) {
                        LaurelWreath(size: 110, weight: .regular).foregroundStyle(theme.gold)
                        Text(plan.userName.isEmpty ? "Graduate" : plan.userName).font(SummaFont.serif(44, relativeTo: .largeTitle))
                    }
                case .number(let value, let label):
                    VStack(spacing: 8) {
                        Text(value).font(SummaFont.serif(96, relativeTo: .largeTitle)).foregroundStyle(theme.gold)
                        Text(label).font(SummaFont.serifItalic(24, relativeTo: .title3))
                    }
                case .text(let heading, let body):
                    VStack(spacing: 12) {
                        Eyebrow(heading, color: theme.gold)
                        Text(body).font(SummaFont.serif(28, relativeTo: .title2)).multilineTextAlignment(.center)
                    }
                case .photo(let image, let label):
                    VStack(spacing: 12) {
                        Image(uiImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .accessibilityLabel("Progress photo")
                        Eyebrow(label, color: theme.gold)
                    }
                }
            }
            .padding(32)
            .foregroundStyle(Color(hex: "#EEEBE4"))
            .id(index)
            .transition(.opacity)
        }
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                .foregroundStyle(.white).padding(.trailing, 12).accessibilityLabel("Close")
        }
        .overlay(alignment: .bottom) {
            HStack {
                Button("Back") { if index > 0 { index -= 1 } }.disabled(index == 0)
                Spacer()
                Text("\(min(index, all.count - 1) + 1) of \(all.count)").font(.caption)
                Spacer()
                Button(index >= all.count - 1 ? "Done" : "Next") { if index >= all.count - 1 { dismiss() } else { index += 1 } }
            }
            .foregroundStyle(.white).padding(.horizontal, 24).padding(.bottom, 12).frame(minHeight: 44)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: index)
        .task(id: index) {
            // Advances on its own unless Reduce Motion is on; the buttons always work.
            guard !reduceMotion, index < all.count - 1 else { return }
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { index += 1 }
        }
    }
}

// MARK: Chapters

struct ChaptersView: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var clock: TodayClock
    @Query(sort: \Plan.createdAt, order: .reverse) private var plans: [Plan]
    let current: Plan
    @State private var viewing: Plan? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ScreenTitle(eyebrow: "Chapters", title: "Every 90 days, kept.")
            ForEach(plans) { plan in
                let result = Graduation.evaluate(timelines: plan.timelines)
                let finished = plan.isFinished(today: clock.today)
                Button { viewing = plan } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Eyebrow("Chapter \(plan.chapter)" + (plan.id == current.id ? " · current" : ""), color: theme.gold)
                        Text(plan.objective).font(SummaFont.serif(22, relativeTo: .title3)).foregroundStyle(theme.text).multilineTextAlignment(.leading)
                        Text("\(plan.start.formatted(.dateTime.month(.abbreviated).day().year())) – \(plan.end.formatted(.dateTime.month(.abbreviated).day().year()))")
                            .font(.footnote).foregroundStyle(theme.muted)
                        Text(finished ? (result.eligible ? "Graduated · \(result.percent)%" : "Completed · \(result.percent)%") : "In progress")
                            .font(.footnote.weight(.semibold)).foregroundStyle(theme.text)
                    }
                    .card()
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens this chapter's result")
            }
        }
        .sheet(item: $viewing) { plan in
            JourneyHost(sheet: .graduation, plan: plan).environment(\.theme, theme)
        }
    }
}


// MARK: Graduation ring

/// The large ring at the top of Graduation. It fills with activities completed out of every
/// activity scheduled across the 90 days, tinted by the current stage, with a mark at 80%.
struct GraduationRingView: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let result: GraduationResult
    let stage: Stage
    let day: Int
    let finished: Bool

    @State private var shown: Double = 0

    var body: some View {
        let fraction = GraduationRing.fraction(result)
        let colors = GraduationRing.gradientHexes(for: stage).map { Color(hex: $0) }
        let aura = GraduationRing.auraIntensity(day: day, finished: finished)
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let line = max(18, side * 0.085)
            ZStack {
                if aura > 0 {
                    // A still glow that strengthens toward day 90. Nothing here animates continuously.
                    Circle()
                        .stroke(Color(hex: "#F6D98A").opacity(0.20 + 0.50 * aura), lineWidth: line * (1.1 + 0.9 * aura))
                        .blur(radius: 10 + 18 * aura)
                        .padding(line / 2)
                }
                Circle().stroke(stage.color.opacity(theme.isDark ? 0.14 : 0.18), lineWidth: line).padding(line / 2)
                Circle()
                    .trim(from: 0, to: max(0.0001, shown))
                    .stroke(AngularGradient(colors: colors + [colors[0]], center: .center, startAngle: .degrees(0), endAngle: .degrees(360)),
                            style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: .black.opacity(theme.isDark ? 0.35 : 0.12), radius: 3, y: 2)
                    .padding(line / 2)
                    .opacity(shown > 0 ? 1 : 0)
                // The graduation line at 80%.
                Capsule()
                    .fill(theme.text.opacity(0.75))
                    .frame(width: 2, height: line + 8)
                    .offset(y: -(side / 2 - line / 2))
                    .rotationEffect(.degrees(360 * GraduationRing.thresholdFraction))
                VStack(spacing: 4) {
                    Text("\(result.percent)%")
                        .font(SummaFont.serif(side * 0.26, relativeTo: .largeTitle))
                        .minimumScaleFactor(0.5).lineLimit(1)
                        .contentTransition(.numericText())
                    Text("GRADUATION PROGRESS").font(.caption.weight(.semibold)).tracking(2).foregroundStyle(theme.muted)
                    Text("\(result.completed) of \(result.scheduled) scheduled activities")
                        .font(.footnote).foregroundStyle(theme.muted)
                    Text("\(Graduation.threshold)% graduates").font(.caption).foregroundStyle(stage.color)
                }
                .padding(.horizontal, line * 1.6)
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: 380)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12).padding(.horizontal, 8)
        .onAppear { fill(to: fraction) }
        .onChange(of: fraction) { _, value in fill(to: value) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Graduation progress")
        .accessibilityValue("\(result.percent) percent. \(result.completed) of \(result.scheduled) scheduled activities completed across 90 days. \(Graduation.threshold) percent is needed to graduate.")
        .accessibilityIdentifier("graduation.ring")
    }

    private func fill(to value: Double) {
        if reduceMotion { shown = value } else { withAnimation(.easeOut(duration: 0.9)) { shown = value } }
    }
}
