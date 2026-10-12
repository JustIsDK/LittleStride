import Foundation
import Security

struct AIQuestion: Codable, Identifiable {
    var id: String { text }
    var subject: String
    var text: String
    var answer: String
    var studentAnswer: String
    var knowledge: String
    var observation: String
    var possibleCause: String
    var status: String
}
struct AIAnalysis: Codable { var questions: [AIQuestion] }
struct TextbookAnalysis: Codable {
    var subject: String
    var title: String
    var publisher: String
    var edition: String
    var grade: String
    var term: String
    var progress: String
    var uncertainty: String
}
struct AICheck: Codable {
    var results: [Result]
    struct Result: Codable, Identifiable { var id: String; var answer: String; var result: String; var observation: String }
}
struct ServiceFailure: LocalizedError {
    var message: String
    var errorDescription: String? { message }
}
enum SecretStore {
    static func load() -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "LittleStride.AI", kSecAttrAccount as String: "api-key", kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    static func save(_ secret: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "LittleStride.AI", kSecAttrAccount as String: "api-key"]
        if secret.isEmpty { SecItemDelete(query as CFDictionary); return }
        let value: [String: Any] = [kSecValueData as String: Data(secret.utf8), kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, value as CFDictionary)
        if status == errSecItemNotFound {
            var new = query; value.forEach { new[$0.key] = $0.value }
            let result = SecItemAdd(new as CFDictionary, nil)
            guard result == errSecSuccess else { throw ServiceFailure(message: "Keychain 保存失败（\(result)）。") }
        } else if status != errSecSuccess { throw ServiceFailure(message: "Keychain 更新失败（\(status)）。") }
    }
}
struct AIService {
    let configuration: AIConfiguration
    func endpoint() throws -> URL {
        guard let base = URL(string: configuration.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)), base.scheme == "https", base.host != nil, base.user == nil, base.password == nil, base.query == nil, base.fragment == nil else { throw ServiceFailure(message: "请填写不含密钥或查询参数的 HTTPS Base URL。") }
        guard !base.path.hasSuffix("/responses"), !base.path.hasSuffix("/chat/completions"), !configuration.model.trimmingCharacters(in: .whitespaces).isEmpty else { throw ServiceFailure(message: "请填写基础地址和准确模型 ID，不要把完整接口路径填入 Base URL。") }
        return base.appendingPathComponent(configuration.api == "Responses" ? "responses" : "chat/completions")
    }
    func call(prompt: String, image: Data? = nil) async throws -> String {
        let url = try endpoint(), key = SecretStore.load()
        guard !key.isEmpty else { throw ServiceFailure(message: "尚未保存 API Key。") }
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        guard !configuration.authHeader.isEmpty, !configuration.authHeader.contains(where: { $0.isNewline }) else { throw ServiceFailure(message: "认证请求头名称无效。") }
        request.setValue(configuration.bearer ? "Bearer \(key)" : key, forHTTPHeaderField: configuration.authHeader)
        var body: [String: Any] = ["model": configuration.model, "stream": false]
        if configuration.api == "Responses" {
            var content: [[String: Any]] = [["type": "input_text", "text": prompt]]
            if let image { content.append(["type": "input_image", "image_url": "data:image/jpeg;base64," + image.base64EncodedString()]) }
            body["input"] = [["role": "user", "content": content]]
        } else {
            var content: [[String: Any]] = [["type": "text", "text": prompt]]
            if let image { content.append(["type": "image_url", "image_url": ["url": "data:image/jpeg;base64," + image.base64EncodedString()]]) }
            body["messages"] = [["role": "user", "content": content]]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        let (bytes, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ServiceFailure(message: "服务未返回 HTTP 响应。") }
        guard (200..<300).contains(http.statusCode) else {
            let suggestion = http.statusCode == 401 ? "检查 Key、认证方式和服务权限。" : http.statusCode == 404 ? "检查接口协议与基础路径。" : http.statusCode == 429 ? "检查服务额度或稍后重试。" : "检查服务商兼容性或稍后重试。"
            // No remote response body or credential is surfaced in diagnostic logs.
            throw ServiceFailure(message: "HTTP \(http.statusCode) · \(url.path)\n\(suggestion)")
        }
        guard let root = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { throw ServiceFailure(message: "返回不是有效 JSON。") }
        if configuration.api == "Responses" {
            if let text = root["output_text"] as? String, !text.isEmpty { return text }
            let output = root["output"] as? [[String: Any]] ?? []
            let text = output.flatMap { $0["content"] as? [[String: Any]] ?? [] }.compactMap { $0["text"] as? String }.joined(separator: "\n")
            if !text.isEmpty { return text }
        } else if let choices = root["choices"] as? [[String: Any]], let message = choices.first?["message"] as? [String: Any], let text = message["content"] as? String { return text }
        throw ServiceFailure(message: "服务返回格式不兼容，或没有可用文本结果。")
    }
    func decode<T: Decodable>(_ type: T.Type, prompt: String, image: Data? = nil) async throws -> T {
        let response = try await call(prompt: prompt + "\n只输出一个JSON对象，不要Markdown或额外说明。", image: image)
        var text = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") { text = text.components(separatedBy: "\n").dropFirst().dropLast().joined(separator: "\n") }
        do { return try JSONDecoder().decode(type, from: Data(text.utf8)) }
        catch { throw ServiceFailure(message: "模型结果未通过结构校验，未写入题库。可更换模型或重试。") }
    }
    func analyze(image: Data, profile: ChildProfile) async throws -> AIAnalysis {
        let prompt = """
        分析小学作业照片。年级：\(profile.grade)，学期：\(profile.term)。教材信息：\(profile.textbooks)。
        找出错误、受助或无法判断的题目；不为正确题编造错误。不清楚的内容留空，status写待核实。
        区分观察事实和可能原因；不能从简单错误推断态度差。知识点只按证据归类。最多返回12题。
        JSON格式：{"questions":[{"subject":"数学/语文/英语","text":"完整题干","answer":"正确答案，无法判断留空","studentAnswer":"照片原始作答","knowledge":"具体知识点","observation":"可观察错误","possibleCause":"尚需确认的可能原因","status":"错误/部分正确/待核实"}]}
        """
        return try await decode(AIAnalysis.self, prompt: prompt, image: image)
    }
    func textbook(image: Data) async throws -> TextbookAnalysis {
        try await decode(TextbookAnalysis.self, prompt: "识别教材封面、版权页、目录或当前学习页。仅按照片取证，不补造出版社、版本、目录。不因拍到某页就推断已掌握。返回JSON：{\"subject\":\"数学/语文/英语或空\",\"title\":\"\",\"publisher\":\"\",\"edition\":\"\",\"grade\":\"\",\"term\":\"\",\"progress\":\"仅当前可见章节\",\"uncertainty\":\"需核实项\"}。", image: image)
    }
    func generate(_ q: Question, profile: ChildProfile) async throws -> AIAnalysis {
        try await decode(AIAnalysis.self, prompt: "为\(profile.grade)\(q.subject.rawValue)生成一道同类题。原题：\(q.text)，答案：\(q.answer)，解析：\(q.explanation)。保持知识点和难度，不拔高，核算答案。格式{\"questions\":[{\"subject\":\"\(q.subject.rawValue)\",\"text\":\"\",\"answer\":\"\",\"studentAnswer\":\"\",\"knowledge\":\"\",\"observation\":\"说明解法\",\"possibleCause\":\"\",\"status\":\"生成练习\"}]}。")
    }
}
