//
//  HistorySessionDetail.swift
//  页面 09：历史训练详情的纯值语义层。
//
//  这一层**不 import SwiftUI**，全部是纯函数与纯数据结构。这么做有两条理由：
//
//  1. 本机是 Windows，没有 Swift 编译器。纯值类型可以逐字照搬成 Python 类做
//     断言推演（见 Tools/probe_page09_semantics.py），把「动作已从动作库消失时
//     页面该怎么显示」「复制成草稿要清掉哪些字段」这类逻辑错误在打包前抓出来。
//  2. 历史记录是**只读快照 + 可变动作库**的组合。所有「快照字段优先、动作库兜底」
//     的判断集中在这里一处，视图层只消费结果，不去自己拼兜底逻辑。
//

import Foundation

// MARK: - 动作记录的可用性

/// 历史记录里的一个动作相对于**当前**动作库的可用性。
///
/// 历史训练记录存的是 `exerciseID` 与当时的重量次数，动作库却是随时可变的。
/// 用户可能把某个自定义动作删掉，或把某个导入动作隐藏掉。
/// 这种情况下历史记录**必须照常显示动作名与全部已完成数据**，
/// 只有「跳到动作详情」这个入口需要降级。
enum HistoryExerciseAvailability: Equatable {

    /// 动作库里有，且可见。可以跳详情、可以看媒体。
    case available

    /// 动作库里有，但用户把它隐藏了。
    ///
    /// 刻意与 `missing` 分开：隐藏是可逆的用户选择，不该说成「已不可用」，
    /// 否则用户会以为数据丢了。文案上用「已隐藏」提示去动作库里恢复。
    case hidden

    /// 动作库里已经没有这条 id 了（自定义动作被删除，或动作库被整体替换）。
    case missing

    /// 是否还能进入动作详情
    var canOpenDetail: Bool { self == .available }

    /// 是否还能展示媒体。隐藏的动作仍然可以看，缺失的不行。
    var canShowMedia: Bool { self != .missing }

    /// 降级提示文案。可正常打开时返回 nil，视图层据此决定要不要显示提示条。
    var noticeText: String? {
        switch self {
        case .available:
            return nil
        case .hidden:
            return "该动作已隐藏，仍可查看这一天的完成记录。"
        case .missing:
            return "该动作已不可用，仅保留历史记录中的名称与数据。"
        }
    }

    /// 无障碍朗读用的短描述
    var accessibilityText: String {
        switch self {
        case .available: return ""
        case .hidden: return "该动作已隐藏"
        case .missing: return "该动作已不可用"
        }
    }
}

// MARK: - 动作记录的展示模型

/// 历史训练详情里的一个动作分组。
///
/// 它同时携带两种来源的数据：
/// - **快照**：`entries` 里的重量、次数、完成时间。这是当时真实发生的事。
/// - **动作库**：`displayName` / `primaryMuscle`。这是现在的信息，可能已变。
///
/// 关键约定：**动作名永远不是空的**。动作库查不到时回退到快照里存的名字
/// （`WorkoutSession.entries` 只有 id，所以回退名就是 id 本身或其兜底串），
/// 再退一步用「未知动作」。绝不能出现一行没有标题的动作卡。
struct HistoryExerciseRecord: Identifiable, Equatable {

    /// 分组标识即动作 id。同一次训练里替换过动作会出现两张卡，
    /// 各自是独立的 id，不会撞。
    var id: String { exerciseID }

    let exerciseID: String
    /// 展示名称。已做兜底，非空。
    let displayName: String
    /// 主肌群中文名。动作库缺失时为空串。
    let primaryMuscle: String
    /// 肌群图标分组。动作库缺失时按 `other` 兜底。
    let iconGroup: MuscleIconGroup
    let availability: HistoryExerciseAvailability

    /// 该动作的全部组，按 `index` 升序
    let entries: [SetEntry]

    /// 已完成且非热身的组数（正式组）
    var workingSetCount: Int {
        entries.filter { $0.isCompleted && !$0.isWarmup }.count
    }

    /// 已完成的全部组数（含热身）
    var completedSetCount: Int {
        entries.filter { $0.isCompleted }.count
    }

    /// 计划 / 记录的组数
    var totalSetCount: Int { entries.count }

    /// 该动作容量。热身组在 `SetEntry.volume` 里恒为 0，这里不用再过滤。
    var volume: Double {
        entries.reduce(0) { $0 + ($1.isCompleted ? $1.volume : 0) }
    }

