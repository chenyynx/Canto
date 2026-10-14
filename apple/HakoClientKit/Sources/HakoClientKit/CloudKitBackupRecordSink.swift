import CloudKit
import Foundation

// iCloud entitlement gate（2026-10-14 崩溃修复）：CKContainer(identifier:) 在无
// iCloud 容器 entitlement 的进程里构造会直接抛 NSException（SIGABRT 闪退）——
// 见 ICloudEntitlementProbe.swift 头注释。因此这里改为：
//   1) 惰性构造：init 只记录标识符，首次真正用到 CloudKit 时才建容器
//   2) entitlement gate：无权限时不触碰 CKContainer，直接走 unavailable 错误
//      （UI 显示 iCloud 不可用，功能不闪退）
public final class CloudKitBackupRecordSink: BackupRecordSink, @unchecked Sendable {
    private let containerIdentifier: String
    private var container: CKContainer?
    public var diagnostics: (@Sendable (String) -> Void)?

    public init(containerIdentifier: String) {
        self.containerIdentifier = containerIdentifier
    }

    /// 惰性容器：无 entitlement 时返回 nil（调用方走 unavailable 路径）。
    private func ensuredContainer() throws -> CKContainer {
        if let container { return container }
        guard ICloudEntitlementProbe.hasICloudEntitlement else {
            throw BackupRecordSinkError.unavailable(
                "iCloud is not available in this build (no iCloud container entitlement)."
            )
        }
        let created = CKContainer(identifier: containerIdentifier)
        container = created
        return created
    }

    public func upsert(_ payload: BackupRecordPayload) async throws {
        let container = try ensuredContainer()
        try await requireAccount(container)
        if let diagnostics {
            let user = (try? await container.userRecordID().recordName) ?? "unavailable"
            diagnostics("icloud auto backup: user record \(user), container \(container.containerIdentifier)")
        }
        let assetURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("hako-backup-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: assetURL) }
        do {
            try payload.archive.write(to: assetURL, options: .atomic)
            let record = Self.record(for: payload, assetURL: assetURL)
            _ = try await container.privateCloudDatabase.modifyRecords(
                saving: [record], deleting: [], savePolicy: .allKeys, atomically: true
            )
        } catch let error as BackupRecordSinkError {
            throw error
        } catch {
            throw Self.mapped(error)
        }
    }

    public func deleteOwn(installID: String) async throws {
        let container = try ensuredContainer()
        try await requireAccount(container)
        do {
            _ = try await container.privateCloudDatabase.modifyRecords(
                saving: [], deleting: [CKRecord.ID(recordName: installID)], savePolicy: .allKeys, atomically: true
            )
        } catch {
            if let ck = error as? CKError, ck.code == .unknownItem { return }
            throw Self.mapped(error)
        }
    }

    public static func record(for payload: BackupRecordPayload, assetURL: URL) -> CKRecord {
        let record = CKRecord(
            recordType: BackupRecordSchema.recordType,
            recordID: CKRecord.ID(recordName: payload.installID)
        )
        record[BackupRecordSchema.kindField] = BackupRecordSchema.kindAuto as NSString
        record[BackupRecordSchema.archiveField] = CKAsset(fileURL: assetURL)
        record[BackupRecordSchema.exportedAtField] = payload.exportedAt as NSDate
        record[BackupRecordSchema.sourceDeviceField] = payload.sourceDevice as NSString
        record[BackupRecordSchema.sourceInstallIDField] = payload.installID as NSString
        record[BackupRecordSchema.schemaVersionField] = payload.schemaVersion as NSNumber
        return record
    }

    private func requireAccount(_ container: CKContainer) async throws {
        let status: CKAccountStatus
        do {
            status = try await container.accountStatus()
        } catch {
            throw BackupRecordSinkError.unavailable(error.localizedDescription)
        }
        switch status {
        case .available: return
        case .noAccount: throw BackupRecordSinkError.noAccount
        default:
            throw BackupRecordSinkError.unavailable(
                "iCloud account status: \(CloudKitBackupRecordSource.name(of: status))"
            )
        }
    }

    public static func mapped(_ error: Error) -> BackupRecordSinkError {
        guard let ck = error as? CKError else { return .unavailable(error.localizedDescription) }
        switch ck.code {
        case .notAuthenticated:
            return .noAccount
        case .networkUnavailable, .networkFailure, .serviceUnavailable:
            return .offline(ck.localizedDescription)
        case .quotaExceeded:
            return .quotaExceeded
        case .requestRateLimited, .zoneBusy:
            return .rateLimited(retryAfterSeconds: ck.retryAfterSeconds ?? 30)
        default:
            return .unavailable(ck.localizedDescription)
        }
    }
}
