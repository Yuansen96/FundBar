import CryptoKit
import Foundation

/// 对比本机、云端与上次共同确认的内容。SyncPayload 的相等比较不计 updatedAt。
enum SyncConflictDecision: Equatable {
    case unchanged
    case pushLocal
    case applyRemote
    case applyRemoteSavingLocal
    case conflict
}

enum SyncConflictPolicy {
    static func decide(
        local: SyncPayload,
        remote: SyncPayload?,
        baseline: SyncPayload?
    ) -> SyncConflictDecision {
        guard let remote else {
            return baseline == nil ? .pushLocal : .conflict
        }
        if local == remote { return .unchanged }
        guard let baseline else {
            // 旧版没有共同基线，无法确认哪一端含有尚未上传的修改。
            return .conflict
        }
        let localChanged = local != baseline
        let remoteChanged = remote != baseline
        if localChanged && remoteChanged { return .conflict }
        if localChanged { return .pushLocal }
        if remoteChanged && remote.updatedAt <= baseline.updatedAt { return .conflict }
        return .applyRemote
    }
}

private enum SyncIntent: Equatable {
    case reconcile
    case keepLocal
    case keepRemote
}

private struct SyncJob {
    let intent: SyncIntent
    let local: SyncPayload
    let baseline: SyncPayload?
    let deviceID: String
    let enabled: Bool
}

private enum SyncOutcome {
    case unavailable
    case disabled
    case unchanged(SyncPayload)
    case pushed(SyncPayload)
    case remote(SyncPayload)
    case conflict
    case stale
}