    /// 是否只有热身组：卡片上改用「热身」措辞，避免显示「0 组」让人以为记录丢了
    var isWarmupOnly: Bool {
        completedSetCount > 0 && workingSetCount == 0
    }

    /// 「3 组」/「3 组（含 1 组热身）」
    var setCountText: String {
        if isWarmupOnly {
            return "热身 \(completedSetCount) 组"
        }
        let warmups = entries.filter { $0.isCompleted && $0.isWarmup }.count
        return warmups > 0 ? "\(completedSetCount) 组 · 含 \(warmups) 组热身" : "\(completedSetCount) 组"
    }

    /// 卡片上的容量文案。为 0 时显示破折号，不显示「容量 0 kg」。
    var volumeText: String {
        volume > 0 ? FormatterKit.volume(volume) : "—"
    }

    /// 全部组都未完成时，卡片要明确说明，而不是显示一堆空行
    var hasAnyCompleted: Bool { completedSetCount > 0 }

    /// 无障碍标签：「杠铃卧推，胸，完成 4 组，容量 2400 千克」
    var accessibilityLabel: String {
        var parts: [String] = [displayName]
        if !primaryMuscle.isEmpty { parts.append(primaryMuscle) }
        parts.append(hasAnyCompleted ? "完成 \(setCountText)" : "没有已完成的组")
        if volume > 0 {
            parts.append("该动作容量 \(FormatterKit.plainNumber(volume)) 千克")
        }
        let notice = availability.accessibilityText
        if !notice.isEmpty { parts.append(notice) }
        return parts.joined(separator: "，")
    }
}

// MARK: - 单组展示

/// 一组在历史详情里的展示文案。
///
/// 单独抽出来是因为「完成时间」的格式在一处定义、两处使用（卡片与无障碍），
/// 而且 `completedAt` 有一个必须处理的历史脏数据：早期版本缺字段时
/// `SetEntry` 解码会补 `Date(timeIntervalSince1970: 0)`，也就是 1970 年。
/// 那个时间点不能当作真实完成时间念给用户听。
enum HistorySetDisplay {

    /// 补位用的哨兵时间。与 `SetEntry.init(from:)` 里的兜底值保持一致。
    static let unknownCompletionDate = Date(timeIntervalSince1970: 0)

    /// 完成时间文本。没有完成时间、或时间落在纪元起点（旧数据兜底值）时返回 nil。
    ///
    /// 判据用「早于 2001-01-01」而不是「等于 1970-01-01」：
    /// 只要时钟明显不对（比如设备时间被设成 1970 年代）就一律不显示，
    /// 否则页面上会出现一个看起来像 bug 的「1970年1月1日 08:00」。
    static func completionTimeText(for entry: SetEntry) -> String? {
        guard let completedAt = entry.completedAt else { return nil }
        guard completedAt > referenceFloor else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: completedAt)
    }

    /// 早于此时间的完成时间一律视为无效兜底值。
    /// 取 2001-01-01（Cocoa 时间原点）—— 这个 App 2026 年才存在，
    /// 任何早于 Cocoa 原点的时间都只可能是默认值或坏时钟。
    static let referenceFloor = Date(timeIntervalSinceReferenceDate: 0)

    /// 一组的主文案：「40 kg × 8」
    static func loadText(for entry: SetEntry) -> String {
        guard entry.isCompleted else {
            return "未完成 · 目标 \(entry.targetRepsText) 次"
        }
        return "\(FormatterKit.weight(entry.weight)) × \(entry.reps)"
    }

    /// 是否达标。仅已完成且非热身组有意义。
    static func targetStateText(for entry: SetEntry) -> String? {
        guard entry.isCompleted, !entry.isWarmup else { return nil }
        return entry.metTarget ? nil : "低于目标"
    }

    /// 一组的无障碍朗读语句
    static func accessibilityLabel(for entry: SetEntry) -> String {
        var parts = ["第 \(entry.index) 组"]
        if entry.isWarmup { parts.append("热身组") }
        if entry.isCompleted {
            parts.append("\(FormatterKit.weight(entry.weight))，\(entry.reps) 次")
        } else {
            parts.append("未完成，目标 \(entry.targetRepsText) 次")
        }
        if let state = targetStateText(for: entry) { parts.append(state) }
        if let time = completionTimeText(for: entry) {
            parts.append("完成于 \(time)")
        }
        return parts.joined(separator: "，")
    }
}

