//
//  FavoriteExercisesViewModel.swift
//  页面 16：收藏动作的状态机。加载、搜索防抖、肌群筛选、排序、取消收藏与撤销。
//
//  数据只来自本地动作库的 `isFavorite` 状态；取消收藏即时落盘，
//  同时保留一条「撤销」记录，5 秒内可一键恢复。
//

import Foundation
import Combine

@MainActor
final class FavoriteExercisesViewModel: ObservableObject {

    // MARK: - 状态

    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    @Published private(set) var loadState: LoadState = .loading

    /// 全量动作（含隐藏条目）。收藏列表由它按 `isFavorite` 推导。
    @Published private(set) var allExercises: [ExerciseLibraryItem] = []
    /// 动作 id → 最近使用名次（0 最新），用于「最近使用」排序。
    @Published private(set) var recentRank: [String: Int] = [:]

    /// 搜索框文案。变化后 150ms 才真正生效。
    @Published var searchText: String = ""
    @Published private(set) var debouncedKeyword: String = ""

    /// 肌群大类筛选，nil 表示全部。
    @Published var muscleCategory: String? = nil
    @Published var sort: FavoriteSortOrder = .recentlyFavorited

    /// 待撤销的取消收藏条目。非 nil 时界面显示「已取消收藏 + 撤销」。
    @Published private(set) var undoItem: ExerciseLibraryItem?

    /// 操作失败提示，nil 表示不提示
    @Published var errorMessage: String?

    // MARK: - 配置

    private let repository: FitnessRepository
    private var searchCancellable: AnyCancellable?
    private var undoTask: Task<Void, Never>?

    /// 撤销窗口时长
    static let undoWindow: TimeInterval = 5

    init(repository: FitnessRepository) {
        self.repository = repository
        bindSearch()
    }

    private func bindSearch() {
        searchCancellable = $searchText
            .removeDuplicates()
            .debounce(for: .seconds(0.15), scheduler: RunLoop.main)
            .sink { [weak self] text in
                self?.debouncedKeyword = text
            }
    }

    // MARK: - 加载

    func load() async {
        loadState = .loading
        do {
            // 首次启动导入动作库；失败不阻断，界面走空状态
            _ = try? repository.seedExerciseLibraryIfNeeded()
            allExercises = try repository.fetchExercises(includeHidden: true)
            let recent = try repository.fetchRecentExercises(limit: 30)
            recentRank = ExerciseSearch.recentRank(of: recent)
            loadState = .loaded
        } catch {
            loadState = .failed(Self.message(for: error))
        }
    }

    // MARK: - 派生

    /// 收藏列表（只含 `isFavorite`）。含隐藏条目——收藏与否与隐藏与否是两回事。
    var favorites: [ExerciseLibraryItem] {
        allExercises.filter(\.isFavorite)
    }

    /// 当前筛选 + 排序下的结果列表
    var results: [ExerciseLibraryItem] {
        FavoriteExercisesFilter.apply(
            to: favorites,
            keyword: debouncedKeyword,
            muscleCategory: muscleCategory,
            sort: sort,
            recentRank: recentRank
        )
    }

    var favoriteCount: Int { favorites.count }

    /// 「全部」之外应展示的肌群 Chip，只显示收藏里真实存在的分组。
    var muscleCategories: [String] {
        let counts = FavoriteExercisesFilter.muscleCounts(in: favorites)
        return MuscleIconGroup.allCases
            .map(\.title)
            .filter { $0 != "其他" && (counts[$0] ?? 0) > 0 }
    }

    var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// 是否有检索 / 筛选条件生效（区别于「库本身没有收藏」）
    var hasActiveCondition: Bool {
        isSearching || muscleCategory != nil
    }

    // MARK: - 交互

    func setMuscleCategory(_ category: String?) {
        // 再点一次同一分组 = 取消该筛选
        muscleCategory = (muscleCategory == category) ? nil : category
    }

    func clearSearch() {
        searchText = ""
        debouncedKeyword = ""
    }

    func resetAll() {
        clearSearch()
        muscleCategory = nil
    }

    /// 取消收藏：即时持久化，并把该条放进撤销队列。
    func unfavorite(_ item: ExerciseLibraryItem) {
        do {
            let newValue = try repository.toggleFavorite(exerciseID: item.id)
            applyFavoritePatch(id: item.id, value: newValue)
            if !newValue {
                presentUndo(for: item)
            }
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    /// 撤销上一次取消收藏：重新收藏。
    func undoUnfavorite() {
        guard let item = undoItem else { return }
        do {
            let newValue = try repository.toggleFavorite(exerciseID: item.id)
            applyFavoritePatch(id: item.id, value: newValue)
        } catch {
            errorMessage = Self.message(for: error)
        }
        undoItem = nil
        undoTask?.cancel()
    }

    /// 详情页 / 编辑器里可能改过收藏或最近使用，回来时刷新。
    func reloadAfterExternalChange() {
        allExercises = (try? repository.fetchExercises(includeHidden: true)) ?? allExercises
        let recent = (try? repository.fetchRecentExercises(limit: 30)) ?? []
        recentRank = ExerciseSearch.recentRank(of: recent)
    }

    // MARK: - 内部

    /// 就地更新内存中某条动作的收藏状态与收藏时间，避免为一次点击重新读全量。
    private func applyFavoritePatch(id: String, value: Bool) {
        guard let index = allExercises.firstIndex(where: { $0.id == id }) else { return }
        allExercises[index].isFavorite = value
        allExercises[index].favoritedAt = value ? Date() : nil
    }

    private func presentUndo(for item: ExerciseLibraryItem) {
        undoItem = item
        undoTask?.cancel()
        undoTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.undoWindow * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.undoItem = nil
        }
    }

    private static func message(for error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return "操作失败：\(error.localizedDescription)"
    }
}
