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
private final class AIUploadObserver: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let progress: (@Sendable (String) -> Void)?
    private let started = Date()
    init(progress: (@Sendable (String) -> Void)?) { self.progress = progress }
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        if totalBytesExpectedToSend > 0, totalBytesSent >= totalBytesExpectedToSend {
            progress?("上传完成（\(Int(Date().timeIntervalSince(started))) 秒），等待 AI 分析…")
        } else if totalBytesExpectedToSend > 0 {
            progress?("正在上传：\(min(100, totalBytesSent * 100 / totalBytesExpectedToSend))%")
        }
    }
}
enum SecretStore {
    static func load(account: String = "api-key") -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "LittleStride.AI", kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    static func save(_ secret: String, account: String = "api-key") throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "LittleStride.AI", kSecAttrAccount as String: account]
        if secret.isEmpty { SecItemDelete(query as CFDictionary); return }
        let value: [String: Any] = [kSecValueData as String: Data(secret.utf8), kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, value as CFDictionary)
        if status == errSecItemNotFound {
            var new = query; value.forEach { new[$0.key] = $0.value }
            let result = SecItemAdd(new as CFDictionary, nil)
            guard result == errSecSuccess else { throw ServiceFailure(message: "Keychain 保存失败（\(result)）。") }
        } else if status != errSecSuccess { throw ServiceFailure(message: "Keychain 更新失败（\(status)）。") }
    }
    static func load(configuration: AIConfiguration) -> String {
        load(account: configuration.credentialScope == nil ? "api-key" : configuration.keyAccount)
    }
}
struct AIService {
    let configuration: AIConfiguration
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 90
        configuration.timeoutIntervalForResource = 120
        return URLSession(configuration: configuration)
    }()
    func endpoint() throws -> URL {
        guard let base = URL(string: configuration.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)), base.scheme == "https", base.host != nil, base.user == nil, base.password == nil, base.query == nil, base.fragment == nil else { throw ServiceFailure(message: "请填写不含密钥或查询参数的 HTTPS Base URL。") }
        guard !base.path.hasSuffix("/responses"), !base.path.hasSuffix("/chat/completions"), !base.path.hasSuffix("/messages"), !configuration.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ServiceFailure(message: "请填写基础地址和准确模型 ID，不要把完整接口路径填入 Base URL。") }
        guard ["Responses", "Chat Completions", "Anthropic Messages"].contains(configuration.api) else { throw ServiceFailure(message: "请选择支持的接口协议。") }
        let path = configuration.api == "Responses" ? "responses" : configuration.api == "Anthropic Messages" ? "messages" : "chat/completions"
        return base.appendingPathComponent(path)
    }
    func call(prompt: String, image: Data? = nil, progress: (@Sendable (String) -> Void)? = nil) async throws -> String {
        let url = try endpoint(), key = SecretStore.load(configuration: configuration)
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
            if let effort = configuration.reasoningEffort, ["low", "medium", "high"].contains(effort) { body["reasoning"] = ["effort": effort] }
        } else if configuration.api == "Anthropic Messages" {
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            var content: [[String: Any]] = [["type": "text", "text": prompt]]
            if let image { content.append(["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": image.base64EncodedString()]]) }
            body["messages"] = [["role": "user", "content": content]]
            body["max_tokens"] = 4096
        } else {
            var content: [[String: Any]] = [["type": "text", "text": prompt]]
            if let image { content.append(["type": "image_url", "image_url": ["url": "data:image/jpeg;base64," + image.base64EncodedString()]]) }
            body["messages"] = [["role": "user", "content": content]]
        }
        let payload = try JSONSerialization.data(withJSONObject: body)
        try Task.checkCancellation()
        progress?("正在连接并上传…")
        let observer = AIUploadObserver(progress: progress)
        let (bytes, response) = try await Self.session.upload(for: request, from: payload, delegate: observer)
        try Task.checkCancellation()
        progress?("正在读取分析结果…")
        guard let http = response as? HTTPURLResponse else { throw ServiceFailure(message: "服务未返回 HTTP 响应。") }
        guard (200..<300).contains(http.statusCode) else {
            let suggestion = http.statusCode == 401 ? "检查 Key、认证方式和服务权限。" : http.statusCode == 404 ? "检查接口协议与基础路径。" : http.statusCode == 429 ? "检查服务额度或稍后重试。" : "检查服务商兼容性或稍后重试。"
            // No remote response body or credential is surfaced in diagnostic logs.
            throw ServiceFailure(message: "HTTP \(http.statusCode) · \(url.path)\n\(suggestion)")
        }
        return try Self.responseText(bytes, contentType: http.value(forHTTPHeaderField: "Content-Type") ?? "")
    }
    // 部分兼容服务忽略 stream:false，仍返回 SSE。两种协议均在这里解析。
    static func responseText(_ bytes: Data, contentType: String) throws -> String {
        let raw = String(data: bytes, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty else { throw ServiceFailure(message: "AI 服务返回了空响应，请检查服务商连接或稍后重试。") }
        if contentType.lowercased().contains("text/event-stream") || raw.hasPrefix("data:") || raw.hasPrefix("event:") || raw.hasPrefix(":") {
            return try streamText(raw)
        }
        let root: [String: Any]
        do {
            guard let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else {
                throw ServiceFailure(message: "AI 服务响应应为 JSON 对象，请检查接口协议与基础地址。")
            }
            root = object
        } catch let error as ServiceFailure { throw error }
        catch {
            throw ServiceFailure(message: "无法解析 AI 服务响应：返回内容不是有效 JSON 或支持的流式数据。请检查 AI 设置中的接口协议与基础地址。")
        }
        try validateResponse(root)
        guard let text = outputText(root), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ServiceFailure(message: "AI 服务响应中没有可用文本。请确认所选模型支持图片分析，以及接口协议与服务商一致。")
        }
        return text
    }
    private static func validateResponse(_ root: [String: Any]) throws {
        if root["error"] != nil && !(root["error"] is NSNull) || ["error", "response.failed"].contains(root["type"] as? String ?? "") || root["status"] as? String == "failed" {
            throw ServiceFailure(message: "AI 服务返回处理错误。请检查模型的图片能力、服务额度和接口配置。")
        }
        if root["status"] as? String == "incomplete" || root["type"] as? String == "response.incomplete" {
            throw ServiceFailure(message: "AI 分析结果被截断，未写入题库。请缩小照片范围后重试，或调整服务商的输出限制。")
        }
        if let choices = root["choices"] as? [[String: Any]], choices.first?["finish_reason"] as? String == "length" {
            throw ServiceFailure(message: "AI 分析结果被截断，未写入题库。请缩小照片范围后重试。")
        }
        if root["stop_reason"] as? String == "max_tokens" { throw ServiceFailure(message: "Claude 分析结果被截断，未写入题库。请缩小照片范围后重试。") }
    }
    private static func contentText(_ content: Any?) -> String? {
        if let text = content as? String { return text }
        guard let parts = content as? [[String: Any]] else { return nil }
        let text = parts.filter { ["text", "output_text"].contains($0["type"] as? String ?? "") }
            .compactMap { $0["text"] as? String }.joined()
        return text.isEmpty ? nil : text
    }
    private static func outputText(_ root: [String: Any]) -> String? {
        if let text = contentText(root["content"]) { return text }
        if let text = root["output_text"] as? String, !text.isEmpty { return text }
        if let output = root["output"] as? [[String: Any]] {
            let text = output.compactMap { contentText($0["content"]) }.joined(separator: "\n")
            if !text.isEmpty { return text }
        }
        if let choices = root["choices"] as? [[String: Any]], let message = choices.first?["message"] as? [String: Any] {
            return contentText(message["content"])
        }
        return nil
    }
    private static func streamText(_ raw: String) throws -> String {
        var deltas = "", finalText: String?, terminated = false
        let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        for event in normalized.components(separatedBy: "\n\n") {
            let payload = event.components(separatedBy: "\n").filter { $0.hasPrefix("data:") }
                .map { String($0.dropFirst(5)).trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
            if payload.isEmpty { continue }
            if payload == "[DONE]" { terminated = true; continue }
            guard let data = payload.data(using: .utf8), let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                throw ServiceFailure(message: "AI 服务返回的流式数据格式无效，请检查服务商兼容性。")
            }
            try validateResponse(root)
            let type = root["type"] as? String ?? ""
            if type == "content_block_delta", let delta = root["delta"] as? [String: Any], delta["type"] as? String == "text_delta", let text = delta["text"] as? String { deltas += text }
            if type == "content_block_start", let block = root["content_block"] as? [String: Any], block["type"] as? String == "text", let text = block["text"] as? String { deltas += text }
            if type == "message_delta", let delta = root["delta"] as? [String: Any] { try validateResponse(delta) }
            if type == "message_stop" { terminated = true }
            if type == "response.output_text.delta", let delta = root["delta"] as? String { deltas += delta }
            if type == "response.output_text.done", let text = root["text"] as? String { finalText = text }
            if type == "response.completed" {
                terminated = true
                if let response = root["response"] as? [String: Any] {
                    try validateResponse(response)
                    if let text = outputText(response) { finalText = text }
                }
            }
            if let choices = root["choices"] as? [[String: Any]], let choice = choices.first {
                if let delta = choice["delta"] as? [String: Any], let text = contentText(delta["content"]) { deltas += text }
                if let text = outputText(root) { finalText = text }
                if choice["finish_reason"] as? String == "stop" { terminated = true }
            }
        }
        guard terminated else { throw ServiceFailure(message: "AI 流式响应未完整结束，未写入题库。请重试或检查服务商连接。") }
        let text = finalText ?? deltas
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ServiceFailure(message: "AI 流式响应中没有分析文本，请确认模型支持图片分析。")
        }
        return text
    }
    func decode<T: Decodable>(_ type: T.Type, prompt: String, image: Data? = nil, progress: (@Sendable (String) -> Void)? = nil) async throws -> T {
        let response = try await call(prompt: prompt + "\n只输出一个JSON对象，不要Markdown或额外说明。示例中的所有字段必须保留，字符串未知时用空字符串，不要用null。", image: image, progress: progress)
        var text = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        if text.hasPrefix("```"), let firstLine = text.firstIndex(of: "\n"), let closing = text.range(of: "```", options: .backwards), closing.lowerBound > firstLine {
            text = String(text[text.index(after: firstLine)..<closing.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        do { return try JSONDecoder().decode(type, from: Data(text.utf8)) }
        catch let error as DecodingError {
            let detail: String
            switch error {
            case .keyNotFound(let key, _): detail = "缺少字段 \(key.stringValue)"
            case .typeMismatch(_, let context): detail = "字段 \(context.codingPath.map(\.stringValue).joined(separator: ".")) 的类型不正确"
            case .valueNotFound(_, let context): detail = "字段 \(context.codingPath.map(\.stringValue).joined(separator: ".")) 不应为 null"
            case .dataCorrupted: detail = "模型分析文本不是有效 JSON，可能带有额外说明或结果不完整"
            @unknown default: detail = "结构不符合要求"
            }
            throw ServiceFailure(message: "已收到 AI 响应，但分析结果无法读取：\(detail)。未写入题库，请重试或更换模型。")
        }
        catch { throw ServiceFailure(message: "已收到 AI 响应，但分析结果未通过结构校验，未写入题库。请重试或更换模型。") }
    }
    func analyze(image: Data?, profile: ChildProfile, text: String? = nil, progress: (@Sendable (String) -> Void)? = nil) async throws -> AIAnalysis {
        let prompt = """
        分析小学作业照片。年级：\(profile.grade)，学期：\(profile.term)。教材信息：\(profile.textbooks)。
        找出错误、受助或无法判断的题目；不为正确题编造错误。不清楚的内容留空，status写待核实。
        区分观察事实和可能原因；不能从简单错误推断态度差。知识点只按证据归类。最多返回12题。
        JSON格式：{"questions":[{"subject":"数学/语文/英语","text":"完整题干","answer":"正确答案，无法判断留空","studentAnswer":"照片原始作答","knowledge":"具体知识点","observation":"可观察错误","possibleCause":"尚需确认的可能原因","status":"错误/部分正确/待核实"}]}
        """
        return try await decode(AIAnalysis.self, prompt: prompt + (text.map { "\n以下为用户核对的本地OCR文字（无图片，不能推断版面、批改痕迹或未提供的作答；无法判断时标待核实）：\n" + $0 } ?? ""), image: image, progress: progress)
    }
    func textbook(image: Data?, text: String? = nil, progress: (@Sendable (String) -> Void)? = nil) async throws -> TextbookAnalysis {
        try await decode(TextbookAnalysis.self, prompt: "识别教材封面、版权页、目录或当前学习页。仅按照片取证，不补造出版社、版本、目录。不因拍到某页就推断已掌握。返回JSON：{\"subject\":\"数学/语文/英语或空\",\"title\":\"\",\"publisher\":\"\",\"edition\":\"\",\"grade\":\"\",\"term\":\"\",\"progress\":\"仅当前可见章节\",\"uncertainty\":\"需核实项\"}。" + (text.map { "\n用户核对的OCR文字（无图片，缺失信息留空）：\n" + $0 } ?? ""), image: image, progress: progress)
    }
    func generate(_ q: Question, profile: ChildProfile) async throws -> AIAnalysis {
        try await decode(AIAnalysis.self, prompt: "为\(profile.grade)\(q.subject.rawValue)生成一道同类题。原题：\(q.text)，答案：\(q.answer)，解析：\(q.explanation)。保持知识点和难度，不拔高，核算答案。格式{\"questions\":[{\"subject\":\"\(q.subject.rawValue)\",\"text\":\"\",\"answer\":\"\",\"studentAnswer\":\"\",\"knowledge\":\"\",\"observation\":\"说明解法\",\"possibleCause\":\"\",\"status\":\"生成练习\"}]}。")
    }
}
