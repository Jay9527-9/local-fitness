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
    @Published private(set) var allExercises: [ExerciseLibraryItem] = []
    /// 最近使用，最多 6 条。为空时页面不渲染该区。
    @Published private(set) var recentExercises: [ExerciseLibraryItem] = []

    /// 搜索框文案。变化后 150ms 才真正生效。
    @Published var searchText: String = ""
    /// 防抖生效后的关键词，用于实际检索。
    @Published private(set) var debouncedKeyword: String = ""

    @Published var filter: ExerciseFilter = .none
    @Published var sort: ExerciseSortOrder

    /// 删除失败等操作的提示文案，nil 表示不提示
    @Published var errorMessage: String?

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
            allExercises = try repository.fetchExercises(includeHidden: true)
            recentExercises = try repository.fetchRecentExercises(limit: Self.recentLimit)
            loadState = .loaded
        } catch {
            loadState = .failed(Self.message(for: error))
        }
    }

    func refresh() async {
        await load()
    }

    // MARK: - 派生结果

    /// 当前筛选条件下的结果列表。
    /// 隐藏条目是否出现完全由 `filter.includeHidden` 决定，默认不展示。
    var results: [ExerciseLibraryItem] {
        ExerciseSearch.apply(
            to: allExercises,
            keyword: debouncedKeyword,
            filter: filter,
            sort: sort,
            recentRank: ExerciseSearch.recentRank(of: recentExercises)
        )
    }

    /// 隐藏条目数量，用于高级筛选里提示
    var hiddenCount: Int {
        allExercises.filter(\.isHidden).count
    }

    /// 自定义动作数量
    var customCount: Int {
        allExercises.filter(\.isCustom).count
    }

    /// 收藏数量
    var favoriteCount: Int {
        allExercises.filter(\.isFavorite).count
    }

    /// 各肌群的动作数，用于 Chip 角标
    var muscleCounts: [String: Int] {
        ExerciseSearch.muscleCounts(in: allExercises)
    }

    /// 可用的器械清单，由数据推导而非硬编码
    var availableEquipments: [String] {
        ExerciseSearch.availableEquipments(in: allExercises)
    }

    /// 「全部」之外应展示的肌群 Chip。
    /// 固定顺序便于形成肌肉记忆，且只显示数据里真实存在的分组。
    var muscleCategories: [String] {
        let counts = muscleCounts
        return MuscleIconGroup.allCases
            .map(\.title)
            .filter { ($0 != "其他") && (counts[$0] ?? 0) > 0 }
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
        filter.muscleCategory = category
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
        allExercises = (try? repository.fetchExercises(includeHidden: true)) ?? allExercises
        recentExercises = (try? repository.fetchRecentExercises(limit: Self.recentLimit))
            ?? recentExercises
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
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    /// 记录一次使用，用于「最近使用」区
    func recordUsage(_ item: ExerciseLibraryItem) {
        do {
            try repository.recordExerciseUsage(id: item.id)
            recentExercises = try repository.fetchRecentExercises(limit: Self.recentLimit)
        } catch {
            // 记录失败不影响主流程，静默处理
        }
    }

    // MARK: - 内部

    /// 就地修改内存中的某条动作，避免为了一个布尔值重新读全量数据
    private func applyPatch(id: String, _ change: (inout ExerciseLibraryItem) -> Void) {
        guard let index = allExercises.firstIndex(where: { $0.id == id }) else { return }
        change(&allExercises[index])
    }

    private static func message(for error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return "操作失败：\(error.localizedDescription)"
    }
}
