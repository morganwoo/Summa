import SwiftUI
import SwiftData
import SummaCore

/// Friends: leaderboard, activity, and friend management. Part of Summa Pro.
struct FriendsView: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var clock: TodayClock
    @ObservedObject private var backend = Backend.shared
    let plan: Plan

    @State private var paywall: PaywallContext? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow("Friends")
                    Text("Kept together.").font(SummaFont.serif(36, relativeTo: .largeTitle)).accessibilityAddTraits(.isHeader)
                }
                if !store.isPro {
                    locked
                } else if backend.config == nil {
                    notice("Friends is not connected in this build.",
                           "The social backend has not been configured yet. Your own tracking is unaffected.")
                } else if !backend.isSignedIn {
                    SignInCard()
                } else {
                    FriendsHome(plan: plan)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 90)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            // Opening Friends on a free account is the request that shows the subscription page.
            if !store.isPro { paywall = .friends }
        }
        .sheet(item: $paywall) { SummaProView(context: $0).environment(\.theme, theme) }
    }

    private var locked: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Friends is part of Summa Pro.").font(SummaFont.serif(24, relativeTo: .title3))
            Text("See friends’ shared heatmaps, a weekly leaderboard, and send a supportive nudge. You choose what is shared.")
                .font(.subheadline).foregroundStyle(theme.muted)
            Button("See Summa Pro") { paywall = .friends }
                .buttonStyle(.summaPrimary)
                .accessibilityIdentifier("friends.unlock")
        }
        .card()
        .accessibilityIdentifier("friends.locked")
    }

    private func notice(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Text(detail).font(.footnote).foregroundStyle(theme.muted)
        }
        .card()
    }
}

/// Sign in with a one-time code sent by email.
private struct SignInCard: View {
    @Environment(\.theme) private var theme
    @ObservedObject private var backend = Backend.shared
    @State private var email = ""
    @State private var code = ""
    @State private var codeSent = false
    @State private var working = false
    @State private var message: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sign in to add friends").font(SummaFont.serif(24, relativeTo: .title3))
            Text("An account is needed only for Friends. Your tracking stays on this device and works without one. Onboarding answers and photos are never uploaded.")
                .font(.footnote).foregroundStyle(theme.muted)
            field("Email", text: $email, id: "signin.email")
                .keyboardType(.emailAddress).textContentType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
            if codeSent {
                field("6-digit code from the email", text: $code, id: "signin.code")
                    .keyboardType(.numberPad).textContentType(.oneTimeCode)
            }
            if let message { Text(message).font(.footnote).foregroundStyle(theme.muted) }
            Button(codeSent ? "Sign in" : "Email me a code") { submit() }
                .buttonStyle(.summaPrimary)
                .disabled(working || !email.contains("@") || (codeSent && code.trimmed.count < 6))
                .accessibilityIdentifier("signin.submit")
            if codeSent {
                Button("Use a different email") { codeSent = false; code = ""; message = nil }
                    .font(.footnote.weight(.semibold)).foregroundStyle(theme.gold).frame(minHeight: 44)
            }
        }
        .card()
    }

    private func field(_ placeholder: String, text: Binding<String>, id: String) -> some View {
        TextField(placeholder, text: text)
            .padding(.horizontal, 14).frame(minHeight: 48)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(theme.divider))
            .accessibilityIdentifier(id)
    }

    private func submit() {
        working = true
        message = nil
        Task { @MainActor in
            defer { working = false }
            do {
                if codeSent {
                    try await backend.verify(email: email, code: code)
                } else {
                    try await backend.requestCode(email: email)
                    codeSent = true
                    message = "Check your inbox for a code."
                }
            } catch {
                message = codeSent && !(error is Backend.Failure) ? "That code did not work. Try again."
                    : ((error as? LocalizedError)?.errorDescription ?? "That did not work. Try again.")
            }
        }
    }
}

