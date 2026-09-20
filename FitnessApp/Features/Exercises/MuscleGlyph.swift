//
//  MuscleGlyph.swift
//  代码生成的肌群占位图标。
//
//  为什么要有这个：动作媒体来自第三方数据源，其版权归 Gym visual。
//  若媒体未随包分发，或用户不想展示来源不明的素材，就用这里**纯代码绘制**的
//  几何图形占位 —— 不引用任何第三方插画、Logo 或图标字体。
//
//  每个肌群分组画一组不同的体块，靠形状和位置区分部位，不靠文字。
//

import SwiftUI

// MARK: - 图标本体

struct MuscleGlyph: View {

    let group: MuscleIconGroup
    /// 图标放在多大的方形区域内
    var size: CGFloat = 52
    /// 底色
    var background: Color = DS.Palette.surfaceElevated
    /// 图形颜色
    var tint: Color = DS.Palette.textSecondary
    /// 高亮色，用于标出该肌群的关键体块
    var highlight: Color = DS.Palette.accent

    var body: some View {
        ZStack {
            background

            Canvas { context, canvasSize in
                draw(in: &context, size: canvasSize)
            }
            // 图形本身对无障碍隐藏，语义由外层 accessibilityLabel 承担
            .accessibilityHidden(true)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                .stroke(DS.Palette.stroke, lineWidth: 1)
        )
    }

    // MARK: 绘制

    /// 所有坐标都按 0…1 归一化再乘画布尺寸，保证任意尺寸下比例一致。
    private func draw(in context: inout GraphicsContext, size canvas: CGSize) {
        let w = canvas.width
        let h = canvas.height

        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: x * w, y: y * h)
        }
        func rect(_ x: CGFloat, _ y: CGFloat, _ rw: CGFloat, _ rh: CGFloat) -> CGRect {
            CGRect(x: x * w, y: y * h, width: rw * w, height: rh * h)
        }
        func capsule(_ x: CGFloat, _ y: CGFloat, _ rw: CGFloat, _ rh: CGFloat, _ color: Color) {
            context.fill(
                Path(roundedRect: rect(x, y, rw, rh), cornerRadius: min(rw, rh) * w * 0.5),
                with: .color(color)
            )
        }
        func bar(_ x: CGFloat, _ y: CGFloat, _ rw: CGFloat, _ rh: CGFloat, _ color: Color) {
            context.fill(
                Path(roundedRect: rect(x, y, rw, rh), cornerRadius: min(rw, rh) * w * 0.35),
                with: .color(color)
            )
        }
        func dot(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ color: Color) {
            let radius = r * w
            let center = pt(x, y)
            context.fill(
                Path(ellipseIn: CGRect(
                    x: center.x - radius, y: center.y - radius,
                    width: radius * 2, height: radius * 2
                )),
                with: .color(color)
            )
        }
        func polygon(_ points: [(CGFloat, CGFloat)], _ color: Color) {
            var path = Path()
            guard let first = points.first else { return }
            path.move(to: pt(first.0, first.1))
            for p in points.dropFirst() { path.addLine(to: pt(p.0, p.1)) }
            path.closeSubpath()
            context.fill(path, with: .color(color))
        }

        let dim = tint.opacity(0.55)
        let bright = highlight

        switch group {
        case .chest:
            // 躯干 + 两块胸大肌
            bar(0.38, 0.16, 0.24, 0.68, dim)
            capsule(0.30, 0.28, 0.19, 0.20, bright)
            capsule(0.51, 0.28, 0.19, 0.20, bright)

        case .back:
            // 宽背轮廓 + 中间脊柱
            polygon([(0.50, 0.16), (0.80, 0.30), (0.74, 0.60), (0.50, 0.72), (0.26, 0.60), (0.20, 0.30)], dim)
            bar(0.48, 0.24, 0.04, 0.40, bright)

        case .shoulder:
            // 双肩圆顶
            dot(0.30, 0.32, 0.11, bright)
            dot(0.70, 0.32, 0.11, bright)
            bar(0.44, 0.32, 0.12, 0.40, dim)

        case .arm:
            // 上臂下臂折叠
            capsule(0.26, 0.24, 0.16, 0.34, bright)
            capsule(0.40, 0.46, 0.16, 0.32, dim)
            dot(0.62, 0.26, 0.07, dim)

        case .core:
            // 腹直肌分节 + 两侧腹斜肌
            bar(0.42, 0.20, 0.16, 0.60, bright)
            bar(0.44, 0.30, 0.12, 0.02, background)
            bar(0.44, 0.42, 0.12, 0.02, background)
            bar(0.44, 0.54, 0.12, 0.02, background)
            capsule(0.28, 0.28, 0.10, 0.34, dim)
            capsule(0.62, 0.28, 0.10, 0.34, dim)

        case .leg:
            // 大腿 + 小腿 + 膝
            capsule(0.28, 0.20, 0.20, 0.34, bright)
            dot(0.38, 0.57, 0.06, dim)
            capsule(0.30, 0.62, 0.16, 0.28, dim)

        case .glute:
            // 臀部两个体块
            dot(0.38, 0.46, 0.15, bright)
            dot(0.62, 0.46, 0.15, bright)
            bar(0.34, 0.22, 0.32, 0.14, dim)

        case .calf:
            // 小腿肚 + 跟腱
            capsule(0.38, 0.22, 0.24, 0.36, bright)
            bar(0.46, 0.60, 0.08, 0.22, dim)

        case .cardio:
            // 折线心率 + 两段血管
            var line = Path()
            line.move(to: pt(0.16, 0.52))
            line.addLine(to: pt(0.32, 0.52))
            line.addLine(to: pt(0.40, 0.30))
            line.addLine(to: pt(0.50, 0.70))
            line.addLine(to: pt(0.58, 0.44))
            line.addLine(to: pt(0.84, 0.44))
            context.stroke(line, with: .color(bright), style: StrokeStyle(lineWidth: w * 0.06, lineCap: .round, lineJoin: .round))

        case .neck:
            // 颈部两侧 + 肩线
            bar(0.42, 0.22, 0.16, 0.26, bright)
            bar(0.22, 0.50, 0.56, 0.06, dim)

        case .other:
            // 通用哑铃轮廓
            bar(0.24, 0.30, 0.06, 0.40, dim)
            bar(0.70, 0.30, 0.06, 0.40, dim)
            bar(0.22, 0.45, 0.56, 0.10, bright)
        }
    }
}

