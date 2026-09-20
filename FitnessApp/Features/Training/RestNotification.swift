//
//  RestNotification.swift
//  组间休息结束的本地通知。纯本地，不接任何推送服务。
//
//  设计前提（页面 06 规格）：
//  - **只在用户显式开启时**才申请权限。不在启动时弹窗，不打断第一次训练。
//  - 申请权限与发送通知都**不能影响倒计时**。权限被拒绝、系统出错、
//    用户在设置里关掉通知——任何一种情况下，倒计时都必须照常走到 0 并按原样
//    播放提示音与触感。所以这里所有返回值都是「尽力而为」，调用方不需要判断成败。
//  - 只在 App 不在前台时才有意义（在前台时用户已经能看到面板），
//    但这里不做前台判断——由系统决定是否展示，避免自己维护一套易错的活跃态。
//

import Foundation
import UIKit
import UserNotifications

/// 本地通知的开关与发送。开关状态存在 UserDefaults，是用户级偏好而非训练数据。
enum RestNotification {

    /// 用户是否已开启「休息结束提醒」
    private static let enabledKey = "fitness.restNotification.enabled"

    private static let requestIdentifier = "fitness.rest.finished"

    /// 是否已开启。默认关闭——需要用户主动打开。
    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// 申请权限并开启提醒。
    ///
    /// 返回是否最终拿到授权。**调用方不应据此改变倒计时行为**，
    /// 只用于决定要不要给用户一句提示（例如被拒绝时说明可以去系统设置里打开）。
    static func enable(_ completion: @escaping (Bool) -> Void) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                // 已经授权过，直接开
                DispatchQueue.main.async {
                    isEnabled = true
                    completion(true)
                }
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    DispatchQueue.main.async {
                        // 无论授权与否都记住用户的选择：
                        // 拒绝时把开关落回关闭，界面状态与系统状态保持一致。
                        isEnabled = granted
                        completion(granted)
                    }
                }
            default:
                // 用户此前明确拒绝过，系统不会再弹窗（iOS 不允许重复申请），
                // 只能引导去设置里手动打开。
                DispatchQueue.main.async {
                    isEnabled = false
                    completion(false)
                }
            }
        }
    }

    /// 关闭提醒，并撤掉已经排上队的通知
    static func disable() {
        isEnabled = false
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [requestIdentifier])
    }

    /// 休息结束时发一条本地通知。
    ///
    /// 只有在用户开启的情况下才发；失败一律静默——
    /// 倒计时本身的提示音和触感已经由 `WorkoutSessionViewModel` 负责，不依赖这里。
    static func notifyRestFinished(after seconds: TimeInterval, exerciseName: String) {
        guard isEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = "休息结束"
        content.body = exerciseName.isEmpty
            ? "开始下一组"
            : "「\(exerciseName)」休息结束，开始下一组"
        // 用系统默认提示音。App 包内没有也不引入第三方音频文件。
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(1, seconds),
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: requestIdentifier,
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request) { _ in
            // 静默：通知发不出去不影响倒计时，用户回到 App 依然能看到面板
        }
    }

    /// 撤掉尚未触发的休息通知（跳过休息、提前完成、或训练结束时调用）
    static func cancelPending() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [requestIdentifier])
    }
}