/// iCloud Drive/FundBar/sync.json 的整包同步。I/O 在串行后台队列上执行，
/// MainActor 只处理快照、状态和同步应用，避免文件下载卡住菜单栏。
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
    @Published private(set) var hasConflict = false
    @Published private(set) var syncIssue: String?

    private static let baselineKey = "fundbar.sync.commonBaseline"
    private static let systemConflictKey = "fundbar.sync.systemConflictPending"
    private static let recoveryDeviceKey = "fundbar.sync.recoveryDeviceID"
    private let ioQueue = DispatchQueue(label: "fundbar.sync.file-io", qos: .utility)
    private var defaultsObserver: NSObjectProtocol?
    private var pollTimer: Timer?
    private var isApplyingRemote = false
    private var pendingIntent: SyncIntent?
    private var isProcessing = false
    private var generation = 0

    private init() {}

    // MARK: - 路径与可用性

    static var iCloudDriveRoot: URL? {
        SyncFileIO.cloudRoot
    }

    static var syncFolder: URL? {
        iCloudDriveRoot?.appendingPathComponent("FundBar", isDirectory: true)
    }

    static var syncFileURL: URL? {
        syncFolder?.appendingPathComponent("sync.json")
    }

    static var recoveryFolderURL: URL? {
        syncFolder?.appendingPathComponent("Recovery", isDirectory: true)
    }

    func start() {
        _ = recoveryDeviceID
        refreshAvailability()
        enqueue(.reconcile)
        observeDefaults()
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { _ in
            Task { @MainActor in SyncService.shared.applyRemoteIfNewer() }
        }
    }

    func refreshAvailability() {
        availability = Self.iCloudDriveRoot == nil
            ? .unavailable(reason: "iCloud Drive 未开启或未登录 Apple ID")
            : .available
    }

    private func observeDefaults() {
        guard defaultsObserver == nil else { return }
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.isApplyingRemote else { return }
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                self.pushIfNeeded()
            }
        }
    }

    // MARK: - 请求与结果

    func pushIfNeeded() {
        enqueue(.reconcile)
    }

    func applyRemoteIfNewer(initial: Bool = false) {
        enqueue(.reconcile)
    }

    func resolveConflictKeepingLocal() {
        guard hasConflict, isEnabled else { return }
        enqueue(.keepLocal)
    }

    func resolveConflictKeepingRemote() {
        guard hasConflict, isEnabled else { return }
        enqueue(.keepRemote)
    }

    private func enqueue(_ intent: SyncIntent) {
        // 定时器与本机变更只要求再跑一次：写入前还会核对持仓和基线。
        // 不使正在等待 iCloud 的同一轮对账失效，否则读取慢于轮询周期时会一直重试。
        if isProcessing && intent == .reconcile {
            if pendingIntent == nil { pendingIntent = .reconcile }
            return
        }
        generation &+= 1
        // 用户的解决选择优先于计时器触发的普通对账。
        if pendingIntent == .keepLocal || pendingIntent == .keepRemote {
            if intent != .reconcile { pendingIntent = intent }
        } else {
            pendingIntent = intent
        }
        guard !isProcessing else { return }
        isProcessing = true
        Task { await processLoop() }
    }

    private func processLoop() async {
        while let intent = pendingIntent {
            pendingIntent = nil
            let token = generation
            let job = SyncJob(
                intent: intent,
                local: SyncPayload.build(from: MarketStore.shared.holdings),
                baseline: loadBaseline(),
                deviceID: recoveryDeviceID,
                enabled: isEnabled
            )
            let gate: () -> Bool = { [weak self] in
                // 只在后台文件写锁内调用。主线程此时不会等待 I/O。
                DispatchQueue.main.sync {
                    MainActor.assumeIsolated {
                        guard let self else { return false }
                        return self.generation == token
                            && self.isEnabled
                            && SyncPayload.build(from: MarketStore.shared.holdings) == job.local
                            && self.loadBaseline() == job.baseline
                    }
                }
            }
            let result: Result<SyncOutcome, Error> = await withCheckedContinuation { continuation in
                ioQueue.async {
                    continuation.resume(returning: Result {
                        try SyncFileIO.run(job, gate: gate)
                    })
                }
            }
            finish(result, job: job, token: token)
        }
        isProcessing = false
    }

    private func finish(_ result: Result<SyncOutcome, Error>, job: SyncJob, token: Int) {
        let outcome: SyncOutcome
        do {
            outcome = try result.get()
        } catch {
            if token == generation {
                availability = .available
                syncIssue = "iCloud 同步暂时无法完成：\(error.localizedDescription)"
            }
            return
        }
        if case .unavailable = outcome {
            availability = .unavailable(reason: "iCloud Drive 未开启或未登录 Apple ID")
            syncIssue = nil
            return
        }
        availability = .available
        if case .disabled = outcome { return }

        // 写入已经发生时先记录共同基线，随后再处理等待中的新编辑。
        if case .pushed(let written) = outcome {
            saveBaseline(written)
            if job.intent == .keepLocal {
                UserDefaults.standard.removeObject(forKey: Self.systemConflictKey)
            }
            hasConflict = false
            syncIssue = nil
            lastSyncedAt = Date()
            if currentLocal() != written && pendingIntent == nil && isEnabled {
                enqueue(.reconcile)
            }
            return
        }

        guard token == generation, isEnabled,
              currentLocal() == job.local,
              loadBaseline() == job.baseline else {
            if pendingIntent == nil && isEnabled { enqueue(.reconcile) }
            return
        }
        switch outcome {
        case .unchanged(let remote):
            saveBaseline(remote)
            hasConflict = false
            syncIssue = nil
        case .remote(let remote):
            applyRemoteSynchronously(remote)
            saveBaseline(remote)
            if job.intent == .keepRemote {
                UserDefaults.standard.removeObject(forKey: Self.systemConflictKey)
            }
            hasConflict = false
            syncIssue = nil
            lastSyncedAt = Date()
        case .conflict:
            hasConflict = true
            syncIssue = nil
        case .stale:
            if pendingIntent == nil { enqueue(.reconcile) }
        case .unavailable, .disabled, .pushed:
            break
        }
    }

    private func currentLocal() -> SyncPayload {
        SyncPayload.build(from: MarketStore.shared.holdings)
    }

    private func applyRemoteSynchronously(_ payload: SyncPayload) {
        isApplyingRemote = true
        defer { isApplyingRemote = false }
        let defaults = UserDefaults.standard
        for (key, value) in payload.settings {
            switch value {
            case .string(let string): defaults.set(string, forKey: key)
            case .double(let double): defaults.set(double, forKey: key)
            case .bool(let bool): defaults.set(bool, forKey: key)
            }
        }
        MarketStore.shared.replaceHoldings(payload.holdings)
        Task { await MarketStore.shared.refresh(showLoading: false) }
    }

    private func loadBaseline() -> SyncPayload? {
        guard let data = UserDefaults.standard.data(forKey: Self.baselineKey) else { return nil }
        return try? SyncFileIO.decode(data)
    }

    private func saveBaseline(_ payload: SyncPayload) {
        guard let data = try? SyncFileIO.encode(payload) else { return }
        guard UserDefaults.standard.data(forKey: Self.baselineKey) != data else { return }
        UserDefaults.standard.set(data, forKey: Self.baselineKey)
    }

    private var recoveryDeviceID: String {
        if let existing = UserDefaults.standard.string(forKey: Self.recoveryDeviceKey) {
            return existing
        }
        let created = UUID().uuidString.lowercased()
        UserDefaults.standard.set(created, forKey: Self.recoveryDeviceKey)
        return created
    }

    var isEnabled: Bool {
        if UserDefaults.standard.object(forKey: SettingsKey.icloudSyncEnabled) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: SettingsKey.icloudSyncEnabled)
    }
}