// MARK: - 动作行左侧的缩略图

/// 动作行左侧的 52×52 视觉块。
/// 优先用随包分发的本地缩略图；媒体缺失时回退到代码绘制的肌群图标。
struct ExerciseThumbnail: View {

    let item: ExerciseLibraryItem
    var size: CGFloat = 52

    var body: some View {
        Group {
            if let image = localImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                            .stroke(DS.Palette.stroke, lineWidth: 1)
                    )
            } else {
                MuscleGlyph(
                    group: MuscleIconGroup.of(muscle: item.primaryMuscleText),
                    size: size
                )
            }
        }
        .accessibilityHidden(true)
    }

    /// 从本地 Bundle 读取缩略图。读不到就返回 nil，交给占位图。
    private var localImage: UIImage? {
        guard let url = ExerciseMedia.thumbnailURL(for: item) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
}

// MARK: - 预览

#Preview("肌群占位图") {
    ScrollView {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 76), spacing: DS.Spacing.item)],
            spacing: DS.Spacing.item
        ) {
            ForEach(MuscleIconGroup.allCases, id: \.self) { group in
                VStack(spacing: 6) {
                    MuscleGlyph(group: group, size: 64)
                    Text(group.title)
                        .font(DS.Typography.caption2)
                        .foregroundStyle(DS.Palette.textSecondary)
                }
            }
        }
        .padding(DS.Spacing.page)
    }
    .background(DS.Palette.bg)
    .preferredColorScheme(.dark)
}
