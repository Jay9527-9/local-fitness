//
//  ExerciseTaxonomy.swift
//  Corpus（拉丁文「语料库」，在此指虚构的本地动作语料库）
//  动作库的词表：肌群中文名、检索别名、肌群图标分组。
//
//  说明：词表是本项目为中文检索自行维护的映射表，不是从任何第三方 App 抄来的文案。
//  数据源的原始字段只有英文（target / muscleGroup / equipment），中文展示名由本表补齐。
//

import Foundation

// MARK: - 肌群中文名

enum MuscleName {

    /// 数据集 target 字段（主肌群）到中文名的映射。
    /// 覆盖数据集中实际出现的全部 19 个 target 值。
    private static let targetToChinese: [String: String] = [
        "abs": "腹直肌",
        "pectorals": "胸大肌",
        "biceps": "肱二头肌",
        "glutes": "臀大肌",
        "delts": "三角肌",
        "triceps": "肱三头肌",
        "upper back": "上背",
        "lats": "背阔肌",
        "calves": "小腿三头肌",
        "quads": "股四头肌",
        "forearms": "前臂",
        "cardiovascular system": "心肺",
        "hamstrings": "腘绳肌",
        "spine": "竖脊肌",
        "traps": "斜方肌",
        "adductors": "内收肌",
        "serratus anterior": "前锯肌",
        "abductors": "外展肌",
        "levator scapulae": "肩胛提肌",
    ]

    /// 数据集 muscleGroup / secondaryMuscles 字段里出现的肌群中文名。
    /// 覆盖数据集中实际出现的 40 个肌群标识。
    private static let groupToChinese: [String: String] = [
        "shoulders": "肩部",
        "forearms": "前臂",
        "biceps": "肱二头肌",
        "triceps": "肱三头肌",
        "hamstrings": "腘绳肌",
        "quadriceps": "股四头肌",
        "glutes": "臀部",
        "obliques": "腹斜肌",
        "hip flexors": "髋屈肌",
        "chest": "胸部",
        "trapezius": "斜方肌",
        "traps": "斜方肌",
        "deltoids": "三角肌",
        "calves": "小腿",
        "ankles": "踝关节",
        "core": "核心",
        "lower back": "下背",
        "upper back": "上背",
        "rotator cuff": "肩袖",
        "soleus": "比目鱼肌",
        "rhomboids": "菱形肌",
        "rear deltoids": "三角肌后束",
        "brachialis": "肱肌",
        "back": "背部",
        "feet": "足部",
        "latissimus dorsi": "背阔肌",
        "ankle stabilizers": "踝稳定肌群",
        "wrists": "腕部",
        "upper chest": "上胸",
        "wrist flexors": "腕屈肌",
        "abs": "腹直肌",
        "pectorals": "胸大肌",
        "lats": "背阔肌",
        "spine": "竖脊肌",
        "adductors": "内收肌",
        "abductors": "外展肌",
        "serratus anterior": "前锯肌",
        "levator scapulae": "肩胛提肌",
        "quads": "股四头肌",
        "cardiovascular system": "心肺",
    ]

    /// 主肌群中文名
    static func zh(for target: String) -> String {
        let key = target.lowercased().trimmingCharacters(in: .whitespaces)
        return targetToChinese[key] ?? target
    }

    /// 次级肌群中文名
    static func zhGroup(_ group: String) -> String {
        let key = group.lowercased().trimmingCharacters(in: .whitespaces)
        return groupToChinese[key] ?? group
    }

    /// 一组次级肌群的中文名，去重并保持原顺序
    static func zhGroups(_ groups: [String]) -> [String] {
        var seen = Set<String>()
        return groups.compactMap { group in
            let name = zhGroup(group)
            guard !name.isEmpty, !seen.contains(name) else { return nil }
            seen.insert(name)
            return name
        }
    }
}

// MARK: - 肌群图标分组

/// 占位图标按肌群分为若干形体组，每组画不同的代码图形。
/// 目的是让列表在没有媒体时仍能一眼区分部位，且完全不依赖任何第三方插画。
enum MuscleIconGroup: String, CaseIterable {
    case chest
    case back
    case shoulder
    case arm
    case core
    case leg
    case glute
    case calf
    case cardio
    case neck
    case other

