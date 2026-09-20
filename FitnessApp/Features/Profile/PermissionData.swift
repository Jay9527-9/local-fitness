//
//  PermissionData.swift
//  页面 51：权限管理的值层。
//
//  本文件**不 import SwiftUI，也不 import UserNotifications / Photos**：
//  它只描述「权限有哪几种、有哪几种状态、每种状态怎么显示」，
//  与系统框架打交道的活全部留给 `PermissionCenter`。
//  这样这一层就能被 Python 逐行照搬做值语义推演（四层门禁的第 4 层）。
//
//  规格要点（页面 51）：
//  - 本 App 实际只用两个系统权限：本地通知、相册访问。
//  - 不申请定位、通讯录、蓝牙、麦克风、健康数据或网络权限。
//  - 四种状态：未授权 / 已授权 / 已拒绝 / 受限制。
//  - 页面只反映系统权限状态，不上传权限信息，不含第三方登录或隐私追踪选项。
//

import Foundation

// MARK: - 权限种类

/// 本 App 会用到的系统权限。
///
/// **刻意只有两个 case。** 这是本页最重要的约束：枚举里没有定位、通讯录、
/// 蓝牙、麦克风、健康数据，因此界面不可能多出一行「健康数据」——
/// 「不申请其它权限」这条规格由类型系统兜住，而不是靠文案声明。
enum PermissionKind: String, CaseIterable, Identifiable, Equatable {
    /// 本地通知：仅用于后台的组间休息结束提醒。
    case localNotification
    /// 相册访问：仅用于挑选一张本地头像。
    case photoLibrary

    var id: String { rawValue }

    /// 设置页里的标题。
    var title: String {
        switch self {
        case .localNotification: return "本地通知"
        case .photoLibrary: return "相册访问"
        }
    }

    /// 一行功能说明，写清「用来做什么」。
    var purpose: String {
        switch self {
        case .localNotification:
            return "用于 App 不在前台时，提醒你组间休息已经结束。"
        case .photoLibrary:
            return "仅用于从相册挑选一张照片作为本地头像。"
        }
    }

    /// 权限被拒绝后会影响什么、不影响什么。
    var fallbackNote: String {
        switch self {
        case .localNotification:
            return "不开通知也能正常训练：前台的休息倒计时、提示音与触感都不受影响。"
        case .photoLibrary:
            return "不给相册权限也能正常使用：头像会使用代码绘制的默认样式（昵称首字母）。"
        }
    }

    /// 列表行左侧的 SF Symbol。
    var symbol: String {
        switch self {
        case .localNotification: return "bell.badge"
        case .photoLibrary: return "photo.on.rectangle"
        }
    }
}

// MARK: - 权限状态

/// 系统权限的四种状态。
///
/// 与 `UNAuthorizationStatus` / 相册授权状态一一对应，但用我们自己的四个 case
/// 收口：系统的枚举还含 `.provisional`、`.ephemeral`、`.limited` 等细分，
/// 界面上只展示规格点名的四种，映射关系集中在 `init(systemValue:)` 一处，
/// 避免「同一个状态在标题、颜色、副标题里被各判一次」而判出分歧。
enum PermissionStatus: String, CaseIterable, Identifiable, Equatable {
    /// 还没有问过用户，系统也没弹过窗。
    case notDetermined
    /// 用户已授权。
    case authorized
    /// 用户明确拒绝过（系统不会再弹窗，只能去系统设置里改）。
    case denied
    /// 被系统策略限制（家长控制、MDM 描述文件等），用户自己改不了。
    case restricted

    var id: String { rawValue }

    /// 状态徽章上的短文案。
    var title: String {
        switch self {
        case .notDetermined: return "未授权"
        case .authorized: return "已授权"
        case .denied: return "已拒绝"
        case .restricted: return "受限制"
        }
    }

    /// 状态徽章下的一句解释，说明这个状态意味着什么。
    var detail: String {
        switch self {
        case .notDetermined:
            return "首次使用相关功能时才会弹系统请求。"
        case .authorized:
            return "功能已可用。可随时在系统设置里关闭。"
        case .denied:
            return "系统不会再自动弹窗，需要到系统设置里手动打开。"
        case .restricted:
            return "受系统策略限制，本机无法修改该权限。"
        }
    }

    /// 是否应该显示「前往系统设置」按钮。
    ///
    /// - 未授权：**不显示**。此时该由 App 在用户首次使用功能时触发系统弹窗，
    ///   而不是把用户推去设置里自己找。这是规格里「首次触发时再请求」的落点。
    /// - 已授权：不显示。已经打开了，没有可去设置里改的必要（要关也是用户
    ///   自己去系统设置，App 不提供「去关掉」的引导）。
    /// - 已拒绝：显示。系统不再弹窗，只能引导。
    /// - 受限制：显示。虽然用户大概率改不了，但至少让他知道去哪个页面看。
    var needsSystemSettingsLink: Bool {
        switch self {
        case .notDetermined, .authorized: return false
        case .denied, .restricted: return true
        }
    }

    /// 是否算「此权限已就绪」。只有已授权算就绪。
    var isGranted: Bool { self == .authorized }
}

// MARK: - 系统状态 → 本页状态

/// 把系统侧的授权值（字符串或整数）归一成本页的四种状态。
///
/// 值层不 import UserNotifications / Photos，所以这里收的是**原始值**而不是
/// 系统枚举：`PermissionCenter` 负责把 `UNAuthorizationStatus` / 相册状态
/// 转成字符串再喂进来。这样这层能被 Python 照搬，也避免了在值层里
/// 对系统枚举写 `default:` 兜底（那会把将来新增的系统 case 静默吞掉）。
enum PermissionStatusMapper {

