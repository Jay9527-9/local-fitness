//
//  ExerciseLibraryViewModel.swift
//  动作库页面的状态机：加载、150ms 防抖搜索、筛选、排序、收藏、隐藏、删除。
//
//  只依赖 FitnessRepository 协议。检索全部在内存里做，不发任何网络请求。
//

import Foundation
import Combine

@MainActor
final class ExerciseLibraryViewModel: ObservableObject {

    // MARK: - 状态

    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    @Published private(set) var loadState: LoadState = .loading

    /// 全量动作（含隐藏条目）。筛选与检索都基于这一份数据。
    /// 不要直接赋值 —— 走 replaceAllExercises(_:) 以维护数据版本号。
    @Published private(set) var allExercises: [ExerciseLibraryItem] = [] {
        didSet { dataVersion &+= 1 }
    }
    /// allExercises 的修改版本号，供派生结果判断是否需要重算。
    private var dataVersion: Int = 0
    /// 最近使用，最多 6 条。为空时页面不渲染该区。
    /// 变化会影响 `.recentlyUsed` 排序，因此自动触发派生结果重算。
    @Published private(set) var recentExercises: [ExerciseLibraryItem] = [] {
        didSet { rebuildDerived() }
    }

    /// 搜索框文案。变化后 150ms 才真正生效。
    @Published var searchText: String = ""
    /// 防抖生效后的关键词，用于实际检索。
    @Published private(set) var debouncedKeyword: String = "" {
        didSet { rebuildDerived() }
    }

    @Published var filter: ExerciseFilter = .none {
        didSet { rebuildDerived() }
    }
    @Published var sort: ExerciseSortOrder {
        didSet { rebuildDerived() }
    }

    /// 删除失败等操作的提示文案，nil 表示不提示
    @Published var errorMessage: String?

    // MARK: - 派生结果（预计算）

    // 下面这一组全部是「由 allExercises / filter / sort / debouncedKeyword 决定」
    // 的派生值。曾经它们是计算属性，于是每渲染一行都要把 1324 条动作重新
    // 过滤、重新评分、重新排序一遍 —— 列表滚动时每个可见行都触发一次，
    // 是动作库「加载慢 + 卡顿」的主因。
    //
    // 现在改为在数据或条件变化时**一次性算完**并缓存。视图层只读结果，
    // 不触发任何计算。新增会改变结果的状态时，必须同步调用 rebuildDerived()
    // （见下方 recomputeIfNeeded() 的白名单）。

    /// 当前筛选 / 检索 / 排序后的结果列表
    @Published private(set) var results: [ExerciseLibraryItem] = []
    /// 肌群 Chip 的角标
    @Published private(set) var muscleCounts: [String: Int] = [:]
    /// 「全部」之外应展示的肌群 Chip
    @Published private(set) var muscleCategories: [String] = []
    /// 可用的器械清单，由数据推导而非硬编码
    @Published private(set) var availableEquipments: [String] = []
    /// 高级筛选里提示用的隐藏条目数
    @Published private(set) var hiddenCount: Int = 0
    /// 自定义动作数
    @Published private(set) var customCount: Int = 0
    /// 收藏数
    @Published private(set) var favoriteCount: Int = 0
    /// 结果里是否存在带本地媒体的条目（决定是否渲染署名）
    @Published private(set) var hasLocalMediaInResults: Bool = false

    /// 上一次重算所依据的输入指纹。相同则跳过重算。
    private var derivedKey: DerivedKey?

    /// 影响派生结果的全部输入。任一变化即需重算。
    private struct DerivedKey: Equatable {
        /// 数据版本号。每次 allExercises 被替换或就地修改时递增。
        var dataVersion: Int
        var keyword: String
        var filter: ExerciseFilter
        var sort: ExerciseSortOrder
        /// 最近使用次序，影响 .recentlyUsed 排序与 results 内容
        var recentIDs: [String]
    }

    // MARK: - 配置

    /// 搜索防抖时长
    static let searchDebounce: TimeInterval = 0.15
    /// 最近使用展示上限
    static let recentLimit = 6

    private let repository: FitnessRepository
    private var searchCancellable: AnyCancellable?

    init(repository: FitnessRepository) {
        self.repository = repository
        // 排序偏好持久化到本地 AppPreferences，重启后恢复（页面 26）。
        self.sort = ProfileSettings.exerciseSort
        // 初始化阶段对 @Published 赋值不会触发 didSet，派生结果仍是空数组。
        // 这里显式算一次，保证对象一出生状态就是自洽的（此时 allExercises 为空，
        // 重算代价为零，只是把空态摆正）。
        rebuildDerived()
        bindSearch()
    }

    // MARK: - 排序

