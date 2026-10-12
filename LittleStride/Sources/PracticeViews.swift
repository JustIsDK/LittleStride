import SwiftUI
import PhotosUI

struct PrintSheetView: View {
    @Environment(\.dismiss) private var dismiss
    let sheet: PracticeSheet
    @State private var share: SharePayload?
    @State private var error: String?
    var body: some View {
        List {
            Section { Text(sheet.code).font(.headline); Text("孩子版不包含答案、错因和分析提示。") }
            ForEach(Array(sheet.questions.enumerated()), id: \.element.id) { i, q in Text("\(i + 1). \(q.text)").padding(.vertical, 15) }
            Button("系统打印") { do { SheetRenderer.printPDF(try SheetRenderer.pdf(sheet)) } catch { self.error = error.localizedDescription } }
            Button("分享 / 保存 PDF") { do { share = SharePayload(items: [try SheetRenderer.pdf(sheet)]) } catch { self.error = error.localizedDescription } }
            NavigationLink("做完了，回录结果", destination: RecordSheetView(sheetID: sheet.id))
        }.navigationTitle("练习单预览").stridePage().toolbar { Button("关闭") { dismiss() } }
        .sheet(item: $share) { SystemShare(items: $0.items) }
        .alert("打印文件生成失败", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("好的") {} } message: { Text(error ?? "") }
    }
}
struct AttemptDraft {
    var answer = ""
    var result = "无法判断"
    var help = "未知"
    var reason = "未观察"
    var note = ""
    var corrected = false
}
struct RecordSheetView: View {
    @Environment(LearningStore.self) private var store
    let sheetID: UUID
    @State private var drafts: [UUID: AttemptDraft] = [:]
    @State private var picker: PhotosPickerItem?
    @State private var photo: UIImage?
    @State private var photoBytes: Data?
    @State private var recognizedText = ""
    @State private var textOnly = false
    @State private var textChecked = false
    @State private var preparingPhoto = false
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var checked = false
    @State private var shareResult = false
    private var sheet: PracticeSheet? { store.data.sheets.first { $0.id == sheetID } }
    var body: some View {
        ScrollViewReader { proxy in Form {
            if let sheet {
                Section { Text(sheet.code); Text(sheet.completed ? "此练习单已记录，重复打开不会重复奖励。" : "逐题核对结果和帮助程度，然后保存。") }
                if !sheet.completed {
                    Section("结果照片（可选）") {
                        if let photo { Image(uiImage: photo).resizable().scaledToFit().frame(maxHeight: 220) }
                        if preparingPhoto { SwiftUI.ProgressView("正在压缩并识别文字…") }
                        PhotosPicker("从相册选择", selection: $picker, matching: .images).disabled(busy || preparingPhoto)
                        Button("拍照") { if UIImagePickerController.isSourceTypeAvailable(.camera) { camera = true } else { store.error = "当前设备无相机，请选择相册。" } }.disabled(busy || preparingPhoto)
                        if photoBytes != nil {
                            Toggle("只发送本地识别文字", isOn: $textOnly).disabled(recognizedText.isEmpty || busy)
                            Text("手写、竖式及图形可能识别不完整；文字模式不上传照片，请先核对。需要原始作答痕迹时用图片模式。").font(.caption)
                            if textOnly {
                                TextEditor(text: $recognizedText).frame(minHeight: 150).disabled(busy)
                                Toggle("已核对识别文字与孩子作答", isOn: $textChecked).disabled(busy)
                            }
                        }
                        Button(busy ? "识别中…" : analysisFinished ? "已识别完成 · 请核对结果" : textOnly ? "发送核对文字，AI 辅助批改" : "发送照片，AI 辅助批改") { startAnalysis(sheet) }.disabled(photoBytes == nil || busy || preparingPhoto || analysisFinished || (textOnly && (!textChecked || recognizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)))
                        if analysisFinished {
                            Label(analysisSummary, systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(StrideStyle.green)
                            Button("重新识别这张照片") { confirmRetry = true }.font(.caption)
                        }
                        Text("可不使用 AI，直接填写实际结果。照片只有在点击分析时发往配置服务。").font(.caption)
                    }
                    ForEach(sheet.questions) { q in
                        Section(q.text) {
                            TextField("孩子本次答案", text: draft(q.id, \.answer))
                            Picker("结果", selection: draft(q.id, \.result)) { ForEach(["正确", "部分正确", "错误", "未作答", "无法判断"], id: \.self) { Text($0) } }
                            Picker("帮助程度", selection: draft(q.id, \.help)) { ForEach(["独立", "一般提醒", "解题提示", "讲解或示范后完成", "未知"], id: \.self) { Text($0) } }
                            Picker("关键理由", selection: draft(q.id, \.reason)) { ForEach(["能", "部分能", "不能", "未观察", "不适用"], id: \.self) { Text($0) } }
                            TextField("本次表现 / 备注", text: draft(q.id, \.note), axis: .vertical)
                            Toggle("需要的订正已完成", isOn: draft(q.id, \.corrected))
                        }.id(q.id).disabled(busy)
                    }
                    Section {
                        Toggle("已核对作答与判题结果", isOn: $checked)
                        Button("确认并保存") { save(sheet) }.disabled(!checked || busy)
                        Text("未作答不计错、不计奖励；未知结果不更新掌握状态。原始历史不会被覆盖。").font(.caption)
                    }
                } else { NavigationLink("本次成果与分享", destination: ResultShareView(sheetID: sheetID)) }
            }
        }.navigationTitle("练习结果回录").stridePage()
        .onChange(of: analysisDialog) {
            if !analysisDialog && analysisFinished, let first = sheet?.questions.first {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { proxy.scrollTo(first.id, anchor: .top) }
            }
        }
        }
        .overlay {
            if analysisDialog {
                AnalysisStatusDialog(busy: !analysisFinished && analysisError == nil, success: analysisFinished, message: analysisError ?? (analysisFinished ? analysisSummary : analysisStage), started: analysisStarted, cancel: { analysisTask?.cancel() }, close: { analysisDialog = false })
            }
        }
        .onAppear { if let sheet { for q in sheet.questions where drafts[q.id] == nil { drafts[q.id] = AttemptDraft() } } }
        .sheet(isPresented: $camera) { CameraPicker { image in Task { await preparePhoto(image: image) } } }
        .onChange(of: picker) {
            guard let selection = picker else { return }
            Task {
                preparingPhoto = true
                if let bytes = try? await selection.loadTransferable(type: Data.self) { await preparePhoto(data: bytes) }
                else { preparingPhoto = false; store.error = "无法读取所选照片，请重试。" }
            }
        }
        .navigationDestination(isPresented: $shareResult) { ResultShareView(sheetID: sheetID) }
        .onChange(of: recognizedText) { textChecked = false }
        .onDisappear { analysisTask?.cancel() }
        .sensoryFeedback(.success, trigger: analysisFinished) { _, finished in finished }
        .confirmationDialog("重新识别会再次发送照片，并可能产生费用。", isPresented: $confirmRetry, titleVisibility: .visible) {
            Button("重新识别") { if let sheet { startAnalysis(sheet, retry: true) } }
            Button("取消", role: .cancel) {}
        }
    }
    private func draft<Value>(_ id: UUID, _ path: WritableKeyPath<AttemptDraft, Value>) -> Binding<Value> {
        Binding(get: { (drafts[id] ?? AttemptDraft())[keyPath: path] }, set: { var d = drafts[id] ?? AttemptDraft(); d[keyPath: path] = $0; drafts[id] = d; checked = false })
    }
    private func startAnalysis(_ sheet: PracticeSheet, retry: Bool = false) {
        guard !busy, !preparingPhoto, photoBytes != nil, !analysisFinished || retry, !textOnly || (textChecked && !recognizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) else { return }
        busy = true; analysisFinished = false; analysisSummary = ""; analysisError = nil; analysisDialog = true
        analysisStarted = Date(); analysisStage = "准备请求…"
        analysisTask = Task { await analyze(sheet) }
    }
    private func analyze(_ sheet: PracticeSheet) async {
        defer { busy = false }
        guard let bytes = photoBytes else { return }
        do {
            let mapping = sheet.questions.map { "\($0.id.uuidString): \($0.text)；参考答案：\($0.answer)" }.joined(separator: "\n")
            let progress: @Sendable (String) -> Void = { stage in Task { @MainActor in if busy { analysisStage = stage } } }
            let result = try await AIService(configuration: store.data.ai).decode(AICheck.self, prompt: "核对照片中的练习结果。题目编号与参考：\n\(mapping)\n开放题允许合理不同表述。看不清或未作答不能判错误；帮助程度不能从照片推断。返回{\"results\":[{\"id\":\"原题UUID\",\"answer\":\"孩子答案\",\"result\":\"正确/部分正确/错误/未作答/无法判断\",\"observation\":\"可观察事实\"}]}。" + (textOnly ? "\n仅提供用户核对的OCR文字；没有图片，缺失作答或无法判断的题写无法判断：\n" + recognizedText : ""), image: textOnly ? nil : bytes, progress: progress)
            try Task.checkCancellation()
            var recognized = Set<UUID>()
            for r in result.results {
                if let id = UUID(uuidString: r.id), sheet.questions.contains(where: { $0.id == id }), ["正确", "部分正确", "错误", "未作答", "无法判断"].contains(r.result) {
                    recognized.insert(id)
                    var d = drafts[id] ?? AttemptDraft(); d.answer = r.answer; d.result = r.result; d.note = r.observation; drafts[id] = d
                }
            }; checked = false
            analysisSummary = "识别完成：\(recognized.count) / \(sheet.questions.count) 题已填入结果，请逐题核对。"
            analysisFinished = true
            try await Task.sleep(for: .seconds(2))
            analysisDialog = false
        } catch {
            if Task.isCancelled { analysisDialog = false }
            else { analysisError = error.localizedDescription }
        }
    }
    private func preparePhoto(image: UIImage? = nil, data: Data? = nil) async {
        preparingPhoto = true; recognizedText = ""; textOnly = false; textChecked = false; photo = nil; photoBytes = nil; checked = false; analysisFinished = false; analysisSummary = ""
        let prepared = if let image { await PhotoPreparation.prepare(image: image) }
            else if let data { await PhotoPreparation.prepare(data: data) } else { nil as PreparedPhoto? }
        preparingPhoto = false
        guard let prepared else { store.error = "照片处理失败，请重试。"; return }
        photo = prepared.preview; photoBytes = prepared.jpeg; recognizedText = prepared.text
    }
    private func save(_ sheet: PracticeSheet) {
        let attempts = sheet.questions.compactMap { q -> Attempt? in
            let d = drafts[q.id] ?? AttemptDraft()
            guard d.result != "未作答" && d.result != "无法判断" else { return nil }
            return Attempt(questionID: q.id, sheetID: sheet.id, answer: d.answer, result: d.result, help: d.help, reason: d.reason, note: d.note, corrected: d.corrected)
        }
        guard !attempts.isEmpty else { store.error = "没有可确认的作答结果；请继续核实，或延期练习。"; return }
        // Unanswered items stay eligible; the sheet is a single confirmed submission.
        store.record(attempts, sheetID: sheet.id); shareResult = true
    }
}
struct ProgressView: View {
    @Environment(LearningStore.self) private var store
    var body: some View {
        List {
            Section { NavigationLink("多维能力观察", destination: AssessmentView()); NavigationLink("徽章与小伙伴", destination: RewardsView()) }
            if store.data.weaknesses.isEmpty { Text("尚无已记录的薄弱点，先从真实作业建立记录。").foregroundStyle(.secondary) }
            ForEach(store.data.weaknesses) { w in
                Section(w.title) {
                    Text("\(w.subject.rawValue) · \(w.priority) · \(w.status)")
                    let qs = store.data.questions.filter { $0.weaknessID == w.id }
                    let ids = Set(qs.map(\.id))
                    let history = store.data.attempts.filter { ids.contains($0.questionID) }
                    Text("已记录 \(history.count) 次作答，独立正确 \(history.filter { $0.help == "独立" && $0.result == "正确" }.count) 次")
                    Text("下次复习：\(w.nextDate.formatted(date: .abbreviated, time: .omitted))").font(.caption)
                    ForEach(qs.prefix(2)) { q in NavigationLink(q.text, destination: QuestionDetailView(id: q.id)) }
                }
            }
            Section("最近练习成果") { ForEach(store.data.sheets.filter(\.completed).sorted { $0.createdAt > $1.createdAt }) { sheet in NavigationLink(sheet.code, destination: ResultShareView(sheetID: sheet.id)) } }
        }.navigationTitle("学习进展").stridePage()
    }
}
struct RewardsView: View {
    @Environment(LearningStore.self) private var store
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("每一步，都值得被看见。").font(.title.weight(.semibold))
                StrideCard { Text("\(store.points) 成长积分").font(.title.weight(.semibold)); Text("累计 \(store.practiceCount) 次有效练习") }
                StrideCard { Text("🏅 十题小步").font(.title2.bold()); Text(store.practiceCount >= 10 ? "已获得" : "\(store.practiceCount) / 10 次"); SwiftUI.ProgressView(value: Double(min(store.practiceCount, 10)), total: 10); Text("计划内完成并处理订正；不要求一次全对。").font(.caption) }
                StrideCard { Text("✨ 第一个知识点").font(.title2.bold()); Text(store.data.rewards.contains { $0.source.hasPrefix("mastery:") } ? "已获得" : "等待跨日独立掌握证据"); Text("两天独立正确，至少一次同类题，并有关键理由说明。").font(.caption) }
                StrideCard { Text("🦊").font(.system(size: 70)); Text("小芽狐").font(.title2.bold()); Button(store.data.claimedPet ? "已领取" : "领取小伙伴") { store.data.claimedPet = true; store.save() }.buttonStyle(StrideButtonStyle()).disabled(store.practiceCount < 10 || store.data.claimedPet); Text("不消耗积分，不需要每日喂养。休息、延期、求助不扣奖励。").font(.caption) }
            }.padding(24)
        }.background(StrideStyle.background).navigationTitle("成长奖励").stridePage()
    }
}
struct ResultShareView: View {
    @Environment(LearningStore.self) private var store
    let sheetID: UUID
    @State private var showQuestions = false
    @State private var showBadge = true
    @State private var share: SharePayload?
    private var attempts: [Attempt] { store.data.attempts.filter { $0.sheetID == sheetID } }
    private var card: some View {
        VStack(spacing: 18) {
            Text("LittleStride · 学习小记").font(.caption)
            Text("🌱").font(.system(size: 60))
            Text("\(store.data.profile.nickname)的一小步").font(.title.bold())
            Text("完成 \(attempts.count) 道练习").font(.title2)
            Text("本次独立正确 \(attempts.filter { $0.help == "独立" && $0.result == "正确" }.count) 题\n隔天再回看，逐步学得更稳。").multilineTextAlignment(.center)
            if showQuestions { ForEach(attempts) { a in Text(store.question(a.questionID)?.text ?? "").font(.subheadline) } }
            if showBadge && store.practiceCount >= 10 { Text("🏅 已获得「十题小步」").font(.headline) }
            Text("每一步进展，都来自真实的尝试。").font(.caption)
        }.foregroundStyle(StrideStyle.ink).padding(28).frame(width: 330).background(StrideStyle.pale, in: RoundedRectangle(cornerRadius: 24))
    }
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                card
                Toggle("展示题目内容", isOn: $showQuestions)
                Toggle("展示已获得徽章", isOn: $showBadge)
                Text("分享仅展示昵称和本次成果，不带出生日期、年龄、地区、能力短板或原始照片。").font(.caption).foregroundStyle(.secondary)
                Button("分享 / 保存成果图片") {
                    let renderer = ImageRenderer(content: card); renderer.scale = 3
                    if let image = renderer.uiImage { share = SharePayload(items: [image]) }
                }.buttonStyle(StrideButtonStyle()).disabled(attempts.isEmpty)
            }.padding(24)
        }.navigationTitle("本次学习成果").stridePage().sheet(item: $share) { SystemShare(items: $0.items) }
    }
}