    /// 通知授权状态的原始值。对应 `UNAuthorizationStatus`：
    /// notDetermined / denied / authorized / provisional / ephemeral。
    ///
    /// - `provisional`（安静推送）与 `ephemeral`（App Clip 临时授权）都**算已授权**：
    ///   两者系统都允许我们投递通知，只是展示方式不同。判成「未授权」会让
    ///   用户在设置里看到「未授权」，而实际上提醒是能收到的——那种不一致更糟。
    /// - 未知取值一律落到 `notDetermined`，宁可提示用户去功能里触发一次，
    ///   也不要凭空说「已拒绝」（会让用户白跑一趟系统设置）。
    static func fromNotification(rawValue: String) -> PermissionStatus {
        switch rawValue {
        case "notDetermined": return .notDetermined
        case "denied": return .denied
        case "authorized": return .authorized
        case "provisional": return .authorized
        case "ephemeral": return .authorized
        default: return .notDetermined
        }
    }

    /// 相册授权状态的原始值。对应 `PHAuthorizationStatus`：
    /// notDetermined / restricted / denied / authorized / limited。
    ///
    /// - `limited`（用户只授权了部分照片）**算已授权**：PhotosPicker 在受限授权下
    ///   依然能取到用户选中的那张图，头像功能可用。判成未授权会让用户以为
    ///   功能坏了，而实际上只是可选范围小了一点。
    /// - `restricted` 单独保留：它是唯一用户自己改不了的状态，
    ///   界面上要给出不同的解释（受系统策略限制），不能和 denied 混为一谈。
    static func fromPhotoLibrary(rawValue: String) -> PermissionStatus {
        switch rawValue {
        case "notDetermined": return .notDetermined
        case "restricted": return .restricted
        case "denied": return .denied
        case "authorized": return .authorized
        case "limited": return .authorized
        default: return .notDetermined
        }
    }
}

// MARK: - 权限清单

/// 本页要展示的一条权限记录。
struct PermissionEntry: Identifiable, Equatable {
    let kind: PermissionKind
    let status: PermissionStatus

    var id: String { kind.rawValue }

    /// VoiceOver 一次读完这一行：名称 + 状态 + 用途。
    var accessibilityLabel: String {
        "\(kind.title)，\(status.title)。\(kind.purpose)"
    }
}

/// 页面 51 的静态文案与清单装配。
///
/// 全部是纯函数：给定两个状态，产出这一页要显示的全部数据。
/// 没有任何副作用，可以在 Python 里重放。
enum PermissionCatalog {

    /// 本页展示的权限顺序：通知在前（它影响训练过程中的提醒），相册在后。
    static let order: [PermissionKind] = [.localNotification, .photoLibrary]

    /// 按固定顺序装配清单。
    ///
    /// 顺序由 `order` 决定，不依赖字典遍历顺序——字典顺序在 Swift 里是不确定的，
    /// 界面上两行权限每次进来都换位置会让人以为点错了。
    static func entries(
        notification: PermissionStatus,
        photoLibrary: PermissionStatus
    ) -> [PermissionEntry] {
        let map: [PermissionKind: PermissionStatus] = [
            .localNotification: notification,
            .photoLibrary: photoLibrary,
        ]
        return order.map { PermissionEntry(kind: $0, status: map[$0] ?? .notDetermined) }
    }

    /// 页首说明：本 App 申请哪些权限、不申请哪些权限。
    static let scopeNote = "本 App 只使用下面两项系统权限。不申请定位、通讯录、蓝牙、麦克风、健康数据或网络权限。"

    /// 页尾声明：权限信息不上传、不用于追踪。
    static let privacyNote = "本页只反映系统当前的权限状态，权限信息不会上传，也不用于任何形式的追踪。"

    /// 「不申请的网络权限」这句话需要有人兜底说明：本 App 完全离线。
    static let offlineNote = "App 完全离线运行，不联网、无账号、无第三方登录。"

    /// 汇总文案：两项里已有几项可用。
    ///
    /// 拒绝权限不影响核心功能，所以措辞刻意避开「缺少权限」这类报警口吻，
    /// 只陈述事实。
    ///
    /// **「两项」这个词不写死，而是用 `total` 拼出来。** 目前调用方恒传 2 项，
    /// 写死「两项」看起来也没错——但这是个潜伏缺陷：一旦将来新增第三项权限
    /// （例如「健康数据」），文案会继续说「两项权限均已授权」，而界面明明有三行。
    /// 第 4 层推演脚本正是拿一个单项清单把这个坑试出来的。
    /// 空清单返回空串，避免出现「0 项中的 0 项」这种废话。
    static func availabilitySummary(_ entries: [PermissionEntry]) -> String {
        let total = entries.count
        guard total > 0 else { return "" }
        let granted = entries.filter { $0.status.isGranted }.count
        if granted == total { return "\(total) 项权限均已授权。" }
        if granted == 0 { return "\(total) 项权限都未开启，核心功能不受影响。" }
        return "\(total) 项权限中的 \(granted) 项已授权。"
    }

    /// 是否有任意一项处于「用户改不了」的受限制状态。
    ///
    /// 有的话页尾要多一句说明，否则用户会一直点「前往系统设置」却找不到开关。
    static func hasRestricted(_ entries: [PermissionEntry]) -> Bool {
        entries.contains { $0.status == .restricted }
    }
}
