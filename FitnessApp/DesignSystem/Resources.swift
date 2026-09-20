//
//  Resources.swift
//  资源常量：动作库种子文件与媒体署名。
//

import Foundation

enum AppResources {

    /// 动作库种子数据文件名
    static let exerciseSeedFileName = "exerciseLibrary.seed"
    static let exerciseSeedFileExtension = "json"

    /// 动作媒体版权署名。按数据集许可要求，展示动作图片或动画时必须同时展示。
    /// 来源：exercises-dataset（数据结构 MIT），媒体版权归 Gym visual。
    static let exerciseMediaAttribution = "© Gym visual — https://gymvisual.com/"
    static let exerciseDataSourceNote = "动作数据结构来自 exercises-dataset（MIT），媒体版权归 Gym visual。"

    /// App 自己的显示名（页面 13 底部版本信息用）。
    /// 不是原 App 名，也不出现任何第三方品牌。
    static let appName = "本地健身"

    /// App 版本号，来自 Info.plist 的 `CFBundleShortVersionString`。
    /// 导出备份时写入 `appVersion` 字段，供将来做版本兼容判断。
    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    /// 本地数据库（JSON 集合）的版本号。与 `WorkoutBackup.currentVersion` 同一口径。
    static let databaseVersion = "1"

    /// 动作库种子数据的版本号。
    static let exerciseLibraryVersion = "1.0"
}

// MARK: - 单位与格式化

enum FormatterKit {
    private static let chineseLocale = Locale(identifier: "zh_CN")

    /// 「9月19日 星期六」
    static func fullDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = chineseLocale
        f.dateFormat = "M月d日 EEEE"
        return f.string(from: date)
    }

    /// 「9月19日」
    static func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = chineseLocale
        f.dateFormat = "M月d日"
        return f.string(from: date)
    }

    /// 「2026年9月」
    static func monthTitle(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = chineseLocale
        f.dateFormat = "yyyy年M月"
        return f.string(from: date)
    }

    /// 「9/19」，统计图表的横轴刻度用。
    ///
    /// 与 `shortDate`（「9月19日」）的区别：横轴一格只有十几个点宽，
    /// 「9月19日」会被截断成省略号，「9/19」才放得下且仍然可读。
    static func monthDaySlash(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = chineseLocale
        f.dateFormat = "M/d"
        return f.string(from: date)
    }

    /// 「9/19 – 9/25」，按周聚合时横轴或详情里的区间文案
    static func dateRangeSlash(_ start: Date, _ end: Date) -> String {
        "\(monthDaySlash(start)) – \(monthDaySlash(end))"
    }

    /// 「9月19日 星期六」，供日历日期格的无障碍标签使用。
    ///
    /// 与 `fullDate` 的区别：这个不含年份。日历里已经有月份标题给出年月，
    /// 每格再念一遍年份会让 VoiceOver 的朗读变得冗长。
    static func monthDayWeekday(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = chineseLocale
        f.dateFormat = "M月d日 EEEE"
        return f.string(from: date)
    }

    /// 时长。不足一小时显示分钟，超过显示小时加分钟。
    static func duration(seconds: Int) -> String {
        let totalMinutes = max(0, seconds) / 60
        if totalMinutes < 60 { return "\(totalMinutes) 分钟" }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return minutes == 0 ? "\(hours) 小时" : "\(hours) 小时 \(minutes) 分"
    }

    /// 训练容量，保留整数
    static func volume(_ value: Double) -> String {
        "容量 \(Int(value.rounded())) kg"
    }

    /// 里程
    static func distance(meters: Double) -> String {
        String(format: "%.2f 公里", meters / 1000)
    }

    /// 重量。自重动作不显示单位。
    static func weight(_ value: Double) -> String {
        value <= 0 ? "自重" : (value == value.rounded()
            ? "\(Int(value)) kg"
            : String(format: "%.1f kg", value))
    }

    /// 组间休息。「90 秒」/「1 分 30 秒」/「2 分」
    static func rest(seconds: Int) -> String {
        let total = max(0, seconds)
        guard total >= 60 else { return "\(total) 秒" }
        let minutes = total / 60
        let remainder = total % 60
        return remainder == 0 ? "\(minutes) 分" : "\(minutes) 分 \(remainder) 秒"
    }

    /// 秒表格式「12:34」，超过一小时显示「1:02:03」。
    /// 顶部训练计时器与休息倒计时都用它，保证两处数字宽度节奏一致。
    static func stopwatch(seconds: Int) -> String {
        let total = max(0, seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }

    /// 千卡。保留整数。
    static func kilocalories(_ value: Double) -> String {
        "\(Int(max(0, value).rounded())) 千卡"
    }

    /// 训练总结统计卡片用的纯数字，不带单位。容量与距离分开读更清楚。
    static func plainNumber(_ value: Double) -> String {
        "\(Int(max(0, value).rounded()))"
    }

    /// 平均配速。有氧训练的「每公里用时」。
    /// - Parameters:
    ///   - seconds: 训练总时长（秒）
    ///   - meters: 总距离（米）
    /// - Returns: 形如「5'30"」；距离不足 100 米或时长非正时返回「—」，
    ///   避免除零放大误差后出现 0'00" 这类无意义读数。
    static func pace(seconds: Int, meters: Double) -> String {
        guard meters >= 100, seconds > 0 else { return "—" }
        let secondsPerKm = Double(seconds) / (meters / 1000)
        // 配速只在有意义时保留秒；超过 99 分钟按分钟兜底，避免格式溢出。
        guard secondsPerKm < 99 * 60 else { return "—" }
        let total = Int(secondsPerKm.rounded())
        return "\(total / 60)'\(String(format: "%02d", total % 60))\""
    }
}
