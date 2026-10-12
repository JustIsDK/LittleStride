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
        let customStore = LearningStore(directory: directory.appendingPathComponent("manual"))
        let future = Date().addingTimeInterval(86400 * 5)
        let knowledge = Weakness(subject: .math, title: "手动指定", status: "暂时退出", nextDate: future)
        var chosen = Question(subject: .math, text: "今天想练的题", answer: "1", weaknessID: knowledge.id, needsVerification: false, screening: "收录")
        let waiting = Question(subject: .math, text: "未核实的题", answer: "1", weaknessID: knowledge.id)
        customStore.data.weaknesses = [knowledge]
        customStore.data.questions = [chosen, waiting]
        customStore.data.deferred[chosen.id.uuidString] = future
        precondition(customStore.plan().isEmpty)
        let added = await customStore.addToToday(chosen.id)
        precondition(added && customStore.plan().first?.id == chosen.id)
        let duplicate = await customStore.addToToday(chosen.id)
        precondition(duplicate && customStore.plan().count == 1)
        let invalidChoice = await customStore.addToToday(waiting.id)
        precondition(!invalidChoice)
        let nextDay = Date().addingTimeInterval(86400)
        precondition(customStore.plan(on: nextDay).isEmpty)
        let manualReload = LearningStore(directory: directory.appendingPathComponent("manual"))
        precondition(manualReload.isSelectedToday(chosen.id))
        await customStore.removeFromToday(chosen.id)
        precondition(customStore.plan().isEmpty)
        customStore.data.counts[Subject.math.rawValue] = 1
        customStore.data.attempts = [Attempt(questionID: chosen.id, answer: "1", result: "正确", help: "独立", reason: "能", corrected: false)]
        let extra = Question(subject: .math, text: "另一题", answer: "2", weaknessID: knowledge.id, needsVerification: false, screening: "收录")
        customStore.data.questions.append(extra)
        let overflow = await customStore.addToToday(extra.id)
        precondition(!overflow && !customStore.isSelectedToday(extra.id))
        customStore.data.attempts = []
        await customStore.addKnowledgeToToday(knowledge.id)
        precondition(customStore.isSelectedToday(extra.id))
        let displaced = await customStore.addToToday(chosen.id)
        precondition(!displaced && customStore.isSelectedToday(extra.id) && !customStore.isSelectedToday(chosen.id))
        await customStore.removeFromToday(extra.id)
        customStore.data.dailyMinutes = 2
        let noTime = await customStore.addToToday(chosen.id)
        precondition(!noTime && customStore.plan().isEmpty)
        customStore.data.dailyMinutes = 15
        let photo = try customStore.addPhoto(Data([1, 2, 3]))
        chosen.imageID = photo; customStore.data.questions[0] = chosen
        try await customStore.persist()
        try await customStore.discardCollectedPhoto(photo)
        precondition(customStore.photoData(photo) != nil)
        customStore.data.questions[0].imageID = nil
        try await customStore.persist()
        try await customStore.discardCollectedPhoto(photo)
        precondition(customStore.photoData(photo) == nil && !customStore.data.photos.contains { $0.id == photo })
        let cleanedReload = LearningStore(directory: directory.appendingPathComponent("manual"))
        precondition(cleanedReload.data.questions[0].imageID == nil)
        print("PASS: manual selection, overdue override, duplicate selection, verification guard, daily expiry, persisted selections, daily subject cap, referenced photo protection, collected photo deletion")
        print("PASS: plan, deferral, reward idempotency, cross-day mastery, JSON round trip, persisted reload, validated restore, recovery snapshot")
    }
}
