import SwiftUI
import UIKit
import AVFoundation
import UserNotifications
import UniformTypeIdentifiers

struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    func makeUIViewController(context: Context) -> CaptureCameraController {
        let controller = CaptureCameraController()
        controller.onImage = { image in dismiss(); onImage(image) }
        controller.onCancel = { dismiss() }
        return controller
    }
    func updateUIViewController(_ uiViewController: CaptureCameraController, context: Context) {}
}
// A lightweight capture surface: session setup runs off the UI thread, and the
// captured image goes directly to the app preview without a second confirmation screen.
final class CaptureCameraController: UIViewController, AVCapturePhotoCaptureDelegate {
    var onImage: ((UIImage) -> Void)?
    var onCancel: (() -> Void)?
    private let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "LittleStride.camera", qos: .userInitiated)
    private var preview: AVCaptureVideoPreviewLayer?
    private let shutter = UIButton(type: .custom)
    private let status = UILabel()
    private var visible = true
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview); self.preview = preview
        let close = UIButton(type: .system)
        close.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        close.tintColor = .white; close.accessibilityLabel = "关闭相机"
        close.addTarget(self, action: #selector(cancel), for: .touchUpInside)
        shutter.backgroundColor = .white; shutter.layer.cornerRadius = 36
        shutter.layer.borderWidth = 5; shutter.layer.borderColor = UIColor.lightGray.cgColor
        shutter.accessibilityLabel = "拍摄作业照片"; shutter.isEnabled = false
        shutter.addTarget(self, action: #selector(capture), for: .touchUpInside)
        status.text = "正在打开相机…"; status.textColor = .white
        status.textAlignment = .center; status.font = .preferredFont(forTextStyle: .subheadline)
        status.numberOfLines = 0
        for item in [close, shutter, status] { item.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(item) }
        NSLayoutConstraint.activate([
            close.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            close.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            close.widthAnchor.constraint(equalToConstant: 44), close.heightAnchor.constraint(equalToConstant: 44),
            shutter.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            shutter.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            shutter.widthAnchor.constraint(equalToConstant: 72), shutter.heightAnchor.constraint(equalToConstant: 72),
            status.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            status.bottomAnchor.constraint(equalTo: shutter.topAnchor, constant: -20),
            status.widthAnchor.constraint(equalTo: view.widthAnchor, constant: -40)
        ])
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
                DispatchQueue.main.async { if allowed { self?.configureSession() } else { self?.showFailure("请在系统设置中允许 LittleStride 使用相机。") } }
            }
        default: showFailure("请在系统设置中允许 LittleStride 使用相机，也可以从相册选择照片。")
        }
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews(); preview?.frame = view.bounds
        if let connection = preview?.connection, connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated); visible = false
        let session = session
        sessionQueue.async { if session.isRunning { session.stopRunning() } }
    }
    private func configureSession() {
        let session = session, output = output
        sessionQueue.async { [weak self] in
            do {
                session.beginConfiguration()
                defer { session.commitConfiguration() }
                session.sessionPreset = .high
                guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { throw ServiceFailure(message: "没有可用的后置相机。") }
                let input = try AVCaptureDeviceInput(device: device)
                guard session.canAddInput(input), session.canAddOutput(output) else { throw ServiceFailure(message: "无法启动相机，请从相册选择。") }
                session.addInput(input); session.addOutput(output)
                output.maxPhotoQualityPrioritization = .speed
            } catch {
                let message = error.localizedDescription
                DispatchQueue.main.async { self?.showFailure(message) }; return
            }
            session.startRunning()
            DispatchQueue.main.async {
                guard let self, self.visible else { return }
                self.shutter.isEnabled = true; self.status.text = "拍完整题干和作答，尽量靠近并保持清晰"
                self.view.setNeedsLayout()
            }
        }
    }
    @objc private func cancel() { onCancel?() }
    @objc private func capture() {
        guard session.isRunning else { return }
        shutter.isEnabled = false; status.text = "正在拍摄…"
        let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
        settings.photoQualityPrioritization = .speed
        if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
        output.capturePhoto(with: settings, delegate: self)
    }
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let bytes = photo.fileDataRepresentation(), let image = UIImage(data: bytes) else {
            DispatchQueue.main.async { [weak self] in self?.shutter.isEnabled = true; self?.showFailure("照片拍摄失败，请重试。") }; return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.visible else { return }
            self.onImage?(image)
        }
    }
    private func showFailure(_ message: String) {
        guard visible else { return }
        status.text = message
        let alert = UIAlertController(title: "无法使用相机", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "返回", style: .cancel) { [weak self] _ in self?.onCancel?() })
        if AVCaptureDevice.authorizationStatus(for: .video) == .denied {
            alert.addAction(UIAlertAction(title: "打开系统设置", style: .default) { _ in
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            })
        }
        present(alert, animated: true)
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