    /// 切换排序并持久化到本地。只影响显示顺序，不修改动作数据本身。
    func setSort(_ order: ExerciseSortOrder) {
        sort = order
        ProfileSettings.exerciseSort = order
    }

    /// 「最近使用」是否有数据，用于无数据时回退默认顺序并提示。
    var hasRecentUsageData: Bool { !recentExercises.isEmpty }

    /// 「最近收藏」是否有数据。
    var hasRecentFavoriteData: Bool {
        allExercises.contains { $0.favoritedAt != nil }
    }

    /// 当前排序是否因无数据而回退到默认顺序（页面 26 的顶部提示）。
    var isSortFallback: Bool {
        switch sort {
        case .recentlyUsed: return !hasRecentUsageData
        case .recentlyFavorited: return !hasRecentFavoriteData
        default: return false
        }
    }

    /// 搜索防抖。150ms 内的连续输入只触发最后一条。
    private func bindSearch() {
        searchCancellable = $searchText
            .removeDuplicates()
            .debounce(for: .seconds(Self.searchDebounce), scheduler: RunLoop.main)
            .sink { [weak self] text in
                self?.debouncedKeyword = text
            }
    }

    // MARK: - 加载

    func load() async {
        loadState = .loading
        do {
            // 首次启动导入动作库；失败不阻断页面，界面会走空状态
            _ = try? repository.seedExerciseLibraryIfNeeded()

            // 页面需要能操作隐藏项（取消隐藏），所以取全量
            let items = try repository.fetchExercises(includeHidden: true)
            recentExercises = try repository.fetchRecentExercises(limit: Self.recentLimit)
            allExercises = items
            rebuildDerived()
            loadState = .loaded
        } catch {
            loadState = .failed(Self.message(for: error))
        }
    }

    func refresh() async {
        await load()
    }

    // MARK: - 派生结果的重算

    /// 按当前输入重算全部派生结果。
    ///
    /// 设计要点：
    /// 1. 输入指纹（DerivedKey）不变则直接返回 —— 视图层重复触发也不付代价。
    /// 2. 全部字段在同一次调用里算完，只发一轮 objectWillChange，
    ///    避免逐个 @Published 赋值造成多次刷新。
    /// 3. 无筛选、无关键词、默认排序时直接复用 allExercises 的顺序，
    ///    不做任何排序（defaultOrder 本来就等价于原顺序）。
    private func rebuildDerived() {
        let key = DerivedKey(
            dataVersion: dataVersion,
            keyword: debouncedKeyword,
            filter: filter,
            sort: sort,
            recentIDs: recentExercises.map(\.id)
        )
        guard key != derivedKey else { return }
        derivedKey = key

        let all = allExercises

        // --- 结果列表 ---
        let computed = ExerciseSearch.apply(
            to: all,
            keyword: debouncedKeyword,
            filter: filter,
            sort: sort,
            recentRank: ExerciseSearch.recentRank(of: recentExercises)
        )

        // --- 计数与清单，一次遍历同时算完 ---
        var hidden = 0
        var custom = 0
        var favorite = 0
        var counts: [String: Int] = [:]
        var equipmentCounter: [String: Int] = [:]
        var anyLocalMedia = false

        for item in all {
            if item.isHidden { hidden += 1 } else {
                counts[item.categoryZh, default: 0] += 1
            }
            if item.isCustom { custom += 1 }
            if item.isFavorite { favorite += 1 }
            if !item.equipmentText.isEmpty {
                equipmentCounter[item.equipmentText, default: 0] += 1
            }
        }

        // 署名只关心结果集里有没有真媒体
        anyLocalMedia = computed.contains { $0.hasLocalMedia }

        let categories = MuscleIconGroup.allCases
            .map(\.title)
            .filter { ($0 != "其他") && (counts[$0] ?? 0) > 0 }

        let equipments = equipmentCounter
            .sorted { lhs, rhs in
                lhs.value != rhs.value ? lhs.value > rhs.value : lhs.key < rhs.key
            }
            .map(\.key)

        // 一次性写回。@Published 的 willSet 会合并成一次刷新。
        results = computed
        muscleCounts = counts
        muscleCategories = categories
        availableEquipments = equipments
        hiddenCount = hidden
        customCount = custom
        favoriteCount = favorite
        hasLocalMediaInResults = anyLocalMedia
    }

    /// 全量替换动作数据并重算。所有写入 allExercises 的路径都应走这里。
    private func replaceAllExercises(_ items: [ExerciseLibraryItem]) {
        allExercises = items
        recentExercises = (try? repository.fetchRecentExercises(limit: Self.recentLimit))
            ?? recentExercises
        rebuildDerived()
    }

