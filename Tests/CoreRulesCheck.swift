import Foundation
@main struct RuleCheck {
    @MainActor static func main() async throws {
        let directory = URL.temporaryDirectory.appendingPathComponent("LittleStride-rulecheck-\(UUID())")
        let store = LearningStore(directory: directory)
        // Isolated temporary storage; never writes to the app database.
        store.data = AppData()
        let w = Weakness(subject: .math, title: "退位减法")
        store.data.weaknesses = [w]
        let original = Question(subject: .math, text: "52−28", answer: "24", weaknessID: w.id, needsVerification: false, screening: "收录")
        let variant = Question(subject: .math, text: "61−37", answer: "24", parentID: original.id, weaknessID: w.id, needsVerification: false, screening: "生成练习")
        store.data.questions = [original, variant]
        precondition(store.plan().count == 2)
        store.data.deferred[original.id.uuidString] = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        precondition(store.plan().count == 1)
        store.data.deferred = [:]
        let firstSheet = store.makeSheet([original, variant])
        let first = Attempt(questionID: original.id, sheetID: firstSheet.id, answer: "24", result: "正确", help: "独立", reason: "能", corrected: false)
        let second = Attempt(questionID: variant.id, sheetID: firstSheet.id, answer: "24", result: "正确", help: "独立", reason: "能", corrected: false)
        store.record([first, second], sheetID: firstSheet.id)
        precondition(store.points == 2)
        precondition(store.data.weaknesses[0].status != "暂时退出")
        store.record([first, second], sheetID: firstSheet.id)
        precondition(store.points == 2 && store.data.attempts.count == 2)
        let laterSheet = store.makeSheet([variant])
        var later = second; later.id = UUID(); later.sheetID = laterSheet.id; later.date = Calendar.current.date(byAdding: .day, value: 2, to: Date())!
        store.record([later], sheetID: laterSheet.id)
        precondition(store.data.weaknesses[0].status == "暂时退出")
        precondition(store.points == 8)
        try await store.persist()
        let bytes = try JSONEncoder().encode(store.data)
        let decoded = try JSONDecoder().decode(AppData.self, from: bytes)
        precondition(decoded.attempts.count == 3 && decoded.rewards.count == 4)
        precondition(!String(data: bytes, encoding: .utf8)!.contains("api-key"))
        try await store.restore(bytes)
        let reloaded = LearningStore(directory: directory)
        precondition(reloaded.data.attempts.count == 3 && reloaded.points == 8)
        var invalid = decoded; invalid.questions = []
        do { try await store.restore(JSONEncoder().encode(invalid)); preconditionFailure("Invalid relations were accepted") }
        catch StoreFailure.invalidRelations { }
        precondition(store.data.questions.count == 2)
        let recovery = try FileManager.default.contentsOfDirectory(at: directory.appendingPathComponent("Recovery"), includingPropertiesForKeys: nil)
        precondition(!recovery.isEmpty)
        print("PASS: plan, deferral, reward idempotency, cross-day mastery, JSON round trip, persisted reload, validated restore, recovery snapshot")
    }
}
