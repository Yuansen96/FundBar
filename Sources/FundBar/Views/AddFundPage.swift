import SwiftUI

/// 添加/修改基金:输入代码 → 从蛋卷拉名称与净值 → 填持有金额(选填成本)→ 保存
struct AddFundPage: View {
    var onDone: () -> Void

    @ObservedObject private var store = MarketStore.shared
    @State private var codeInput = ""
    @State private var amountInput = ""
    @State private var costInput = ""
    @State private var fetchedDetail: FundDetail?
    @State private var isLoading = false
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Button(action: onDone) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)
                Text("添加基金")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
            }

            Text("基金代码")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("如 161725", text: $codeInput)
                .textFieldStyle(.roundedBorder)
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
                        Text("净值 \(detail.unitNav?.priceText ?? "--")(\(detail.navDate ?? "--")) · 当日 \(detail.dayChangePercent?.percentText ?? "--")")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
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
                Text("保存")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 3)
            }
            .buttonStyle(.borderedProminent)
            .disabled(fetchedDetail == nil || parsedAmount == nil)

            Spacer()
        }
        .padding(16)
    }

    private var parsedAmount: Double? {
        guard let value = Double(amountInput), value > 0 else { return nil }
        return value
    }

    private var parsedCost: Double? {
        guard let value = Double(costInput), value > 0 else { return nil }
        return value
    }

    private func fetchDetail() {
        let code = codeInput.trimmingCharacters(in: .whitespaces)
        guard !code.isEmpty else { return }
        isLoading = true
        errorText = nil
        fetchedDetail = nil
        Task { @MainActor in
            do {
                fetchedDetail = try await DanjuanAPI.shared.fetchFundDetail(code: code)
            } catch {
                errorText = "查询失败:\(error.localizedDescription)"
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
