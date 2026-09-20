//
//  ExerciseMedia.swift
//  动作媒体解析与展示。
//
//  媒体版权声明（必须随媒体一同展示）：
//  © Gym visual — https://gymvisual.com/
//  数据来源：exercises-dataset（数据结构 MIT），媒体归 Gym visual 所有。
//

import SwiftUI

// MARK: - 媒体解析

enum ExerciseMedia {

    /// 打包进 App 的媒体目录名
    static let mediaDirectory = "ExerciseMedia"

    /// 把种子数据中的相对路径解析为 Bundle 内的真实路径
    /// 种子里的形式是 `images/0001-2gPfomN.jpg` 与 `videos/0001-2gPfomN.gif`
    static func url(for relativePath: String) -> URL? {
        guard !relativePath.isEmpty else { return nil }

        let parts = relativePath.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }

        let folder = parts[0]                       // images / videos
        let file = parts[1]                         // 0001-2gPfomN.jpg
        let name = (file as NSString).deletingPathExtension
        let ext = (file as NSString).pathExtension

        return Bundle.main.url(
            forResource: name,
            withExtension: ext,
            subdirectory: "\(mediaDirectory)/\(folder)"
        )
    }

    /// 静态缩略图
    static func thumbnailURL(for item: ExerciseLibraryItem) -> URL? {
        url(for: item.image)
    }

    /// 动画
    static func animationURL(for item: ExerciseLibraryItem) -> URL? {
        url(for: item.gifURL)
    }

    /// 媒体是否随包分发。未打包时界面回退为图标占位，不显示破图。
    /// 结果缓存一次 —— 这个判断在每行动画视图里都会被读，重复查 Bundle 无意义。
    private static let mediaBundledFlag: Bool = {
        Bundle.main.url(
            forResource: "0001-2gPfomN",
            withExtension: "jpg",
            subdirectory: "\(mediaDirectory)/images"
        ) != nil
    }()

    static var isMediaBundled: Bool { mediaBundledFlag }

    /// GIF 解码缓存。
    /// GIF 体积远大于缩略图（单条可达数百 KB），在 body 里同步
    /// `Data(contentsOf:)` + `UIImage(data:)` 会直接卡住主线程。
    /// 这里缓存解码结果，并配合异步加载避免阻塞渲染。
    private static let animationCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 12
        return cache
    }()

    /// 取一条动作的动画图。命中缓存直接返回；未命中则同步读盘解码。
    /// 调用方应在异步上下文里调用，不要放进 body 求值路径。
    static func animationImage(for item: ExerciseLibraryItem) -> UIImage? {
        guard let url = animationURL(for: item) else { return nil }

        let key = url.path as NSString
        if let cached = animationCache.object(forKey: key) { return cached }

        guard let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else { return nil }
        animationCache.setObject(image, forKey: key)
        return image
    }
}

// MARK: - 动作动画

/// 动作动画。使用打包进 App 的 GIF，支持播放与暂停。
/// 媒体未随包分发时，由调用方改用 MuscleGlyph 的代码绘制占位图。
struct ExerciseAnimationView: View {

    let item: ExerciseLibraryItem
    /// 是否自动播放
    var autoPlay: Bool = true
    /// 宽高比。列表页用 1:1，详情页用 16:9。
    var aspectRatio: CGFloat = 1

    @State private var isPlaying = true
    /// 解码后的动画帧。异步装载，避免在主线程读盘 + 解码 GIF。
    @State private var image: UIImage?
    /// 是否已尝试过加载。用于区分「还没加载完」与「确实没有素材」，
    /// 避免素材缺失时先闪一下占位图再闪回来。
    @State private var didAttemptLoad = false

    var body: some View {
        ZStack {
            DS.Palette.surfaceElevated

            if let image {
                // SwiftUI 的 Image 会自动播放 GIF 首帧以外的动画帧
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .opacity(isPlaying ? 1 : 0.55)
            } else if didAttemptLoad {
                fallback
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(aspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .onTapGesture {
            guard autoPlay else { return }
            withAnimation(DS.Motion.standard) { isPlaying.toggle() }
        }
        .task(id: item.gifURL) {
            // 放后台线程读盘解码，主线程只负责赋值。
            // 单条 GIF 可能数百 KB，同步解码会让详情页明显掉帧。
            let loaded = await Task.detached(priority: .userInitiated) {
                ExerciseMedia.animationImage(for: item)
            }.value
            image = loaded
            didAttemptLoad = true
        }
        .accessibilityElement()
        .accessibilityLabel("\(item.displayName) 动作动画")
        .accessibilityHint(isPlaying ? "双击暂停" : "双击播放")
    }

    private var fallback: some View {
        VStack(spacing: DS.Spacing.item) {
            MuscleGlyph(
                group: MuscleIconGroup.of(muscle: item.primaryMuscleText),
                size: 84,
                background: DS.Palette.surfaceElevated,
                tint: DS.Palette.textTertiary
            )
            Text("动画素材未随包分发")
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Palette.textTertiary)
        }
    }
}

// MARK: - 署名

/// 媒体署名。凡展示动作媒体处均须一并渲染。
struct MediaAttributionLabel: View {
    var body: some View {
        Text(AppResources.exerciseMediaAttribution)
            .font(DS.Typography.caption2)
            .foregroundStyle(DS.Palette.textTertiary)
            .accessibilityLabel("动作素材版权归 Gym visual 所有")
    }
}
