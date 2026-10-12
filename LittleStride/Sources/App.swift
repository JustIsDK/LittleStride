import SwiftUI

@main struct LittleStrideApp: App {
    @State private var store = LearningStore()
    @AppStorage("appearance") private var appearance = "system"
    var body: some Scene {
        WindowGroup {
            RootView().environment(store).tint(StrideStyle.green).buttonStyle(StridePressStyle()).preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
        }
    }
}
enum StrideStyle {
    static func color(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1)
        })
    }
    static let green = color(0x24634c, 0x9bd2b2)
    static let ink = color(0x213d32, 0xe3eee5)
    static let background = color(0xf5f7f3, 0x161e19)
    static let surface = color(0xffffff, 0x1e2922)
    static let pale = color(0xe8f0e8, 0x263d31)
    static let line = color(0xdce4da, 0x394b3e)
    static let muted = color(0x5e6e64, 0xa9b9ad)
    static let onAccent = color(0xffffff, 0x173426)
    static let warning = color(0x89531e, 0xe1bd83)
}
struct StrideCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14) { content }
            .frame(maxWidth: .infinity, alignment: .leading).padding(20)
            .background(StrideStyle.surface, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(StrideStyle.line, lineWidth: 1))
    }
}
struct Tag: View {
    var text: String
    var body: some View {
        Text(text).font(.caption).padding(.horizontal, 9).padding(.vertical, 6)
            .background(StrideStyle.pale, in: RoundedRectangle(cornerRadius: 7)).foregroundStyle(StrideStyle.green)
    }
}
struct StrideButtonStyle: ButtonStyle {
    var secondary = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 48).padding(.horizontal, 12)
            .foregroundStyle(secondary ? StrideStyle.green : StrideStyle.onAccent)
            .background(secondary ? StrideStyle.pale : StrideStyle.green, in: RoundedRectangle(cornerRadius: 12))
            .opacity(enabled ? 1 : 0.45)
            .brightness(configuration.isPressed && enabled ? -0.08 : 0)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.95 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
            .sensoryFeedback(.impact(weight: .light), trigger: configuration.isPressed) { _, pressed in pressed && enabled }
    }
}
struct StridePressStyle: ButtonStyle {
    var fullWidth = false
    func makeBody(configuration: Configuration) -> some View {
        StridePressSurface(label: configuration.label, pressed: configuration.isPressed, fullWidth: fullWidth)
    }
}
private struct StridePressSurface<Label: View>: View {
    let label: Label
    let pressed: Bool
    let fullWidth: Bool
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var highlighted = false
    var body: some View {
        label
            .padding(.horizontal, fullWidth ? 16 : 0)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: fullWidth ? 56 : 44, alignment: .leading)
            .background(fullWidth ? (highlighted && enabled ? StrideStyle.green.opacity(0.22) : StrideStyle.pale) : Color.clear, in: RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
            .brightness(highlighted && enabled ? -0.08 : 0)
            .opacity(enabled ? (highlighted ? 0.85 : 1) : 0.45)
            .scaleEffect(highlighted && enabled && !reduceMotion ? 0.95 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: highlighted ? 0.06 : 0.2), value: highlighted)
            .onChange(of: pressed) { if pressed && enabled { highlighted = true } }
            .task(id: pressed) {
                guard !pressed else { return }
                do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
                highlighted = false
            }
            .sensoryFeedback(.impact(weight: .light), trigger: pressed) { _, down in down && enabled }
    }
}
struct AnalysisStatusDialog: View {
    let busy: Bool
    let success: Bool
    let message: String
    let started: Date
    let cancel: () -> Void
    let close: () -> Void
    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea().contentShape(Rectangle())
            VStack(spacing: 18) {
                if busy { SwiftUI.ProgressView().controlSize(.large).tint(StrideStyle.green) }
                else { Image(systemName: success ? "checkmark.circle.fill" : "exclamationmark.circle.fill").font(.system(size: 44)).foregroundStyle(success ? StrideStyle.green : StrideStyle.warning) }
                Text(busy ? "正在分析照片" : success ? "分析成功" : "分析失败").font(.title3.weight(.semibold))
                Text(message).font(.subheadline).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                if busy {
                    TimelineView(.periodic(from: started, by: 1)) { context in
                        Text("已等待 \(max(0, Int(context.date.timeIntervalSince(started)))) 秒").font(.caption).foregroundStyle(.secondary)
                    }
                    Button("取消分析", action: cancel).buttonStyle(StrideButtonStyle(secondary: true))
                } else if success {
                    Text("2 秒后自动展示结果，请核对后保存。").font(.caption).foregroundStyle(.secondary)
                } else {
                    Button("返回修改或重试", action: close).buttonStyle(StrideButtonStyle())
                }
            }.padding(26).frame(maxWidth: 340).background(StrideStyle.surface, in: RoundedRectangle(cornerRadius: 24)).padding(24)
                .accessibilityAddTraits(.isModal)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
extension View {
    func stridePage() -> some View {
        self.scrollContentBackground(.hidden).background(StrideStyle.background)
            .foregroundStyle(StrideStyle.ink)
            .toolbarBackground(StrideStyle.background, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
    }
}
struct RootView: View {
    @Environment(LearningStore.self) private var store
    @State private var tab = 0
    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { TodayView() }.id(tab).tag(0)
            NavigationStack { CaptureView() }.id(tab).tag(1)
            NavigationStack { LibraryView() }.id(tab).tag(2)
            NavigationStack { ProgressView() }.id(tab).tag(3)
        }
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: 0) {
                tabButton(0, "今日", "house")
                tabButton(1, "拍照", "camera")
                tabButton(2, "错题库", "books.vertical")
                tabButton(3, "进展", "chart.bar")
            }.padding(.horizontal, 14).padding(.vertical, 9)
                .background(StrideStyle.surface)
                .overlay(alignment: .top) { Rectangle().fill(StrideStyle.line).frame(height: 1) }
        }
        .alert("需要处理", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("知道了") { store.error = nil } } message: { Text(store.error ?? "") }
        .alert("已更新", isPresented: Binding(get: { store.notice != nil }, set: { if !$0 { store.notice = nil } })) { Button("好的") { store.notice = nil } } message: { Text(store.notice ?? "") }
    }
    private func tabButton(_ index: Int, _ title: String, _ symbol: String) -> some View {
        Button { tab = index } label: {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 20, weight: .regular))
                    .frame(width: 50, height: 28)
                    .background(tab == index ? StrideStyle.pale : .clear, in: RoundedRectangle(cornerRadius: 10))
                Text(title).font(.system(size: 10, weight: tab == index ? .semibold : .regular))
            }.frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(tab == index ? StrideStyle.green : StrideStyle.muted)
        }.buttonStyle(StridePressStyle()).accessibilityAddTraits(tab == index ? .isSelected : [])
    }
}
struct TodayView: View {
    @Environment(LearningStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("appearance") private var appearance = "system"
    @ScaledMetric(relativeTo: .largeTitle) private var durationSize = 64.0
    @State private var sheet: PracticeSheet?
    private var plan: [PlanItem] { store.plan() }
    private var minutes: Int { plan.reduce(0) { $0 + $1.minutes } }
    private var pendingCount: Int { store.data.questions.filter(\.needsVerification).count }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                introduction
                summary
                subjects
                if plan.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("暂无到期练习").font(.headline)
                        Text("从真实作业开始记录。没有到期内容时，不额外凑题。")
                            .font(.subheadline).foregroundStyle(StrideStyle.muted)
                        NavigationLink("录入学习材料", destination: CaptureView()).font(.subheadline)
                    }.padding(.vertical, 4)
                } else {
                    HStack {
                        NavigationLink("查看选题依据", destination: TodayQuestionsView())
                        Spacer()
                        Menu("来不及？延后") {
                            Button("明天最早安排") { store.deferQuestions(plan.map(\.id), days: 1) }
                            Button("后天最早安排") { store.deferQuestions(plan.map(\.id), days: 2) }
                        }
                    }.font(.caption).frame(minHeight: 44)
                }
                growth
                if pendingCount > 0 { pendingMaterials }
                utilities
                Text("每次少量练习，按自己的节奏来。延期会重新排期，不额外叠加题量。")
                    .font(.caption).foregroundStyle(StrideStyle.muted).lineSpacing(4)
            }.padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 30)
        }.background(StrideStyle.background).navigationTitle("").stridePage().navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(StrideStyle.background, for: .navigationBar)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $sheet) { s in NavigationStack { PrintSheetView(sheet: s) }.tint(StrideStyle.green) }
    }
    private var header: some View {
        HStack(spacing: 10) {
            HStack(spacing: 9) {
                Image("BrandMark").resizable().frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 9)).accessibilityHidden(true)
                Text("LittleStride").font(.system(size: 20, weight: .bold)).tracking(-0.6)
            }.foregroundStyle(StrideStyle.ink).accessibilityElement(children: .combine)
            Spacer(minLength: 3)
            Button { appearance = colorScheme == .dark ? "light" : "dark" } label: {
                Image(systemName: "circle.lefthalf.filled").foregroundStyle(StrideStyle.muted).frame(width: 40, height: 44)
            }.accessibilityLabel("切换深色或浅色外观")
            NavigationLink(destination: ProfileView()) {
                Text(String(store.data.profile.nickname.prefix(2))).font(.caption.weight(.semibold))
                    .foregroundStyle(StrideStyle.green).frame(width: 40, height: 40)
                    .background(StrideStyle.pale, in: Circle())
            }.accessibilityLabel("孩子档案")
        }.padding(.bottom, 6)
    }
    private var introduction: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(Date().formatted(.dateTime.month().day().weekday(.wide)))
                .font(.caption).foregroundStyle(StrideStyle.muted)
            Text("\(store.data.profile.nickname)，今天也走一小步。")
                .font(.system(.title, design: .default).weight(.semibold)).tracking(-0.8)
                .foregroundStyle(StrideStyle.ink).fixedSize(horizontal: false, vertical: true)
            Text("留一点时间，把学过的知识练稳。")
                .font(.subheadline).foregroundStyle(StrideStyle.muted)
        }
    }
    private var summary: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text(plan.isEmpty ? "今日待练已清空" : "今日待练计划")
                    .font(.caption.weight(.semibold)).foregroundStyle(StrideStyle.green)
                Spacer()
                Text("每日上限 \(store.data.dailyMinutes) 分钟").font(.caption).foregroundStyle(StrideStyle.muted)
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center) { duration; Spacer(minLength: 15); counts }
                VStack(alignment: .leading, spacing: 12) { duration; counts }
            }
            HStack(spacing: 10) {
                if plan.isEmpty {
                    NavigationLink("查看学习进展", destination: ProgressView()).buttonStyle(StrideButtonStyle())
                } else {
                    Button("预览并打印练习单") { sheet = store.makeSheet(plan.map(\.question)) }
                        .buttonStyle(StrideButtonStyle())
                }
                NavigationLink(destination: CaptureView(initialMode: "练习回录")) {
                    Image(systemName: "camera").font(.title3).foregroundStyle(StrideStyle.green)
                        .frame(width: 48, height: 48).background(StrideStyle.surface, in: RoundedRectangle(cornerRadius: 12))
                }.accessibilityLabel("拍照回录练习结果")
            }
        }.padding(22).background(StrideStyle.pale, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(StrideStyle.line, lineWidth: 1))
    }
    private var duration: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(String(format: "%02d", minutes)).font(.system(size: durationSize, weight: .medium)).tracking(-3).monospacedDigit()
            Text("分钟左右").font(.caption).foregroundStyle(StrideStyle.muted)
        }.foregroundStyle(StrideStyle.ink)
    }
    private var counts: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(Set(plan.map { $0.question.subject }).count) 个学科")
            Text("\(plan.count) 道练习")
        }.font(.subheadline).foregroundStyle(StrideStyle.muted)
        .padding(.leading, 18).overlay(alignment: .leading) { Rectangle().fill(StrideStyle.line).frame(width: 1) }
    }
    private var subjects: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("今天练什么").font(.headline)
                Spacer()
                NavigationLink("学科与题量 ↗", destination: PlanSettingsView()).font(.caption).frame(minHeight: 44)
            }
            VStack(spacing: 0) {
                ForEach(Array(Subject.allCases.enumerated()), id: \.element.id) { index, subject in
                    let items = plan.filter { $0.question.subject == subject }
                    HStack(spacing: 12) {
                        Text(String(subject.rawValue.prefix(1))).font(.subheadline.weight(.semibold))
                            .foregroundStyle(items.isEmpty ? StrideStyle.muted : StrideStyle.green)
                            .frame(width: 38, height: 42)
                            .background(items.isEmpty ? StrideStyle.background : StrideStyle.pale, in: RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 5) {
                            Text(subject.rawValue).font(.subheadline.weight(.semibold))
                            Text(subjectDescription(items)).font(.caption).foregroundStyle(StrideStyle.muted).lineLimit(2)
                        }
                        Spacer(minLength: 4)
                        VStack(alignment: .trailing, spacing: 5) {
                            Text(items.isEmpty ? "今日未安排" : "\(items.count) 题").font(.caption.weight(.semibold))
                            if !items.isEmpty { Text("约 \(items.reduce(0) { $0 + $1.minutes }) 分钟").font(.caption2).foregroundStyle(StrideStyle.muted) }
                        }
                    }.padding(.vertical, 18)
                    if index < Subject.allCases.count - 1 { Divider().overlay(StrideStyle.line) }
                }
            }.padding(.horizontal, 18).background(StrideStyle.surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(StrideStyle.line, lineWidth: 1))
        }
    }
    private func subjectDescription(_ items: [PlanItem]) -> String {
        if let first = items.first { return store.weakness(first.question.weaknessID)?.title ?? "校内基础回看" }
        return "按自己的节奏安排"
    }
    private var growth: some View {
        NavigationLink(destination: RewardsView()) {
            HStack(spacing: 15) {
                Image(systemName: store.data.claimedPet ? "pawprint" : "chart.bar")
                    .font(.title2).foregroundStyle(StrideStyle.green).frame(width: 58, height: 58)
                    .background(StrideStyle.pale, in: Circle())
                VStack(alignment: .leading, spacing: 7) {
                    Text(store.practiceCount >= 10 ? "十题小步 · 徽章已解锁" : "再完成 \(10 - store.practiceCount) 次，点亮第一枚徽章")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(StrideStyle.ink)
                    Text("\(store.practiceCount) 次有效练习 · \(store.points) 成长积分").font(.caption).foregroundStyle(StrideStyle.muted)
                    SwiftUI.ProgressView(value: Double(min(store.practiceCount, 10)), total: 10).tint(StrideStyle.green)
                        .accessibilityLabel("十题里程碑")
                }
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(StrideStyle.muted)
            }.padding(.vertical, 20)
                .overlay(alignment: .top) { Rectangle().fill(StrideStyle.line).frame(height: 1) }
                .overlay(alignment: .bottom) { Rectangle().fill(StrideStyle.line).frame(height: 1) }
        }.buttonStyle(StridePressStyle())
    }
    private var pendingMaterials: some View {
        NavigationLink(destination: LibraryView(initialFilter: "待核实")) {
            HStack(spacing: 12) {
                Circle().fill(StrideStyle.warning).frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(pendingCount) 项材料等你确认").font(.subheadline.weight(.semibold))
                    Text("补充一次观察，让分析更准确").font(.caption).foregroundStyle(StrideStyle.muted)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(StrideStyle.muted)
            }.padding(17).foregroundStyle(StrideStyle.ink)
                .background(StrideStyle.surface, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(StrideStyle.line, lineWidth: 1))
        }.buttonStyle(StridePressStyle())
    }
    private var utilities: some View {
        VStack(spacing: 0) {
            utility("孩子档案与能力观察", detail: store.data.profile.grade, destination: ProfileView())
            utility("AI 服务设置", detail: store.data.ai.model.isEmpty ? "待配置" : "已配置", destination: AISettingsView())
            utility("计划与提醒", detail: store.data.reminder ? String(format: "%02d:%02d", store.data.reminderHour, store.data.reminderMinute) : "已关闭", destination: SettingsView())
        }
    }
    private func utility<Destination: View>(_ title: String, detail: String, destination: Destination) -> some View {
        NavigationLink(destination: destination) {
            HStack { Text(title).foregroundStyle(StrideStyle.green); Spacer(); Text(detail).foregroundStyle(StrideStyle.muted) }
                .font(.caption).frame(minHeight: 48).overlay(alignment: .bottom) { Rectangle().fill(StrideStyle.line).frame(height: 1) }
        }.buttonStyle(StridePressStyle())
    }
}
struct TodayQuestionsView: View {
    @Environment(LearningStore.self) private var store
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                ForEach(store.plan()) { item in
                    NavigationLink(destination: QuestionDetailView(id: item.id)) {
                        StrideCard {
                            Tag(text: item.question.subject.rawValue)
                            Text(item.question.text).foregroundStyle(StrideStyle.ink)
                            Text(store.weakness(item.question.weaknessID)?.title ?? "校内基础复习").font(.caption).foregroundStyle(StrideStyle.muted)
                        }
                    }.buttonStyle(StridePressStyle())
                }
            }.padding(24)
        }.navigationTitle("今日选题依据").stridePage().stridePage()
    }
}
struct PlanSettingsView: View {
    @Environment(LearningStore.self) private var store
    var body: some View {
        @Bindable var store = store
        Form {
            Section("今天练哪几科") {
                ForEach(Subject.allCases) { subject in
                    Toggle(subject.rawValue, isOn: Binding(get: { store.data.subjects.contains(subject) }, set: { value in
                        if value { if !store.data.subjects.contains(subject) { store.data.subjects.append(subject) } }
                        else { store.data.subjects.removeAll { $0 == subject } }; store.save()
                    }))
                    if store.data.subjects.contains(subject) { Stepper("\(subject.rawValue)最多 \(store.data.counts[subject.rawValue, default: 1]) 题", value: Binding(get: { store.data.counts[subject.rawValue, default: 1] }, set: { store.data.counts[subject.rawValue] = $0; store.save() }), in: 1...3) }
                }
            }
            Section("时间与实际安排") {
                Picker("每日上限", selection: $store.data.dailyMinutes) { ForEach([5, 10], id: \.self) { Text("\($0) 分钟").tag($0) } }
                let plan = store.plan()
                Text("当前可安排：\(plan.count) 题 · 约 \(plan.reduce(0) { $0 + $1.minutes }) 分钟")
                Text("按到期时间和优先级选题；放不下的内容保留，不累加到明天。可以暂时关闭所有科目。").font(.caption).foregroundStyle(.secondary)
            }
        }.navigationTitle("学科与题量").stridePage().onChange(of: store.data.dailyMinutes) { store.save() }
    }
}
struct LibraryView: View {
    @Environment(LearningStore.self) private var store
    @State private var filter: String
    @State private var search = ""
    init(initialFilter: String = "全部") { _filter = State(initialValue: initialFilter) }
    private var questions: [Question] { store.data.questions.filter { q in (filter == "全部" || (filter == "待核实" ? q.needsVerification : q.subject.rawValue == filter)) && (search.isEmpty || q.text.localizedCaseInsensitiveContains(search)) } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("少量代表题，清楚的记录").font(.title.weight(.semibold)).tracking(-0.8)
                Text("按薄弱点归类，同类题不会重复堆积。")
                    .font(.subheadline).foregroundStyle(StrideStyle.muted)
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(StrideStyle.muted)
                    TextField("搜索题目", text: $search).submitLabel(.search)
                }.padding(14).background(StrideStyle.surface, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(StrideStyle.line, lineWidth: 1))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(["全部", "待核实", "数学", "语文", "英语"], id: \.self) { value in
                            Button { filter = value } label: {
                                Text(value).font(.caption.weight(filter == value ? .semibold : .regular))
                                    .foregroundStyle(filter == value ? StrideStyle.ink : StrideStyle.muted)
                                    .padding(.horizontal, 14).frame(minHeight: 44)
                                    .background(filter == value ? StrideStyle.surface : .clear, in: RoundedRectangle(cornerRadius: 8))
                            }.buttonStyle(StridePressStyle()).accessibilityAddTraits(filter == value ? .isSelected : [])
                        }
                    }.padding(4)
                }.background(StrideStyle.pale, in: RoundedRectangle(cornerRadius: 12))
                if questions.isEmpty {
                    StrideCard {
                        Image(systemName: "books.vertical").font(.largeTitle).foregroundStyle(StrideStyle.green)
                        Text("暂无题目").font(.headline)
                        Text("拍照分析或手动录入，记录从真实材料开始。")
                            .font(.subheadline).foregroundStyle(StrideStyle.muted)
                        NavigationLink("手动录入第一道题", destination: QuestionEditorView())
                    }
                }
                ForEach(questions) { q in
                    NavigationLink(destination: QuestionDetailView(id: q.id)) {
                        StrideCard {
                            HStack { Tag(text: q.subject.rawValue); Spacer(); Tag(text: q.needsVerification ? "待核实" : q.screening) }
                            Text(q.text).foregroundStyle(StrideStyle.ink).font(.title3).lineLimit(3)
                            if let w = store.weakness(q.weaknessID) {
                                Text(w.title).font(.caption).foregroundStyle(StrideStyle.muted)
                                Text(w.status).font(.caption).foregroundStyle(StrideStyle.green)
                            }
                        }
                    }.buttonStyle(StridePressStyle())
                }
            }.padding(24)
        }.navigationTitle("错题库").stridePage()
        .toolbar { NavigationLink(destination: QuestionEditorView()) { Image(systemName: "plus") }.accessibilityLabel("添加题目") }
    }
}
struct QuestionDetailView: View {
    @Environment(LearningStore.self) private var store
    let id: UUID
    @State private var busy = false
    @State private var generated: AIQuestion?
    var body: some View {
        ScrollView {
            if let q = store.question(id) {
                VStack(alignment: .leading, spacing: 18) {
                    StrideCard { Tag(text: q.subject.rawValue); Text(q.text).font(.title3); Text("原始作答：\(q.originalAnswer.isEmpty ? "未记录" : q.originalAnswer)"); Text("答案：\(q.answer.isEmpty ? "待核实" : q.answer)"); Text(q.explanation).foregroundStyle(.secondary) }
                    StrideCard { Text("观察事实").font(.headline); Text(q.evidence.isEmpty ? "待补充" : q.evidence); Text("可能原因（未确认）").font(.headline); Text(q.possibleCause.isEmpty ? "尚无证据，不能推断" : q.possibleCause); Text("来源：\(q.source)").font(.caption).foregroundStyle(.secondary) }
                    if let imageID = q.imageID, let asset = store.data.photos.first(where: { $0.id == imageID }), let image = UIImage(data: asset.data) { Image(uiImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 16)) }
                    if let w = store.weakness(q.weaknessID) { StrideCard { Text(w.title).font(.headline); Text("\(w.priority) · \(w.status)"); Text("下次回看：\(w.nextDate.formatted(date: .abbreviated, time: .omitted))") } }
                    NavigationLink("修改题目 / 核实信息", destination: QuestionEditorView(existing: q))
                    Button(busy ? "生成中…" : "AI 生成一道同类题") { Task { await generate(q) } }.buttonStyle(StrideButtonStyle()).disabled(busy || q.needsVerification)
                    Text("生成内容须核对后入库，不自动增加今日任务或奖励。").font(.caption).foregroundStyle(.secondary)
                    if let generated { NavigationLink("核对生成题并入库", destination: QuestionEditorView(ai: generated, parent: q)) }
                    let attempts = store.data.attempts.filter { $0.questionID == id }.sorted { $0.date > $1.date }
                    Text("作答历程").font(.headline)
                    ForEach(attempts) { a in StrideCard { Text(a.date.formatted(date: .abbreviated, time: .shortened)); Text("\(a.result) · \(a.help)"); Text(a.note); Text("理由说明：\(a.reason)").font(.caption) } }
                }.padding(20)
            }
        }.background(StrideStyle.background).navigationTitle("题目详情").stridePage()
    }
    private func generate(_ q: Question) async {
        busy = true; defer { busy = false }
        do { let result = try await AIService(configuration: store.data.ai).generate(q, profile: store.data.profile); guard let first = result.questions.first, !first.text.isEmpty, !first.answer.isEmpty else { throw ServiceFailure(message: "生成结果没有完整题目和答案。") }; generated = first }
        catch { store.error = error.localizedDescription }
    }
}
