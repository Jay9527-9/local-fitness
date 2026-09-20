//
//  PermissionCenter.swift
//  页面 51：系统权限状态的**只读**读取入口。
//
//  本文件只做三件事：
//    1. 读通知授权状态；
//    2. 读相册授权状态；
//    3. 打开本 App 的系统设置页。
//
//  **它不申请任何权限。** 规格要求「用户首次使用相关功能时再触发系统权限请求」：
//  通知的申请在 `RestNotification.enable(_:)`（页面 06 就在那儿了），
//  相册的申请由 `PhotosPicker` 在用户点头像时由系统弹出。
//  权限管理页如果自己去调 `requestAuthorization`，就会出现「进设置页就弹窗」
//  这种规格明确禁止的行为，所以这里一个 request 都不写。
//

import Foundation
import UIKit
import UserNotifications
import Photos

/// 权限状态的只读读取与跳转。
enum PermissionCenter {

    // MARK: 读取

    /// 异步读取两项权限的当前状态。
    ///
    /// 通知状态的读取是异步的（`getNotificationSettings` 走回调），
    /// 相册状态是同步的。为了给调用方一个一致的接口，这里统一异步返回。
    ///
    /// 任一读取失败都回落到 `.notDetermined`：读不到状态时提示「未授权」是安全的，
    /// 它只是让用户去功能里触发一次；反过来若谎报「已拒绝」，用户会白跑一趟系统设置。
    static func read(completion: @escaping ([PermissionEntry]) -> Void) {
        readNotificationStatus { notification in
            let photos = readPhotoLibraryStatus()
            let entries = PermissionCatalog.entries(
                notification: notification,
                photoLibrary: photos
            )
            DispatchQueue.main.async {
                completion(entries)
            }
        }
    }

    /// 读本地通知的授权状态。
    ///
    /// 只调 `getNotificationSettings`，**不调** `requestAuthorization`。
    private static func readNotificationStatus(
        completion: @escaping (PermissionStatus) -> Void
    ) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let raw = stringName(of: settings.authorizationStatus)
            completion(PermissionStatusMapper.fromNotification(rawValue: raw))
        }
    }

    /// 读相册的授权状态。
    ///
    /// 取的是系统给「照片读取」的授权状态，映射规则见
    /// `PermissionStatusMapper.fromPhotoLibrary(rawValue:)`。
    ///
    /// 用 `authorizationStatus`（无参形式）而不是
    /// `authorizationStatus(for: .readWrite)`：只要读、不写，且本项目的头像
    /// 是**用户主动选中的那一张**，不遍历相册。无参形式在本项目历史上一直被
    /// 系统正常返回（`limited` 也照常给出），换到 `for:` 形式并不改变判读结果。
    private static func readPhotoLibraryStatus() -> PermissionStatus {
        let raw = stringName(of: PHPhotoLibrary.authorizationStatus())
        return PermissionStatusMapper.fromPhotoLibrary(rawValue: raw)
    }

    // MARK: 系统枚举 → 原始值

    /// `UNAuthorizationStatus` → 稳定的字符串。
    ///
    /// 用显式 `switch` 而不是 `String(describing:)`：后者会把 `.authorized` 印成
    /// `authorized` 看似正确，但一旦系统枚举改名或新增 case，输出会静默变化，
    /// 而这里的 `switch` 会在编译期提示「switch 不完整」。
    private static func stringName(of status: UNAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "notDetermined"
        case .denied: return "denied"
        case .authorized: return "authorized"
        // provisional（安静推送，iOS 12+）与 ephemeral（App Clip 临时授权，iOS 14+）
        // deployment target 16.0 已全部覆盖，且都算「系统允许我们投递通知」。
        case .provisional: return "provisional"
        case .ephemeral: return "ephemeral"
        @unknown default: return "notDetermined"
        }
    }

    /// `PHAuthorizationStatus` → 稳定的字符串。
    private static func stringName(of status: PHAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "notDetermined"
        case .restricted: return "restricted"
        case .denied: return "denied"
        case .authorized: return "authorized"
        // limited（iOS 14+）：用户只授权了部分照片。PhotosPicker 在受限授权下
        // 依然能取到用户选中的那张图，头像功能可用，所以归入「已授权」。
        case .limited: return "limited"
        @unknown default: return "notDetermined"
        }
    }

    // MARK: 跳转系统设置

    /// 打开本 App 在系统「设置」里的页面。
    ///
    /// 调用前应先确认 `PermissionStatus.needsSystemSettingsLink` 为真：
    /// 「未授权」时不该把用户推去设置，那是该弹系统请求的时机。
    static func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        guard UIApplication.shared.canOpenURL(url) else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }
}