// MARK: - 摘要与统计

/// 历史训练详情的顶部摘要。
///
/// 力量与有氧共用同一个结构，靠 `metrics` 数组区分，
/// 这样视图层只有一套渲染逻辑，不会出现「加了有氧字段忘了改力量分支」。
struct HistorySessionSummary: Equatable {

    /// 单格统计
    struct Metric: Identifiable, Equatable {
        let id: String
        let title: String
        /// 数值型指标的值。`literalText` 非空时不使用。
        let value: Double
        var unit: String?
        /// 直接显示的文本（平均配速这类比值不适合递增动画）
        var literalText: String?
        var isAccent: Bool = false
    }

    let sessionID: UUID
    let name: String
    /// 训练类型
    let kind: WorkoutSession.Kind
    /// 「9月10日 星期四」——日期
    let dateText: String
    /// 「19:30」——开始时间
    let startTimeText: String
    /// 「45 分钟」——总时长
    let durationText: String
    /// 是否已结束。理论上历史详情只会被已结束的记录打开，这里仍显式判断，
    /// 避免有人把进行中的记录推进来后显示一个荒谬的「0 分钟」。
    let isFinished: Bool
    let metrics: [Metric]

    /// 摘要卡的无障碍语句：「杠铃日，9月10日 星期四 19:30，力量训练，时长 45 分钟，完成 18 组，总容量 4200 千克」
    var accessibilityLabel: String {
        var parts = [name]
        parts.append("\(dateText) \(startTimeText)")
        parts.append("\(kind.title)训练")
        parts.append("时长 \(durationText)")
        for metric in metrics {
            if let literal = metric.literalText {
                parts.append("\(metric.title) \(literal)\(metric.unit ?? "")")
            } else {
                parts.append("\(metric.title) \(FormatterKit.plainNumber(metric.value))\(metric.unit ?? "")")
            }
        }
        return parts.joined(separator: "，")
    }

    /// 力量训练展示总组数 / 总容量；有氧展示距离 / 平均配速 / 消耗。
    ///
    /// 与页面 07 总结页的取值保持一致：都走 `WorkoutSession` 上的派生属性，
    /// 不在详情页重算一遍。同一份记录在两个页面上数字不同是最难查的 bug。
    static func build(
        session: WorkoutSession,
        dateText: String,
        startTimeText: String
    ) -> HistorySessionSummary {
        let durationText = FormatterKit.duration(seconds: session.durationSeconds)
        var metrics: [Metric] = [
            Metric(
                id: "sets",
                title: "总组数",
                value: Double(session.completedSetCount),
                unit: "组"
            )
        ]

        if session.kind == .cardio {
            metrics.append(Metric(
                id: "distance",
                title: "距离",
                value: session.distanceKilometers,
                unit: "公里",
                literalText: session.distanceMeters == nil
                    ? "—"
                    : String(format: "%.2f", session.distanceKilometers),
                isAccent: true
            ))
            // 配速不是可累加的量，直接给文本，不参与递增动画
            metrics.append(Metric(
                id: "pace",
                title: "平均配速",
                value: 0,
                unit: "/ 公里",
                literalText: FormatterKit.pace(
                    seconds: session.durationSeconds,
                    meters: session.distanceMeters ?? 0
                ),
                isAccent: true
            ))
            metrics.append(Metric(
                id: "kcal",
                title: "消耗估算",
                value: session.kilocalories,
                unit: "千卡"
            ))
        } else {
            metrics.append(Metric(
                id: "volume",
                title: "总容量",
                value: session.totalVolume,
                unit: "kg",
                isAccent: true
            ))
            metrics.append(Metric(
                id: "exercises",
                title: "动作数",
                value: Double(session.completedExerciseCount),
                unit: "个"
            ))
        }

        return HistorySessionSummary(
            sessionID: session.id,
            name: session.name,
            kind: session.kind,
            dateText: dateText,
            startTimeText: startTimeText,
            durationText: durationText,
            isFinished: session.isFinished,
            metrics: metrics
        )
    }
}

// MARK: - 只读契约

/// 已完成训练的只读规则。
///
/// 规格明确要求「不允许在历史详情直接修改完成组数据，避免统计结果失真」。
/// 把这条规则做成一个显式的、可推演的函数，而不是散落在视图里靠「没写编辑按钮」来保证。
/// 将来如果有人想在历史页加编辑入口，必须先改这里，改动会被
/// `Tools/probe_page09_semantics.py` 的断言挡下来。
enum HistoryEditPolicy {