    var title: String {
        switch self {
        case .chest: return "胸"
        case .back: return "背"
        case .shoulder: return "肩"
        case .arm: return "手臂"
        case .core: return "核心"
        case .leg: return "腿"
        case .glute: return "臀"
        case .calf: return "小腿"
        case .cardio: return "有氧"
        case .neck: return "颈"
        case .other: return "其他"
        }
    }

    /// 由动作的主肌群推导图标分组
    static func of(muscle: String) -> MuscleIconGroup {
        switch muscle.lowercased() {
        case "胸", "chest", "pectorals", "serratus anterior", "upper chest":
            return .chest
        case "背", "back", "lats", "latissimus dorsi", "upper back", "lower back",
             "rhomboids", "spine", "traps", "trapezius":
            return .back
        case "肩", "shoulders", "delts", "deltoids", "rear deltoids", "rotator cuff":
            return .shoulder
        case "手臂", "前臂", "arm", "biceps", "triceps", "forearms", "brachialis",
             "wrist flexors", "wrists":
            return .arm
        case "核心", "core", "abs", "obliques", "hip flexors":
            return .core
        case "臀", "臀大肌", "glutes":
            return .glute
        case "小腿", "calves", "soleus":
            return .calf
        case "腿", "leg", "quads", "quadriceps", "hamstrings", "adductors",
             "abductors", "ankles", "ankle stabilizers", "feet":
            return .leg
        case "有氧", "cardiovascular system":
            return .cardio
        case "颈", "neck", "levator scapulae":
            return .neck
        default:
            return .other
        }
    }
}

// MARK: - 检索别名

/// 中文口语别名 → 数据源英文词 的映射。
/// 数据源的名称是英文（如 "barbell bench press"），但用户会用中文搜「卧推」。
/// 本表把常见中文说法挂到对应条目上，使中文检索可用。
/// 这是本项目自行维护的检索词表，与任何第三方 App 的文案无关。
enum ExerciseAliases {

