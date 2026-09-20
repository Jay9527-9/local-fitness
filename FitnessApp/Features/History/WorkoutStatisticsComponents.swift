//
//  WorkoutStatisticsComponents.swift
//  训练统计页的图表与卡片组件。
//
//  所有图表都是**纯 SwiftUI Shape 手绘**，没有引入 Charts 框架。
//  三个理由：
//  1. Charts 的轴标签、颜色、选中态要按本项目的深色令牌逐个覆写，
//     覆写量已经超过自己画一遍；
//  2. 手绘的每一根柱子都是独立视图，可以各自挂 VoiceOver 标签与点击区，
//     而 Charts 的 mark 内部无障碍要靠 annotation 绕；
//  3. 规格要求「横向空间不足时可降级为列表」——自己画才能把同一份数据
//     在「图」与「列表」两种渲染之间切换而不用改数据层。
//
//  所有图形都 `.accessibilityHidden(true)`，朗读交给外层拼好的文字摘要，
//  避免 VoiceOver 逐个形状念出一串没有意义的碎片。
//

import SwiftUI

// MARK: - 摘要统计卡

/// 摘要区的一张紧凑统计卡。
///
/// 四张卡用 `LazyVGrid` 排两列，而不是硬塞一行四张：
/// 动态字体调到最大时一行四张会把数字压得看不清，
/// 两列在任一字体档位下都还有可读空间。
struct StatsMetricCard: View {

    let metric: StatsMetric