    /// 搜索框是否处于生效状态（用于展示清除按钮）
    var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// 关键词是否已被防抖提交。未提交时列表仍是上一次的结果。
    var isDebouncePending: Bool {
        searchText.trimmingCharacters(in: .whitespaces) != debouncedKeyword
    }

    /// 结果为空时的提示语。区分「无匹配」与「库本身为空」。
    var emptyMessage: String {
        if isSearching {
            return "没有找到匹配「\(debouncedKeyword)」的动作。"
        }
        if filter.isAnyActive {
            return "当前筛选条件下没有动作。"
        }
        return "动作库还是空的。可以新建一个自定义动作，或检查内置数据是否随包分发。"
    }

    // MARK: - 交互

    func setMuscleCategory(_ category: String?) {
        // 整体赋值而非改字段：@Published 结构体字段的就地修改不会触发 didSet，
        // 派生结果就不知道要重算。
        var next = filter
        next.muscleCategory = category
        filter = next
    }

    /// 从动作详情页点肌群标签跳回来时应用筛选。
    /// 顺序很重要：先清搜索关键词，再按肌群筛选，否则会落进「关键词 + 肌群」的空结果。
    /// 同时把高级筛选重置，避免旧条件叠加成空列表让用户以为筛选坏了。
    func applyMuscleFilterFromDetail(_ muscle: String) {
        clearSearch()
        var next = ExerciseFilter.none
        next.muscleCategory = muscle
        next.includeHidden = filter.includeHidden
        filter = next
        sort = .defaultOrder
    }

    /// 详情页或弹窗里改过数据后重新拉取，避免列表显示过期状态
    func reloadAfterExternalChange() {
        let items = (try? repository.fetchExercises(includeHidden: true)) ?? allExercises
        replaceAllExercises(items)
    }

    func clearSearch() {
        searchText = ""
        debouncedKeyword = ""
    }

    /// 清空全部筛选与搜索
    func resetAll() {
        filter = ExerciseFilter(
            muscleCategory: nil,
            muscleGroups: [],
            equipments: [],
            difficulty: nil,
            source: .all,
            onlyFavorite: false,
            includeHidden: filter.includeHidden
        )
        clearSearch()
    }

    /// 切换收藏
    func toggleFavorite(_ item: ExerciseLibraryItem) {
        do {
            let newValue = try repository.toggleFavorite(exerciseID: item.id)
            applyPatch(id: item.id) { $0.isFavorite = newValue }
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    /// 切换隐藏。隐藏后该条目会从列表消失，需在高级筛选里勾选「包含已隐藏」才能再看到。
    func toggleHidden(_ item: ExerciseLibraryItem) {
        do {
            let newValue = try repository.toggleHidden(exerciseID: item.id)
            applyPatch(id: item.id) { $0.isHidden = newValue }
            // 刚被隐藏的条目要从最近使用里剔除
            recentExercises = try repository.fetchRecentExercises(limit: Self.recentLimit)
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    /// 删除自定义动作。官方导入动作会抛错，由仓储层拒绝。
    func deleteCustomExercise(_ item: ExerciseLibraryItem) {
        guard item.isCustom else {
            errorMessage = "内置动作不能删除，可以改为收藏或隐藏。"
            return
        }
        do {
            try repository.deleteExercise(id: item.id)
            allExercises.removeAll { $0.id == item.id }
            recentExercises = try repository.fetchRecentExercises(limit: Self.recentLimit)
            rebuildDerived()
        } catch {
            errorMessage = Self.message(for: error)
        }
    }
    /// 新增或更新一条自定义动作，成功后刷新内存副本
    func upsertCustomExercise(_ item: ExerciseLibraryItem) {
        do {
            try repository.save(exercise: item)
            if let index = allExercises.firstIndex(where: { $0.id == item.id }) {
                allExercises[index] = item
            } else {
                allExercises.append(item)
            }
            rebuildDerived()
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    /// 记录一次使用，用于「最近使用」区
    func recordUsage(_ item: ExerciseLibraryItem) {
        do {
            try repository.recordExerciseUsage(id: item.id)
            recentExercises = try repository.fetchRecentExercises(limit: Self.recentLimit)
            // 最近使用会影响 .recentlyUsed 排序与结果集，需重算
            rebuildDerived()
        } catch {
            // 记录失败不影响主流程，静默处理
        }
    }

    // MARK: - 内部

    /// 就地修改内存中的某条动作，避免为了一个布尔值重新读全量数据
    private func applyPatch(id: String, _ change: (inout ExerciseLibraryItem) -> Void) {
        guard let index = allExercises.firstIndex(where: { $0.id == id }) else { return }
        change(&allExercises[index])
        // 收藏 / 隐藏状态直接参与筛选与计数，就地改完必须重算
        rebuildDerived()
    }

    private static func message(for error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return "操作失败：\(error.localizedDescription)"
    }
}
