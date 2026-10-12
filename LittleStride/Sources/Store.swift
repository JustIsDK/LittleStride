import Foundation
import Observation

@MainActor @Observable final class LearningStore {
    var data: AppData
    var error: String?
    var notice: String?
    var writing = false
    private let file: URL
    private let persistenceQueue = DispatchQueue(label: "LittleStride.persistence", qos: .utility)
    private var persistenceEnabled = true
    var canSave: Bool { persistenceEnabled }
    private var pinnedPhotos = Set<UUID>()
    private var photosFolder: URL { file.deletingLastPathComponent().appendingPathComponent("Photos", isDirectory: true) }
    init(directory: URL? = nil) {
        let folder = directory ?? URL.applicationSupportDirectory.appendingPathComponent("LittleStride", isDirectory: true)
        file = folder.appendingPathComponent("learning.json")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: file.path) {
                let loaded = try JSONDecoder().decode(AppData.self, from: Data(contentsOf: file))
                guard [1, 2].contains(loaded.schemaVersion) else { throw StoreFailure.invalidVersion }
                data = loaded
            } else { data = AppData() }
            try FileManager.default.createDirectory(at: photosFolder, withIntermediateDirectories: true)
            var migrated = data
            migrated.schemaVersion = 2
            for index in migrated.photos.indices {
                if let bytes = migrated.photos[index].data {
                    try bytes.write(to: photoURL(migrated.photos[index].id), options: [.atomic, .completeFileProtectionUnlessOpen])
                    migrated.photos[index].data = nil
                }
            }
            if data.schemaVersion != 2 || data.photos.contains(where: { $0.data != nil }) {
                try JSONEncoder().encode(migrated).write(to: file, options: [.atomic, .completeFileProtectionUnlessOpen])
                data = migrated
            }
        } catch {
            data = AppData(); persistenceEnabled = false
            self.error = "本地数据无法读取，已停止写入以保护原文件。请导入有效备份或联系支持。\(error.localizedDescription)"
        }
    }
    func save() {
        guard !writing else { return }
        guard persistenceEnabled else { error = "本地数据受保护，无法保存。请先恢复有效备份。"; return }
        data.updatedAt = Date()
        let snapshot = data, destination = file
        // Keep structured writes ordered without blocking the UI.
        persistenceQueue.async { [weak self] in
            do { try JSONEncoder().encode(snapshot).write(to: destination, options: [.atomic, .completeFileProtectionUnlessOpen]) }
            catch {
                let message = "保存失败：\(error.localizedDescription)"
                Task { @MainActor [weak self] in self?.error = message }
            }
        }
    }
    func confirm(_ changes: () -> Void) async -> Bool {
        guard !writing, persistenceEnabled else { error = "本地数据暂时无法保存，请先恢复有效备份。"; return false }
        writing = true; defer { writing = false }
        let previous = data
        changes()
        do { try await persist(); return true }
        catch { data = previous; self.error = "保存失败：\(error.localizedDescription)"; return false }
    }
    func persist() async throws {
        guard persistenceEnabled else { throw StoreFailure.persistenceDisabled }
        data.updatedAt = Date()
        let snapshot = data, destination = file
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            persistenceQueue.async {
                do {
                    try JSONEncoder().encode(snapshot).write(to: destination, options: [.atomic, .completeFileProtectionUnlessOpen])
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
    func releasePhoto(_ id: UUID) { pinnedPhotos.remove(id) }
    func discardCollectedPhoto(_ id: UUID) async throws {
        guard !writing else { throw StoreFailure.persistenceDisabled }
        writing = true; defer { writing = false }
        releasePhoto(id)
        let protected = try await protectedPhotos()
        guard !protected.contains(id) else { return }
        let previous = data
        data.photos.removeAll { $0.id == id }
        do { try await persist() } catch { data = previous; throw error }
        let url = photoURL(id)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
    func photoURL(_ id: UUID) -> URL { photosFolder.appendingPathComponent(id.uuidString + ".jpg") }
    func photoData(_ id: UUID) -> Data? { try? Data(contentsOf: photoURL(id)) }
    func knowledgeID(subject: Subject, title: String) -> UUID? {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        if let existing = data.weaknesses.first(where: { $0.subject == subject && $0.title == title }) { return existing.id }
        let weakness = Weakness(subject: subject, title: title); data.weaknesses.append(weakness); return weakness.id
    }
    func question(_ id: UUID) -> Question? { data.questions.first { $0.id == id } }
    func weakness(_ id: UUID?) -> Weakness? { data.weaknesses.first { $0.id == id } }
    func add(_ question: Question, knowledge: String) {
        var q = question
        q.weaknessID = knowledgeID(subject: q.subject, title: knowledge)
        if let existing = data.questions.first(where: { $0.text == q.text && $0.subject == q.subject && $0.source == q.source }) {
            notice = "已有相同来源的题目，未重复入库。编号 \(existing.id.uuidString.prefix(8))"
        } else {
            data.questions.append(q)
            if q.parentID == nil, let wi = data.weaknesses.firstIndex(where: { $0.id == q.weaknessID }) {
                data.weaknesses[wi].status = "待首次复习"; data.weaknesses[wi].nextDate = Date()
            }
        }
    }
    func addPhoto(_ image: Data) throws -> UUID {
        guard persistenceEnabled else { throw StoreFailure.persistenceDisabled }
        let asset = PhotoAsset(data: nil)
        try image.write(to: photoURL(asset.id), options: [.atomic, .completeFileProtectionUnlessOpen])
        data.photos.append(asset); pinnedPhotos.insert(asset.id); save(); return asset.id
    }
    func plan(on date: Date = Date()) -> [PlanItem] {
        let calendar = Calendar.current
        let completed = Set(data.attempts.filter { calendar.isDate($0.date, inSameDayAs: date) }.map(\.questionID))
        let selected = Set((data.todaySelections ?? [:]).filter { calendar.isDate($0.value, inSameDayAs: date) }.keys)
        let candidates = data.questions.filter { q in
            q.deletedAt == nil && !q.needsVerification && ["收录", "生成练习"].contains(q.screening) && data.subjects.contains(q.subject)
            && !completed.contains(q.id)
            && (selected.contains(q.id.uuidString) || (data.deferred[q.id.uuidString].map { calendar.startOfDay(for: $0) <= calendar.startOfDay(for: date) } ?? true))
            && (selected.contains(q.id.uuidString) || (weakness(q.weaknessID).map { $0.status != "暂时退出" && calendar.startOfDay(for: $0.nextDate) <= calendar.startOfDay(for: date) } ?? true))
        }.sorted {
            let selectedA = selected.contains($0.id.uuidString), selectedB = selected.contains($1.id.uuidString)
            if selectedA != selectedB { return selectedA }
            if selectedA && selectedB { return (data.todaySelections?[$0.id.uuidString] ?? .distantPast) < (data.todaySelections?[$1.id.uuidString] ?? .distantPast) }
            let a = weakness($0.weaknessID), b = weakness($1.weaknessID)
            if a?.priority != b?.priority { return a?.priority == "P1" }
            return (a?.nextDate ?? $0.createdAt) < (b?.nextDate ?? $1.createdAt)
        }
        let todayAttempts = data.attempts.filter { calendar.isDate($0.date, inSameDayAs: date) }
        let completedQuestions = Set(todayAttempts.map(\.questionID)).compactMap { question($0) }
        let spent = completedQuestions.reduce(0) { $0 + ($1.subject == .english ? 2 : 3) }
        var result: [PlanItem] = [], used: [String: Int] = [:]
        for q in completedQuestions { used[q.subject.rawValue, default: 0] += 1 }
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
    func isSelectedToday(_ id: UUID, on date: Date = Date()) -> Bool {
        data.todaySelections?[id.uuidString].map { Calendar.current.isDate($0, inSameDayAs: date) } ?? false
    }
    func addToToday(_ id: UUID, on date: Date = Date()) async -> Bool {
        guard let q = question(id), q.deletedAt == nil, !q.needsVerification, ["收录", "生成练习"].contains(q.screening) else {
            error = "请先核实题目并选择收录或生成练习。"; return false
        }
        guard data.subjects.contains(q.subject) else { error = "请先在学科与题量中开启\(q.subject.rawValue)。"; return false }
        guard !data.attempts.contains(where: { $0.questionID == id && Calendar.current.isDate($0.date, inSameDayAs: date) }) else {
            error = "这道题今天已经完成。"; return false
        }
        let previous = data.todaySelections
        var selected = (previous ?? [:]).filter { Calendar.current.isDate($0.value, inSameDayAs: date) }
        if selected[id.uuidString] == nil { selected[id.uuidString] = date }
        data.todaySelections = selected
        let planned = Set(plan(on: date).map(\.id))
        data.todaySelections = previous
        guard planned.contains(id), selected.keys.allSatisfy({ key in
            guard let uuid = UUID(uuidString: key) else { return false }
            return planned.contains(uuid) || data.attempts.contains { $0.questionID == uuid && Calendar.current.isDate($0.date, inSameDayAs: date) }
        }) else { error = "今天的时间、学科题量或知识点上限已满，请先调整计划。"; return false }
        if await confirm({ data.todaySelections = selected }) { notice = "已加入今天练习，可在首页预览练习单。"; return true }
        return false
    }
    func addKnowledgeToToday(_ weaknessID: UUID) async {
        let candidates = data.questions.filter { $0.deletedAt == nil && $0.weaknessID == weaknessID && !$0.needsVerification && ["收录", "生成练习"].contains($0.screening) }
            .sorted { $0.createdAt > $1.createdAt }
        guard let q = candidates.first(where: { q in
            !data.attempts.contains { $0.questionID == q.id && Calendar.current.isDateInToday($0.date) }
        }) else { error = "这个知识点暂无已核实且今天未完成的题目。"; return }
        _ = await addToToday(q.id)
    }
    func removeFromToday(_ id: UUID) async {
        if await confirm({ data.todaySelections?.removeValue(forKey: id.uuidString) }) { notice = "已取消指定；到期题仍可能按自动计划出现。" }
    }
    func deleteQuestion(_ id: UUID) async -> Bool {
        guard let index = data.questions.firstIndex(where: { $0.id == id && $0.deletedAt == nil }) else { return false }
        let imageID = data.questions[index].imageID
        // Keep the record for printed sheets, attempts and generated-question ancestry.
        guard await confirm({
            data.questions[index].deletedAt = Date()
            data.questions[index].imageID = nil
            data.todaySelections?.removeValue(forKey: id.uuidString)
            data.deferred.removeValue(forKey: id.uuidString)
        }) else { return false }
        if let imageID {
            do { try await discardCollectedPhoto(imageID) }
            catch let cleanupError { self.error = "题目已删除，原图清理失败：" + cleanupError.localizedDescription }
        }
        return true
    }
    func deferQuestions(_ ids: [UUID], days: Int) async {
        let date = Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()
        if await confirm({ for id in ids { data.deferred[id.uuidString] = date; data.todaySelections?.removeValue(forKey: id.uuidString) } }) { notice = "已延后，后续计划仍遵守每日时间上限。" }
    }
    func makeSheet(_ questions: [Question]) -> PracticeSheet {
        let sheet = PracticeSheet(questions: questions); data.sheets.append(sheet); return sheet
    }
    func record(_ attempts: [Attempt], sheetID: UUID) {
        guard let index = data.sheets.firstIndex(where: { $0.id == sheetID }), !data.sheets[index].completed else { notice = "该练习单已记录，未重复计数。"; return }
        data.attempts.append(contentsOf: attempts)
        data.sheets[index].completed = true
        for a in attempts {
            if ["正确", "部分正确", "错误"].contains(a.result), let id = question(a.questionID)?.weaknessID, let wi = data.weaknesses.firstIndex(where: { $0.id == id }) {
                let related = Set(data.questions.filter { $0.weaknessID == id }.map(\.id))
                let failures = data.attempts.filter { related.contains($0.questionID) && ($0.result != "正确" || $0.help != "独立") }.map(\.date)
                let reopened = data.questions.filter { related.contains($0.id) && $0.parentID == nil }.map(\.createdAt).max() ?? .distantPast
                let since = max(failures.max() ?? .distantPast, reopened)
                let independent = data.attempts.filter { related.contains($0.questionID) && $0.date > since && $0.result == "正确" && $0.help == "独立" }
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
    }
    var points: Int { data.rewards.reduce(0) { total, reward in let sum = total.addingReportingOverflow(reward.points); return sum.overflow ? Int.max : sum.partialValue } }
    var practiceCount: Int { data.rewards.filter { $0.source.hasPrefix("practice:") }.count }
    func backupBytes() async throws -> Data {
        var snapshot = data
        let referenced = Set(data.questions.compactMap(\.imageID) + data.sheets.flatMap { $0.questions.compactMap(\.imageID) })
        snapshot.photos.removeAll { !referenced.contains($0.id) }
        let folder = photosFolder
        return try await Task.detached(priority: .utility) {
            var portable = snapshot
            portable.schemaVersion = 1
            for index in portable.photos.indices {
                portable.photos[index].data = try Data(contentsOf: folder.appendingPathComponent(portable.photos[index].id.uuidString + ".jpg"))
            }
            return try JSONEncoder().encode(portable)
        }.value
    }
    func backup() async throws -> URL {
        let bytes = try await backupBytes()
        let url = try AppCache.file(name: "LittleStride-\(UUID().uuidString).json")
        try await Task.detached(priority: .utility) { try bytes.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen]) }.value
        return url
    }
    func restore(_ bytes: Data) async throws {
        guard !writing else { throw StoreFailure.persistenceDisabled }
        writing = true; defer { writing = false }
        var incoming = try await Task.detached(priority: .utility) { try JSONDecoder().decode(AppData.self, from: bytes) }.value
        guard [1, 2].contains(incoming.schemaVersion) else { throw StoreFailure.invalidVersion }
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
              incoming.attempts.allSatisfy({ attempt in
                  ids.contains(attempt.questionID) && (attempt.sheetID.map { sheetID in
                      incoming.sheets.first { $0.id == sheetID }?.questions.contains { $0.id == attempt.questionID } ?? false
                  } ?? true)
              }),
              incoming.sheets.allSatisfy({ sheet in
                  Set(sheet.questions.map(\.id)).count == sheet.questions.count && sheet.questions.allSatisfy { q in
                      ids.contains(q.id) && (q.imageID.map { photoIDs.contains($0) } ?? true)
                      && (q.weaknessID.map { weaknessIDs.contains($0) } ?? true)
                      && (q.parentID.map { ids.contains($0) } ?? true)
                  }
              }),
              [5, 10].contains(incoming.dailyMinutes),
              (0...23).contains(incoming.reminderHour), (0...59).contains(incoming.reminderMinute),
              (incoming.todaySelections ?? [:]).keys.allSatisfy({ UUID(uuidString: $0).map { ids.contains($0) } ?? false }),
              incoming.counts.allSatisfy({ Subject(rawValue: $0.key) != nil && (1...3).contains($0.value) }),
              incoming.rewards.allSatisfy({ [1, 5].contains($0.points) }),
              incoming.photos.allSatisfy({ $0.data != nil || FileManager.default.fileExists(atPath: photoURL($0.id).path) }),
              incoming.questions.allSatisfy({ q in q.weaknessID.flatMap { id in incoming.weaknesses.first { $0.id == id } }.map { $0.subject == q.subject } ?? true }) else { throw StoreFailure.invalidRelations }
        let imported = incoming, localPhotos = photosFolder
        incoming = try await Task.detached(priority: .utility) {
            var restored = imported
            for index in restored.photos.indices where restored.photos[index].data == nil {
                restored.photos[index].data = try Data(contentsOf: localPhotos.appendingPathComponent(restored.photos[index].id.uuidString + ".jpg"))
            }
            return restored
        }.value
        incoming.ai = data.ai; incoming.schemaVersion = 2
        // New IDs keep old files intact even if imported IDs overlap or the write fails.
        var mapping: [UUID: UUID] = [:]
        for index in incoming.photos.indices {
            let id = UUID(); mapping[incoming.photos[index].id] = id; incoming.photos[index].id = id
        }
        for index in incoming.questions.indices { if let id = incoming.questions[index].imageID { incoming.questions[index].imageID = mapping[id] } }
        for si in incoming.sheets.indices { for qi in incoming.sheets[si].questions.indices {
            if let id = incoming.sheets[si].questions[qi].imageID { incoming.sheets[si].questions[qi].imageID = mapping[id] }
        } }
        let snapshot = incoming, destination = file, folder = photosFolder
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            persistenceQueue.async {
                do {
                    let recovery = destination.deletingLastPathComponent().appendingPathComponent("Recovery", isDirectory: true)
                    try FileManager.default.createDirectory(at: recovery, withIntermediateDirectories: true)
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    if FileManager.default.fileExists(atPath: destination.path) {
                        try FileManager.default.copyItem(at: destination, to: recovery.appendingPathComponent("before-restore-\(UUID()).json"))
                    }
                    var local = snapshot
                    for index in local.photos.indices {
                        try local.photos[index].data!.write(to: folder.appendingPathComponent(local.photos[index].id.uuidString + ".jpg"), options: [.atomic, .completeFileProtectionUnlessOpen])
                        local.photos[index].data = nil
                    }
                    try JSONEncoder().encode(local).write(to: destination, options: [.atomic, .completeFileProtectionUnlessOpen])
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
        for index in incoming.photos.indices { incoming.photos[index].data = nil }
        data = incoming; persistenceEnabled = true
    }
    private func protectedPhotos() async throws -> Set<UUID> {
        guard persistenceEnabled else { throw StoreFailure.persistenceDisabled }
        var ids = pinnedPhotos.union(data.questions.compactMap(\.imageID))
        ids.formUnion(data.sheets.flatMap { $0.questions.compactMap(\.imageID) })
        let recovery = file.deletingLastPathComponent().appendingPathComponent("Recovery", isDirectory: true)
        let active = ids
        return try await Task.detached(priority: .utility) {
            var protected = active
            if FileManager.default.fileExists(atPath: recovery.path) {
                for url in try FileManager.default.contentsOfDirectory(at: recovery, includingPropertiesForKeys: nil) where url.pathExtension == "json" {
                    let old = try JSONDecoder().decode(AppData.self, from: Data(contentsOf: url))
                    let referenced = Set(old.questions.compactMap(\.imageID) + old.sheets.flatMap { $0.questions.compactMap(\.imageID) })
                    protected.formUnion(old.photos.filter { $0.data == nil && referenced.contains($0.id) }.map(\.id))
                }
            }
            return protected
        }.value
    }
    func cacheSize() async throws -> Int64 {
        let protected = try await protectedPhotos()
        let photos = try FileManager.default.contentsOfDirectory(at: photosFolder, includingPropertiesForKeys: [.fileSizeKey])
        return try photos.filter { UUID(uuidString: $0.deletingPathExtension().lastPathComponent).map { !protected.contains($0) } ?? false }
            .reduce(AppCache.size()) { try $0 + Int64($1.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) }
    }
    func clearCache() async throws -> Int64 {
        guard !writing else { throw StoreFailure.persistenceDisabled }
        writing = true; defer { writing = false }
        let protected = try await protectedPhotos()
        let photos = try FileManager.default.contentsOfDirectory(at: photosFolder, includingPropertiesForKeys: [.fileSizeKey])
        var freed = try AppCache.clear()
        for url in photos {
            guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent), !protected.contains(id) else { continue }
            let size = Int64(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
            try FileManager.default.removeItem(at: url); freed += size
            data.photos.removeAll { $0.id == id }
        }
        data.photos.removeAll { !protected.contains($0.id) }
        try await persist(); return freed
    }
}
enum StoreFailure: LocalizedError {
    case invalidVersion, invalidRelations, persistenceDisabled
    var errorDescription: String? { switch self {
    case .invalidVersion: "备份格式版本不支持。"
    case .invalidRelations: "备份的数值、照片或题目关联无效。"
    case .persistenceDisabled: "本地数据受保护，无法保存。请先恢复有效备份。"
    } }
}
// Only this app's generated exports are disposable; active/recent shares stay available.
@MainActor enum AppCache {
    static var pinned = Set<URL>()
    static var directory: URL { URL.cachesDirectory.appendingPathComponent("LittleStrideExports", isDirectory: true) }
    static func file(name: String) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(name)
    }
    static func disposable() throws -> [URL] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]).filter {
            guard !pinned.contains($0) else { return false }
            return try ($0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? Date()) < Date().addingTimeInterval(-3600)
        }
    }
    static func size() throws -> Int64 { try disposable().reduce(0) { try $0 + Int64($1.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) } }
    static func clear() throws -> Int64 {
        var freed: Int64 = 0
        for url in try disposable() {
            let size = Int64(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
            try FileManager.default.removeItem(at: url); freed += size
        }
        return freed
    }
}