private struct FriendsHome: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var clock: TodayClock
    @ObservedObject private var backend = Backend.shared
    let plan: Plan

    @State private var section = 0
    @State private var sort: Leaderboard.Sort = .completed
    @State private var board: [LeaderboardEntry] = []
    @State private var friends: [FriendRow] = []
    @State private var feed: [ActivityRow] = []
    @State private var nudges: [NudgeRow] = []
    @State private var hits: [UserHit] = []
    @State private var query = ""
    @State private var status: String? = nil
    @State private var loading = false
    @State private var needsUsername = false
    @State private var newUsername = ""
    @State private var viewing: LeaderboardEntry? = nil
    @State private var showAccount = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(backend.username.map { "@\($0)" } ?? "Signed in").font(.footnote).foregroundStyle(theme.muted)
                Spacer()
                Button { showAccount = true } label: { Label("Privacy and account", systemImage: "lock.shield") }
                    .font(.footnote.weight(.semibold)).foregroundStyle(theme.gold).frame(minHeight: 44)
                    .accessibilityIdentifier("friends.account")
            }
            if needsUsername { usernameCard }
            Picker("Section", selection: $section) {
                Text("Leaderboard").tag(0)
                Text("Activity").tag(1)
                Text("Friends").tag(2)
            }
            .pickerStyle(.segmented)
            if let status {
                HStack(alignment: .firstTextBaseline) {
                    Text(status).font(.footnote).foregroundStyle(theme.muted)
                    Spacer()
                    Button("Retry") { Task { await load() } }.font(.footnote.weight(.semibold)).foregroundStyle(theme.gold)
                }
                .card(padding: 14)
            }
            if loading && board.isEmpty { ProgressView().frame(maxWidth: .infinity) }
            switch section {
            case 0: leaderboard
            case 1: activity
            default: friendsList
            }
        }
        .task { await load() }
        .sheet(item: $viewing) { entry in
            FriendHeatmapSheet(entry: entry).environment(\.theme, theme)
        }
        .sheet(isPresented: $showAccount, onDismiss: { Task { await load() } }) {
            SocialAccountSheet(plan: plan).environment(\.theme, theme)
        }
    }

    // MARK: Loading

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            do {
                try await backend.sync(plan: plan, today: clock.today)
                needsUsername = false
            } catch Backend.Failure.usernameTaken {
                needsUsername = true
            } catch Backend.Failure.server(_) where UsernameRule.problem(with: backend.username ?? plan.username) != nil {
                needsUsername = true
            }
            board = try await backend.fetch("leaderboard", ["week_start": Leaderboard.weekStart(for: clock.today).string])
            friends = try await backend.fetch("friends_overview")
            feed = try await backend.fetch("activity_feed")
            nudges = try await backend.fetch("my_nudges")
            status = nil
        } catch {
            status = (error as? LocalizedError)?.errorDescription ?? "Could not load friends."
        }
    }

    private func act(_ function: String, _ arguments: [String: Any], done: String? = nil) {
        Task { @MainActor in
            do {
                try await backend.call(function, arguments)
                if let done { status = done }
                await load()
                if let done { status = done }
            } catch {
                status = (error as? LocalizedError)?.errorDescription ?? "That did not work."
            }
        }
    }

    private func nudge(_ userID: UUID, _ name: String, _ message: NudgeMessage) {
        Task { @MainActor in
            do {
                let sent: Bool = try await backend.fetch("send_nudge", ["target": userID.uuidString, "p_message_key": message.rawValue])
                status = sent ? "Nudge sent to @\(name)." : "You have already nudged @\(name) today, or they have nudges muted."
                if sent { Haptics.select() }
            } catch {
                status = (error as? LocalizedError)?.errorDescription ?? "That did not work."
            }
        }
    }

    // MARK: Sections

    private var usernameCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Choose a username").font(.headline)
            Text("Yours is taken or not set. Friends find you by it.").font(.footnote).foregroundStyle(theme.muted)
            TextField("username", text: $newUsername)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .padding(.horizontal, 14).frame(minHeight: 48)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(theme.divider))
            UsernameStatus(text: newUsername)
            Button("Save username") {
                Task { @MainActor in
                    do {
                        try await backend.saveProfile(username: newUsername, plan: plan)
                        needsUsername = false
                        await load()
                    } catch {
                        status = (error as? LocalizedError)?.errorDescription ?? "That did not work."
                    }
                }
            }
            .buttonStyle(.summaPrimary)
            .disabled(UsernameRule.problem(with: newUsername) != nil)
        }
        .card()
    }

    @ViewBuilder
    private var leaderboard: some View {
        Picker("Sort", selection: $sort) {
            Text("Completed").tag(Leaderboard.Sort.completed)
            Text("Consistency").tag(Leaderboard.Sort.consistency)
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Sort leaderboard")
        let ranked = Leaderboard.ranked(board, by: sort)
        if ranked.count <= 1 {
            Text("Add a friend to compare this week. Only friends who accept and share their heatmap appear here.")
                .font(.footnote).foregroundStyle(theme.muted).card()
        }
        ForEach(Array(ranked.enumerated()), id: \.element.id) { index, entry in
            HStack(spacing: 12) {
                Text("\(index + 1)").font(SummaFont.serif(26, relativeTo: .title2)).frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.isMe ? "@\(entry.username) · you" : "@\(entry.username)").font(.headline)
                    Text("\(entry.weekCompleted) done this week" + (entry.weekPercent.map { " · \($0)%" } ?? ""))
                        .font(.footnote).foregroundStyle(theme.muted)
                    if let day = entry.dayNumber(today: clock.today) {
                        HStack(spacing: 5) {
                            Circle().fill(Stage.forDay(day).color).frame(width: 7, height: 7)
                            Text("Day \(day) · \(Stage.forDay(day).name)").font(.caption).foregroundStyle(theme.muted)
                        }
                    }
                }
                Spacer()
                if !entry.isMe {
                    Menu {
                        Button("View heatmap") { viewing = entry }
                        ForEach(NudgeMessage.allCases, id: \.self) { message in
                            Button("Nudge: \(message.text)") { nudge(entry.userId, entry.username, message) }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle").font(.title3).foregroundStyle(theme.gold).frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Actions for \(entry.username)")
                }
            }
            .card(padding: 14)
            .accessibilityElement(children: .contain)
        }
        Text("Ranked by activities completed since Monday. The percentage is completed ÷ scheduled, so a lighter schedule is not a disadvantage.")
            .font(.caption).foregroundStyle(theme.muted)
    }

    @ViewBuilder
    private var activity: some View {
        if !nudges.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow("Nudges for you", color: theme.gold)
                ForEach(Array(nudges.enumerated()), id: \.offset) { _, row in
                    Text("@\(row.fromUsername): \(NudgeMessage(rawValue: row.messageKey)?.text ?? "A supportive nudge.")").font(.subheadline)
                }
            }
            .card()
        }
        if feed.isEmpty {
            Text("Milestones from you and your friends appear here: finished weeks, new stages, day 90, and graduation.")
                .font(.footnote).foregroundStyle(theme.muted).card()
        }
        ForEach(Array(feed.enumerated()), id: \.offset) { _, row in
            HStack(spacing: 10) {
                Image(systemName: "laurel.leading").foregroundStyle(theme.gold)
                Text("@\(row.username) \(ActivityEvent.describe(kind: row.kind, detail: row.detail))").font(.subheadline)
                Spacer()
            }
            .card(padding: 14)
        }
    }

    @ViewBuilder
    private var friendsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow("Find by username")
            HStack(spacing: 10) {
                TextField("username", text: $query)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.search)
                    .onSubmit { search() }
                    .padding(.horizontal, 14).frame(minHeight: 48)
                    .background(theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(theme.divider))
                    .accessibilityIdentifier("friends.search")
                Button("Search") { search() }
                    .font(.subheadline.weight(.semibold)).foregroundStyle(theme.gold).frame(minHeight: 44)
                    .disabled(query.trimmed.count < 3)
            }
            ForEach(hits) { hit in
                HStack {
                    Text("@\(hit.username)").font(.subheadline)
                    Spacer()
                    Button("Add") { act("request_friend", ["target": hit.userId.uuidString], done: "Request sent to @\(hit.username).") }
                        .font(.subheadline.weight(.semibold)).foregroundStyle(theme.gold).frame(minHeight: 44)
                }
            }
        }
        .card()
        group("Requests", "incoming") { row in
            Button("Accept") { act("respond_friend", ["from_user": row.userId.uuidString, "accept": true]) }
            Button("Decline") { act("respond_friend", ["from_user": row.userId.uuidString, "accept": false]) }
        }
        group("Friends", "friend") { row in
            Button("Remove") { act("remove_friend", ["other": row.userId.uuidString]) }
            Button("Block", role: .destructive) { act("block_user", ["other": row.userId.uuidString]) }
        }
        group("Sent", "outgoing") { row in
            Button("Cancel request") { act("remove_friend", ["other": row.userId.uuidString]) }
        }
        group("Blocked", "blocked") { row in
            Button("Unblock") { act("unblock_user", ["other": row.userId.uuidString]) }
        }
        if friends.isEmpty {
            Text("No friends yet. A request must be accepted before either of you can see the other’s progress.")
                .font(.footnote).foregroundStyle(theme.muted)
        }
    }

    @ViewBuilder
    private func group<Actions: View>(_ title: String, _ relation: String, @ViewBuilder actions: @escaping (FriendRow) -> Actions) -> some View {
        let rows = friends.filter { $0.relation == relation }
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Eyebrow(title)
                ForEach(rows) { row in
                    HStack {
                        Text("@\(row.username)").font(.subheadline)
                        Spacer()
                        Menu { actions(row) } label: {
                            Image(systemName: "ellipsis.circle").font(.title3).foregroundStyle(theme.gold).frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Actions for \(row.username)")
                    }
                }
            }
            .card()
        }
    }

    private func search() {
        guard query.trimmed.count >= 3 else { return }
        Task { @MainActor in
            do {
                hits = try await backend.fetch("search_users", ["q": query.trimmed])
                status = hits.isEmpty ? "No one found with that username." : nil
            } catch {
                status = (error as? LocalizedError)?.errorDescription ?? "Search did not work."
            }
        }
    }
}