    /// 「—」也是有效展示，所以不能用 `if let value` 把整卡藏掉
    private var isEmptyValue: Bool { metric.value == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.tight) {
            Text(metric.title)
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Palette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(metric.displayText)
                    .font(.system(size: DS.Size.statsMetricFont, weight: .bold))
                    .foregroundStyle(
                        isEmptyValue
                            ? DS.Palette.textTertiary
                            : (metric.isAccent ? DS.Palette.accent : DS.Palette.textPrimary)
                    )
                    .lineLimit(1)
                    // 容量可能是六七位数，缩小比截断好
                    .minimumScaleFactor(0.5)

                if let unit = metric.unit, !isEmptyValue {
                    Text(unit)
                        .font(DS.Typography.caption2)
                        .foregroundStyle(DS.Palette.textTertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, DS.Spacing.card)
        .padding(.vertical, DS.Spacing.item)
        .frame(maxWidth: .infinity, minHeight: DS.Size.statsMetricCardHeight, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .fill(DS.Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .stroke(DS.Palette.stroke, lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(metric.accessibilityText)
    }
}

// MARK: - 训练频率柱状图

/// 一根柱子（或一整周）。
///
/// 力量与有氧堆叠：力量在下、有氧在上。堆叠而不是并列，
/// 是因为同一格里两种训练同时出现的概率不高，并列会让柱宽减半、
/// 在 30 天的范围里细到看不清。
private struct FrequencyBar: View {

    let bucket: StatsFrequencyBucket
    let maxCount: Int
    let barWidth: CGFloat
    let isSelected: Bool
    let onTap: () -> Void

    /// 整柱满高对应这个像素高度
    private let fullHeight: CGFloat = DS.Size.statsFrequencyChartHeight

    private var total: Int { bucket.totalCount }

    /// 柱高。有训练时至少给 3pt，否则 1 次的柱子会细得看不见。
    private var barHeight: CGFloat {
        guard total > 0, maxCount > 0 else { return 0 }
        let ratio = CGFloat(total) / CGFloat(maxCount)
        return max(3, ratio * fullHeight)
    }

    /// 力量段的高度占比
    private var strengthRatio: CGFloat {
        guard total > 0 else { return 0 }
        return CGFloat(bucket.strengthCount) / CGFloat(total)
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                Spacer(minLength: 0)

                ZStack(alignment: .bottom) {
                    // 空柱的底槽：让「这天没练」也是一根可见的细线，
                    // 否则横轴上会出现整片空白，柱子位置看起来是乱的。
                    if total == 0 {
                        Capsule()
                            .fill(Color.white.opacity(0.06))
                            .frame(width: barWidth, height: 3)
                    } else {
                        VStack(spacing: 0) {
                            // 有氧在上
                            if bucket.cardioCount > 0 {
                                Rectangle()
                                    .fill(DS.Palette.cardio.opacity(isSelected ? 1 : 0.68))
                                    .frame(
                                        width: barWidth,
                                        height: barHeight * (1 - strengthRatio)
                                    )
                            }
                            // 力量在下
                            if bucket.strengthCount > 0 {
                                Rectangle()
                                    .fill(
                                        isSelected
                                            ? DS.Palette.statsSelectedBar
                                            : DS.Palette.statsStrengthBar
                                    )
                                    .frame(
                                        width: barWidth,
                                        height: barHeight * strengthRatio
                                    )
                            }
                        }
                        .clipShape(
                            RoundedRectangle(cornerRadius: min(4, barWidth / 2), style: .continuous)
                        )
                    }
                }
                .frame(height: fullHeight, alignment: .bottom)
            }
            .frame(minWidth: DS.Size.minTapTarget, minHeight: fullHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(bucket.accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint("轻点两下查看这天的训练时长")
    }
}

/// 训练频率图。
struct StatsFrequencyChart: View {

    let buckets: [StatsFrequencyBucket]
    let granularity: StatsFrequencyGranularity
    /// 选中格的日期
    @Binding var selectedDate: Date?
    let onSelect: (StatsFrequencyBucket) -> Void

    private var maxCount: Int { StatsFrequencyBuilder.maxCount(in: buckets) }

    /// 是否需要横向滚动。
    ///
    /// 规格要求「图表在小屏幕横向空间不足时可横向滚动或降级为列表」。
    /// 判定用「每格能不能分到至少 22pt」——低于这个宽度柱子会细到点不中，
    /// 那时候横向滚动比硬挤更可用。
    private var needsHorizontalScroll: Bool {
        buckets.count > 30
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.item) {
            legend
            chartBody
            if let selected = selectedBucket {
                selectionDetail(selected)
            }
        }
    }

    // MARK: 图例

    /// 图例。两种颜色必须各有文字说明 ——
    /// 只靠颜色区分训练类型，对色觉障碍用户等于没有信息。
    private var legend: some View {
        HStack(spacing: DS.Spacing.item) {
            legendDot(color: DS.Palette.statsStrengthBar, text: "力量")
            legendDot(color: DS.Palette.cardio, text: "有氧")
            Spacer(minLength: 0)
            Text(granularity.title)
                .font(DS.Typography.caption2)
                .foregroundStyle(DS.Palette.textTertiary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("图例：力量训练用灰绿色，有氧训练用蓝绿色，\(granularity.title)统计")
    }

    private func legendDot(color: Color, text: String) -> some View {
        HStack(spacing: 4) {
            Capsule()
                .fill(color)
                .frame(width: 10, height: 6)
            Text(text)
                .font(DS.Typography.caption2)
                .foregroundStyle(DS.Palette.textSecondary)
        }
    }

    // MARK: 绘图区

    private var chartBody: some View {
        HStack(alignment: .top, spacing: DS.Spacing.tight) {
            // 纵轴刻度：0 / 中值 / 最大值。三档够了，
            // 再多会在 160pt 高里挤成一列数字。
            axisLabels

            if buckets.isEmpty {
                emptyChart
            } else if needsHorizontalScroll {
                ScrollView(.horizontal, showsIndicators: false) {
                    barsRow
                }
            } else {
                barsRow
            }
        }
    }

    private var axisLabels: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text("\(maxCount)")
                .font(DS.Typography.caption2)
                .foregroundStyle(DS.Palette.textTertiary)
            Spacer(minLength: 0)
            if maxCount > 1 {
                Text("\(maxCount / 2)")
                    .font(DS.Typography.caption2)
                    .foregroundStyle(DS.Palette.textTertiary)
                Spacer(minLength: 0)
            }
            Text("0")
                .font(DS.Typography.caption2)
                .foregroundStyle(DS.Palette.textTertiary)
        }
        .frame(width: DS.Size.statsAxisWidth, height: DS.Size.statsFrequencyChartHeight + 18, alignment: .trailing)
        .accessibilityHidden(true)
    }

    private var barsRow: some View {
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(buckets) { bucket in
                VStack(spacing: 4) {
                    FrequencyBar(
                        bucket: bucket,
                        maxCount: maxCount,
                        barWidth: barWidth,
                        isSelected: isSelected(bucket),
                        onTap: {
                            Haptics.light()
                            withAnimation(DS.Motion.standard) {
                                selectedDate = isSelected(bucket) ? nil : bucket.date
                            }
                            onSelect(bucket)
                        }
                    )

                    // 横轴标签。柱子多时只标首尾与中间，否则文字会糊在一起。
                    Text(shouldShowAxisLabel(for: bucket) ? bucket.axisLabel : " ")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(
                            isSelected(bucket)
                                ? DS.Palette.accent
                                : DS.Palette.textTertiary
                        )
                        .lineLimit(1)
                        .fixedSize()
                        .frame(height: 12)
                        .accessibilityHidden(true)
                }
                .frame(minWidth: DS.Size.minTapTarget)
            }
        }
    }

    private var emptyChart: some View {
        VStack(spacing: DS.Spacing.tight) {
            Text("这个时间范围内没有训练记录")
                .font(DS.Typography.callout)
                .foregroundStyle(DS.Palette.textTertiary)
            Text("换一个时间范围，或先完成一次训练。")
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Palette.textTertiary)
        }
        .frame(maxWidth: .infinity, minHeight: DS.Size.statsFrequencyChartHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("训练频率图，这个时间范围内没有训练记录")
    }

    /// 柱子宽度。
    ///
    /// 不滚动时按可用宽度均分再夹到上限；滚动时固定一个可点中的宽度。
    private var barWidth: CGFloat {
        let available = UIScreen.main.bounds.width
            - DS.Spacing.page * 2
            - DS.Spacing.card * 2
            - DS.Size.statsAxisWidth
        guard buckets.count > 0 else { return 6 }
        let slot = needsHorizontalScroll
            ? 30
            : max(DS.Size.statsBarMinWidth, min(DS.Size.statsBarMaxWidth, available / CGFloat(buckets.count)))
        // 柱子本身取格宽的 62%，留出间隙，视觉上才有「一根一根」的节奏
        return max(2, slot * 0.62)
    }

    private func isSelected(_ bucket: StatsFrequencyBucket) -> Bool {
        guard let selectedDate else { return false }
        return Calendar.current.isDate(selectedDate, inSameDayAs: bucket.date)
    }

    /// 标签抽稀：柱子不多时每根都标，多了就只标每根之间的间隔。
    private func shouldShowAxisLabel(for bucket: StatsFrequencyBucket) -> Bool {
        guard buckets.count > DS.Size.statsAxisLabelMaxCount else { return true }
        let stride = max(1, buckets.count / DS.Size.statsAxisLabelMaxCount)
        guard let index = buckets.firstIndex(where: { $0.date == bucket.date }) else { return false }
        return index % stride == 0
    }

    // MARK: 选中详情

    private var selectedBucket: StatsFrequencyBucket? {
        guard let selectedDate else { return nil }
        return buckets.first { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }
    }

    /// 点击柱子后的详情行。
    ///
    /// 规格要求「点击柱状图显示该日训练数量和时长」，所以这里必须给出数字，
    /// 而不是只把柱子变色了事。
    private func selectionDetail(_ bucket: StatsFrequencyBucket) -> some View {
        HStack(spacing: DS.Spacing.item) {
            Image(systemName: "hand.tap")
                .font(.caption)
                .foregroundStyle(DS.Palette.accent)
            Text(detailTitle(for: bucket))
                .font(DS.Typography.footnote.weight(.semibold))
                .foregroundStyle(DS.Palette.textPrimary)
            Text(bucket.detailText)
                .font(DS.Typography.footnote)
                .foregroundStyle(DS.Palette.textSecondary)
                .lineLimit(2)
            Spacer(minLength: 0)
            Button {
                withAnimation(DS.Motion.standard) { selectedDate = nil }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.textTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("取消选中")
        }
        .padding(.horizontal, DS.Spacing.item)
        .padding(.vertical, DS.Spacing.tight)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                .fill(DS.Palette.surfaceElevated)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(bucket.accessibilityLabel)
    }

    private func detailTitle(for bucket: StatsFrequencyBucket) -> String {
        if bucket.days.count > 1 {
            let end = bucket.days.last ?? bucket.date
            return FormatterKit.dateRangeSlash(bucket.date, end)
        }
        return FormatterKit.shortDate(bucket.date)
    }
}

// MARK: - 容量趋势折线图

/// 容量趋势的折线路径。
///
/// 用 Catmull-Rom 风格的平滑：控制点取相邻两点的中点，
/// 得到一条不越过数据点、也不产生虚假峰值的曲线。
/// 不用三次样条 —— 后者在数据剧烈波动时会过冲，
/// 画出一个高于当天实际容量的尖峰，属于说谎。
private struct VolumeLineShape: Shape {

    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard points.count > 1 else { return path }

        path.move(to: points[0])
        for index in 0..<(points.count - 1) {
            let current = points[index]
            let next = points[index + 1]
            let midpoint = CGPoint(
                x: (current.x + next.x) / 2,
                y: (current.y + next.y) / 2
            )
            // 以中点为控制点画二次贝塞尔：曲线始终被夹在两点之间，不外扩。
            path.addQuadCurve(to: midpoint, control: current)
            if index == points.count - 2 {
                path.addQuadCurve(to: next, control: midpoint)
            }
        }
        return path
    }
}

/// 折线下方的渐变填充
private struct VolumeFillShape: Shape {

    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard points.count > 1 else { return path }

        path.move(to: CGPoint(x: points[0].x, y: rect.maxY))
        path.addLine(to: points[0])

        for index in 0..<(points.count - 1) {
            let current = points[index]
            let next = points[index + 1]
            let midpoint = CGPoint(x: (current.x + next.x) / 2, y: (current.y + next.y) / 2)
            path.addQuadCurve(to: midpoint, control: current)
            if index == points.count - 2 {
                path.addQuadCurve(to: next, control: midpoint)
            }
        }

        path.addLine(to: CGPoint(x: points[points.count - 1].x, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// 容量趋势图。折线 + 数据点，可选柱线组合。
struct StatsVolumeChart: View {

    let points: [StatsVolumePoint]
    /// 选中点的日期
    @Binding var selectedDate: Date?
    let onSelect: (StatsVolumePoint) -> Void

    /// 数据点少于这个数量时，额外在折线下方画出细柱，
    /// 让「只有两三个点」的图不至于空得像一条随机线段。
    private let barOverlayThreshold = 8

    private var maxVolume: Double {
        points.map { $0.volume }.max() ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.item) {
            if points.isEmpty {
                emptyState
            } else {
                chart
                if let selected = selectedPoint {
                    selectionDetail(selected)
                }
            }
        }
    }

    // MARK: 绘图

    private var chart: some View {
        GeometryReader { proxy in
            let layout = Layout(
                size: proxy.size,
                points: points,
                maxVolume: maxVolume
            )

            ZStack(alignment: .topLeading) {
                // 横向网格线三条
                gridLines(size: proxy.size)

                // 柱线组合：点少时补细柱
                if points.count <= barOverlayThreshold {
                    barOverlay(layout: layout)
                }

                // 折线下渐变
                VolumeFillShape(points: layout.scaledPoints)
                    .fill(
                        LinearGradient(
                            colors: [DS.Palette.statsVolumeFill, .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                // 折线本体
                VolumeLineShape(points: layout.scaledPoints)
                    .stroke(
                        DS.Palette.statsVolumeLine,
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                    )

                // 数据点
                dataPoints(layout: layout)
            }
        }
        .frame(height: DS.Size.statsVolumeChartHeight)
        .accessibilityHidden(true)
    }

    private func gridLines(size: CGSize) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { index in
                Rectangle()
                    .fill(DS.Palette.statsGrid)
                    .frame(height: 1)
                if index < 2 { Spacer(minLength: 0) }
            }
        }
        .frame(height: size.height)
    }

    private func barOverlay(layout: Layout) -> some View {
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                let height = layout.barHeight(for: point)
                Rectangle()
                    .fill(DS.Palette.statsVolumeLine.opacity(0.18))
                    .frame(width: layout.barWidth, height: height)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .offset(y: layout.size.height - height)
                    .id(index)
            }
        }
    }

    private func dataPoints(layout: Layout) -> some View {
        ForEach(Array(points.enumerated()), id: \.element.id) { _, point in
            let position = layout.position(for: point)
            Circle()
                .fill(
                    isSelected(point)
                        ? DS.Palette.statsSelectedBar
                        : DS.Palette.statsVolumeLine
                )
                .frame(width: isSelected(point) ? 9 : 5, height: isSelected(point) ? 9 : 5)
                .overlay(
                    Circle().stroke(DS.Palette.bg, lineWidth: 1.5)
                )
                .position(x: position.x, y: position.y)
        }
    }

    private var emptyState: some View {
        VStack(spacing: DS.Spacing.tight) {
            Text("这个范围内没有可统计的容量")
                .font(DS.Typography.callout)
                .foregroundStyle(DS.Palette.textTertiary)
                .multilineTextAlignment(.center)
            Text("容量来自力量训练里已完成的正式组。有氧训练不计容量。")
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Palette.textTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: DS.Size.statsVolumeChartHeight)
        .padding(.horizontal, DS.Spacing.item)
        // 明确「没有数据」而不是画一条贴着横轴的零折线 —— 规格的硬要求
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("容量趋势图，这个范围内没有容量数据")
    }

    // MARK: 选中

    private var selectedPoint: StatsVolumePoint? {
        guard let selectedDate else { return nil }
        return points.first { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }
    }

    private func isSelected(_ point: StatsVolumePoint) -> Bool {
        guard let selectedDate else { return false }
        return Calendar.current.isDate(selectedDate, inSameDayAs: point.date)
    }

    private func selectionDetail(_ point: StatsVolumePoint) -> some View {
        HStack(spacing: DS.Spacing.item) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.caption)
                .foregroundStyle(DS.Palette.accent)
            Text(FormatterKit.shortDate(point.date))
                .font(DS.Typography.footnote.weight(.semibold))
                .foregroundStyle(DS.Palette.textPrimary)
            Text("容量 \(FormatterKit.plainNumber(point.volume)) kg · \(point.sessionCount) 次训练")
                .font(DS.Typography.footnote)
                .foregroundStyle(DS.Palette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            Button {
                withAnimation(DS.Motion.standard) { selectedDate = nil }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.textTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("取消选中")
        }
        .padding(.horizontal, DS.Spacing.item)
        .padding(.vertical, DS.Spacing.tight)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                .fill(DS.Palette.surfaceElevated)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(point.accessibilityLabel)
    }

    // MARK: 坐标换算

    /// 把数据点映射到绘图区坐标。
    ///
    /// 抽成独立结构是为了让「只有 1 个点时怎么画」这类边界能单独推演：
    /// 单点时 `(count - 1) == 0`，若直接做除法会得到 NaN。
    private struct Layout {
        let size: CGSize
        let points: [StatsVolumePoint]
        let maxVolume: Double

        /// 左右各留一点内边距，否则首尾的数据点会被裁掉半个圆
        private var horizontalInset: CGFloat { 8 }
        private var verticalInset: CGFloat { 10 }

        private var usableWidth: CGFloat {
            max(1, size.width - horizontalInset * 2)
        }

        private var usableHeight: CGFloat {
            max(1, size.height - verticalInset * 2)
        }

        var barWidth: CGFloat {
            guard points.count > 0 else { return 6 }
            return max(4, min(20, usableWidth / CGFloat(points.count) * 0.5))
        }

        /// 单点时居中，多点时按等距分布。
        private func xPosition(for index: Int) -> CGFloat {
            guard points.count > 1 else { return size.width / 2 }
            let step = usableWidth / CGFloat(points.count - 1)
            return horizontalInset + step * CGFloat(index)
        }

        private func yPosition(for volume: Double) -> CGFloat {
            guard maxVolume > 0 else { return size.height - verticalInset }
            let ratio = CGFloat(volume / maxVolume)
            return size.height - verticalInset - ratio * usableHeight
        }

        var scaledPoints: [CGPoint] {
            points.enumerated().map { index, point in
                CGPoint(x: xPosition(for: index), y: yPosition(for: point.volume))
            }
        }

        func position(for point: StatsVolumePoint) -> CGPoint {
            guard let index = points.firstIndex(where: { $0.id == point.id }) else {
                return CGPoint(x: size.width / 2, y: size.height / 2)
            }
            return CGPoint(x: xPosition(for: index), y: yPosition(for: point.volume))
        }

        func barHeight(for point: StatsVolumePoint) -> CGFloat {
            guard maxVolume > 0 else { return 0 }
            return max(1, CGFloat(point.volume / maxVolume) * usableHeight)
        }
    }
}

// MARK: - 常练动作行

/// 「常练动作」列表的一行。点击进入动作历史趋势子页。
struct StatsTopExerciseRow: View {

    let stat: TopExerciseStat
    let rank: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: DS.Spacing.item) {
                // 名次。用文字而不是奖牌图标 —— 图标需要额外美术资源，
                // 而本项目坚持零第三方素材。
                Text("\(rank)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(rank == 1 ? DS.Palette.onAccent : DS.Palette.textSecondary)
                    .frame(width: 22, height: 22)
                    .background(
                        Circle().fill(
                            rank == 1 ? DS.Palette.accent : DS.Palette.surfaceElevated
                        )
                    )
                    .accessibilityHidden(true)

                MuscleGlyph(group: stat.iconGroup, size: 34)

                VStack(alignment: .leading, spacing: 3) {
                    Text(stat.displayName)
                        .font(DS.Typography.callout.weight(.medium))
                        .foregroundStyle(DS.Palette.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: DS.Spacing.item) {
                        if !stat.primaryMuscle.isEmpty {
                            MetaLabel(text: stat.primaryMuscle)
                        }
                        MetaLabel(text: stat.volumeText, icon: "scalemass")
                    }
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 3) {
                    Text(stat.setCountText)
                        .font(DS.Typography.callout.weight(.semibold))
                        .foregroundStyle(DS.Palette.accent)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DS.Palette.textTertiary)
                }
            }
            .frame(minHeight: DS.Size.minTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("第 \(rank) 名，\(stat.accessibilityLabel)")
        .accessibilityHint("轻点两下查看这个动作的历史趋势")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - 肌群分布横条

/// 「训练部位分布」的一行：肌群名 + 横向进度条 + 组数 + 百分比。
///
/// 规格明确要求「使用横向进度条，不使用饼图」。
/// 深色底上饼图的低饱和色块之间对比不足，且很难标注百分比；
/// 横向条在纵向空间上可比，也更容易挂无障碍标签。
struct StatsMuscleBarRow: View {

    let row: MuscleDistributionRow

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.tight) {
            HStack(spacing: DS.Spacing.tight) {
                Text(row.title)
                    .font(DS.Typography.footnote.weight(.medium))
                    .foregroundStyle(DS.Palette.textPrimary)

                Spacer(minLength: DS.Spacing.tight)

                Text(row.setCountText)
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Palette.textSecondary)

                Text(row.percentText)
                    .font(DS.Typography.caption.weight(.semibold))
                    .foregroundStyle(DS.Palette.textPrimary)
                    .frame(width: 42, alignment: .trailing)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.07))
                    Capsule()
                        .fill(Color(hex: row.colorHex))
                        .frame(width: max(2, proxy.size.width * CGFloat(max(0, min(1, row.ratio)))))
                }
            }
            .frame(height: DS.Size.statsMuscleBarHeight)
        }
        .padding(.vertical, DS.Spacing.tight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel)
    }
}

