import SwiftUI
import UniformTypeIdentifiers

struct ProfileView: View {
    @Environment(LearningStore.self) private var store
    @State private var editingBirthDate = false
    @State private var draftBirthDate = Date()
    var body: some View {
        @Bindable var store = store
        Form {
            Section("基本信息") {
                TextField("昵称", text: $store.data.profile.nickname)
                Button {
                    draftBirthDate = store.data.profile.birthDateValue ?? Date()
                    editingBirthDate = true
                } label: {
                    HStack {
                        Text("出生日期（可选）").foregroundStyle(.primary)
                        Spacer()
                        Text(store.data.profile.birthDate ?? "填写出生日期").foregroundStyle(.secondary)
                    }
                }
                if let age = store.data.profile.currentAge {
                    LabeledContent("当前年龄", value: "\(age) 周岁")
                }
                if store.data.profile.birthDate != nil {
                    Button("清除出生日期", role: .destructive) {
                        store.data.profile.birthDate = nil
                        store.data.profile.age = ""
                        store.save()
                    }
                }
                Picker("年级", selection: $store.data.profile.grade) { ForEach(["一年级", "二年级", "三年级", "四年级", "五年级", "六年级"], id: \.self) { Text($0) } }
                TextField("学习地区", text: $store.data.profile.region)
                Picker("学期", selection: $store.data.profile.term) { Text("上学期"); Text("下学期") }
            }
            Section("各科教材与进度") {
                ForEach(Subject.allCases) { subject in
                    TextField("\(subject.rawValue)：版本 / 册次", text: Binding(get: { store.data.profile.textbooks[subject.rawValue, default: ""] }, set: { store.data.profile.textbooks[subject.rawValue] = $0 }))
                    TextField("\(subject.rawValue)：当前单元 / 页码", text: Binding(get: { store.data.profile.progress[subject.rawValue, default: ""] }, set: { store.data.profile.progress[subject.rawValue] = $0 }))
                }
                NavigationLink("拍照识别教材与进度", destination: CaptureView())
                Text("地区不等于教材版本，无法确认时留空。").font(.caption)
            }
            Section {
                NavigationLink("多维能力观察", destination: AssessmentView())
                NavigationLink("AI 服务设置", destination: AISettingsView())
                NavigationLink("备份、恢复与 iCloud", destination: DataSettingsView())
                NavigationLink("提醒与计划设置", destination: SettingsView())
            }
        }.navigationTitle("孩子档案").stridePage().onDisappear { store.save() }
        .sheet(isPresented: $editingBirthDate) {
            NavigationStack {
                Form {
                    DatePicker("出生日期", selection: $draftBirthDate, in: ...Date(), displayedComponents: .date)
                        .datePickerStyle(.wheel)
                        .environment(\.calendar, Calendar(identifier: .gregorian))
                    Text("年龄根据出生日期自动计算，无需每年修改。出生日期不会出现在成果分享中。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .navigationTitle("出生日期")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { editingBirthDate = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            store.data.profile.birthDate = ChildProfile.dateString(draftBirthDate)
                            store.data.profile.age = ""
                            store.save()
                            editingBirthDate = false
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }
}
struct AssessmentView: View {
    @Environment(LearningStore.self) private var store
    var body: some View {
        Form {
            Section { Text("回想最近两周，不清楚就选择未观察。家长反馈是线索，不直接改变知识点掌握状态。").font(.subheadline) }
            ForEach(["数学", "语文", "英语", "学习过程"], id: \.self) { group in
                Section(group) {
                    ForEach(ObservationDimension.all.filter { $0.group == group }) { d in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(d.title).font(.headline); Text(d.prompt).font(.caption).foregroundStyle(.secondary)
                            Picker("观察", selection: Binding(get: { store.data.profile.observations[d.id, default: "未观察"] }, set: { store.data.profile.observations[d.id] = $0; store.save() })) { ForEach(["未观察", "多数时候独立完成", "偶尔需要提醒", "经常需要帮助"], id: \.self) { Text($0) } }
                        }
                    }
                }
            }
            Section("已有作答证据") {
                ForEach(store.data.weaknesses) { w in Text("\(w.subject.rawValue) · \(w.title) · \(w.status)") }
                Text("证据不足的维度保持待观察。不会生成智力或注意力诊断。").font(.caption)
            }
        }.navigationTitle("能力观察").stridePage()
    }
}
struct AISettingsView: View {
    @Environment(LearningStore.self) private var store
    @State private var key = ""
    @State private var keyPresent = false
    @State private var busy = false
    @State private var testResult = "尚未检测"
    @State private var connectionMode = "key"
    @State private var provider: AIProvider = .custom
    var body: some View {
        @Bindable var store = store
        Form {
            Section("接入方式") {
                Picker("接入方式", selection: $connectionMode) {
                    Text("API Key").tag("key")
                    Text("账号授权").tag("account")
                }.pickerStyle(.segmented)
                Text(connectionMode == "key" ? "使用官方 API 或自定义服务。选服务商、获取参数，再保存并检测。" : "账号授权需要服务商支持第三方 App 的授权流程，当前尚未接通。登录控制台后获取 API Key，可以先用 API Key 方式连接。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("选择服务商") {
                Picker("服务商", selection: $provider) {
                    ForEach(AIProvider.allCases) { item in Text(item.name).tag(item) }
                }
                Text(provider.guide).font(.caption).foregroundStyle(.secondary)
                if let url = provider.consoleURL { Link("登录 \(provider.name) 控制台 / 获取 API Key ↗", destination: url) }
                if connectionMode == "key" && provider != .custom {
                    Button("填入该服务商的推荐参数") { applyProvider() }
                    Text("会替换地址与协议并清空模型输入。每个服务地址的密钥分开保存；切换不会把旧服务的 Key 发给新服务。模型 ID 请按控制台填写。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if connectionMode == "account" {
                Section("授权接入状态") {
                    Label("账号授权尚未接入", systemImage: "person.crop.circle.badge.clock")
                    Text("各服务商的账号授权需要分别核实并适配。网页登录成功只代表登录服务商网站，不代表 LittleStride 已获得调用权限。App 不收集服务商账号密码。")
                        .font(.caption).foregroundStyle(.secondary)
                    if provider == .openai {
                        Link("OpenAI 账号授权官方说明 ↗", destination: URL(string: "https://developers.openai.com/siwc/token-sharing-open-source/sign-in")!)
                    }
                    Button("改用 API Key 接入") { connectionMode = "key" }
                }
            } else {
                Section("连接参数") {
                    Picker("接口协议", selection: $store.data.ai.api) {
                        Text("Responses").tag("Responses")
                        Text("Chat Completions").tag("Chat Completions")
                        Text("Anthropic Messages").tag("Anthropic Messages")
                    }
                    Text("按服务商 API 文档选择协议。Claude 官方用 Anthropic Messages；中转服务按中转商文档选择。Codex 的 wire_api = responses 对应 Responses。")
                        .font(.caption).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("服务地址 · Base URL")
                        TextField("https://服务域名/v1", text: $store.data.ai.baseURL).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                        Text("从服务商文档复制基础地址，保留 /v1 等路径前缀；不要附加 /responses、/chat/completions 或 /messages。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("模型 ID")
                        TextField("从模型列表复制准确 ID", text: $store.data.ai.model).textInputAutocapitalization(.never).autocorrectionDisabled()
                        Text("使用 API 模型 ID，不能只填产品名称。作业、教材和回录识别都需要模型支持图片输入。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("API Key")
                        SecureField(keyPresent ? "此地址已保存 Key；留空不修改" : "粘贴此服务商的 API Key", text: $key).textInputAutocapitalization(.never).autocorrectionDisabled()
                        Text("在服务商开发者控制台的 API Keys 页面创建。只粘贴密钥本身，不要加 Bearer。Codex 的 env_key 是变量名，应填变量实际值；auth.json 的登录令牌不能当作 API Key。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    DisclosureGroup("高级认证与响应速度") {
                        TextField("认证请求头名称", text: $store.data.ai.authHeader).textInputAutocapitalization(.never).autocorrectionDisabled()
                        Toggle("添加 Bearer 前缀", isOn: $store.data.ai.bearer)
                        Text("常见兼容接口使用 Authorization + Bearer。Claude 官方使用 x-api-key 且关闭 Bearer。")
                            .font(.caption).foregroundStyle(.secondary)
                        if store.data.ai.api == "Responses" {
                            Picker("模型思考强度", selection: Binding(get: { store.data.ai.reasoningEffort ?? "default" }, set: { store.data.ai.reasoningEffort = $0 == "default" ? nil : $0 })) {
                                Text("服务默认").tag("default"); Text("低 · 可减少等待").tag("low")
                                Text("中").tag("medium"); Text("高").tag("high")
                            }
                            Text("仅用于支持 reasoning.effort 的 Responses 模型。不确定时用服务默认；低强度可能减少等待，也可能影响分析质量。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Text("Key 只保存在本机 Keychain，不随备份或 iCloud 同步。换设备需重新填写。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if connectionMode == "key" { Section("保存与检测") {
                Button("保存连接配置") { save() }
                Button(busy ? "检测中…" : "检测文本与结构化输出") { Task { await test() } }.disabled(busy)
                Text(testResult).font(.caption).textSelection(.enabled)
                Text("此检测会实际访问配置的服务并可能产生费用；图片能力需在照片分析时验证。不自动切换服务商。").font(.caption).foregroundStyle(.secondary)
                if keyPresent { Button("删除本机 Key", role: .destructive) { do { try SecretStore.save("", account: store.data.ai.keyAccount); keyPresent = false; key = "" } catch { store.error = error.localizedDescription } } }
            } }
        }.buttonStyle(StridePressStyle(fullWidth: true)).navigationTitle("AI 服务设置").stridePage().onAppear {
            provider = AIProvider(rawValue: store.data.ai.provider ?? "custom") ?? .custom
            migrateKey(); refreshKeyStatus()
        }
        .onChange(of: store.data.ai.baseURL) { refreshKeyStatus() }
        .onDisappear { key = ""; store.save() }
    }
    private func refreshKeyStatus() { keyPresent = !SecretStore.load(configuration: store.data.ai).isEmpty }
    private func migrateKey() {
        guard store.data.ai.credentialScope == nil else { return }
        do {
            let legacy = SecretStore.load()
            if !legacy.isEmpty && !store.data.ai.baseURL.isEmpty { try SecretStore.save(legacy, account: store.data.ai.keyAccount) }
            store.data.ai.credentialScope = store.data.ai.keyAccount
            store.save()
        } catch { store.error = error.localizedDescription }
    }
    private func applyProvider() {
        key = ""; store.data.ai.provider = provider.rawValue
        store.data.ai.baseURL = provider.baseURL; store.data.ai.api = provider.api
        store.data.ai.model = ""; store.data.ai.reasoningEffort = nil
        store.data.ai.authHeader = provider == .claude ? "x-api-key" : "Authorization"
        store.data.ai.bearer = provider != .claude
        store.data.ai.credentialScope = store.data.ai.keyAccount
        refreshKeyStatus(); testResult = "推荐地址与协议已填入；请填写模型 ID 和该服务地址的 Key。"
    }
    @discardableResult private func save() -> Bool {
        do {
            _ = try AIService(configuration: store.data.ai).endpoint()
            if !key.isEmpty { try SecretStore.save(key.trimmingCharacters(in: .whitespacesAndNewlines), account: store.data.ai.keyAccount); key = "" }
            store.data.ai.credentialScope = store.data.ai.keyAccount
            refreshKeyStatus(); store.save(); testResult = "配置已保存，尚未检测当前连接。"; return true
        } catch { store.error = error.localizedDescription; return false }
    }
    private func test() async {
        guard save() else { return }; busy = true; defer { busy = false }
        struct Probe: Codable { var ok: Bool }
        do {
            let result = try await AIService(configuration: store.data.ai).decode(Probe.self, prompt: "连接测试，只返回 {\"ok\":true}。")
            testResult = result.ok ? "文本与 JSON 解析通过。图片能力未检测。" : "服务返回结果未符合测试要求。"
        } catch { testResult = error.localizedDescription }
    }
}
struct SettingsView: View {
    @Environment(LearningStore.self) private var store
    var body: some View {
        @Bindable var store = store
        Form {
            Section { NavigationLink("AI 服务设置", destination: AISettingsView()); NavigationLink("备份、恢复与 iCloud", destination: DataSettingsView()); NavigationLink("学科与题量", destination: PlanSettingsView()) }
            Section("每日提醒") {
                Toggle("开启通知", isOn: $store.data.reminder)
                Stepper("\(store.data.reminderHour) 时", value: $store.data.reminderHour, in: 0...23)
                Stepper("\(store.data.reminderMinute) 分", value: $store.data.reminderMinute, in: 0...59)
                Button("保存并申请通知权限") { store.save(); Task { await ReminderService.update(store) } }
                Text("每天通知打开当前计划。iOS 后台不保证每天动态计算题量，因此通知不携带可能过期的题目摘要。").font(.caption)
            }
        }.navigationTitle("服务与计划设置").stridePage()
    }
}
struct DataSettingsView: View {
    @Environment(LearningStore.self) private var store
    @State private var share: SharePayload?
    @State private var importer = false
    @State private var incoming: Data?
    @State private var confirmRestore = false
    @State private var busy = false
    @State private var cloudStatus = "尚未检查 iCloud 可用性"
    var body: some View {
        Form {
            Section("完整本地备份") {
                Text("结构化 JSON 包含题目、知识点、作答、计划、奖励和已保存照片；不包含 API Key。")
                Button("导出备份 / 保存到文件") { do { share = SharePayload(items: [try store.backup()]) } catch { store.error = error.localizedDescription } }
                Button("选择备份文件恢复") { importer = true }
                Text("恢复将替换本机数据，操作前自动保存一份旧数据快照。跨 App 使用仍需对方支持此格式。").font(.caption)
            }
            Section("iCloud Drive 快照") {
                Text(cloudStatus).font(.caption)
                Button(busy ? "处理中…" : "备份到 iCloud") { Task { await upload() } }.disabled(busy)
                Button("从 iCloud 读取最近备份") { Task { await download() } }.disabled(busy)
                Text("此版本提供手动云端快照与恢复。自动多设备同步和冲突合并尚未开启。需要签名时配置 iCloud 容器；不可用时会明确报错。").font(.caption)
            }
        }.navigationTitle("数据与恢复").stridePage()
        .sheet(item: $share) { SystemShare(items: $0.items) }
        .fileImporter(isPresented: $importer, allowedContentTypes: [.json]) { result in
            do { let url = try result.get(); let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }; incoming = try Data(contentsOf: url); confirmRestore = true }
            catch { store.error = error.localizedDescription }
        }
        .confirmationDialog("确认替换本机数据？", isPresented: $confirmRestore, titleVisibility: .visible) {
            Button("保存旧快照并恢复", role: .destructive) {
                do { _ = try store.backup(); if let incoming { try store.restore(incoming); store.notice = "数据已恢复。API Key 仍使用本机设置。" } }
                catch { store.error = error.localizedDescription }; incoming = nil
            }
            Button("取消", role: .cancel) { incoming = nil }
        }
    }
    private func upload() async {
        busy = true; defer { busy = false }
        do { try await CloudSnapshots.upload(JSONEncoder().encode(store.data)); cloudStatus = "备份已写入 iCloud Drive 本地容器，系统负责上传。\(Date().formatted(date: .abbreviated, time: .shortened))" }
        catch { cloudStatus = error.localizedDescription }
    }
    private func download() async {
        busy = true; defer { busy = false }
        do { incoming = try await CloudSnapshots.latest(); confirmRestore = true; cloudStatus = "已读取备份，等待确认恢复。" }
        catch { cloudStatus = error.localizedDescription }
    }
}
enum CloudSnapshots {
    static func directory() throws -> URL {
        guard FileManager.default.ubiquityIdentityToken != nil, let root = FileManager.default.url(forUbiquityContainerIdentifier: nil) else { throw ServiceFailure(message: "iCloud 不可用。请检查设备登录、iCloud Drive 及应用签名容器。") }
        let directory = root.appendingPathComponent("Documents/LittleStride", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true); return directory
    }
    static func upload(_ bytes: Data) async throws {
        try await Task.detached {
            let directory = try directory()
            let file = directory.appendingPathComponent("snapshot-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString).json")
            try bytes.write(to: file, options: .atomic)
        }.value
    }
    static func latest() async throws -> Data {
        try await Task.detached {
            let files = try FileManager.default.contentsOfDirectory(at: directory(), includingPropertiesForKeys: [.contentModificationDateKey, .ubiquitousItemDownloadingStatusKey]).filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
            guard let latest = files.first else { throw ServiceFailure(message: "尚未找到 iCloud 快照。新设备上请等待系统同步后重试。") }
            let values = try latest.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
            if let status = values.ubiquitousItemDownloadingStatus, status != .current {
                try FileManager.default.startDownloadingUbiquitousItem(at: latest)
                throw ServiceFailure(message: "云端快照正在下载，请稍后重试。")
            }
            return try Data(contentsOf: latest)
        }.value
    }
}
