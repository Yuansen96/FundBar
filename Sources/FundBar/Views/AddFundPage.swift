import SwiftUI

/// 添加/编辑基金:输入代码 → 从蛋卷拉名称与净值 → 填持有金额(选填成本)→ 保存
struct AddFundPage: View {
    /// 非 nil 时为编辑模式:代码锁定,金额/成本预填
    var editing: Holding?
    var onDone: () -> Void

    @ObservedObject private var store = MarketStore.shared
    @State private var codeInput: String
    @State private var amountInput: String
    @State private var costInput: String
    @State private var fetchedDetail: FundDetail?
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var searchInput = ""
    @State private var searchResults: [EastmoneyFundAPI.SearchHit] = []
    @State private var isSearching = false

    init(editing: Holding?, onDone: @escaping () -> Void) {
        self.editing = editing
        self.onDone = onDone
        _codeInput = State(initialValue: editing?.code ?? "")
        _amountInput = State(initialValue: editing.map { String(format: "%.0f", $0.amount) } ?? "")
        _costInput = State(initialValue: editing.flatMap { $0.cost.map { String(format: "%.0f", $0) } } ?? "")
        _fetchedDetail = State(initialValue: editing.map {
            FundDetail(code: $0.code, name: $0.name, unitNav: nil, navDate: nil, dayChangePercent: nil)
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Button(action: onDone) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)
                Text(editing == nil ? "添加基金" : "编辑基金")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
            }

            if editing == nil {
                HStack(spacing: 8) {
                    TextField("搜索基金:名称 / 简拼 / 代码", text: $searchInput)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(searchFunds)
                    Button(action: searchFunds) {
                        Text(isSearching ? "搜索中…" : "搜索")
                    }
                    .disabled(searchInput.trimmingCharacters(in: .whitespaces).isEmpty || isSearching)
                }
                ForEach(searchResults) { hit in
                    Button {
                        codeInput = hit.code
                        searchResults = []
                        fetchDetail()
                    } label: {
                        HStack {
                            Text(hit.name)
                                .font(.system(size: 12.5))
                                .lineLimit(1)
                            Spacer()
                            Text(hit.code)
                                .font(.system(size: 11).monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                        .padding(.vertical, 5)
                        .padding(.horizontal, 6)
                        .background(Color.primary.opacity(0.03))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                }
                if isSearching {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                }
            }

            Text("基金代码")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("如 161725", text: $codeInput)
                .textFieldStyle(.roundedBorder)
                .disabled(editing != nil)
                .onSubmit(fetchDetail)

            HStack(spacing: 10) {
                Button(action: fetchDetail) {
                    Text(isLoading ? "查询中…" : "查询基金")
                }
                .disabled(codeInput.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
                if isLoading {
                    ProgressView().controlSize(.small)
                }
                if let detail = fetchedDetail {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(detail.name)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        if detail.unitNav != nil {
                            Text("净值 \(detail.unitNav?.priceText ?? "--")(\(detail.navDate ?? "--")) · 当日 \(detail.dayChangePercent?.percentText ?? "--")")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            if let errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Divider()

            Text("持有金额(元)")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("如 10000", text: $amountInput)
                .textFieldStyle(.roundedBorder)

            Text("成本金额(选填,用于计算持有收益)")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("如 12000", text: $costInput)
                .textFieldStyle(.roundedBorder)

            Button(action: save) {
                Text(editing == nil ? "保存" : "保存修改")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 3)
            }
            .buttonStyle(.borderedProminent)
            .disabled(fetchedDetail == nil || parsedAmount == nil)

            Spacer()
        }
        .padding(16)
        .task {
            // 编辑模式自动补拉最新净值,填充查询结果区
            if editing != nil, fetchedDetail?.unitNav == nil {
                fetchDetail()
            }
        }
    }

    private var parsedAmount: Double? {
        guard let value = Double(amountInput), value > 0 else { return nil }
        return value
    }

    private var parsedCost: Double? {
        guard let value = Double(costInput), value > 0 else { return nil }
        return value
    }

    private func searchFunds() {
        let keyword = searchInput.trimmingCharacters(in: .whitespaces)
        guard !keyword.isEmpty else { return }
        isSearching = true
        Task { @MainActor in
            searchResults = (try? await EastmoneyFundAPI.shared.searchFunds(keyword: keyword)) ?? []
            isSearching = false
        }
    }

    private func fetchDetail() {
        let code = codeInput.trimmingCharacters(in: .whitespaces)
        guard !code.isEmpty else { return }
        isLoading = true
        errorText = nil
        Task { @MainActor in
            do {
                let detail = try await DanjuanAPI.shared.fetchFundDetail(code: code)
                // 编辑模式下保留已有的名称展示兜底
                if fetchedDetail == nil || fetchedDetail?.code == detail.code {
                    fetchedDetail = detail
                }
            } catch {
                // 编辑模式查询失败不打断编辑(保留旧名称)
                if fetchedDetail == nil {
                    errorText = "查询失败:\(friendlyNetworkMessage(error))"
                }
            }
            isLoading = false
        }
    }

    private func save() {
        guard let detail = fetchedDetail, let amount = parsedAmount else { return }
        store.addOrUpdateHolding(
            Holding(code: detail.code, name: detail.name, amount: amount, cost: parsedCost)
        )
        onDone()
    }
}
