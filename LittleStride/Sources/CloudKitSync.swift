import CloudKit
import Foundation
import SwiftUI

enum CloudSyncFailure: LocalizedError {
    case unavailable, missingProfile, invalidSnapshot
    var errorDescription: String? {
        switch self {
        case .unavailable: "CloudKit 当前不可用，请检查 Apple ID、iCloud 和网络连接。"
        case .missingProfile: "还没有共享的小朋友档案，请先在主手机创建共享档案。"
        case .invalidSnapshot: "CloudKit 返回的数据无法读取，未替换本机数据。"
        }
    }
}

/// CloudKit stores one portable snapshot as a CKAsset. Local persistence remains the source of truth
/// while a sync is in progress; a downloaded snapshot is only applied after Store.restore validates it.
@MainActor final class CloudKitSync: NSObject, ObservableObject {
    static let containerIdentifier = "iCloud.com.justisdk.LittleStride"
    static let recordType = "ChildProfile"
    let container = CKContainer(identifier: containerIdentifier)
    @Published private(set) var state = "尚未连接"
    @Published private(set) var share: CKShare?

    func accountStatus() async {
        do {
            let status = try await container.accountStatus()
            state = status == .available ? "iCloud 已连接" : "请在系统设置登录 iCloud"
        } catch { state = error.localizedDescription }
    }

    func createOrUpdate(snapshot: Data, profileID: UUID) async throws -> CKShare {
        let recordID = CKRecord.ID(recordName: profileID.uuidString)
        let database = container.privateCloudDatabase
        let record: CKRecord
        if let existing = try? await database.record(for: recordID) { record = existing }
        else { record = CKRecord(recordType: Self.recordType, recordID: recordID) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("LittleStride-cloud-\(profileID).json")
        try snapshot.write(to: url, options: .atomic)
        record["snapshot"] = CKAsset(fileURL: url)
        record["updatedAt"] = Date() as CKRecordValue
        // CKRecord.share is a reference; fetch the actual share when this profile was shared before.
        let share: CKShare
        if let reference = record.share,
           let fetched = try? await database.record(for: reference.recordID) as? CKShare {
            share = fetched
        } else {
            share = CKShare(rootRecord: record)
            share[CKShare.SystemFieldKey.title] = "LittleStride · 小朋友档案" as CKRecordValue
            share.publicPermission = .none
        }
        _ = try await database.modifyRecords(saving: [record, share], deleting: [])
        self.share = share
        state = "共享档案已更新"
        try? FileManager.default.removeItem(at: url)
        return share
    }

    func fetchShared(profileID: UUID) async throws -> Data {
        let id = CKRecord.ID(recordName: profileID.uuidString)
        let record = try await container.sharedCloudDatabase.record(for: id)
        guard let asset = record["snapshot"] as? CKAsset, let url = asset.fileURL else { throw CloudSyncFailure.invalidSnapshot }
        return try Data(contentsOf: url)
    }

    func prepareShare(profileID: UUID) async throws -> CKShare {
        let recordID = CKRecord.ID(recordName: profileID.uuidString)
        let record = try await container.privateCloudDatabase.record(for: recordID)
        guard let reference = record.share,
              let share = try await container.privateCloudDatabase.record(for: reference.recordID) as? CKShare else {
            throw CloudSyncFailure.missingProfile
        }
        self.share = share
        return share
    }
}

struct CloudShareSheet: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer
    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.availablePermissions = [.allowReadWrite]
        controller.delegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ controller: UICloudSharingController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        func cloudSharingController(_ c: UICloudSharingController, failedToSaveShareWithError error: Error) { }
        func itemTitle(for c: UICloudSharingController) -> String? { "LittleStride · 小朋友档案" }
        func cloudSharingControllerDidSaveShare(_ c: UICloudSharingController) { }
        func cloudSharingControllerDidStopSharing(_ c: UICloudSharingController) { }
    }
}
