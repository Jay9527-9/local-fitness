//
//  CardioSessionMath.swift
//  有氧训练执行页（页面 31）与总结页（页面 32）的纯值层。
//
//  不 import SwiftUI：目标解析、圆环进度、配速与速度换算都是纯函数，
//  可被 Python 照搬推演。所有数据只来自用户手动录入，不来自 GPS 或网络。
//

import Foundation

// MARK: - 目标解析

/// 从训练备注里解析有氧目标（新建页把目标写进 note 的「目标时长：30分钟」）。
/// 解析失败返回 nil，表示自由训练或无目标。
enum CardioGoalParser {

    /// 解析结果：目标类型 + 数值（时长分钟 / 距离公里 / 热量千卡）。
    static func parse(note: String?) -> (kind: CardioGoalKind, value: Double)? {
        guard let note, !note.isEmpty else { return nil }
        for kind in [CardioGoalKind.duration, .distance, .calories] {
            let prefix = "\(kind.title)："
            guard let range = note.range(of: prefix) else { continue }
            let rest = note[range.upperBound...]
            // 取到数字结束为止（允许小数）
            let digits = rest.prefix { $0.isNumber || $0 == "." }
            guard let value = Double(digits), value > 0 else { continue }
            return (kind, value)
        }
        return nil
    }
}

// MARK: - 圆环进度

enum CardioRingProgress {

    /// 计算圆环进度（0…1），无目标时返回 nil（自由训练只显示已进行时长）。
    /// - Parameters:
    ///   - goalKind: 目标类型
    ///   - goalValue: 目标数值（时长分钟 / 距离公里 / 热量千卡）
    ///   - elapsedSeconds: 已进行秒数
    ///   - distanceMeters: 已累计距离
    ///   - kilocalories: 已累计热量
    static func progress(
        goalKind: CardioGoalKind,
        goalValue: Double,
        elapsedSeconds: Int,
        distanceMeters: Double,
        kilocalories: Double
    ) -> Double? {
        guard goalKind != .free, goalValue > 0 else { return nil }
        switch goalKind {
        case .free:
            return nil
        case .duration:
            let targetSeconds = goalValue * 60
            guard targetSeconds > 0 else { return nil }
            return min(1, Double(elapsedSeconds) / targetSeconds)
        case .distance:
            let targetMeters = goalValue * 1000
            guard targetMeters > 0 else { return nil }
            return min(1, distanceMeters / targetMeters)
        case .calories:
            return min(1, kilocalories / goalValue)
        }
    }
}

// MARK: - 配速 / 速度

enum CardioPace {

    /// 配速展示（秒/公里），如「5′30″/公里」；数据不足返回 nil。
    static func paceText(secondsPerKm: Double?) -> String? {
        guard let seconds = secondsPerKm, seconds > 0, seconds.isFinite else { return nil }
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return "\(minutes)′\(String(format: "%02d", secs))″/公里"
    }

    /// 由距离与时长推导平均配速（秒/公里）；距离或时长为 0 时返回 nil。
    static func pace(fromDistanceMeters meters: Double, elapsedSeconds: Int) -> Double? {
        guard meters > 0, elapsedSeconds > 0 else { return nil }
        return Double(elapsedSeconds) / (meters / 1000)
    }

    /// 由距离与时长推导平均速度（公里/小时）；返回 nil 表示数据不足。
    static func speedKmPerHour(fromDistanceMeters meters: Double, elapsedSeconds: Int) -> Double? {
        guard meters > 0, elapsedSeconds > 0 else { return nil }
        let hours = Double(elapsedSeconds) / 3600
        guard hours > 0 else { return nil }
        return (meters / 1000) / hours
    }
}
