//
//  CardioSetup.swift
//  新建有氧训练的纯值层（页面 30）。
//
//  不 import SwiftUI：运动类型、目标类型、校验与目标文案都是纯值。
//  默认不使用 GPS、健康平台、蓝牙或网络，全部为手动录入。
//

import Foundation

// MARK: - 运动类型

enum CardioSport: String, CaseIterable, Identifiable {
    case run
    case walk
    case cycle
    case row
    case elliptical
    case jumpRope
    case swim
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .run: return "跑步"
        case .walk: return "步行"
        case .cycle: return "骑行"
        case .row: return "划船"
        case .elliptical: return "椭圆机"
        case .jumpRope: return "跳绳"
        case .swim: return "游泳"
        case .other: return "其他"
        }
    }
}

// MARK: - 目标类型

enum CardioGoalKind: String, CaseIterable, Identifiable {
    case free
    case duration
    case distance
    case calories

    var id: String { rawValue }

    var title: String {
        switch self {
        case .free: return "自由训练"
        case .duration: return "目标时长"
        case .distance: return "目标距离"
        case .calories: return "目标热量"
        }
    }

    /// 目标值的单位文案，自由训练无单位。
    var unitText: String {
        switch self {
        case .free: return ""
        case .duration: return "分钟"
        case .distance: return "公里"
        case .calories: return "千卡"
        }
    }

    /// 自由训练不要求目标值。
    var requiresGoalValue: Bool { self != .free }
}

// MARK: - 有氧训练设置

struct CardioSetup: Equatable {
    var name: String
    var sport: CardioSport
    var goalKind: CardioGoalKind
    var goalValue: Double?
    var note: String?
    var saveAsTemplate: Bool

    init(
        name: String = "",
        sport: CardioSport = .run,
        goalKind: CardioGoalKind = .free,
        goalValue: Double? = nil,
        note: String? = nil,
        saveAsTemplate: Bool = false
    ) {
        self.name = name
        self.sport = sport
        self.goalKind = goalKind
        self.goalValue = goalValue
        self.note = note
        self.saveAsTemplate = saveAsTemplate
    }
}

// MARK: - 校验

enum CardioSetupValidation {

    static let nameMaxLength = 50

    /// 规范化训练名称：去首尾空白，截断到 50 字。
    static func normalizedName(_ raw: String) -> String {
        String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(nameMaxLength))
    }

    /// 校验结果。nil 表示通过。
    static func validationError(_ setup: CardioSetup) -> String? {
        if normalizedName(setup.name).isEmpty {
            return "请填写训练名称。"
        }
        if setup.goalKind.requiresGoalValue {
            guard let value = setup.goalValue, value > 0 else {
                return "请填写目标\(setup.goalKind.unitText)数值。"
            }
        }
        return nil
    }

    /// 目标摘要，用于训练名旁展示或写入备注。自由训练返回 nil。
    static func goalSummary(_ setup: CardioSetup) -> String? {
        guard setup.goalKind.requiresGoalValue,
              let value = setup.goalValue, value > 0 else { return nil }
        let formatted = value == value.rounded() ? "\(Int(value))" : String(format: "%.1f", value)
        return "\(setup.goalKind.title)：\(formatted)\(setup.goalKind.unitText)"
    }

    /// 由设置拼出落盘备注：目标摘要 + 用户备注（可选）。
    static func composedNote(_ setup: CardioSetup) -> String? {
        var parts: [String] = []
        if let summary = goalSummary(setup) { parts.append(summary) }
        let trimmed = (setup.note ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { parts.append(trimmed) }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }
}
