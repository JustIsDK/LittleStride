import Foundation

enum Subject: String, Codable, CaseIterable, Identifiable {
    case math = "数学", chinese = "语文", english = "英语"
    var id: String { rawValue }
    var symbol: String { switch self { case .math: "number"; case .chinese: "book"; case .english: "textformat.abc" } }
}
struct ChildProfile: Codable {
    var nickname = "小朋友"
    var age = ""
    var grade = "三年级"
    var region = "上海"
    var term = "上学期"
    var textbooks: [String: String] = [:]
    var progress: [String: String] = [:]
    var observations: [String: String] = [:]
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
    var baseURL = ""
    var model = ""
    var api = "Responses"
    var authHeader = "Authorization"
    var bearer = true
}
struct PhotoAsset: Codable, Identifiable {
    var id = UUID()
    var data: Data
    var date = Date()
}
struct AppData: Codable {
    var schemaVersion = 1
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
    var reminder = false
    var reminderHour = 19
    var reminderMinute = 45
    var ai = AIConfiguration()
    var updatedAt = Date()
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