/// 所有文件协调、iCloud 下载等待与恢复副本 I/O 仅由后台串行队列调用。
private enum SyncFileIO {
    private static let systemConflictKey = "fundbar.sync.systemConflictPending"
    private typealias Remote = (payload: SyncPayload, data: Data)

    static var cloudRoot: URL? {
        guard let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else {
            return nil
        }
        let root = library.appendingPathComponent("Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return nil }
        return root
    }

    static func run(_ job: SyncJob, gate: () -> Bool) throws -> SyncOutcome {
        guard let root = cloudRoot else { return .unavailable }
        guard job.enabled else { return .disabled }
        let folder = root.appendingPathComponent("FundBar", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let fileURL = folder.appendingPathComponent("sync.json")
        let recoveryURL = folder.appendingPathComponent("Recovery", isDirectory: true)

        switch job.intent {
        case .reconcile:
            try preserveSystemVersionsIfNeeded(at: fileURL, recovery: recoveryURL, deviceID: job.deviceID)
            let remote = try readRemote(at: fileURL)
            guard gate() else { return .stale }
            let decision = UserDefaults.standard.bool(forKey: systemConflictKey)
                ? SyncConflictDecision.conflict
                : SyncConflictPolicy.decide(local: job.local, remote: remote?.payload, baseline: job.baseline)
            if decision == .pushLocal {
                return try pushLocal(job, at: fileURL, recovery: recoveryURL, gate: gate)
            }
            return try handleWithoutPush(
                decision, job: job, remote: remote, recovery: recoveryURL
            )
        case .keepLocal:
            return try coordinatedWrite(at: fileURL) { coordinatedURL in
                _ = try preserveSystemVersionsInWrite(
                    at: coordinatedURL, recovery: recoveryURL, deviceID: job.deviceID
                )
                let current = try decodeCurrent(at: coordinatedURL)
                try saveRecovery(job.local, label: "local", in: recoveryURL, deviceID: job.deviceID)
                if let current {
                    try saveRecovery(current.data, label: "icloud", in: recoveryURL, deviceID: job.deviceID)
                }
                guard gate() else { return .stale }
                var written = job.local
                written.updatedAt = max(
                    Date(), (current?.payload.updatedAt ?? .distantPast).addingTimeInterval(1)
                )
                try encode(written).write(to: coordinatedURL, options: .atomic)
                return .pushed(written)
            }
        case .keepRemote:
            try preserveSystemVersionsIfNeeded(at: fileURL, recovery: recoveryURL, deviceID: job.deviceID)
            guard let remote = try readRemote(at: fileURL) else {
                throw SyncIOError.remoteUnavailable
            }
            guard gate() else { return .stale }
            try saveRecovery(job.local, label: "local", in: recoveryURL, deviceID: job.deviceID)
            try saveRecovery(remote.data, label: "icloud", in: recoveryURL, deviceID: job.deviceID)
            return .remote(remote.payload)
        }
    }

    private static func pushLocal(
        _ job: SyncJob,
        at fileURL: URL,
        recovery: URL,
        gate: () -> Bool
    ) throws -> SyncOutcome {
        try coordinatedWrite(at: fileURL) { coordinatedURL in
            _ = try preserveSystemVersionsInWrite(
                at: coordinatedURL, recovery: recovery, deviceID: job.deviceID
            )
            let current = try decodeCurrent(at: coordinatedURL)
            guard gate() else { return .stale }
            let decision = UserDefaults.standard.bool(forKey: systemConflictKey)
                ? SyncConflictDecision.conflict
                : SyncConflictPolicy.decide(
                    local: job.local, remote: current?.payload, baseline: job.baseline
                )
            guard decision == .pushLocal else {
                return try handleWithoutPush(decision, job: job, remote: current, recovery: recovery)
            }
            var written = job.local
            written.updatedAt = max(
                Date(), (current?.payload.updatedAt ?? .distantPast).addingTimeInterval(1)
            )
            try encode(written).write(to: coordinatedURL, options: .atomic)
            return .pushed(written)
        }
    }

    private static func handleWithoutPush(
        _ decision: SyncConflictDecision,
        job: SyncJob,
        remote: Remote?,
        recovery: URL
    ) throws -> SyncOutcome {
        switch decision {
        case .unchanged:
            guard let remote else { return .stale }
            return .unchanged(remote.payload)
        case .applyRemote:
            guard let remote else { return .stale }
            return .remote(remote.payload)
        case .applyRemoteSavingLocal:
            guard let remote else { return .stale }
            try saveRecovery(job.local, label: "local", in: recovery, deviceID: job.deviceID)
            try saveRecovery(remote.data, label: "icloud", in: recovery, deviceID: job.deviceID)
            return .remote(remote.payload)
        case .conflict:
            try saveRecovery(job.local, label: "local", in: recovery, deviceID: job.deviceID)
            if let remote {
                try saveRecovery(remote.data, label: "icloud", in: recovery, deviceID: job.deviceID)
            }
            return .conflict
        case .pushLocal:
            return .stale
        }
    }

    private static func readRemote(at fileURL: URL) throws -> Remote? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return try coordinatedRead(at: fileURL) { try decodeCurrent(at: $0) }
    }

    private static func decodeCurrent(at fileURL: URL) throws -> Remote? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        return (try decode(data), data)
    }

