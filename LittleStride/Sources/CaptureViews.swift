import SwiftUI
import PhotosUI
import ImageIO

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
        }.navigationTitle(editing ? "核实与修改" : "录入题目").stridePage()
        .onChange(of: question.needsVerification) {
            if !question.needsVerification && question.screening == "待核实" { question.screening = question.parentID == nil ? "收录" : "生成练习" }
        }
        .onAppear { if editing, let w = store.weakness(question.weaknessID) { knowledge = w.title } }
    }
}
struct CaptureView: View {
    @Environment(LearningStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var mode: String
    init(initialMode: String = "作业入库") { _mode = State(initialValue: initialMode) }
    @State private var picker: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var imageBytes: Data?
    @State private var preparing = false
    @State private var photoRevision = UUID()
    @State private var camera = false
    @State private var busy = false
    @State private var analysisTask: Task<Void, Never>?
    @State private var analysisStage = ""
    @State private var analysisStarted = Date()
    @State private var analysisFinished = false
    @State private var analysisSummary = ""
    @State private var confirmRetry = false
    @State private var analysisDialog = false
    @State private var analysisError: String?
    @State private var results: [AIQuestion] = []
    @State private var imageID: UUID?
    @State private var textbook: TextbookAnalysis?
    var body: some View {
        ScrollViewReader { proxy in ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("把学习过程留下来").font(.title.weight(.semibold))
                Picker("用途", selection: $mode) { ForEach(["作业入库", "教材与进度", "练习回录"], id: \.self) { Text($0) } }.pickerStyle(.segmented).disabled(busy || preparing)
                if mode == "练习回录" {
                    Text("选择已生成的练习单，再拍照核对作答。").foregroundStyle(.secondary)
                    ForEach(store.data.sheets.sorted { $0.createdAt > $1.createdAt }) { sheet in
                        NavigationLink(destination: RecordSheetView(sheetID: sheet.id)) { StrideCard { Text(sheet.code).font(.headline); Text("\(sheet.questions.count) 题 · \(sheet.completed ? "已记录" : "待回录")") } }
                    }
                    if store.data.sheets.isEmpty { Text("先从今日计划生成练习单。").foregroundStyle(.secondary) }
                } else {
                    StrideCard {
                        if let image { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 260) }
                        else if preparing { SwiftUI.ProgressView("正在准备照片…").frame(maxWidth: .infinity).padding(25) }
                        else { Image(systemName: "camera.viewfinder").font(.system(size: 50)).foregroundStyle(StrideStyle.green).frame(maxWidth: .infinity).padding(25) }
                        HStack {
                            Button("拍照") { if UIImagePickerController.isSourceTypeAvailable(.camera) { camera = true } else { store.error = "此设备没有可用相机，请从相册选择。" } }.buttonStyle(StrideButtonStyle(secondary: true))
                            PhotosPicker(selection: $picker, matching: .images) { Label("相册", systemImage: "photo") }.buttonStyle(StrideButtonStyle(secondary: true))
                        }.disabled(busy || preparing)
                        Text(mode == "教材与进度" ? "可拍封面、版权页、目录或当前学习页。每次分析一张，确认后补充档案。" : "拍完整题干、作答和批改痕迹。看不清的内容不会自动确认。").font(.caption).foregroundStyle(.secondary)
                    }
                    NavigationLink("AI 配置与连接检查", destination: AISettingsView())
                    Button(busy ? "分析中…" : analysisFinished ? "已分析完成 · 请核对下方结果" : "发送照片并分析") { startAnalysis() }.buttonStyle(StrideButtonStyle()).disabled(imageBytes == nil || busy || preparing || analysisFinished)
                    if let imageBytes { Text("上传照片约 \(ByteCountFormatter.string(fromByteCount: Int64(imageBytes.count), countStyle: .file))，已在后台压缩。").font(.caption).foregroundStyle(.secondary) }
                    Text("仅在点击分析后，照片发送至你配置的服务。失败保留照片，可重试。").font(.caption).foregroundStyle(.secondary)
                    if analysisFinished {
                        StrideCard {
                            Label("分析完成", systemImage: "checkmark.circle.fill").font(.headline).foregroundStyle(StrideStyle.green)
                            Text(analysisSummary)
                            Text("点击下面的结果核对并保存，分析成功不等于已入库。").font(.caption).foregroundStyle(.secondary)
                            Button("重新分析这张照片") { confirmRetry = true }.font(.caption)
                        }.id("analysisResult").transition(.opacity)
                    }
                    ForEach(Array(results.enumerated()), id: \.offset) { _, q in NavigationLink(destination: QuestionEditorView(ai: q, imageID: imageID)) { StrideCard { Tag(text: q.subject); Text(q.text); Text(q.observation).font(.caption).foregroundStyle(.secondary); Text("核对并入库 →") } }.disabled(busy) }
                    if let textbook { NavigationLink("核对教材信息并填写档案", destination: TextbookConfirmView(analysis: textbook)).disabled(busy) }
                    if mode == "作业入库" { NavigationLink("不用 AI，手动录入题目", destination: QuestionEditorView()) }
                }
            }.padding(24)
        }.background(StrideStyle.background).navigationTitle("拍照录入").stridePage().navigationBarTitleDisplayMode(.inline)
            .onChange(of: analysisDialog) {
                if analysisFinished && !analysisDialog { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { proxy.scrollTo("analysisResult", anchor: .center) } }
            }
        }
        .overlay {
            if analysisDialog {
                AnalysisStatusDialog(busy: !analysisFinished && analysisError == nil, success: analysisFinished, message: analysisError ?? (analysisFinished ? analysisSummary : analysisStage), started: analysisStarted, cancel: { analysisTask?.cancel() }, close: { analysisDialog = false })
            }
        }
        .sensoryFeedback(.success, trigger: analysisFinished) { _, finished in finished }
        .confirmationDialog("重新分析会再次发送照片，并可能产生费用。", isPresented: $confirmRetry, titleVisibility: .visible) {
            Button("重新分析") { startAnalysis(retry: true) }
            Button("取消", role: .cancel) {}
        }
        .sheet(isPresented: $camera) { CameraPicker { selected in Task { await preparePhoto(image: selected) } } }
        .onChange(of: picker) {
            let selection = picker
            Task {
                preparing = true
                if let bytes = try? await selection?.loadTransferable(type: Data.self) { await preparePhoto(data: bytes) }
                else { preparing = false; store.error = "无法读取所选照片，请重试。" }
            }
        }
        .onChange(of: mode) { results = []; textbook = nil; analysisFinished = false; analysisSummary = "" }
        .onDisappear { analysisTask?.cancel() }
    }
    private func startAnalysis(retry: Bool = false) {
        guard !busy, !preparing, imageBytes != nil, !analysisFinished || retry else { return }
        busy = true; analysisFinished = false; analysisSummary = ""; analysisError = nil; analysisDialog = true
        analysisStarted = Date(); analysisStage = "准备请求…"
        analysisTask = Task { await analyze() }
    }
    private func analyze() async {
        defer { busy = false }
        guard let bytes = imageBytes else { return }
        if imageID == nil { imageID = store.addPhoto(bytes) }
        do {
            let service = AIService(configuration: store.data.ai)
            let progress: @Sendable (String) -> Void = { stage in Task { @MainActor in if busy { analysisStage = stage } } }
            if mode == "教材与进度" {
                let result = try await service.textbook(image: bytes, progress: progress)
                try Task.checkCancellation(); textbook = result
                analysisSummary = "教材信息已识别，请核对后更新孩子档案。"
            } else {
                let response = try await service.analyze(image: bytes, profile: store.data.profile, progress: progress)
                try Task.checkCancellation()
                results = response.questions.filter { !$0.text.isEmpty && Subject(rawValue: $0.subject) != nil && ["错误", "部分正确", "待核实"].contains($0.status) }
                analysisSummary = results.isEmpty ? "未识别到可收录错题，未新增题量。可检查照片清晰度和批改痕迹。" : "识别到 \(results.count) 道待核对题目，本次尚未入库。"
            }
            analysisFinished = true
            try await Task.sleep(for: .seconds(2))
            analysisDialog = false
        } catch {
            if Task.isCancelled { analysisDialog = false }
            else { analysisError = error.localizedDescription }
        }
    }
    private func preparePhoto(image selected: UIImage? = nil, data: Data? = nil) async {
        let revision = UUID(); photoRevision = revision
        preparing = true; image = nil; imageBytes = nil; results = []; textbook = nil; imageID = nil; analysisFinished = false; analysisSummary = ""
        let prepared = if let selected { await PhotoPreparation.prepare(image: selected) }
            else if let data { await PhotoPreparation.prepare(data: data) } else { nil as PreparedPhoto? }
        guard revision == photoRevision else { return }
        preparing = false
        guard let prepared else { store.error = "照片处理失败，请重新拍照或选择照片。"; return }
        image = prepared.preview; imageBytes = prepared.jpeg
    }
}
struct PreparedPhoto {
    let preview: UIImage
    let jpeg: Data
}
enum PhotoPreparation {
    nonisolated static func prepare(image: UIImage) async -> PreparedPhoto? {
        await Task.detached(priority: .userInitiated) {
            autoreleasepool {
                guard image.size.width > 0, image.size.height > 0 else { return nil }
                let scale = min(1, 1800 / max(image.size.width, image.size.height))
                let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
                let preview = UIGraphicsImageRenderer(size: target, format: format).image { context in
                    UIColor.white.setFill(); context.fill(CGRect(origin: .zero, size: target))
                    image.draw(in: CGRect(origin: .zero, size: target))
                }
                guard let jpeg = preview.jpegData(compressionQuality: 0.75) else { return nil }
                return PreparedPhoto(preview: preview, jpeg: jpeg)
            }
        }.value
    }
    nonisolated static func prepare(data: Data) async -> PreparedPhoto? {
        await Task.detached(priority: .userInitiated) {
            autoreleasepool {
                guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
                      let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: 1800,
                        kCGImageSourceShouldCacheImmediately: true
                      ] as CFDictionary) else { return nil }
                let preview = UIImage(cgImage: thumbnail)
                guard let jpeg = preview.jpegData(compressionQuality: 0.75) else { return nil }
                return PreparedPhoto(preview: preview, jpeg: jpeg)
            }
        }.value
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
        }.navigationTitle("教材识别确认").stridePage()
    }
}