// MARK: - 时间范围抽屉

/// 时间范围选择抽屉。六种预设 + 自定义起止日期。
struct StatsRangePickerContent: View {

    let selected: StatsRangeKind
    /// 自定义范围的起止，仅在选择自定义时使用
    @Binding var customStart: Date
    @Binding var customEnd: Date
    let onSelect: (StatsRangeKind) -> Void
    /// 自定义日期改动后立即生效
    let onCustomDateChanged: () -> Void

    var body: some View {
        VStack(spacing: DS.Spacing.tight) {
            ForEach(StatsRangeKind.allCases) { kind in
                rangeRow(kind)

                if kind == .custom, selected == .custom {
                    customDatePickers
                }
            }
        }
    }

    private func rangeRow(_ kind: StatsRangeKind) -> some View {
        let isSelected = kind == selected
        return Button {
            Haptics.light()
            onSelect(kind)
        } label: {
            HStack(spacing: DS.Spacing.item) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title)
                        .font(DS.Typography.callout.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(DS.Palette.textPrimary)
                    Text(kind.subtitle)
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Palette.textTertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(DS.Palette.accent)
                }
            }
            .frame(minHeight: DS.Size.minTapTarget)
            .padding(.horizontal, DS.Spacing.item)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                    .fill(isSelected ? DS.Palette.surfaceElevated : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(kind.title)，\(kind.subtitle)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// 自定义起止日期。
    ///
    /// 用两个 `DatePicker` 而不是日历弹窗：统计页的自定义范围
    /// 通常是「上个月初到上个月底」这种跨月区间，
    /// 两个滚轮比在日历上点两次更快，也不会有「点错月份」的问题。
    private var customDatePickers: some View {
        VStack(spacing: DS.Spacing.item) {
            DatePicker(
                "开始日期",
                selection: $customStart,
                displayedComponents: .date
            )
            .datePickerStyle(.compact)
            .onChange(of: customStart) { _ in onCustomDateChanged() }

            DatePicker(
                "结束日期",
                selection: $customEnd,
                in: customStart...,
                displayedComponents: .date
            )
            .datePickerStyle(.compact)
            .onChange(of: customEnd) { _ in onCustomDateChanged() }

            if customStart > customEnd {
                Text("开始日期晚于结束日期，统计时已自动交换。")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Palette.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .tint(DS.Palette.accent)
        .padding(DS.Spacing.item)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                .fill(DS.Palette.surfaceElevated)
        )
    }
}

// MARK: - 容量筛选抽屉

/// 容量趋势的筛选抽屉：全部动作 / 按肌群 / 按单个动作。
struct StatsVolumeFilterContent: View {

    let filters: [StatsVolumeFilter]
    let selected: StatsVolumeFilter
    let onSelect: (StatsVolumeFilter) -> Void

    /// 肌群组
    private var muscleFilters: [StatsVolumeFilter] {
        filters.filter { if case .muscle = $0 { return true } else { return false } }
    }

    /// 单动作组
    private var exerciseFilters: [StatsVolumeFilter] {
        filters.filter { if case .exercise = $0 { return true } else { return false } }
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: DS.Spacing.item) {
                filterRow(.all)

                if !muscleFilters.isEmpty {
                    groupTitle("按肌群")
                    ForEach(muscleFilters, id: \.cacheKey) { filter in
                        filterRow(filter)
                    }
                }

                if !exerciseFilters.isEmpty {
                    groupTitle("按单个动作")
                    ForEach(exerciseFilters, id: \.cacheKey) { filter in
                        filterRow(filter)
                    }
                }
            }
            .padding(.bottom, DS.Spacing.section)
        }
    }

