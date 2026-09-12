import Foundation

/// iCloud Drive 同步:把持仓与设置写成 JSON 存入 iCloud Drive/FundBar/,
/// 同一 Apple ID 的多台 Mac 自动互相同步。
/// 说明:iCloud Drive 文件方案无需开发者账号/entitlement(CloudKit 需要正式签名);
/// 合并策略为「新时间戳整体覆盖」。
@MainActor
final class SyncService: ObservableObject {
    static let shared = SyncService()

    enum Availability: Equatable {
        case checking
        case unavailable(reason: String)
        case available
    }

    @Published private(set) var availability: Availability = .checking
    @Published private(set) var lastSyncedAt: Date?

    private var defaultsObserver: NSObjectProtocol?
    private var pollTimer: Timer?
    /// 自己最近一次写入文件的 updatedAt,用于忽略自己的写入
    private var lastPushedUpdatedAt: Date?
    /// 最近一次采用的远端 updatedAt
    private var lastAppliedRemoteUpdatedAt: Date?
    private var isApplyingRemote = false

    private init() {}

    // MARK: - 路径与可用性

    static var iCloudDriveRoot: URL? {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
        guard let library else { return nil }
        let cloudDocs = library.appendingPathComponent("Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: cloudDocs.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }
        return cloudDocs
    }

    static var syncFolder: URL? {
        guard let root = iCloudDriveRoot else { return nil }
        let folder = root.appendingPathComponent("FundBar", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    static var syncFileURL: URL? {
        syncFolder?.appendingPathComponent("sync.json")
    }

    func start() {
        refreshAvailability()
        applyRemoteIfNewer(initial: true)
        observeDefaults()
        pushIfNeeded()
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { _ in
            Task { @MainActor in
                SyncService.shared.applyRemoteIfNewer()
            }
        }
    }

    func refreshAvailability() {
        if let root = Self.iCloudDriveRoot {
            availability = .available
            _ = root
        } else {
            availability = .unavailable(reason: "iCloud Drive 未开启或未登录 Apple ID")
        }
    }

    // MARK: - 设置变更监听 → 推送

    private func observeDefaults() {
        guard defaultsObserver == nil else { return }
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.isApplyingRemote else { return }
                // 稍作防抖,合并连续写入
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                self.pushIfNeeded()
            }
        }
    }

    // MARK: - 推送 / 拉取

    func pushIfNeeded() {
        guard isEnabled, let fileURL = Self.syncFileURL else { return }
        var payload = SyncPayload.build(from: MarketStore.shared.holdings)
        let now = Date()
        payload.updatedAt = now
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(payload)
            try data.write(to: fileURL, options: .atomic)
            lastPushedUpdatedAt = now
            lastSyncedAt = now
        } catch {
            // iCloud Drive 偶发未挂载,静默等待下次
        }
    }

    /// 远端文件比本地新时采用(整体覆盖持仓与设置)
    func applyRemoteIfNewer(initial: Bool = false) {
        refreshAvailability()
        guard isEnabled, let fileURL = Self.syncFileURL else { return }
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let payload = try? decoder.decode(SyncPayload.self, from: data) else { return }

        // 自己刚写的,跳过
        if let pushed = lastPushedUpdatedAt, abs(payload.updatedAt.timeIntervalSince(pushed)) < 2 {
            return
        }
        if let applied = lastAppliedRemoteUpdatedAt, payload.updatedAt <= applied {
            return
        }
        guard initial || payload.updatedAt > (lastAppliedRemoteUpdatedAt ?? .distantPast) else { return }

        isApplyingRemote = true
        defer { isApplyingRemote = false }
        payload.apply()
        lastAppliedRemoteUpdatedAt = payload.updatedAt
        lastSyncedAt = Date()
    }

    var isEnabled: Bool {
        if UserDefaults.standard.object(forKey: SettingsKey.icloudSyncEnabled) == nil {
            return true // 未显式设置过时默认开启
        }
        return UserDefaults.standard.bool(forKey: SettingsKey.icloudSyncEnabled)
    }
}
