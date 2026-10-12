import Foundation
import Observation

@MainActor @Observable final class LearningStore {
    var data: AppData
    var error: String?
    var notice: String?
    private let file: URL
    private let persistenceQueue = DispatchQueue(label: "LittleStride.persistence", qos: .utility)
    private var persistenceEnabled = true
    init(directory: URL? = nil) {
        let folder = directory ?? URL.applicationSupportDirectory.appendingPathComponent("LittleStride", isDirectory: true)
        file = folder.appendingPathComponent("learning.json")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: file.path) {
                let loaded = try JSONDecoder().decode(AppData.self, from: Data(contentsOf: file))
                guard loaded.schemaVersion == 1 else { throw StoreFailure.invalidVersion }
                data = loaded
            } else { data = AppData() }
        } catch {
            data = AppData(); persistenceEnabled = false
            self.error = "本地数据无法读取，已停止写入以保护原文件。请导入有效备份或联系支持。\(error.localizedDescription)"
        }
    }
    func save() {
        guard persistenceEnabled else { return }
        data.updatedAt = Date()
        let snapshot = data, destination = file
        // Enqueue on the main actor in revision order; encoding photos must not block the UI.
        persistenceQueue.async { [weak self] in
            do { try JSONEncoder().encode(snapshot).write(to: destination, options: [.atomic, .completeFileProtectionUnlessOpen]) }
            catch {
                let message = "保存失败：\(error.localizedDescription)"
                Task { @MainActor [weak self] in self?.error = message }
            }
        }
    }
    func question(_ id: UUID) -> Question? { data.questions.first { $0.id == id } }
    func weakness(_ id: UUID?) -> Weakness? { data.weaknesses.first { $0.id == id } }
    func add(_ question: Question, knowledge: String) {
        var q = question
        if !knowledge.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let w = data.weaknesses.first(where: { $0.subject == q.subject && $0.title == knowledge }) { q.weaknessID = w.id }
            else { let w = Weakness(subject: q.subject, title: knowledge); data.weaknesses.append(w); q.weaknessID = w.id }
        }
        if let existing = data.questions.first(where: { $0.text == q.text && $0.subject == q.subject && $0.source == q.source }) {
            notice = "已有相同来源的题目，未重复入库。编号 \(existing.id.uuidString.prefix(8))"
        } else { data.questions.append(q) }
        save()
    }
    func addPhoto(_ image: Data) -> UUID {
        let asset = PhotoAsset(data: image); data.photos.append(asset); save(); return asset.id
    }
    func plan(on date: Date = Date()) -> [PlanItem] {
        let calendar = Calendar.current
        let completed = Set(data.attempts.filter { calendar.isDate($0.date, inSameDayAs: date) }.map(\.questionID))
        let candidates = data.questions.filter { q in
            !q.needsVerification && ["收录", "生成练习"].contains(q.screening) && data.subjects.contains(q.subject)
            && !completed.contains(q.id)
            && (data.deferred[q.id.uuidString].map { calendar.startOfDay(for: $0) <= calendar.startOfDay(for: date) } ?? true)
            && (weakness(q.weaknessID).map { $0.status != "暂时退出" && calendar.startOfDay(for: $0.nextDate) <= calendar.startOfDay(for: date) } ?? true)
        }.sorted {
            let a = weakness($0.weaknessID), b = weakness($1.weaknessID)
            if a?.priority != b?.priority { return a?.priority == "P1" }
            return (a?.nextDate ?? $0.createdAt) < (b?.nextDate ?? $1.createdAt)
        }
        let todayAttempts = data.attempts.filter { calendar.isDate($0.date, inSameDayAs: date) }
        let completedQuestions = Set(todayAttempts.map(\.questionID)).compactMap { question($0) }
        let spent = completedQuestions.reduce(0) { $0 + ($1.subject == .english ? 2 : 3) }
        var result: [PlanItem] = [], used: [String: Int] = [:]
        var weakIDs = Set(completedQuestions.compactMap(\.weaknessID))
        var remaining = max(0, data.dailyMinutes - spent)
        for q in candidates {
            if used[q.subject.rawValue, default: 0] >= data.counts[q.subject.rawValue, default: 1] { continue }
            if let id = q.weaknessID, !weakIDs.contains(id), weakIDs.count >= 2 { continue }
            let minutes = q.subject == .english ? 2 : 3
            guard minutes <= remaining else { continue }
            result.append(.init(question: q, minutes: minutes)); used[q.subject.rawValue, default: 0] += 1
            if let id = q.weaknessID { weakIDs.insert(id) }; remaining -= minutes
        }
        return result
    }
    func deferQuestions(_ ids: [UUID], days: Int) {
        let date = Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()
        for id in ids { data.deferred[id.uuidString] = date }
        save(); notice = "已延后，后续计划仍遵守每日时间上限。"
    }
    func makeSheet(_ questions: [Question]) -> PracticeSheet {
        let sheet = PracticeSheet(questions: questions); data.sheets.append(sheet); save(); return sheet
    }
    func record(_ attempts: [Attempt], sheetID: UUID) {
        guard let index = data.sheets.firstIndex(where: { $0.id == sheetID }), !data.sheets[index].completed else { notice = "该练习单已记录，未重复计数。"; return }
        data.attempts.append(contentsOf: attempts)
        data.sheets[index].completed = true
        for a in attempts {
            if ["正确", "部分正确", "错误"].contains(a.result), let id = question(a.questionID)?.weaknessID, let wi = data.weaknesses.firstIndex(where: { $0.id == id }) {
                let related = Set(data.questions.filter { $0.weaknessID == id }.map(\.id))
                let independent = data.attempts.filter { related.contains($0.questionID) && $0.result == "正确" && $0.help == "独立" }
                let dates = Set(independent.map { Calendar.current.startOfDay(for: $0.date) })
                let variant = independent.contains { question($0.questionID)?.parentID != nil }
                let explained = independent.contains { $0.reason == "能" }
                let mastered = dates.count >= 2 && variant && explained
                data.weaknesses[wi].status = mastered ? "暂时退出" : "复习中"
                data.weaknesses[wi].nextDate = Calendar.current.date(byAdding: .day, value: a.result == "正确" ? 2 : 1, to: a.date) ?? Date()
                let source = "mastery:\(id)"
                if mastered && !data.rewards.contains(where: { $0.source == source }) { data.rewards.append(.init(source: source, points: 5)) }
            }
            let source = "practice:\(a.questionID):\(Calendar.current.startOfDay(for: a.date).timeIntervalSince1970)"
            let daily = data.rewards.filter { $0.source.hasPrefix("practice:") && Calendar.current.isDate($0.date, inSameDayAs: a.date) }.count
            if (a.result == "正确" || a.corrected), a.result != "未作答", daily < 5, !data.rewards.contains(where: { $0.source == source }) {
                data.rewards.append(.init(source: source, points: 1, date: a.date))
            }
        }
        save(); notice = "已保存作答历史并更新复习安排。"
    }
    var points: Int { data.rewards.reduce(0) { $0 + $1.points } }
    var practiceCount: Int { data.rewards.filter { $0.source.hasPrefix("practice:") }.count }
    func backup() throws -> URL {
        let url = URL.temporaryDirectory.appendingPathComponent("LittleStride-\(UUID().uuidString.prefix(8)).json")
        try JSONEncoder().encode(data).write(to: url, options: .atomic); return url
    }
    func restore(_ bytes: Data) throws {
        let incoming = try JSONDecoder().decode(AppData.self, from: bytes)
        guard incoming.schemaVersion == 1 else { throw StoreFailure.invalidVersion }
        guard incoming.profile.birthDate == nil || incoming.profile.currentAge != nil else {
            throw StoreFailure.invalidRelations
        }
        let ids = Set(incoming.questions.map(\.id))
        let weaknessIDs = Set(incoming.weaknesses.map(\.id))
        let photoIDs = Set(incoming.photos.map(\.id))
        let sheetIDs = Set(incoming.sheets.map(\.id))
        guard ids.count == incoming.questions.count,
              weaknessIDs.count == incoming.weaknesses.count,
              photoIDs.count == incoming.photos.count,
              sheetIDs.count == incoming.sheets.count,
              Set(incoming.attempts.map(\.id)).count == incoming.attempts.count,
              Set(incoming.rewards.map(\.source)).count == incoming.rewards.count,
              incoming.questions.allSatisfy({ q in
                  (q.weaknessID.map { weaknessIDs.contains($0) } ?? true)
                  && (q.parentID.map { ids.contains($0) } ?? true)
                  && (q.imageID.map { photoIDs.contains($0) } ?? true)
              }),
              incoming.attempts.allSatisfy({ ids.contains($0.questionID) && ($0.sheetID.map { sheetIDs.contains($0) } ?? true) }),
              incoming.sheets.allSatisfy({ $0.questions.allSatisfy { ids.contains($0.id) } }),
              [5, 10].contains(incoming.dailyMinutes),
              incoming.rewards.allSatisfy({ $0.points >= 0 }) else { throw StoreFailure.invalidRelations }
        // Drain earlier writes before preserving the database being replaced.
        persistenceQueue.sync {}
        // Preserve the current database before replacement, outside temporary storage.
        let backupFolder = file.deletingLastPathComponent().appendingPathComponent("Recovery", isDirectory: true)
        try FileManager.default.createDirectory(at: backupFolder, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.copyItem(at: file, to: backupFolder.appendingPathComponent("before-restore-\(UUID().uuidString).json"))
        }
        data = incoming; persistenceEnabled = true; save()
    }
}
enum StoreFailure: LocalizedError {
    case invalidVersion, invalidRelations
    var errorDescription: String? { switch self { case .invalidVersion: "备份格式版本不支持。"; case .invalidRelations: "备份的题目编号或作答关联无效。" } }
}
