import SwiftUI
import UIKit
import UserNotifications
import UniformTypeIdentifiers

struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let vc = UIImagePickerController(); vc.sourceType = .camera; vc.delegate = context.coordinator; return vc
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }; parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
struct SystemShare: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
struct SharePayload: Identifiable { let id = UUID(); var items: [Any] }

enum SheetRenderer {
    @MainActor static func pdf(_ sheet: PracticeSheet) throws -> URL {
        let format = UIGraphicsPDFRendererFormat()
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842), format: format)
        let bytes = renderer.pdfData { context in
            var y: CGFloat = 0
            func page() {
                context.beginPage(); y = 105
                ("LittleStride · 今日小练习" as NSString).draw(at: CGPoint(x: 36, y: 30), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 20)])
                ("\(sheet.code)　姓名：________　日期：________" as NSString).draw(at: CGPoint(x: 36, y: 65), withAttributes: [.font: UIFont.systemFont(ofSize: 11)])
            }
            page()
            for (index, q) in sheet.questions.enumerated() {
                let text = "\(index + 1). [\(q.subject.rawValue)] \(q.text)" as NSString
                let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 15)]
                let height = text.boundingRect(with: CGSize(width: 520, height: 10000), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes, context: nil).height
                if y + height + 110 > 790 { page() }
                text.draw(in: CGRect(x: 36, y: y, width: 520, height: height + 5), withAttributes: attributes)
                y += height + 110
            }
        }
        let url = URL.temporaryDirectory.appendingPathComponent("\(sheet.code).pdf"); try bytes.write(to: url); return url
    }
    @MainActor static func printPDF(_ url: URL) {
        let vc = UIPrintInteractionController.shared
        let info = UIPrintInfo(dictionary: nil); info.jobName = "LittleStride 练习单"; info.outputType = .general
        vc.printInfo = info; vc.printingItem = url; vc.present(animated: true)
    }
}
@MainActor enum ReminderService {
    static func update(_ store: LearningStore) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["daily-plan"])
        guard store.data.reminder else { return }
        do {
            let allowed = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            guard allowed else { store.notice = "通知未获授权，首页仍可查看计划。"; return }
            var components = DateComponents(); components.hour = store.data.reminderHour; components.minute = store.data.reminderMinute
            let content = UNMutableNotificationContent(); content.title = "LittleStride · 今天的一小步"
            content.body = "打开查看今天到期的科目、题量和预计用时。来不及可以调整计划。"; content.sound = .default
            try await center.add(UNNotificationRequest(identifier: "daily-plan", content: content, trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)))
        } catch { store.error = "提醒设置失败：\(error.localizedDescription)" }
    }
}