    private func groupTitle(_ text: String) -> some View {
        Text(text)
            .font(DS.Typography.caption.weight(.semibold))
            .foregroundStyle(DS.Palette.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, DS.Spacing.tight)
            .accessibilityAddTraits(.isHeader)
    }

    private func filterRow(_ filter: StatsVolumeFilter) -> some View {
        let isSelected = filter == selected
        return Button {
            Haptics.light()
            onSelect(filter)
        } label: {
            HStack(spacing: DS.Spacing.item) {
                if case .muscle(let group) = filter {
                    Capsule()
                        .fill(Color(hex: MuscleDistributionPalette.hex(for: group)))
                        .frame(width: 12, height: 6)
                }

                Text(filter.title)
                    .font(DS.Typography.callout.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(DS.Palette.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(DS.Palette.accent)
                }
            }
            .frame(minHeight: DS.Size.minTapTarget)
            .padding(.horizontal, DS.Spacing.item)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                    .fill(isSelected ? DS.Palette.surfaceElevated : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(filter.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - 数据管理入口

/// 统计页底部的「数据管理」入口卡。
struct StatsDataManagementCard: View {

    let onTap: () -> Void

    var body: some View {
        CardContainer {
            Button(action: onTap) {
                HStack(spacing: DS.Spacing.item) {
                    Image(systemName: "externaldrive")
                        .font(.body)
                        .foregroundStyle(DS.Palette.accent)
                        .frame(width: 26)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("数据管理")
                            .font(DS.Typography.cardTitle)
                            .foregroundStyle(DS.Palette.textPrimary)
                        Text("导出 JSON 备份、导入备份、清除全部训练记录")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Palette.textSecondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DS.Palette.textTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("数据管理")
            .accessibilityHint("导出备份、导入备份或清除训练记录")
            .accessibilityAddTraits(.isButton)
        }
    }
}

// MARK: - 图表卡容器

/// 统一的图表卡外壳：标题 + 可选副标题 + 可选尾部操作 + 内容。
struct StatsChartCard<Content: View>: View {

    let title: String
    var subtitle: String?
    /// 尾部操作文案（如当前筛选名）
    var trailingText: String?
    var onTrailingTap: (() -> Void)?
    /// 整张图的 VoiceOver 摘要
    var accessibilitySummary: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.item) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.tight) {
                Text(title)
                    .font(DS.Typography.cardTitle)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .accessibilityAddTraits(.isHeader)

                if let subtitle {
                    Text(subtitle)
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Palette.textTertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: DS.Spacing.tight)

                if let trailingText {
                    if let onTrailingTap {
                        Button {
                            Haptics.light()
                            onTrailingTap()
                        } label: {
                            HStack(spacing: 3) {
                                Text(trailingText)
                                    .font(DS.Typography.caption)
                                    .lineLimit(1)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .foregroundStyle(DS.Palette.accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(
                                Capsule().fill(DS.Palette.surfaceElevated)
                            )
                        }
                        .buttonStyle(PressableButtonStyle())
                        .accessibilityLabel("筛选：\(trailingText)")
                        .accessibilityHint("轻点两下切换筛选维度")
                    } else {
                        Text(trailingText)
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Palette.textTertiary)
                    }
                }
            }

            content
        }
        .padding(DS.Spacing.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .fill(DS.Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .stroke(DS.Palette.stroke, lineWidth: 1)
        )
        // 摘要挂在卡片上而不是逐个形状上：VoiceOver 一次读完一张图，
        // 而不是让用户点进十几个元素才能听明白。
        .accessibilityElement(children: .contain)
    }
}

// MARK: - 统计页骨架屏

struct StatsSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.section) {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: DS.Spacing.item),
                          GridItem(.flexible(), spacing: DS.Spacing.item)],
                spacing: DS.Spacing.item
            ) {
                ForEach(0..<4, id: \.self) { _ in
                    SkeletonBlock(height: DS.Size.statsMetricCardHeight)
                }
            }
            SkeletonBlock(height: 220)
            SkeletonBlock(height: 232)
            SkeletonBlock(height: 240)
            SkeletonBlock(height: 220)
        }
        .accessibilityElement()
        .accessibilityLabel("正在计算训练统计")
    }
}