    /// 关键词 → 命中该词即追加的别名。匹配对象为动作的英文名称（小写）。
    private static let rules: [(match: [String], aliases: [String])] = [
        // 胸
        (["bench press"], ["卧推", "平板卧推"]),
        (["incline", "bench press"], ["上斜卧推"]),
        (["decline", "bench press"], ["下斜卧推"]),
        (["chest press"], ["坐姿推胸"]),
        (["push-up", "push up"], ["俯卧撑"]),
        (["fly", "chest"], ["飞鸟", "夹胸"]),
        (["pec deck"], ["蝴蝶机夹胸"]),
        (["dip"], ["双杠臂屈伸"]),
        (["pullover"], ["仰卧上拉"]),
        (["cable crossover"], ["绳索夹胸", "绳索交叉"]),

        // 背
        (["pull-up", "pull up", "chin-up", "chin up"], ["引体向上"]),
        (["lat pulldown", "pulldown"], ["高位下拉", "下拉"]),
        (["row"], ["划船"]),
        (["deadlift"], ["硬拉"]),
        (["shrug"], ["耸肩"]),
        (["face pull"], ["面拉"]),
        (["straight arm"], ["直臂下压"]),
        (["hyperextension"], ["山羊挺身", "背屈伸"]),
        (["rack pull"], ["架上硬拉"]),

        // 肩
        (["shoulder press", "overhead press", "military press"], ["肩推", "推举", "实力举"]),
        (["lateral raise"], ["侧平举", "侧举"]),
        (["front raise"], ["前平举"]),
        (["rear delt", "reverse fly"], ["后束飞鸟", "反向飞鸟"]),
        (["upright row"], ["直立划船"]),
        (["arnold"], ["阿诺德推举"]),
        (["raise"], ["平举"]),

        // 手臂
        (["curl"], ["弯举"]),
        (["hammer curl"], ["锤式弯举"]),
        (["preacher"], ["牧师凳"]),
        (["concentration"], ["集中弯举"]),
        (["pushdown"], ["下压", "臂屈伸"]),
        (["skull crusher", "lying triceps"], ["仰卧臂屈伸", "碎颅者"]),
        (["kickback"], ["臂后伸"]),
        (["extension", "triceps"], ["臂屈伸"]),
        (["wrist curl"], ["腕弯举"]),
        (["reverse curl"], ["反握弯举"]),

        // 核心
        (["crunch"], ["卷腹"]),
        (["sit-up", "sit up"], ["仰卧起坐"]),
        (["plank"], ["平板支撑"]),
        (["leg raise"], ["举腿"]),
        (["russian twist"], ["俄罗斯转体", "转体"]),
        (["ab wheel", "wheel roller"], ["健腹轮"]),
        (["side bend"], ["体侧屈"]),
        (["hanging"], ["悬垂"]),
        (["dead bug"], ["死虫式"]),
        (["mountain climber"], ["登山跑"]),
        (["bicycle"], ["自行车卷腹"]),
        (["v-up", "v up"], ["V字卷腹"]),

        // 腿
        (["squat"], ["深蹲"]),
        (["front squat"], ["前蹲", "颈前深蹲"]),
        (["lunge"], ["弓步", "箭步蹲"]),
        (["leg press"], ["腿举"]),
        (["leg extension"], ["腿屈伸"]),
        (["leg curl"], ["腿弯举"]),
        (["step-up", "step up"], ["登阶"]),
        (["hip thrust"], ["臀推"]),
        (["romanian", "rdl"], ["罗马尼亚硬拉"]),
        (["good morning"], ["早安式"]),
        (["hack squat"], ["哈克深蹲"]),
        (["split squat"], ["分腿蹲"]),
        (["hip abduction"], ["髋外展"]),
        (["hip adduction"], ["髋内收"]),

        // 小腿
        (["calf raise", "calf press"], ["提踵"]),
        (["calf"], ["小腿"]),

        // 有氧
        (["run", "running", "treadmill"], ["跑步", "跑步机"]),
        (["walk", "walking"], ["快走", "步行"]),
        (["bike", "cycling", "bicycle"], ["单车", "骑行"]),
        (["elliptical"], ["椭圆机"]),
        (["rower", "rowing machine"], ["划船机"]),
        (["jump rope", "skipping"], ["跳绳"]),
        (["stair", "stepmill"], ["爬楼", "台阶机"]),
        (["burpee"], ["波比跳"]),
        (["jumping jack"], ["开合跳"]),
        (["skierg"], ["滑雪机"]),
        (["sled"], ["雪橇"]),

        // 器械与动作形态的补充别名
        (["cable"], ["绳索"]),
        (["barbell"], ["杠铃"]),
        (["dumbbell"], ["哑铃"]),
        (["kettlebell"], ["壶铃"]),
        (["smith"], ["史密斯"]),
        (["machine"], ["器械"]),
        (["band"], ["弹力带"]),
        (["seated"], ["坐姿"]),
        (["standing"], ["站姿"]),
        (["lying"], ["仰卧"]),
        (["kneeling"], ["跪姿"]),
        (["single leg", "one leg"], ["单腿"]),
        (["close grip", "close-grip"], ["窄距"]),
        (["wide grip", "wide-grip"], ["宽距"]),
        (["reverse grip", "reverse-grip"], ["反握"]),
        (["isometric"], ["等长"]),
        (["stretch"], ["拉伸"]),
    ]

    /// 为一条动作生成别名。
    /// 保留种子数据自带的别名，再按名称追加规则命中的中文说法。
    static func aliases(forName name: String, existing: [String] = []) -> [String] {
        let lowered = name.lowercased()
        var result = existing

        for rule in rules {
            guard rule.match.contains(where: { lowered.contains($0) }) else { continue }
            for alias in rule.aliases where !result.contains(alias) {
                result.append(alias)
            }
        }
        return result
    }

    /// 批量补齐种子数据缺失的别名
    static func enrich(_ items: [ExerciseLibraryItem]) -> [ExerciseLibraryItem] {
        items.map { item in
            var copy = item
            copy.aliases = aliases(forName: item.name, existing: item.aliases)
            if copy.primaryMuscle.isEmpty {
                copy.primaryMuscle = MuscleName.zh(for: item.target)
            }
            return copy
        }
    }
}

// MARK: - 中文字符判断

extension String {
    /// 是否含中文字符。用于判断别名里是否有可展示的中文说法。
    var containsHan: Bool {
        unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value)      // CJK 统一表意文字
                || (0x3400...0x4DBF).contains(scalar.value)  // 扩展 A
        }
    }
}
