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

    /// 取一条动作的动画图。命中缓存直接返回；未命中则读盘解码。
    /// 调用方应在异步上下文里调用，不要放进 body 求值路径。
    ///
    /// 关键：必须用 `UIImage(contentsOfFile:)` 而非 `UIImage(data:)`。
    /// 系统图像解码器只有在「按文件路径解码」时才会把 GIF 的**多帧**回填到
    /// `UIImage.images`；`UIImage(data:)` 在很多系统版本上只拿到首帧。
    /// 拿不到多帧，`GifImageView` 也就无从逐帧循环 —— 这正是之前
    /// 「动作 GIF 不动」的根因之一。
    static func animationImage(for item: ExerciseLibraryItem) -> UIImage? {
        guard let url = animationURL(for: item) else { return nil }

        let key = url.path as NSString
        if let cached = animationCache.object(forKey: key) { return cached }

        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
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
                // GIF 必须走 UIKit 的 UIImageView 才能逐帧播放：
                // SwiftUI 的 `Image(uiImage:)` 只会画出 GIF 的**首帧**，
                // 不会循环动画（这是之前「动作 GIF 不动」的根因）。
                GifImageView(image: image, isPlaying: isPlaying)
                    .opacity(isPlaying ? 1 : 0.55)
            } else if didAttemptLoad {
                fallback
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(aspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .contentShape(Rectangle())
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

// MARK: - GIF 渲染

/// 用 UIKit 的 `UIImageView` 渲染**动画** GIF。
///
/// 为什么不能用 SwiftUI 的 `Image(uiImage:)`：
/// SwiftUI 的 `Image` 只把 `UIImage` 当作单帧位图绘制，**不会**逐帧循环播放
/// 动画。即便 `UIImage` 本身携带了多帧（GIF），`Image(uiImage:)` 仍只显示首帧。
/// 只有 `UIImageView` 在拿到「多帧 UIImage」时会自动循环播放，因此 GIF 的播放
/// 必须走 UIKit —— 这是 `ExerciseAnimationView` 之前「动作 GIF 不动」的根因。
///
/// 暂停语义：调用方把 `isPlaying` 置 false 时停止动画，停在首帧（UIImageView
/// 的 `stopAnimating` 行为）；再次播放从首帧重新开始，符合演示类动画的预期。
struct GifImageView: UIViewRepresentable {

    let image: UIImage
    let isPlaying: Bool

    func makeUIView(context: Context) -> UIImageView {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.backgroundColor = .clear
        return imageView
    }

    func updateUIView(_ uiView: UIImageView, context: Context) {
        // 多帧（动画）图才需要 start/stop；静态图直接显示即可。
        uiView.image = image
        if image.images != nil {
            if isPlaying {
                uiView.startAnimating()
            } else {
                uiView.stopAnimating()
            }
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