    /// 已结束的记录不允许直接改组数据
    static func allowsSetDataEditing(session: WorkoutSession) -> Bool {
        !session.isFinished
    }

    /// 已结束的记录不允许改标题以外的运动学字段。
    /// 这里只回答「能不能改」；具体能改哪些字段见 `allowedFields`。
    static func allowedFields(session: WorkoutSession) -> Set<Field> {
        guard session.isFinished else {
            // 未结束的草稿走训练执行页，历史详情不负责编辑
            return []
        }
        // 已完成的记录只开放两个纯标注字段
        return [.title, .note]
    }

    enum Field: String {
        case title
        case note
        /// 组数据（重量 / 次数 / 完成状态）——永远不允许在历史详情修改
        case setData
    }

    /// 「如需重练」的引导文案。删除与编辑都要避开「复制成草稿」这条正路时才提示。
    static let redoHint = "要重新练一次，请用「复制为新训练草稿」。"
}

// MARK: - 复制为新训练草稿

/// 把一条已完成的训练复制成一份未完成草稿。
///
/// 规格要求：复制动作顺序、目标组数和最近实际重量 / 次数，
/// **不复制**完成状态、完成时间与旧备注。
///
/// 这个函数是纯的（输入一条记录，输出另一条记录），所以可以直接推演。
/// 它替代了页面 08 里 `HistoryViewModel.duplicate` 的自由训练版本——
/// 那版把备注也复制了过去，与本页规格冲突；本页以规格为准。
enum HistorySessionDuplicator {

    /// 复制结果。之所以返回结构体而不是直接给 `WorkoutSession`，
    /// 是为了让调用方能拿到「复制了几组、几个动作」用于 toast 文案。
    struct Result: Equatable {
        let draft: WorkoutSession
        let exerciseCount: Int
        let setCount: Int
        /// 有多少组被复制时没有实际重量（自重或从未填写），文案里会说明
        let bodyweightSetCount: Int
    }

    /// 生成草稿。
    /// - Parameters:
    ///   - session: 源记录，通常是已完成的
    ///   - startedAt: 新草稿的开始时间，默认此刻
    ///   - nameSuffix: 名称后缀
    static func makeDraft(
        from session: WorkoutSession,
        startedAt: Date = .now,
        nameSuffix: String = " 副本"
    ) -> Result {

        // 组记录：保留动作、组号、重量、次数与目标区间，清掉完成状态。
        // `id` 必须换新——否则复制出的草稿与源记录共用组 id，
        // 将来「按 entryID 定位某一组」的写操作会同时命中两条记录。
        let copiedEntries: [SetEntry] = session.entries.map { entry in
            var copy = entry
            copy.id = UUID()
            copy.completedAt = nil
            return copy
        }

        // 动作出现顺序按源记录的 entries 顺序保留。
        // 这里统计「出现过」的动作数，而不是「完成过」的，因为草稿里所有组都是待完成，
        // 用完成数会得出 0。
        var seen: [String] = []
        for entry in copiedEntries where !seen.contains(entry.exerciseID) {
            seen.append(entry.exerciseID)
        }

        let bodyweightCount = copiedEntries.filter { $0.weight <= 0 }.count

        let draft = WorkoutSession(
            id: UUID(),
            name: draftName(from: session.name, suffix: nameSuffix),
            kind: session.kind,
            startedAt: startedAt,
            endedAt: nil,
            entries: copiedEntries,
            // 里程与消耗是**这一次**发生的事，不该带进新草稿，
            // 否则用户还没跑就已经有 5 公里了。
            distanceMeters: nil,
            consumedKilocalories: nil,
            planID: nil,
            // 旧备注属于那一次训练，不复制
            note: nil
        )

        return Result(
            draft: draft,
            exerciseCount: seen.count,
            setCount: copiedEntries.count,
            bodyweightSetCount: bodyweightCount
        )
    }

    /// 名称：原名称加后缀。已经以「副本」结尾时不再叠加，
    /// 避免连点两次出现「推拉腿 副本 副本」。
    static func draftName(from name: String, suffix: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "训练" : trimmed
        let marker = suffix.trimmingCharacters(in: .whitespaces)
        if !marker.isEmpty, base.hasSuffix(marker) {
            return base
        }
        return base + suffix
    }
}

// MARK: - 索引构建

/// 把一条训练记录与动作库合成历史详情要用的展示数据。
enum HistorySessionDetailIndex {

