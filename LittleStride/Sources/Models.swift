import Foundation

enum Subject: String, Codable, CaseIterable, Identifiable {
    case math = "数学", chinese = "语文", english = "英语"
    var id: String { rawValue }
    var symbol: String { switch self { case .math: "number"; case .chinese: "book"; case .english: "textformat.abc" } }
}
struct ChildProfile: Codable {
    var nickname = "小朋友"
    var age = "" // 仅兼容旧备份，不作为当前年龄或出生日期使用。
    var birthDate: String? // 日期本身，YYYY-MM-DD；不含时区。
    var grade = "三年级"
    var region = "上海"
    var term = "上学期"
    var textbooks: [String: String] = [:]
    var progress: [String: String] = [:]
    var observations: [String: String] = [:]

    static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    var birthDateValue: Date? {
        guard let birthDate else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: birthDate), Self.dateString(date) == birthDate else { return nil }
        return date
    }
    var currentAge: Int? {
        let calendar = Calendar(identifier: .gregorian)
        guard let date = birthDateValue, date <= Date() else { return nil }
        return calendar.dateComponents([.year], from: date, to: calendar.startOfDay(for: Date())).year
    }
}
struct Question: Codable, Identifiable {
    var id = UUID()
    var subject: Subject
    var text: String
    var answer: String
    var explanation = ""
    var originalAnswer = ""
    var source = "手动录入"
    var imageID: UUID?
    var parentID: UUID?
    var weaknessID: UUID?
    var evidence = ""
    var possibleCause = ""
    var needsVerification = true
    var screening = "待核实"
    var createdAt = Date()
    var deletedAt: Date?
}
struct Weakness: Codable, Identifiable {
    var id = UUID()
    var subject: Subject
    var title: String
    var priority = "P2"
    var status = "待首次复习"
    var nextDate = Date()
}
struct Attempt: Codable, Identifiable {
    var id = UUID()
    var questionID: UUID
    var sheetID: UUID?
    var date = Date()
    var answer: String
    var result: String
    var help: String
    var reason: String
    var note = ""
    var corrected: Bool
}
struct PracticeSheet: Codable, Identifiable {
    var id = UUID()
    var createdAt = Date()
    var questions: [Question]
    var completed = false
    var code: String { "LS-" + id.uuidString.prefix(8).uppercased() }
}
struct RewardEvent: Codable, Identifiable {
    var id = UUID()
    var source: String
    var points: Int
    var date = Date()
}
struct AIConfiguration: Codable {
    var provider: String?
    var credentialScope: String?
    var reasoningEffort: String?
    var baseURL = ""
    var model = ""
    var api = "Responses"
    var authHeader = "Authorization"
    var bearer = true
    var keyAccount: String { "api-key:" + baseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
}
enum AIProvider: String, CaseIterable, Identifiable {
    case custom, openai, claude, deepseek, qwen, glm
    var id: String { rawValue }
    var name: String {
        switch self { case .custom: "自定义 / 中转服务"; case .openai: "OpenAI · GPT"; case .claude: "Anthropic · Claude"; case .deepseek: "DeepSeek"; case .qwen: "通义千问"; case .glm: "智谱 · GLM" }
    }
    var baseURL: String {
        switch self {
        case .custom: ""
        case .openai: "https://api.openai.com/v1"
        case .claude: "https://api.anthropic.com/v1"
        case .deepseek: "https://api.deepseek.com/v1"
        case .qwen: "https://dashscope.aliyuncs.com/compatible-mode/v1"
        case .glm: "https://open.bigmodel.cn/api/paas/v4"
        }
    }
    var api: String { self == .claude ? "Anthropic Messages" : self == .openai ? "Responses" : "Chat Completions" }
    var consoleURL: URL? {
        guard self != .custom else { return nil }
        let address = switch self {
        case .custom: ""
        case .openai: "https://platform.openai.com/api-keys"
        case .claude: "https://platform.claude.com/settings/keys"
        case .deepseek: "https://platform.deepseek.com/api_keys"
        case .qwen: "https://bailian.console.aliyun.com/"
        case .glm: "https://open.bigmodel.cn/"
        }
        return URL(string: address)
    }
    var guide: String {
        switch self {
        case .custom: "向服务商获取完整 Base URL、接口协议、模型 ID 和 API Key。照抄路径前缀（例如 /v1），不要复制 /responses 或 /chat/completions。Codex 配置的 base_url 对应服务地址，model 对应模型 ID，wire_api = responses 对应 Responses。"
        case .openai: "登录 OpenAI API 平台，在 API Keys 创建密钥，并检查项目额度和模型访问权限。模型 ID 从平台文档或模型列表复制。ChatGPT 订阅与 API 用量分开管理。"
        case .claude: "登录 Claude 开发者控制台，在 API Keys 创建密钥。模型 ID 从控制台的 API 文档复制。官方接口使用 Anthropic Messages、x-api-key 请求头，不加 Bearer；Claude 中转商可能提供不同协议。"
        case .deepseek: "登录 DeepSeek 开放平台，在 API Keys 创建密钥，复制官方模型 ID。文本连接通过不代表可识别照片；请先确认所选模型和接口支持图片输入，不支持时改用有视觉能力的服务。"
        case .qwen: "登录阿里云百炼，开通模型服务并创建 API Key。从模型广场复制有视觉能力的模型 ID。此预设为中国内地兼容接口；其他地域须使用相应地域的地址与密钥。"
        case .glm: "登录智谱开放平台，在 API Keys 创建密钥。从模型文档复制模型 ID，拍照分析需选择支持视觉输入的模型。"
        }
    }
}
struct PhotoAsset: Codable, Identifiable {
    var id = UUID()
    var data: Data? // Only legacy files and portable backups embed bytes.
    var date = Date()
}
struct AppData: Codable {
    var schemaVersion = 2
    var profile = ChildProfile()
    var questions: [Question] = []
    var weaknesses: [Weakness] = []
    var attempts: [Attempt] = []
    var sheets: [PracticeSheet] = []
    var rewards: [RewardEvent] = []
    var photos: [PhotoAsset] = []
    var claimedPet = false
    var subjects: [Subject] = [.math, .chinese]
    var counts: [String: Int] = ["数学": 2, "语文": 1, "英语": 1]
    var dailyMinutes = 10
    var deferred: [String: Date] = [:]
    var todaySelections: [String: Date]?
    var reminder = false
    var reminderHour = 19
    var reminderMinute = 45
    var ai = AIConfiguration()
    var updatedAt = Date()
    /// Stable identity used by CloudKit sharing. It is deliberately separate from the local file path.
    var sharedProfileID: UUID?
}
struct PlanItem: Identifiable {
    var question: Question
    var minutes: Int
    var id: UUID { question.id }
}
struct ObservationDimension: Identifiable {
    var id: String
    var group: String
    var title: String
    var prompt: String
    static let all: [Self] = [
        .init(id: "mcalc", group: "数学", title: "计算步骤", prompt: "熟悉的计算能否按步骤完成，并检查进退位？"),
        .init(id: "mconcept", group: "数学", title: "概念与数量关系", prompt: "能否说明为什么这样列式？"),
        .init(id: "mread", group: "数学", title: "读题与应用", prompt: "能否说清已知什么、要求什么？"),
        .init(id: "cread", group: "语文", title: "识字与流畅阅读", prompt: "能否独立读通课文？"),
        .init(id: "cmeaning", group: "语文", title: "阅读理解", prompt: "能否复述并找到回答依据？"),
        .init(id: "cwrite", group: "语文", title: "书面表达", prompt: "能否把一件事按顺序写清楚？"),
        .init(id: "elisten", group: "英语", title: "听懂与认读", prompt: "能否听懂、认读课内词句？"),
        .init(id: "espell", group: "英语", title: "拼写与回忆", prompt: "合上书后能否拼写学过的词？"),
        .init(id: "euse", group: "英语", title: "句型运用", prompt: "换个情境能否用学过的句型？"),
        .init(id: "start", group: "学习过程", title: "开始与推进", prompt: "能否开始并完成一小段约定任务？"),
        .init(id: "check", group: "学习过程", title: "检查与订正", prompt: "能否按约定检查并处理错误？"),
        .init(id: "recall", group: "学习过程", title: "间隔回忆与求助", prompt: "隔几天能否回忆方法，说清卡点？")
    ]
}

struct AITiming: Codable {
    var preparation: Double?
    var ocr: Double?
    var connection: Double?
    var upload: Double?
    var wait: Double?
    var receive: Double?
    var parse: Double?
    mutating func merge(_ value: Self) {
        preparation = value.preparation ?? preparation; ocr = value.ocr ?? ocr
        connection = value.connection ?? connection; upload = value.upload ?? upload
        wait = value.wait ?? wait; receive = value.receive ?? receive
        if let parsed = value.parse { parse = (parse ?? 0) + parsed }
    }
    var summary: String {
        let values: [(String, Double?)] = [("压缩", preparation), ("OCR", ocr), ("连接", connection), ("上传", upload), ("等待响应", wait), ("接收", receive), ("解析", parse)]
        return " " + values.compactMap { name, seconds in seconds.map { name + String(format: " %.1f 秒", $0) } }.joined(separator: " · ")
    }
}
