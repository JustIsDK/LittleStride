import SwiftUI
import PhotosUI

struct QuestionEditorView: View {
    @Environment(LearningStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var question: Question
    @State private var knowledge: String
    private let editing: Bool
    init(existing: Question? = nil, ai: AIQuestion? = nil, parent: Question? = nil, imageID: UUID? = nil) {
        editing = existing != nil
        if let existing { _question = State(initialValue: existing); _knowledge = State(initialValue: "") }
        else if let ai {
            let q = Question(subject: Subject(rawValue: ai.subject) ?? parent?.subject ?? .math, text: ai.text, answer: ai.answer, explanation: parent == nil ? "" : ai.observation, originalAnswer: ai.studentAnswer, source: parent == nil ? "AI 图片分析（待核实）" : "AI 同类题", imageID: imageID, parentID: parent?.id, weaknessID: parent?.weaknessID, evidence: parent == nil ? ai.observation : "", possibleCause: ai.possibleCause, screening: parent == nil ? "待核实" : "生成练习")
            _question = State(initialValue: q); _knowledge = State(initialValue: ai.knowledge)
        } else { _question = State(initialValue: Question(subject: .math, text: "", answer: "")); _knowledge = State(initialValue: "") }
    }
    var body: some View {
        Form {
            Section("题目") {
                Picker("学科", selection: $question.subject) { ForEach(Subject.allCases) { Text($0.rawValue).tag($0) } }
                TextField("完整题目", text: $question.text, axis: .vertical).lineLimit(3...10)
                TextField("答案", text: $question.answer, axis: .vertical)
                TextField("解析（家长用）", text: $question.explanation, axis: .vertical)
                TextField("具体知识点", text: $knowledge)
            }
            Section("来源与证据") {
                TextField("来源 / 页码 / 题号", text: $question.source)
                TextField("孩子原始作答", text: $question.originalAnswer, axis: .vertical)
                TextField("可观察事实", text: $question.evidence, axis: .vertical)
                TextField("可能原因（未经确认）", text: $question.possibleCause, axis: .vertical)
            }
            Section("筛选确认") {
                Toggle("仍需核实，不安排练习", isOn: $question.needsVerification)
                Picker("处理", selection: $question.screening) { ForEach(["待核实", "收录", "观察", "不纳入", "生成练习"], id: \.self) { Text($0) } }
                Text("确认入库只代表材料已核对，不代表孩子已经掌握。来源不明、看不清的题目请保留待核实。").font(.caption).foregroundStyle(.secondary)
            }
            Button("保存题目") {
                guard !question.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { store.error = "请填写题目。"; return }
                if !question.needsVerification && question.answer.isEmpty { store.error = "确认练习前请补充答案。"; return }
                if question.needsVerification { question.screening = "待核实" }
                if editing, let index = store.data.questions.firstIndex(where: { $0.id == question.id }) {
                    if !knowledge.isEmpty, store.weakness(question.weaknessID)?.title != knowledge {
                        if let matched = store.data.weaknesses.first(where: { $0.title == knowledge && $0.subject == question.subject }) { question.weaknessID = matched.id }
                        else { let new = Weakness(subject: question.subject, title: knowledge); store.data.weaknesses.append(new); question.weaknessID = new.id }
                    }
                    store.data.questions[index] = question; store.save()
                } else { store.add(question, knowledge: knowledge) }
                dismiss()
            }.disabled(question.text.isEmpty)
        }.navigationTitle(editing ? "核实与修改" : "录入题目")
        .onChange(of: question.needsVerification) {
            if !question.needsVerification && question.screening == "待核实" { question.screening = question.parentID == nil ? "收录" : "生成练习" }
        }
        .onAppear { if editing, let w = store.weakness(question.weaknessID) { knowledge = w.title } }
    }
}
struct CaptureView: View {
    @Environment(LearningStore.self) private var store
    @State private var mode = "作业入库"
    @State private var picker: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var camera = false
    @State private var busy = false
    @State private var results: [AIQuestion] = []
    @State private var imageID: UUID?
    @State private var textbook: TextbookAnalysis?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("把学习过程留下来").font(.largeTitle.bold())
                Picker("用途", selection: $mode) { ForEach(["作业入库", "教材与进度", "练习回录"], id: \.self) { Text($0) } }.pickerStyle(.segmented)
                if mode == "练习回录" {
                    Text("选择已生成的练习单，再拍照核对作答。").foregroundStyle(.secondary)
                    ForEach(store.data.sheets.sorted { $0.createdAt > $1.createdAt }) { sheet in
                        NavigationLink(destination: RecordSheetView(sheetID: sheet.id)) { StrideCard { Text(sheet.code).font(.headline); Text("\(sheet.questions.count) 题 · \(sheet.completed ? "已记录" : "待回录")") } }
                    }
                    if store.data.sheets.isEmpty { Text("先从今日计划生成练习单。").foregroundStyle(.secondary) }
                } else {
                    StrideCard {
                        if let image { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 260) }
                        else { Image(systemName: "camera.viewfinder").font(.system(size: 50)).foregroundStyle(StrideStyle.green).frame(maxWidth: .infinity).padding(25) }
                        HStack {
                            Button("拍照") { if UIImagePickerController.isSourceTypeAvailable(.camera) { camera = true } else { store.error = "此设备没有可用相机，请从相册选择。" } }.buttonStyle(.bordered)
                            PhotosPicker(selection: $picker, matching: .images) { Label("相册", systemImage: "photo") }.buttonStyle(.bordered)
                        }
                        Text(mode == "教材与进度" ? "可拍封面、版权页、目录或当前学习页。每次分析一张，确认后补充档案。" : "拍完整题干、作答和批改痕迹。看不清的内容不会自动确认。").font(.caption).foregroundStyle(.secondary)
                    }
                    NavigationLink("AI 配置与连接检查", destination: AISettingsView())
                    Button(busy ? "分析中…" : "发送照片并分析") { Task { await analyze() } }.buttonStyle(.borderedProminent).disabled(image == nil || busy)
                    Text("仅在点击分析后，照片发送至你配置的服务。失败保留照片，可重试。").font(.caption).foregroundStyle(.secondary)
                    ForEach(Array(results.enumerated()), id: \.offset) { _, q in NavigationLink(destination: QuestionEditorView(ai: q, imageID: imageID)) { StrideCard { Tag(text: q.subject); Text(q.text); Text(q.observation).font(.caption).foregroundStyle(.secondary); Text("核对并入库 →") } } }
                    if let textbook { NavigationLink("核对教材信息并填写档案", destination: TextbookConfirmView(analysis: textbook)) }
                    if mode == "作业入库" { NavigationLink("不用 AI，手动录入题目", destination: QuestionEditorView()) }
                }
            }.padding(20)
        }.background(StrideStyle.background).navigationTitle("拍照录入").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $camera) { CameraPicker { image = $0; results = []; textbook = nil; imageID = nil } }
        .onChange(of: picker) { Task { if let bytes = try? await picker?.loadTransferable(type: Data.self), let selected = UIImage(data: bytes) { image = selected; results = []; textbook = nil; imageID = nil } } }
        .onChange(of: mode) { results = []; textbook = nil }
    }
    private func analyze() async {
        guard let bytes = image?.resizedJPEG() else { return }
        busy = true; defer { busy = false }
        if imageID == nil { imageID = store.addPhoto(bytes) }
        do {
            let service = AIService(configuration: store.data.ai)
            if mode == "教材与进度" { textbook = try await service.textbook(image: bytes) }
            else { let response = try await service.analyze(image: bytes, profile: store.data.profile); results = response.questions.filter { !$0.text.isEmpty && Subject(rawValue: $0.subject) != nil && ["错误", "部分正确", "待核实"].contains($0.status) }; if results.isEmpty { store.notice = "未识别出可收录的错误题目，未新增题量。" } }
        } catch { store.error = error.localizedDescription }
    }
}
extension UIImage {
    func resizedJPEG() -> Data? {
        let scale = min(1, 1800 / max(size.width, size.height))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let image = UIGraphicsImageRenderer(size: target).image { _ in draw(in: CGRect(origin: .zero, size: target)) }
        return image.jpegData(compressionQuality: 0.8)
    }
}
struct TextbookConfirmView: View {
    @Environment(LearningStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var analysis: TextbookAnalysis
    @State private var subject: Subject
    init(analysis: TextbookAnalysis) { _analysis = State(initialValue: analysis); _subject = State(initialValue: Subject(rawValue: analysis.subject) ?? .math) }
    var body: some View {
        Form {
            Section("按照片核对") {
                Picker("学科", selection: $subject) { ForEach(Subject.allCases) { Text($0.rawValue).tag($0) } }
                TextField("书名", text: $analysis.title); TextField("出版社", text: $analysis.publisher); TextField("版本", text: $analysis.edition); TextField("年级", text: $analysis.grade); TextField("册次 / 学期", text: $analysis.term)
                TextField("当前可见章节 / 页码", text: $analysis.progress)
                Text(analysis.uncertainty).foregroundStyle(.secondary)
                Text("拍到某页不等于前面已学完或已掌握；未知内容可留空。").font(.caption)
            }
            Button("确认并更新教材档案") {
                let parts = [analysis.title, analysis.publisher, analysis.edition, analysis.grade, analysis.term].filter { !$0.isEmpty }
                if !parts.isEmpty { store.data.profile.textbooks[subject.rawValue] = parts.joined(separator: " · ") }
                if !analysis.progress.isEmpty { store.data.profile.progress[subject.rawValue] = analysis.progress }
                store.save(); dismiss()
            }
        }.navigationTitle("教材识别确认")
    }
}
