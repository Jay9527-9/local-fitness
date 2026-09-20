//
//  PressableButtonStyle.swift
//  统一的按压反馈：按下缩放至 0.97，松开 180ms 弹性回弹。
//  使用 ButtonStyle 的 configuration.isPressed，不叠加手势，避免干扰点击取消与无障碍。
//

import SwiftUI

struct PressableButtonStyle: ButtonStyle {
    /// 按下时的缩放比例
    var pressedScale: CGFloat = 0.97
    /// 常态缩放，用于选中态等
    var normalScale: CGFloat = 1.0

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : normalScale)
            .animation(DS.Motion.buttonPress, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    /// 通用可按压样式
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
}
