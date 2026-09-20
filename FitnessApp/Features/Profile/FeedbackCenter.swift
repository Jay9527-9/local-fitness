//
//  FeedbackCenter.swift
//  页面 43：声音与触感的统一触发中心。
//
//  只使用 App 包内系统提示音（AudioToolbox 系统音），不请求网络、不下载音频。
//  所有触发先经 `FeedbackPolicy` 判定总开关 + 子开关 + 设备支持。
//

import UIKit
import AudioToolbox

/// 可触发的声音类别。
enum FeedbackSoundKind {
    case restEnd
    case lastTen
    case setComplete

    /// 对应的细分开关。
    var subEnabled: Bool {
        switch self {
        case .restEnd: return ProfileSettings.soundRestEnd
        case .lastTen: return ProfileSettings.soundLastTen
        case .setComplete: return ProfileSettings.soundSetComplete
        }
    }

    /// 系统音 ID。全部来自 iOS 内置系统音，无第三方音频。
    var systemSoundID: SystemSoundID {
        switch self {
        case .restEnd: return 1057
        case .lastTen: return 1105
        case .setComplete: return 1057
        }
    }
}

/// 可触发的触感类别。
enum FeedbackHapticKind {
    case setComplete
    case restEnd
    case workoutComplete

    var subEnabled: Bool {
        switch self {
        case .setComplete: return ProfileSettings.hapticSetComplete
        case .restEnd: return ProfileSettings.hapticRestEnd
        case .workoutComplete: return ProfileSettings.hapticWorkoutComplete
        }
    }

    /// 触感强度样式。用 UIKit 反馈生成器，兼容 iOS 16。
    var style: UIImpactFeedbackGenerator.FeedbackStyle {
        switch self {
        case .setComplete: return .medium
        case .restEnd: return .light
        case .workoutComplete: return .heavy
        }
    }
}

/// 声音与触感的统一触发入口。
enum FeedbackCenter {

    /// 设备是否支持触感。iOS 16 目标设备均支持；保留能力探测路径。
    static var hapticsAvailable: Bool {
        NSClassFromString("UIImpactFeedbackGenerator") != nil
    }

    /// 播放某类声音。总提示音关闭或对应子开关关闭时静默跳过。
    static func play(_ sound: FeedbackSoundKind) {
        guard FeedbackPolicy.shouldPlaySound(
            master: ProfileSettings.soundEnabled,
            sub: sound.subEnabled
        ) else { return }
        AudioServicesPlaySystemSound(sound.systemSoundID)
    }

    /// 触发某类触感。总触感 / 子开关 / 设备支持任一不满足即跳过。
    static func trigger(_ haptic: FeedbackHapticKind) {
        guard FeedbackPolicy.shouldTriggerHaptic(
            master: ProfileSettings.hapticsEnabled,
            sub: haptic.subEnabled,
            available: hapticsAvailable
        ) else { return }
        let generator = UIImpactFeedbackGenerator(style: haptic.style)
        generator.prepare()
        generator.impactOccurred()
    }
}