    /// 构建动作记录列表。
    ///
    /// 顺序规则：**按训练完成时的动作顺序**，即 `session.entriesByExercise`
    /// 给出的首次出现顺序。这里刻意不按容量或组数排序——
    /// 用户回看一次训练时，记忆里的顺序就是当时做的顺序。
    ///
    /// - Parameters:
    ///   - session: 训练记录
    ///   - library: 当前动作库。传空数组也能工作，此时全部走 `missing` 降级。
    static func records(
        for session: WorkoutSession,
        library: [ExerciseLibraryItem]
    ) -> [HistoryExerciseRecord] {

        var byID: [String: ExerciseLibraryItem] = [:]
        for item in library where byID[item.id] == nil {
            byID[item.id] = item
        }

        return session.entriesByExercise.map { group in
            let item = byID[group.exerciseID]

            let availability: HistoryExerciseAvailability
            if let item {
                availability = item.isHidden ? .hidden : .available
            } else {
                availability = .missing
            }

            return HistoryExerciseRecord(
                exerciseID: group.exerciseID,
                displayName: displayName(for: group.exerciseID, item: item),
                primaryMuscle: item?.primaryMuscle ?? "",
                iconGroup: iconGroup(for: item),
                availability: availability,
                entries: group.entries.sorted { $0.index < $1.index }
            )
        }
    }

    /// 展示名称。三级兜底：动作库中文别名 → 动作库原名 → id 本身。
    ///
    /// 第三级用 id 而不是「未知动作」：自定义动作的 id 形如 `custom-<UUID>` 很难看，
    /// 但比一句无法区分的「未知动作」更有诊断价值；而导入动作的 id 是数字串
    /// （如 `0025`），用户至少能凭它找回动作。真到了连 id 都没有的程度才用兜底串。
    static func displayName(for exerciseID: String, item: ExerciseLibraryItem?) -> String {
        if let item {
            let display = item.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !display.isEmpty { return display }
            let raw = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !raw.isEmpty { return raw }
        }
        let trimmedID = exerciseID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedID.isEmpty ? "未知动作" : trimmedID
    }

    /// 肌群图标分组。动作库缺失时用 `other`，图形组件会画一个中性体块。
    private static func iconGroup(for item: ExerciseLibraryItem?) -> MuscleIconGroup {
        guard let item else { return .other }
        return MuscleIconGroup.of(muscle: item.primaryMuscle)
    }

    /// 详情页顶部的日期与开始时间。
    static func dateText(_ session: WorkoutSession) -> String {
        FormatterKit.fullDate(session.startedAt)
    }

    static func startTimeText(_ session: WorkoutSession) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: session.startedAt)
    }

    /// 汇总：有几个动作、几组、多少容量。用于「动作记录」区标题右侧。
    static func totals(for records: [HistoryExerciseRecord]) -> (exerciseCount: Int, setCount: Int) {
        (records.count, records.reduce(0) { $0 + $1.completedSetCount })
    }
}

// MARK: - 动作记录排序

/// 历史详情的排序方式。
///
/// 目前只暴露「动作顺序」一种，`volume` 分支留着但**未接到界面上**：
/// 规格明确要求「按训练完成时的动作顺序排列」，多加一个排序切换会违背它。
/// 保留 `volume` 的理由是有推演断言覆盖它（`probe_page09_semantics.py` 第 05 组）——
/// 万一将来规格改口要加排序，那段逻辑已经被验证过是稳定的（并列时保持原序）。
enum HistoryRecordOrder: String, CaseIterable, Identifiable {
    case performed
    case volume

    var id: String { rawValue }

    var title: String {
        switch self {
        case .performed: return "动作顺序"
        case .volume: return "按容量"
        }
    }

    /// 排序。`performed` 是默认，保持传入顺序（即当时的动作顺序）。
    func apply(to records: [HistoryExerciseRecord]) -> [HistoryExerciseRecord] {
        switch self {
        case .performed:
            return records
        case .volume:
            // 容量并列时保持原有相对顺序，不引入不稳定排序
            return records.enumerated()
                .sorted { lhs, rhs in
                    if lhs.element.volume == rhs.element.volume {
                        return lhs.offset < rhs.offset
                    }
                    return lhs.element.volume > rhs.element.volume
                }
                .map { $0.element }
        }
    }

    /// 详情页实际采用的排序。集中在这里，避免视图层写死。
    static let detailDefault: HistoryRecordOrder = .performed
}
