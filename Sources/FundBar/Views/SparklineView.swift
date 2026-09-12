import SwiftUI

/// 指数行内迷你走势(最近 20 日收盘),手绘 Path 避免 Charts 实例开销
struct SparklineView: View {
    let values: [Double]

    private var rising: Bool {
        guard let first = values.first, let last = values.last else { return true }
        return last >= first
    }

    var body: some View {
        let color = rising ? CnStyle.up : CnStyle.down
        return pathView(color: color)
    }

    private func pathView(color: Color) -> some View {
        let line = sparklinePath()
        return ZStack {
            line
                .stroke(color.opacity(0.25), lineWidth: 6)
            line
                .stroke(color.opacity(0.85), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
        }
    }

    private func sparklinePath() -> Path {
        var path = Path()
        guard values.count > 1 else { return path }
        let minV = values.min() ?? 0
        let maxV = values.max() ?? 1
        let range = max(maxV - minV, 0.0001)
        let width: CGFloat = 44
        let height: CGFloat = 16
        for (offset, value) in values.enumerated() {
            let x = CGFloat(offset) / CGFloat(values.count - 1) * width
            let y = height - CGFloat((value - minV) / range) * (height - 2) - 1
            if offset == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        return path
    }
}
