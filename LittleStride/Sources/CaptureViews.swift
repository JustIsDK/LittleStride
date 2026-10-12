import SwiftUI
import PhotosUI
import ImageIO
import Vision
import Observation

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
                Task {
                    let saved = await store.confirm {
                        if editing, let index = store.data.questions.firstIndex(where: { $0.id == question.id }) {
                            question.weaknessID = store.knowledgeID(subject: question.subject, title: knowledge)
                            store.data.questions[index] = question
                        } else { store.add(question, knowledge: knowledge) }
                    }
                    if saved { dismiss() }
                }
            }.disabled(question.text.isEmpty)
        }.navigationTitle(editing ? "核实与修改" : "录入题目").stridePage()
        .onChange(of: question.needsVerification) {
            if !question.needsVerification && question.screening == "待核实" { question.screening = question.parentID == nil ? "收录" : "生成练习" }
        }
        .onChange(of: question.screening) {
            // Choosing a final handling state is the explicit confirmation step.
            if ["收录", "生成练习", "观察", "不纳入"].contains(question.screening) {
                question.needsVerification = false
            } else if question.screening == "待核实" {
                question.needsVerification = true
            }
        }
        .onAppear { if editing, let w = store.weakness(question.weaknessID) { knowledge = w.title } }
    }
}
@MainActor @Observable final class AnalysisState {
    var id = UUID()
    var busy = false
    var task: Task<Void, Never>?
    var stage = ""
    var started = Date()
    var finished = false
    var summary = ""
    var dialog = false
    var error: String?
    var timing = AITiming()
    func begin() {
        id = UUID()
        busy = true; finished = false; summary = ""; error = nil; dialog = true
        started = Date(); stage = "准备请求…"; timing = AITiming()
    }
    func complete(preparation: Double, ocr: Double) async throws {
        await Task.yield()
        try Task.checkCancellation()
        timing.preparation = preparation; timing.ocr = ocr
        summary += " 分析耗时 \(Int(Date().timeIntervalSince(started))) 秒。" + timing.summary
        finished = true
        try await Task.sleep(for: .seconds(2)); dialog = false
    }
    func fail(_ failure: Error) {
        if Task.isCancelled { dialog = false }
        else { error = failure.localizedDescription }
    }
}
private struct CaptureDraft {
    var image: UIImage?
    var bytes: Data?
    var imageID: UUID?
    var results: [AIQuestion] = []
    var textbook: TextbookAnalysis?
    var finished = false
    var summary = ""
    var text = ""
    var textOnly = false
    var textChecked = false
    var preparationSeconds = 0.0
    var ocrSeconds = 0.0
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
    @State private var analysis = AnalysisState()
    @State private var confirmRetry = false
    @State private var results: [AIQuestion] = []
    @State private var imageID: UUID?
    @State private var textbook: TextbookAnalysis?
    @State private var drafts: [String: CaptureDraft] = [:]
    @State private var recognizedText = ""
    @State private var ocrTask: Task<Void, Never>?
    @State private var recognizing = false
    @State private var preparationSeconds = 0.0
    @State private var ocrSeconds = 0.0
    @State private var textOnly = false
    @State private var textChecked = false
    var body: some View {
        ScrollViewReader { proxy in ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("把学习过程留下来").font(.title.weight(.semibold))
                Picker("用途", selection: $mode) { ForEach(["作业入库", "教材与进度", "练习回录"], id: \.self) { Text($0) } }.pickerStyle(.segmented).disabled(analysis.busy || preparing)
                if mode == "练习回录" {
                    Text("选择已生成的练习单，再拍照核对作答。").foregroundStyle(.secondary)
                    ForEach(store.data.sheets.sorted { $0.createdAt > $1.createdAt }) { sheet in
                        NavigationLink(destination: RecordSheetView(sheetID: sheet.id)) { StrideCard { Text(sheet.code).font(.headline); Text("\(sheet.questions.count) 题 · \(sheet.completed ? "已记录" : "待回录")") } }
                    }
                    if store.data.sheets.isEmpty { Text("先从今日计划生成练习单。").foregroundStyle(.secondary) }
                } else {
                    StrideCard {
                        if let image { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 260) }
                        else if preparing { SwiftUI.ProgressView("正在压缩照片…").frame(maxWidth: .infinity).padding(25) }
                        else { Image(systemName: "camera.viewfinder").font(.system(size: 50)).foregroundStyle(StrideStyle.green).frame(maxWidth: .infinity).padding(25) }
                        HStack {
                            Button("拍照") { if UIImagePickerController.isSourceTypeAvailable(.camera) { camera = true } else { store.error = "此设备没有可用相机，请从相册选择。" } }.buttonStyle(StrideButtonStyle(secondary: true))
                            PhotosPicker(selection: $picker, matching: .images) { Label("相册", systemImage: "photo") }.buttonStyle(StrideButtonStyle(secondary: true))
                        }.disabled(analysis.busy || preparing)
                        Text(mode == "教材与进度" ? "可拍封面、版权页、目录或当前学习页。每次分析一张，确认后补充档案。" : "拍完整题干、作答和批改痕迹。看不清的内容不会自动确认。").font(.caption).foregroundStyle(.secondary)
                    }
                    if imageBytes != nil {
                        StrideCard {
                            Button(recognizing ? "正在本地识别…" : recognizedText.isEmpty ? "本地识别文字（可选）" : "重新识别文字") { recognizeText() }.disabled(analysis.busy || recognizing)
                            Toggle("只发送本地识别文字", isOn: $textOnly).disabled(recognizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || analysis.busy)
                            Text("文字模式不上传图片，适合清晰印刷内容。手写答案、竖式、图形和批改痕迹可能丢失，需要保留时用图片模式。识别在本机完成。").font(.caption).foregroundStyle(.secondary)
                            if textOnly {
                                TextEditor(text: $recognizedText).frame(minHeight: 150).disabled(analysis.busy)
                                Toggle("已核对题干与作答，文字足够完成本次分析", isOn: $textChecked).disabled(analysis.busy)
                            } else {
                                Text(recognizedText.isEmpty ? "图片可直接发送；需要文字模式时，点击本地识别。" : "本地已识别文字，可切换文字模式核对。").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    NavigationLink("AI 配置与连接检查", destination: AISettingsView())
                    Button(analysis.busy ? "分析中…" : analysis.finished ? "已分析完成 · 请核对下方结果" : textOnly ? "发送核对后的文字并分析" : "发送照片并分析") { startAnalysis() }.buttonStyle(StrideButtonStyle()).disabled(imageBytes == nil || analysis.busy || preparing || analysis.finished || (textOnly && (!textChecked || recognizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)))
                    if let imageBytes { Text("上传照片约 \(ByteCountFormatter.string(fromByteCount: Int64(imageBytes.count), countStyle: .file))，已在后台压缩。").font(.caption).foregroundStyle(.secondary) }
                    Text(textOnly ? "本次只发送你核对后的文字，不发送照片。" : "仅在点击分析后，压缩照片发送至你配置的服务。失败保留照片，可重试。").font(.caption).foregroundStyle(.secondary)
                    if analysis.finished {
                        StrideCard {
                            Label("分析完成", systemImage: "checkmark.circle.fill").font(.headline).foregroundStyle(StrideStyle.green)
                            Text(analysis.summary)
                            Text("点击下面的结果核对并保存，分析成功不等于已入库。").font(.caption).foregroundStyle(.secondary)
                            Button("重新分析这张照片") { confirmRetry = true }.font(.caption)
                        }.id("analysisResult").transition(.opacity)
                    }
                    ForEach(Array(results.enumerated()), id: \.offset) { _, q in NavigationLink(destination: QuestionEditorView(ai: q, imageID: imageID)) { StrideCard { Tag(text: q.subject); Text(q.text); Text(q.observation).font(.caption).foregroundStyle(.secondary); Text("核对并入库 →") } }.disabled(analysis.busy) }
                    if let textbook { NavigationLink("核对教材信息并填写档案", destination: TextbookConfirmView(analysis: textbook)).disabled(analysis.busy) }
                    if mode == "作业入库" { NavigationLink("不用 AI，手动录入题目", destination: QuestionEditorView()) }
                }
            }.padding(24)
        }.background(StrideStyle.background).navigationTitle("拍照录入").stridePage().navigationBarTitleDisplayMode(.inline)
            .onChange(of: analysis.dialog) {
                if analysis.finished && !analysis.dialog { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { proxy.scrollTo("analysisResult", anchor: .center) } }
            }
        }
        .overlay {
            if analysis.dialog {
                AnalysisStatusDialog(busy: !analysis.finished && analysis.error == nil, success: analysis.finished, message: analysis.error ?? (analysis.finished ? analysis.summary : analysis.stage), started: analysis.started, cancel: { analysis.task?.cancel() }, close: { analysis.dialog = false })
            }
        }
        .sensoryFeedback(.success, trigger: analysis.finished) { _, finished in finished }
        .confirmationDialog("重新分析会再次发送照片，并可能产生费用。", isPresented: $confirmRetry, titleVisibility: .visible) {
            Button("重新分析") { startAnalysis(retry: true) }
            Button("取消", role: .cancel) {}
        }
        .sheet(isPresented: $camera) { CameraPicker { selected in Task { await preparePhoto(image: selected) } } }
        .onChange(of: picker) {
            guard let selection = picker else { return }
            Task {
                preparing = true
                if let bytes = try? await selection.loadTransferable(type: Data.self) { await preparePhoto(data: bytes) }
                else { preparing = false; store.error = "无法读取所选照片，请重试。" }
            }
        }
        .onChange(of: mode) { oldMode, newMode in
            drafts[oldMode] = CaptureDraft(image: image, bytes: imageBytes, imageID: imageID, results: results, textbook: textbook, finished: analysis.finished, summary: analysis.summary, text: recognizedText, textOnly: textOnly, textChecked: textChecked, preparationSeconds: preparationSeconds, ocrSeconds: ocrSeconds)
            let draft = drafts[newMode] ?? CaptureDraft()
            image = draft.image; imageBytes = draft.bytes; imageID = draft.imageID
            results = draft.results; textbook = draft.textbook; analysis.finished = draft.finished; analysis.summary = draft.summary
            recognizedText = draft.text; textOnly = draft.textOnly; textChecked = draft.textChecked
            ocrTask?.cancel(); recognizing = false
            preparationSeconds = draft.preparationSeconds; ocrSeconds = draft.ocrSeconds
            photoRevision = UUID(); picker = nil; analysis.error = nil; analysis.dialog = false
        }
        .onChange(of: recognizedText) { textChecked = false }
        .onDisappear { analysis.task?.cancel(); ocrTask?.cancel(); recognizing = false }
    }
    private func startAnalysis(retry: Bool = false) {
        guard !analysis.busy, !preparing, imageBytes != nil, !analysis.finished || retry, !textOnly || (textChecked && !recognizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) else { return }
        analysis.begin(); results = []; textbook = nil
        analysis.task = Task { await analyze() }
    }
    private func analyze() async {
        defer { analysis.busy = false }
        guard let bytes = imageBytes else { return }
        let runID = analysis.id
        do {
            if imageID == nil { imageID = try store.addPhoto(bytes) }
            let service = AIService(configuration: store.data.ai, timing: { value in Task { @MainActor in if analysis.id == runID { analysis.timing.merge(value) } } })
            let progress: @Sendable (String) -> Void = { stage in Task { @MainActor in if analysis.busy && analysis.id == runID { analysis.stage = stage } } }
            if mode == "教材与进度" {
                let result = try await service.textbook(image: textOnly ? nil : bytes, text: textOnly ? recognizedText : nil, progress: progress)
                try Task.checkCancellation(); textbook = result
                analysis.summary = "教材信息已识别，请核对后更新孩子档案。"
            } else {
                let response = try await service.analyze(image: textOnly ? nil : bytes, profile: store.data.profile, text: textOnly ? recognizedText : nil, progress: progress)
                try Task.checkCancellation()
                guard response.questions.allSatisfy({ !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && Subject(rawValue: $0.subject) != nil && ["错误", "部分正确", "待核实"].contains($0.status) }) else {
                    throw ServiceFailure(message: "AI 返回的题目学科、题干或状态无效，请重新分析。")
                }
                results = response.questions
                analysis.summary = results.isEmpty ? "未识别到可收录错题，未新增题量。可检查照片清晰度和批改痕迹。" : "识别到 \(results.count) 道待核对题目，本次尚未入库。"
            }
            try await analysis.complete(preparation: preparationSeconds, ocr: ocrSeconds)
        } catch {
            analysis.fail(error)
        }
    }
    private func recognizeText() {
        guard let preview = image else { return }
        ocrTask?.cancel(); recognizing = true
        ocrTask = Task {
            defer { recognizing = false }
            let started = Date()
            do {
                let text = try await PhotoPreparation.recognize(preview)
                try Task.checkCancellation()
                recognizedText = text; ocrSeconds = Date().timeIntervalSince(started)
                textOnly = !text.isEmpty; textChecked = false
                if text.isEmpty { store.error = "没有识别到可用文字，请使用图片模式。" }
            } catch { if !Task.isCancelled { store.error = "文字识别失败，请使用图片模式。" } }
        }
    }
    private func preparePhoto(image selected: UIImage? = nil, data: Data? = nil) async {
        let revision = UUID(); photoRevision = revision
        if let imageID { store.releasePhoto(imageID) }
        ocrTask?.cancel(); recognizing = false; ocrSeconds = 0
        let preparedAt = Date()
        preparing = true; recognizedText = ""; textOnly = false; textChecked = false; image = nil; imageBytes = nil; results = []; textbook = nil; imageID = nil; analysis.finished = false; analysis.summary = ""
        let prepared = if let selected { await PhotoPreparation.prepare(image: selected) }
            else if let data { await PhotoPreparation.prepare(data: data) } else { nil as PreparedPhoto? }
        guard revision == photoRevision else { return }
        preparing = false; preparationSeconds = Date().timeIntervalSince(preparedAt)
        guard let prepared else { store.error = "照片处理失败，请重新拍照或选择照片。"; return }
        image = prepared.preview; imageBytes = prepared.jpeg
    }
}
struct PreparedPhoto {
    let preview: UIImage
    let jpeg: Data
}
enum PhotoPreparation {
    private nonisolated static func finish(_ preview: UIImage) -> PreparedPhoto? {
        var quality: CGFloat = 0.75
        guard var jpeg = preview.jpegData(compressionQuality: quality) else { return nil }
        while jpeg.count > 900_000 && quality > 0.45 {
            quality -= 0.1
            guard let smaller = preview.jpegData(compressionQuality: quality) else { break }
            jpeg = smaller
        }
        return PreparedPhoto(preview: preview, jpeg: jpeg)
    }
    nonisolated static func recognize(_ image: UIImage) async throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        request.usesLanguageCorrection = false
        let task = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            guard let cgImage = image.cgImage else { return "" }
            try VNImageRequestHandler(cgImage: cgImage).perform([request])
            try Task.checkCancellation()
            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { request.cancel(); task.cancel() }
    }
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
                return finish(preview)
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
                return finish(preview)
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
                Task { if await store.confirm({
                    if !parts.isEmpty { store.data.profile.textbooks[subject.rawValue] = parts.joined(separator: " · ") }
                    if !analysis.progress.isEmpty { store.data.profile.progress[subject.rawValue] = analysis.progress }
                }) { dismiss() } }
            }
        }.navigationTitle("教材识别确认").stridePage()
    }
}
