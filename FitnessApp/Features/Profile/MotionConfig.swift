//
//  MotionConfig.swift
//  页面 44：统一动画配置。
//
//  全 App 通过这一个入口判断「是否减少动画」，避免每个页面各自读
//  UIAccessibility / UserDefaults。减少动画时禁用动效、数字直接显示最终值。
//

import SwiftUI

enum MotionConfig {

    /// 当前是否应减少动画。
    /// - `.alwaysReduced`：恒减少；
    /// - `.normal`：恒正常动画；
    /// - `.followSystem`：读系统「减少动态效果」无障碍开关。
    static var isReduced: Bool {
        ProfileSettings.motionPreference.isReduced(systemReduceMotion: UIAccessibility.isReduceMotionEnabled)
    }

    /// 统一动画入口。减少动画时返回 nil（即 `.animation(nil)` 禁用动效），
    /// 否则返回传入的标准动画。
    static func animation(_ standard: Animation) -> Animation? {
        isReduced ? nil : standard
    }

    /// 淡入动画：正常时 220ms 淡入，减少时立即切换（nil）。
    static var fade: Animation? { animation(DS.Motion.tabSwitch) }
}
