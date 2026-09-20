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
    static var isMediaBundled: Bool {
        Bundle.main.url(
            forResource: "0001-2gPfomN",
            withExtension: "jpg",
            subdirectory: "\(mediaDirectory)/images"
        ) != nil
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

    var body: some View {
        ZStack {
            DS.Palette.surfaceElevated

            if let url = ExerciseMedia.animationURL(for: item),
               let data = try? Data(contentsOf: url),
               let image = UIImage(data: data) {
                // SwiftUI 的 Image 会自动播放 GIF 首帧以外的动画帧
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .opacity(isPlaying ? 1 : 0.55)
            } else {
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