/// A friend's shared habits over their 90 days. Shows only what they chose to share.
private struct FriendHeatmapSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var clock: TodayClock
    let entry: LeaderboardEntry
    @State private var rows: [HeatmapRow] = []
    @State private var message: String? = "Loading"

    var body: some View {
        let start = entry.planStart.flatMap { DayKey($0) }
        let today = clock.today
        let habits = Dictionary(grouping: rows, by: { $0.habitId }).values.sorted { ($0.first?.title ?? "") < ($1.first?.title ?? "") }
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("@\(entry.username)").font(SummaFont.serif(34, relativeTo: .largeTitle)).accessibilityAddTraits(.isHeader)
                    if let day = entry.dayNumber(today: clock.today) {
                        HStack(spacing: 6) {
                            Circle().fill(Stage.forDay(day).color).frame(width: 8, height: 8)
                            Text("Day \(day) · \(Stage.forDay(day).name)").font(.subheadline)
                        }
                    }
                    if entry.totalScheduled > 0 {
                        Text("\(Int((Double(entry.totalCompleted) / Double(entry.totalScheduled) * 100).rounded()))% complete · \(entry.totalCompleted) of \(entry.totalScheduled)")
                            .font(.footnote).foregroundStyle(theme.muted)
                    }
                    if let message { Text(message).font(.footnote).foregroundStyle(theme.muted) }
                    ForEach(Array(habits.enumerated()), id: \.offset) { _, days in
                        let done = Set(days.filter { $0.done }.map { $0.day })
                        let scheduled = Set(days.map { $0.day })
                        let accent = Color.accent(days.first?.colorHex ?? "")
                        VStack(alignment: .leading, spacing: 10) {
                            Text(days.first?.title ?? "Habit").font(.headline)
                            if let start {
                                Canvas { context, size in
                                    let blanks = (start.weekday + 5) % 7
                                    let columns = CGFloat(Int((Double(blanks + 90) / 7).rounded(.up)))
                                    let cell = size.width / (columns * 1.2 - 0.2)
                                    for index in 0..<90 {
                                        let day = start.adding(index)
                                        let slot = index + blanks
                                        let rect = CGRect(x: CGFloat(slot / 7) * cell * 1.2, y: CGFloat(slot % 7) * cell * 1.2, width: cell, height: cell)
                                        let status: DayStatus = done.contains(day.string) ? .completed
                                            : (!scheduled.contains(day.string) ? (day > today ? .upcoming : .unscheduled) : (day == today ? .pending : .missed))
                                        DayCellRenderer.draw(status, in: rect, context: &context, accent: accent, theme: theme, isToday: day == today, isSelected: false)
                                    }
                                }
                                .aspectRatio(14 * 1.2 / (7 * 1.2), contentMode: .fit)
                                .accessibilityLabel("\(done.count) of \(scheduled.count) scheduled days completed")
                            }
                            Text("\(done.count) of \(scheduled.count) scheduled days").font(.footnote).foregroundStyle(theme.muted)
                        }
                        .card()
                    }
                }
                .padding(20)
            }
            .marbleBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .foregroundStyle(theme.text)
        .task {
            do {
                rows = try await Backend.shared.fetch("friend_heatmap", ["friend": entry.userId.uuidString])
                message = rows.isEmpty ? "Nothing is shared right now. They may have hidden their heatmap." : nil
            } catch {
                message = (error as? LocalizedError)?.errorDescription ?? "Could not load."
            }
        }
    }
}

