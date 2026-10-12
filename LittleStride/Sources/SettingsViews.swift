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
    var body: some View {
        @Bindable var store = store
        Form {
            Section("个人服务连接") {
                Picker("接口协议", selection: $store.data.ai.api) {
                    Text("Responses").tag("Responses")
                    Text("Chat Completions").tag("Chat Completions")
                }
                TextField("HTTPS Base URL（可含 /v1）", text: $store.data.ai.baseURL).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                TextField("准确模型 ID", text: $store.data.ai.model).textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField(keyPresent ? "已保存 Key；留空不修改" : "API Key", text: $key).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("认证请求头名称", text: $store.data.ai.authHeader).textInputAutocapitalization(.never).autocorrectionDisabled()
                Toggle("添加 Bearer 前缀", isOn: $store.data.ai.bearer)
                Text("Key 仅保存在本机 Keychain，不随备份或 iCloud 同步。换设备需重新填写。请求采用非流式以兼容结构化分析。").font(.caption)
            }
            Section("保存与检测") {
                Button("保存连接配置") { save() }
                Button(busy ? "检测中…" : "检测文本与结构化输出") { Task { await test() } }.disabled(busy)
                Text(testResult).font(.caption).textSelection(.enabled)
                Text("此检测会实际访问配置的服务并可能产生费用；图片能力需在照片分析时验证。不自动切换服务商。").font(.caption).foregroundStyle(.secondary)
                if keyPresent { Button("删除本机 Key", role: .destructive) { do { try SecretStore.save(""); keyPresent = false; key = "" } catch { store.error = error.localizedDescription } } }
            }
        }.navigationTitle("AI 服务设置").stridePage().onAppear { keyPresent = !SecretStore.load().isEmpty }
        .onDisappear { key = ""; store.save() }
    }
    @discardableResult private func save() -> Bool {
        do {
            _ = try AIService(configuration: store.data.ai).endpoint()
            if !key.isEmpty { try SecretStore.save(key); key = "" }
            keyPresent = !SecretStore.load().isEmpty; store.save(); testResult = "配置已保存，尚未检测当前连接。"; return true
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
