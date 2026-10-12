import SwiftUI

@main struct LittleStrideApp: App {
    @State private var store = LearningStore()
    var body: some Scene {
        WindowGroup {
            RootView().environment(store).tint(StrideStyle.green).preferredColorScheme(.light)
        }
    }
}
enum StrideStyle {
    static let green = Color(red: 0.14, green: 0.46, blue: 0.36)
    static let ink = Color(red: 0.10, green: 0.24, blue: 0.22)
    static let background = Color(red: 0.97, green: 0.98, blue: 0.95)
}
struct StrideCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View { VStack(alignment: .leading, spacing: 14) { content }.frame(maxWidth: .infinity, alignment: .leading).padding(20).background(.white, in: RoundedRectangle(cornerRadius: 20)) }
}
struct Tag: View {
    var text: String
    var body: some View { Text(text).font(.caption).padding(.horizontal, 9).padding(.vertical, 6).background(StrideStyle.green.opacity(0.10), in: RoundedRectangle(cornerRadius: 8)).foregroundStyle(StrideStyle.green) }
}
struct RootView: View {
    @Environment(LearningStore.self) private var store
    var body: some View {
        TabView {
            NavigationStack { TodayView() }.tabItem { Label("今日", systemImage: "house") }
            NavigationStack { CaptureView() }.tabItem { Label("拍照", systemImage: "camera") }
            NavigationStack { LibraryView() }.tabItem { Label("错题库", systemImage: "books.vertical") }
            NavigationStack { ProgressView() }.tabItem { Label("进展", systemImage: "chart.bar") }
        }
        .alert("需要处理", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("知道了") { store.error = nil } } message: { Text(store.error ?? "") }
        .alert("已更新", isPresented: Binding(get: { store.notice != nil }, set: { if !$0 { store.notice = nil } })) { Button("好的") { store.notice = nil } } message: { Text(store.notice ?? "") }
    }
}
struct TodayView: View {
    @Environment(LearningStore.self) private var store
    @State private var sheet: PracticeSheet?
    private var plan: [PlanItem] { store.plan() }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("每天一点，慢慢学会。").font(.largeTitle.bold()).foregroundStyle(StrideStyle.ink)
                Text("\(store.data.profile.nickname) · \(store.data.profile.grade)").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 16) {
                    HStack { Text("今日复习计划"); Spacer(); Text("\(Set(plan.map { $0.question.subject }).count) 科 · \(plan.count) 题") }
                    Text("\(plan.reduce(0) { $0 + $1.minutes }) 分钟左右").font(.system(size: 36, weight: .semibold))
                    Text("每日上限 \(store.data.dailyMinutes) 分钟 · 最多两个薄弱点").font(.caption)
                    Button("生成练习单并打印") { sheet = store.makeSheet(plan.map(\.question)) }.buttonStyle(.borderedProminent).tint(.white).foregroundStyle(StrideStyle.ink).disabled(plan.isEmpty)
                }.padding(22).foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading).background(StrideStyle.ink, in: RoundedRectangle(cornerRadius: 22))
                StrideCard {
                    HStack { Text("今天练哪几科").font(.headline); Spacer(); NavigationLink("调整", destination: PlanSettingsView()) }
                    ForEach(Subject.allCases) { subject in
                        let items = plan.filter { $0.question.subject == subject }
                        HStack { Label(subject.rawValue, systemImage: subject.symbol); Spacer(); Text(items.isEmpty ? "未安排" : "\(items.count) 题 · \(items.reduce(0) { $0 + $1.minutes }) 分钟").font(.subheadline).foregroundStyle(.secondary) }
                    }
                }
                if plan.isEmpty {
                    StrideCard { Text("暂无到期练习").font(.headline); Text("拍照或手动添加题目，确认后按时间上限安排。没有到期内容时，不额外凑题。").foregroundStyle(.secondary); NavigationLink("录入学习材料", destination: CaptureView()) }
                } else {
                    ForEach(plan) { item in
                        StrideCard {
                            HStack { Tag(text: item.question.subject.rawValue); Spacer(); Text("约 \(item.minutes) 分钟").font(.caption).foregroundStyle(.secondary) }
                            NavigationLink(destination: QuestionDetailView(id: item.id)) { Text(item.question.text).foregroundStyle(StrideStyle.ink).frame(maxWidth: .infinity, alignment: .leading) }
                            if let w = store.weakness(item.question.weaknessID) { Text(w.title).font(.caption).foregroundStyle(.secondary) }
                            Menu("来不及？延后") { Button("明天最早安排") { store.deferQuestions([item.id], days: 1) }; Button("后天最早安排") { store.deferQuestions([item.id], days: 2) } }
                        }
                    }
                }
                StrideCard { HStack { Text("成长奖励").font(.headline); Spacer(); Text("🌱").font(.largeTitle) }; Text("累计 \(store.practiceCount) 次有效练习 · \(store.points) 积分"); NavigationLink("查看徽章与小伙伴", destination: RewardsView()) }
                if store.data.questions.contains(where: \.needsVerification) { NavigationLink("待核实题目 \(store.data.questions.filter(\.needsVerification).count) 项", destination: LibraryView(initialFilter: "待核实")) }
                NavigationLink("孩子档案与能力观察", destination: ProfileView())
                NavigationLink("AI 服务与数据设置", destination: SettingsView())
            }.padding(20)
        }.background(StrideStyle.background).navigationTitle("LittleStride").navigationBarTitleDisplayMode(.inline)
        .toolbar { NavigationLink(destination: ProfileView()) { Image(systemName: "person.crop.circle") } }
        .sheet(item: $sheet) { s in NavigationStack { PrintSheetView(sheet: s) } }
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
        }.navigationTitle("学科与题量").onChange(of: store.data.dailyMinutes) { store.save() }
    }
}
struct LibraryView: View {
    @Environment(LearningStore.self) private var store
    @State private var filter: String
    @State private var search = ""
    init(initialFilter: String = "全部") { _filter = State(initialValue: initialFilter) }
    private var questions: [Question] { store.data.questions.filter { q in (filter == "全部" || (filter == "待核实" ? q.needsVerification : q.subject.rawValue == filter)) && (search.isEmpty || q.text.localizedCaseInsensitiveContains(search)) } }
    var body: some View {
        List {
            Picker("分类", selection: $filter) { ForEach(["全部", "待核实", "数学", "语文", "英语"], id: \.self) { Text($0) } }.pickerStyle(.menu)
            if questions.isEmpty { ContentUnavailableView("暂无题目", systemImage: "books.vertical", description: Text("拍照分析或手动录入，记录从真实材料开始。")) }
            ForEach(questions) { q in
                NavigationLink(destination: QuestionDetailView(id: q.id)) {
                    VStack(alignment: .leading, spacing: 8) { HStack { Tag(text: q.subject.rawValue); Tag(text: q.needsVerification ? "待核实" : q.screening) }; Text(q.text).lineLimit(3); if let w = store.weakness(q.weaknessID) { Text(w.title).font(.caption).foregroundStyle(.secondary) } }
                }
            }
        }.navigationTitle("错题库").searchable(text: $search, prompt: "搜索题目")
        .toolbar { NavigationLink(destination: QuestionEditorView()) { Image(systemName: "plus") } }
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
                    Button(busy ? "生成中…" : "AI 生成一道同类题") { Task { await generate(q) } }.buttonStyle(.borderedProminent).disabled(busy || q.needsVerification)
                    Text("生成内容须核对后入库，不自动增加今日任务或奖励。").font(.caption).foregroundStyle(.secondary)
                    if let generated { NavigationLink("核对生成题并入库", destination: QuestionEditorView(ai: generated, parent: q)) }
                    let attempts = store.data.attempts.filter { $0.questionID == id }.sorted { $0.date > $1.date }
                    Text("作答历程").font(.headline)
                    ForEach(attempts) { a in StrideCard { Text(a.date.formatted(date: .abbreviated, time: .shortened)); Text("\(a.result) · \(a.help)"); Text(a.note); Text("理由说明：\(a.reason)").font(.caption) } }
                }.padding(20)
            }
        }.background(StrideStyle.background).navigationTitle("题目详情")
    }
    private func generate(_ q: Question) async {
        busy = true; defer { busy = false }
        do { let result = try await AIService(configuration: store.data.ai).generate(q, profile: store.data.profile); guard let first = result.questions.first, !first.text.isEmpty, !first.answer.isEmpty else { throw ServiceFailure(message: "生成结果没有完整题目和答案。") }; generated = first }
        catch { store.error = error.localizedDescription }
    }
}