/// Privacy controls, username, sign out, and account deletion.
private struct SocialAccountSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @ObservedObject private var backend = Backend.shared
    @AppStorage("summa.social.shareHeatmap") private var shareHeatmap = true
    @AppStorage("summa.social.shareActivity") private var shareActivity = true
    @AppStorage("summa.social.nudgesMuted") private var nudgesMuted = false
    let plan: Plan
    @State private var username = ""
    @State private var message: String? = nil
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        Eyebrow("What friends can see")
                        Toggle("Share my heatmap and leaderboard place", isOn: $shareHeatmap)
                        Toggle("Share my milestones in Activity", isOn: $shareActivity)
                        Toggle("Mute nudges", isOn: $nudgesMuted)
                        Text("Only friends you have accepted can see anything. Onboarding answers and photos are never shared.")
                            .font(.footnote).foregroundStyle(theme.muted)
                    }
                    .tint(theme.gold)
                    .card()

                    VStack(alignment: .leading, spacing: 10) {
                        Eyebrow("Hide a habit from friends")
                        ForEach(plan.activeHabits) { habit in
                            Toggle(habit.title, isOn: Binding(get: { habit.sharedHidden }, set: { habit.sharedHidden = $0; PlanStore.save(context, plan: plan) }))
                        }
                    }
                    .tint(theme.gold)
                    .card()

                    VStack(alignment: .leading, spacing: 10) {
                        Eyebrow("Username")
                        TextField("username", text: $username)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .padding(.horizontal, 14).frame(minHeight: 48)
                            .background(theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(theme.divider))
                        UsernameStatus(text: username)
                        Button("Save username") { run { try await backend.saveProfile(username: username, plan: plan); message = "Username saved." } }
                            .buttonStyle(.summaSecondary)
                            .disabled(UsernameRule.problem(with: username) != nil || UsernameRule.normalized(username) == backend.username)
                    }
                    .card()

                    if let message { Text(message).font(.footnote).foregroundStyle(theme.muted) }

                    VStack(alignment: .leading, spacing: 10) {
                        Eyebrow("Account")
                        if let email = backend.session?.email { Text(email).font(.footnote).foregroundStyle(theme.muted) }
                        Button("Sign out") { Task { await backend.signOut(); dismiss() } }.buttonStyle(.summaSecondary)
                        Button("Delete my account", role: .destructive) { confirmDelete = true }
                            .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                            .accessibilityIdentifier("account.delete")
                        Text("Deleting removes your profile, friendships, shared progress, and nudges from the server. Your plan and check-ins on this device are kept.")
                            .font(.footnote).foregroundStyle(theme.muted)
                    }
                    .card()
                }
                .padding(20)
            }
            .marbleBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .foregroundStyle(theme.text)
        .onAppear { username = backend.username ?? plan.username }
        .onChange(of: shareHeatmap) { _, _ in pushPrivacy() }
        .onChange(of: shareActivity) { _, _ in pushPrivacy() }
        .onChange(of: nudgesMuted) { _, _ in pushPrivacy() }
        .confirmationDialog("Delete your account?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete account", role: .destructive) { run { try await backend.deleteAccount(); dismiss() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
    }

    private func pushPrivacy() {
        run { try await backend.setPrivacy(shareHeatmap: shareHeatmap, shareActivity: shareActivity, nudgesMuted: nudgesMuted) }
    }

    private func run(_ work: @escaping @MainActor () async throws -> Void) {
        Task { @MainActor in
            do { try await work() } catch { message = (error as? LocalizedError)?.errorDescription ?? "That did not work." }
        }
    }
}
