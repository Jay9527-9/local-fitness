//
//  LocalDataBackup.swift
//  页面 18：本地数据的完整备份（训练记录 / 计划 / 身体数据 / 个人资料）。
//
//  与 `WorkoutBackup` 的分工：那个只导出训练记录（页面 10 的边界）；
//  这个是「本地数据管理」页面的全量备份，范围由备份配置页勾选。
//  同样不含 SwiftUI，可被 Python 照搬推演。
//

import Foundation

// MARK: - 备份结构

/// 本地数据备份文件的结构。
struct LocalDataBackup: Codable, Equatable, Identifiable {
    var format: String
    var version: Int
    var exportedAt: Date
    var sessions: [WorkoutSession]
    var plans: [Plan]
    var measurements: [BodyMeasurement]
    var profile: UserProfile?

    /// 供 `.sheet(item:)` 使用的稳定标识。计算属性不参与编解码。
    var id: Date { exportedAt }

    static let currentVersion = 1
    static let formatIdentifier = "fitness-localdata-backup"
}

// MARK: - 备份范围

/// 备份可包含的数据范围。备份配置页据此勾选。
enum LocalDataBackupScope: String, CaseIterable, Identifiable {
    case sessions
    case plans
    case measurements
    case profile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sessions: return "训练记录"
        case .plans: return "训练计划"
        case .measurements: return "身体数据"
        case .profile: return "个人资料"
        }
    }

    var subtitle: String {
        switch self {
        case .sessions: return "已完成的训练记录与休息日标记"
        case .plans: return "自建与导入的训练计划"
        case .measurements: return "体重、体脂率与围度记录"
        case .profile: return "昵称、训练目标、说明与本地头像"
        }
    }
}

// MARK: - 导入结果

enum LocalDataBackupError: LocalizedError, Equatable {
    case emptyFile
    case notJSON
    case wrongFormat(found: String)
    case unsupportedVersion(found: Int)
    case noContent

    var errorDescription: String? {
        switch self {
        case .emptyFile:
            return "这个文件是空的，没有可导入的内容。"
        case .notJSON:
            return "这个文件不是有效的 JSON，可能不是本 App 导出的备份。"
        case .wrongFormat(let found):
            return found.isEmpty
                ? "这个文件缺少格式标识，可能不是本地数据备份。"
                : "这个文件的格式是「\(found)」，不是本地数据备份。"
        case .unsupportedVersion(let found):
            return "备份版本 \(found) 高于当前 App 支持的版本，请先升级 App。"
        case .noContent:
            return "备份里没有任何可导入的数据。"
        }
    }
}

// MARK: - 编解码

enum LocalDataBackupCoder {

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// 按范围构造备份。未勾选的范围对应字段为空 / nil。
    static func makeBackup(
        sessions: [WorkoutSession],
        plans: [Plan],
        measurements: [BodyMeasurement],
        profile: UserProfile?,
        scope: Set<LocalDataBackupScope>,
        exportedAt: Date = .now
    ) -> LocalDataBackup {
        // 只导出已完成的训练；进行中的草稿属于当前操作状态，不导出。
        let finished = sessions
            .filter { $0.isFinished }
            .sorted { $0.startedAt < $1.startedAt }

        return LocalDataBackup(
            format: LocalDataBackup.formatIdentifier,
            version: LocalDataBackup.currentVersion,
            exportedAt: exportedAt,
            sessions: scope.contains(.sessions) ? finished : [],
            plans: scope.contains(.plans) ? plans : [],
            measurements: scope.contains(.measurements) ? measurements : [],
            profile: scope.contains(.profile) ? profile : nil
        )
    }

    static func encode(_ backup: LocalDataBackup) throws -> Data {
        try encoder().encode(backup)
    }

    /// 解码并校验。顺序：空文件 → JSON → 格式标识 → 版本 → 有无内容。
    static func decode(_ data: Data) throws -> LocalDataBackup {
        guard !data.isEmpty else { throw LocalDataBackupError.emptyFile }

        let backup: LocalDataBackup
        do {
            backup = try decoder().decode(LocalDataBackup.self, from: data)
        } catch {
            if (try? JSONSerialization.jsonObject(with: data)) == nil {
                throw LocalDataBackupError.notJSON
            }
            let found = peekFormat(in: data) ?? ""
            throw LocalDataBackupError.wrongFormat(found: found)
        }

        guard backup.format == LocalDataBackup.formatIdentifier else {
            throw LocalDataBackupError.wrongFormat(found: backup.format)
        }
        guard backup.version <= LocalDataBackup.currentVersion else {
            throw LocalDataBackupError.unsupportedVersion(found: backup.version)
        }
        guard backup.hasContent else {
            throw LocalDataBackupError.noContent
        }
        return backup
    }

    private static func peekFormat(in data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object["format"] as? String
    }

    /// 备份文件名，如「本地数据备份-2026-09-19.json」
    static func fileName(for date: Date = .now) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return "本地数据备份-\(f.string(from: date)).json"
    }
}

// MARK: - 派生

extension LocalDataBackup {

    /// 是否至少含一类数据。
    var hasContent: Bool {
        !sessions.isEmpty || !plans.isEmpty || !measurements.isEmpty || profile != nil
    }

    /// 各范围条目数摘要，供预检页与结果提示使用。
    var countSummary: String {
        var parts: [String] = []
        if !sessions.isEmpty { parts.append("训练记录 \(sessions.count) 条") }
        if !plans.isEmpty { parts.append("计划 \(plans.count) 个") }
        if !measurements.isEmpty { parts.append("身体数据 \(measurements.count) 条") }
        if profile != nil { parts.append("个人资料") }
        return parts.isEmpty ? "无内容" : parts.joined(separator: "，")
    }
}

// MARK: - 存储占用文案

/// 估算存储占用的文案。纯函数，可被 Python 照搬推演。
enum StorageSize {

    static func format(_ bytes: Int64) -> String {
        if bytes < 1024 {
            return bytes <= 0 ? "不足 1 KB" : "\(bytes) B"
        }
        let kb = Double(bytes) / 1024
        if kb < 1024 {
            return String(format: "%.1f KB", kb)
        }
        let mb = kb / 1024
        return String(format: "%.1f MB", mb)
    }
}