    private static func preserveSystemVersionsIfNeeded(
        at fileURL: URL, recovery: URL, deviceID: String
    ) throws {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              !(NSFileVersion.unresolvedConflictVersionsOfItem(at: fileURL) ?? []).isEmpty else { return }
        _ = try coordinatedWrite(at: fileURL) {
            try preserveSystemVersionsInWrite(at: $0, recovery: recovery, deviceID: deviceID)
        }
    }

    private static func preserveSystemVersionsInWrite(
        at fileURL: URL, recovery: URL, deviceID: String
    ) throws -> Bool {
        let versions = NSFileVersion.unresolvedConflictVersionsOfItem(at: fileURL) ?? []
        guard !versions.isEmpty else { return false }
        let currentData = try Data(contentsOf: fileURL)
        let currentPayload = try? decode(currentData)
        var hasDifferentContent = false
        try saveRecovery(currentData, label: "icloud", in: recovery, deviceID: deviceID)
        for version in versions {
            let versionData = try Data(contentsOf: version.url)
            let versionPayload = try? decode(versionData)
            if currentPayload == nil || versionPayload == nil || currentPayload != versionPayload {
                hasDifferentContent = true
            }
            try saveRecovery(versionData, label: "version", in: recovery, deviceID: deviceID)
        }
        if hasDifferentContent {
            UserDefaults.standard.set(true, forKey: systemConflictKey)
        }
        for version in versions {
            version.isResolved = true
            try version.remove()
        }
        return hasDifferentContent
    }

    private static func saveRecovery(
        _ payload: SyncPayload, label: String, in folder: URL, deviceID: String
    ) throws {
        try saveRecovery(encode(payload), label: label, in: folder, deviceID: deviceID)
    }

    private static func saveRecovery(
        _ data: Data, label: String, in folder: URL, deviceID: String
    ) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var identity = data
        if var payload = try? decode(data) {
            payload.updatedAt = Date(timeIntervalSince1970: 0)
            identity = try encode(payload)
        }
        let digest = SHA256.hash(data: identity).map { String(format: "%02x", $0) }.joined()
        let destination = folder.appendingPathComponent("sync-\(deviceID)-\(label)-\(digest).json")
        if FileManager.default.fileExists(atPath: destination.path) {
            var existingIdentity = try Data(contentsOf: destination)
            if var existingPayload = try? decode(existingIdentity) {
                existingPayload.updatedAt = Date(timeIntervalSince1970: 0)
                existingIdentity = try encode(existingPayload)
            }
            guard existingIdentity == identity else { throw SyncIOError.recoveryCollision }
            return
        }
        try data.write(to: destination, options: .atomic)
    }

    static func encode(_ payload: SyncPayload) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(payload)
    }

    static func decode(_ data: Data) throws -> SyncPayload {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SyncPayload.self, from: data)
    }

    private static func coordinatedRead<T>(
        at fileURL: URL, _ body: (URL) throws -> T
    ) throws -> T {
        var coordinationError: NSError?
        var result: Result<T, Error>?
        NSFileCoordinator(filePresenter: nil).coordinate(
            readingItemAt: fileURL, options: [], error: &coordinationError
        ) { coordinatedURL in
            result = Result { try body(coordinatedURL) }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw SyncIOError.coordinationDidNotRun }
        return try result.get()
    }

    private static func coordinatedWrite<T>(
        at fileURL: URL, _ body: (URL) throws -> T
    ) throws -> T {
        var coordinationError: NSError?
        var result: Result<T, Error>?
        NSFileCoordinator(filePresenter: nil).coordinate(
            writingItemAt: fileURL, options: [], error: &coordinationError
        ) { coordinatedURL in
            result = Result { try body(coordinatedURL) }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw SyncIOError.coordinationDidNotRun }
        return try result.get()
    }

    private enum SyncIOError: LocalizedError {
        case recoveryCollision
        case remoteUnavailable
        case coordinationDidNotRun

        var errorDescription: String? {
            switch self {
            case .recoveryCollision: return "恢复副本文件与当前数据不一致"
            case .remoteUnavailable: return "云端同步文件暂时不可用，请稍后重试或选择保留本机版本"
            case .coordinationDidNotRun: return "文件协调未执行"
            }
        }
    }
}