// MARK: - 动作趋势行

/// 动作历史趋势里的一行：月份 + 组数进度条 + 容量。
///
/// 用进度条而不是柱状图：这里的一行本来就带文字，
/// 再叠一个独立的柱状图会让「哪根柱子对应哪个月」需要靠对齐去猜。
/// 进度条紧跟在自己的文字后面，归属是明确的。
struct ExerciseTrendRow: View {

    let point: ExerciseTrendPoint
    /// 全部月份里最大的组数，用来定标
    let maxSetCount: Int

    var body: some View {
        HStack(spacing: DS.Spacing.item) {
            Text(point.shortLabel)
                .font(DS.Typography.caption)
                .foregroundStyle(point.isEmpty ? DS.Palette.textTertiary : DS.Palette.textSecondary)
                .frame(width: 40, alignment: .leading)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.07))

                    if !point.isEmpty {
                        Capsule()
                            .fill(DS.Palette.statsVolumeLine)
                            .frame(width: barWidth(in: proxy.size.width))
                    }
                }
            }
            .frame(height: DS.Size.statsMuscleBarHeight)

            Text(point.setCount > 0 ? "\(point.setCount) 组" : "—")
                .font(DS.Typography.caption.weight(.semibold))
                .foregroundStyle(point.isEmpty ? DS.Palette.textTertiary : DS.Palette.textPrimary)
                .frame(width: 46, alignment: .trailing)

            Text(point.isEmpty ? "" : FormatterKit.plainNumber(point.volume))
                .font(DS.Typography.caption2)
                .foregroundStyle(DS.Palette.textTertiary)
                .frame(width: 52, alignment: .trailing)
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(point.accessibilityLabel)
    }

    /// 空月份不给宽度。给个最小宽度的话，「没练」和「练了一点点」
    /// 在视觉上会变得难以区分 —— 宽度为零才是诚实的表达。
    private func barWidth(in total: CGFloat) -> CGFloat {
        guard maxSetCount > 0, point.setCount > 0 else { return 0 }
        let ratio = CGFloat(point.setCount) / CGFloat(maxSetCount)
        return max(4, total * ratio)
    }
}
