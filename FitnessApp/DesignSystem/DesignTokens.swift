//
//  DesignTokens.swift
//  设计令牌：深色炭黑底 + 白色文字 + 单一荧光绿强调色
//
//  说明：#C6FF3E 是本项目自选的独立强调色，并非从任何第三方 App 提取的原始色值。
//

import SwiftUI

enum DS {

    // MARK: - 色彩

    enum Palette {
        /// 页面底色，炭黑
        static let bg = Color(hex: 0x0B0B0C)
        /// 卡片表面
        static let surface = Color(hex: 0x151517)
        /// 次级表面 / 按钮常态
        static let surfaceElevated = Color(hex: 0x1E1E21)
        /// 分割线与描边
        static let stroke = Color.white.opacity(0.08)
        /// 主文字
        static let textPrimary = Color.white
        /// 次要文字
        static let textSecondary = Color.white.opacity(0.58)
        /// 三级文字 / 占位
        static let textTertiary = Color.white.opacity(0.34)
        /// 唯一主强调色，荧光绿
        static let accent = Color(hex: 0xC6FF3E)
        /// 荧光绿之上的文字色
        static let onAccent = Color(hex: 0x0B0B0C)
        /// 危险操作
        static let danger = Color(hex: 0xFF4D4F)
        /// 警示色（页面 50 数据恢复）。黄，用于「数据异常」非致命提示。
        static let warning = Color(hex: 0xFFC53D)
        /// 骨架屏扫光
        static let shimmer = Color.white.opacity(0.07)
        /// 未完成的圆形勾选框描边，低对比灰
        static let checkboxIdle = Color.white.opacity(0.22)
        /// 热身组标签底色，刻意压低对比度以区别于正式组
        static let warmupFill = Color.white.opacity(0.06)
        /// 输入型数值控件的底色
        static let fieldFill = Color.white.opacity(0.06)
        /// 有氧训练标识色，蓝绿。
        ///
        /// 这是本项目在荧光绿之外引入的**唯一**第二种语义色，只用于区分训练类型
        /// （日历标记点、类型标签）。它不是主强调色，任何主按钮、选中态仍用 accent。
        /// 之所以必须新增：规格要求同一天的力量与有氧用不同颜色并列显示，
        /// 单靠荧光绿的深浅在深色底上无法分辨。
        static let cardio = Color(hex: 0x3ED8C6)
        /// 休息日标记灰。比 textTertiary 略亮，保证在炭黑底上仍可见。
        static let restMarker = Color.white.opacity(0.42)
        /// 频率柱状图里力量柱的颜色。
        ///
        /// 按规格「力量训练与有氧训练使用不同但低饱和的颜色」，
        /// 这里刻意不用荧光绿 —— 荧光绿在本项目里是「当前选中」的语义，
        /// 若柱子默认就是荧光绿，选中态就没有可辨识的变化了。
        /// 力量柱取灰绿，与有氧的蓝绿在色相上区分、在明度上接近。
        static let statsStrengthBar = Color(hex: 0x6E8A5A)
        /// 频率柱状图里被选中那一根的突出色
        static let statsSelectedBar = Color(hex: 0xC6FF3E)
        /// 图表网格线与坐标轴
        static let statsGrid = Color.white.opacity(0.10)
        /// 容量折线
        static let statsVolumeLine = Color(hex: 0x8FB56A)
        /// 容量折线下的渐变填充起始色（向上渐隐）
        static let statsVolumeFill = Color(hex: 0x8FB56A).opacity(0.26)

        // MARK: 动作历史趋势（页面 11）

        /// 最高重量折线。用强调绿本身：这一页的主角就是重量，
        /// 它没有别的元素需要跟它抢，不必像统计页那样压低饱和度。
        static let trendWeightLine = Color(hex: 0xC6FF3E)
        /// 最高重量折线下的填充
        static let trendWeightFill = Color(hex: 0xC6FF3E).opacity(0.18)
        /// 容量柱状图的柱子
        static let trendVolumeBar = Color(hex: 0x6E8A5A)
        /// 图表里被选中的那个数据点 / 那根柱子
        static let trendSelected = Color(hex: 0xC6FF3E)
        /// 未选中的数据点圆点
        static let trendDot = Color(hex: 0xC6FF3E).opacity(0.55)
        /// 单位切换器（kg / lb）选中态的底色
        static let trendUnitSelected = Color(hex: 0xC6FF3E).opacity(0.16)

        // MARK: 身体数据（页面 12）

        /// 身体数据趋势折线。同样用强调绿：这一页的主角是身体指标本身。
        static let bodyChartLine = Color(hex: 0xC6FF3E)
        /// 身体数据折线下的填充
        static let bodyChartFill = Color(hex: 0xC6FF3E).opacity(0.18)
        /// 未选中的身体数据点
        static let bodyChartDot = Color(hex: 0xC6FF3E).opacity(0.55)
        /// 被选中的身体数据点
        static let bodyChartSelected = Color(hex: 0xC6FF3E)

        // MARK: 权限状态（页面 51）

        /// 权限「已授权」的状态色。用强调绿：这是唯一一个「此权限可用」的正面状态。
        static let permissionGranted = Color(hex: 0xC6FF3E)
        /// 权限「未授权」的状态色。
        ///
        /// 刻意用中性的三级文字色而不是黄色：未授权是**默认状态**，
        /// 用户什么都没做、功能也确实还没用到它，用警示色会平白制造焦虑。
        /// 规格也明确「拒绝权限不影响核心功能」，界面语气要与此一致。
        static let permissionIdle = Color.white.opacity(0.34)
        /// 权限「已拒绝」的状态色。用警示黄而不是危险红：
        /// 拒绝权限不是错误，只是需要用户去系统设置里改一下。
        static let permissionDenied = Color(hex: 0xFFC53D)
        /// 权限「受限制」的状态色。灰蓝，与其它三种都能区分，
        /// 且传达「这不是你能在这里改的」。
        static let permissionRestricted = Color(hex: 0x8A93A5)
        /// 权限状态徽章的底色（低饱和版本的状态色，避免整行过亮）
        static let permissionBadgeFill = Color.white.opacity(0.06)
    }

    // MARK: - 圆角

    enum Radius {
        static let card: CGFloat = 18
        static let button: CGFloat = 14
        static let chip: CGFloat = 10
        static let sheet: CGFloat = 22
        /// 底部抽屉：24pt
        static let drawer: CGFloat = 24
    }

    // MARK: - 间距

    enum Spacing {
        /// 页面左右边距
        static let page: CGFloat = 16
        /// 卡片内边距
        static let card: CGFloat = 16
        /// 区块之间
        static let section: CGFloat = 22
        /// 元素之间
        static let item: CGFloat = 12
        /// 紧凑元素之间
        static let tight: CGFloat = 6
    }

    // MARK: - 排版（全部使用语义化字体，支持动态字体）

    enum Typography {
        static let largeTitle = Font.largeTitle.weight(.bold)
        static let sectionTitle = Font.title3.weight(.semibold)
        static let cardTitle = Font.headline
        static let body = Font.body
        static let callout = Font.callout
        static let footnote = Font.footnote
        static let caption = Font.caption
        static let caption2 = Font.caption2.weight(.medium)
    }

    // MARK: - 动效

    enum Motion {
        /// 按钮按下回弹：180ms 弹性
        static let buttonPress = Animation.spring(response: 0.18, dampingFraction: 0.72)
        /// Tab 切换横向淡入：220ms
        static let tabSwitch = Animation.easeOut(duration: 0.22)
        /// 常规状态变化
        static let standard = Animation.easeInOut(duration: 0.2)
        /// 底部抽屉上滑 / 下滑：260ms ease-out
        static let drawer = Animation.easeOut(duration: 0.26)
        /// 概览数字变化时的淡入：180ms
        static let numberFade = Animation.easeOut(duration: 0.18)
        /// 圆形勾选框由灰描边切换为荧光绿实心
        static let check = Animation.spring(response: 0.26, dampingFraction: 0.68)
        /// 组间休息最后 3 秒的轻微缩放提示，1.0 → 1.06 往复
        static let restPulse = Animation.easeInOut(duration: 0.35)
        /// 独立驱动呼吸式脉冲。与 restPulse 配合用于最后 3 秒。
        static let restPulseRepeat = Animation.easeInOut(duration: 0.45)
            .repeatForever(autoreverses: true)
        /// 训练总结统计卡片数字从 0 递增到目标值：500ms
        static let countUp = Animation.easeOut(duration: 0.5)
        /// 「动作完成情况」展开 / 收起
        static let disclosure = Animation.easeInOut(duration: 0.22)
        /// 休息面板折叠 / 展开（问题二）：弹性过渡，收起成顶部胶囊、点开还原
        static let spring = Animation.spring(response: 0.4, dampingFraction: 0.85)
    }

    // MARK: - 蒙层

    enum Scrim {
        /// 抽屉背后的黑色遮罩，35% 不透明度
        static let opacity: Double = 0.35
        static let color = Color.black.opacity(opacity)
    }

    // MARK: - 尺寸

    enum Size {
        /// 主按钮最小高度，满足触控目标
        static let buttonHeight: CGFloat = 50
        /// 快捷入口最小高度
        static let quickActionHeight: CGFloat = 48
        /// 最小可点击区域
        static let minTapTarget: CGFloat = 44
        /// 计划卡宽度上限
        static let planCardMaxWidth: CGFloat = 260
        /// 计划卡宽度下限
        static let planCardMinWidth: CGFloat = 200
        /// 计划卡高度。横向滚动容器需要显式高度才能用 GeometryReader 量宽。
        static let planCardHeight: CGFloat = 148
        /// 计划详情页动作卡缩略图边长
        static let planThumbnail: CGFloat = 52
        /// 「训练日」圆形按钮直径
        static let weekdayBadge: CGFloat = 44
        /// 拖拽把手的点击区宽度
        static let dragHandleWidth: CGFloat = 36
        /// 组表左侧组号列宽
        static let setIndexColumn: CGFloat = 40
        /// 组表右侧圆形勾选按钮直径
        static let setCheckbox: CGFloat = 30
        /// 组表中间数值控件的最小宽度
        static let setValueField: CGFloat = 62
        /// 顶部固定栏高度
        static let sessionBarHeight: CGFloat = 56
        /// 顶部计时面板的圆角
        static let timerPanelRadius: CGFloat = 14
        /// 组间休息面板的圆角。规格指定 24pt 顶部圆角。
        static let restPanelRadius: CGFloat = 24
        /// 组间休息面板进度环的直径
        static let restRing: CGFloat = 176
        /// 组间休息进度环的线宽
        static let restRingStroke: CGFloat = 8
        /// 组间休息剩余时间数字的字号。用超大等宽数字，抬眼看即可读。
        static let restCountdownFont: CGFloat = 64
        /// 「倒计时数字样式 = 大号」时的字号（页面 14 训练偏好）。
        static let restCountdownFontLarge: CGFloat = 84
        /// 组间休息面板里调整按钮的高度
        static let restAdjustButtonHeight: CGFloat = 48
        /// 训练总结页顶部代码绘制勾选图形的边长
        static let summaryCheckGlyph: CGFloat = 40
        /// 训练总结页勾选图形外圈直径
        static let summaryCheckRing: CGFloat = 76
        /// 训练总结页勾选图形的线宽
        static let summaryCheckStroke: CGFloat = 7
        /// 训练总结页统计卡片数字字号
        static let summaryMetricFont: CGFloat = 24
        /// 训练总结页「动作完成情况」行的最小高度
        static let summaryRowHeight: CGFloat = 44

        // MARK: 历史日历

        /// 日历单元格的最小高度。宽度由 LazyVGrid 均分，这里是高度下限。
        static let calendarCellHeight: CGFloat = 46
        /// 选中日期的荧光绿圆形直径
        static let calendarSelectionCircle: CGFloat = 36
        /// 今天的细描边圆直径，比选中圆略大一圈，保证两者能同时显示
        static let calendarTodayRing: CGFloat = 42
        /// 今天的细描边线宽
        static let calendarTodayStroke: CGFloat = 1.5
        /// 日期下方标记小圆点的直径
        static let calendarMarkerDot: CGFloat = 5
        /// 同一天最多并列显示的标记点数量，超出时忽略多余记录
        static let calendarMarkerMaxDots: Int = 3
        /// 标记点行的固定高度，保证有无标记时单元格高度一致
        static let calendarMarkerRowHeight: CGFloat = 8

        // MARK: 历史训练详情

        /// 历史详情统计格的字号。
        ///
        /// 比总结页的 `summaryMetricFont`（24）小一档：总结页是「刚练完」的
        /// 高光时刻，历史详情是回头核对数据，同一屏里要放下四格还留白。
        static let detailMetricFont: CGFloat = 21
        /// 历史详情每组行的高度下限
        static let detailSetRowHeight: CGFloat = 34

        // MARK: 训练统计

        /// 统计摘要卡数值的字号。
        ///
        /// 四张卡横排在一行里，比历史详情的 21 再小一档，
        /// 否则「总训练容量」这种六七位数会把卡片撑破。
        static let statsMetricFont: CGFloat = 20
        /// 统计摘要卡的最小高度，保证四张不等宽的卡高度一致
        static let statsMetricCardHeight: CGFloat = 84
        /// 频率柱状图的绘图区高度
        static let statsFrequencyChartHeight: CGFloat = 160
        /// 容量折线图的绘图区高度
        static let statsVolumeChartHeight: CGFloat = 172
        /// 柱状图单根柱子的最大宽度。柱子太宽会像色块而不是图表。
        static let statsBarMaxWidth: CGFloat = 22
        /// 柱状图中力量柱的颜色。刻意压低饱和度，避免与荧光绿强调色抢视线。
        static let statsBarMinWidth: CGFloat = 3
        /// 图表纵轴刻度区的宽度
        static let statsAxisWidth: CGFloat = 32
        /// 肌群分布横向进度条的高度
        static let statsMuscleBarHeight: CGFloat = 8
        /// 图表卡在小屏上降级为横向滚动时，单屏最少显示多少格
        static let statsMinVisibleBuckets: Int = 7
        /// 柱子少于这个数时才显示横轴文字标签，多了会糊成一团
        static let statsAxisLabelMaxCount: Int = 12

        // MARK: 动作历史趋势（页面 11）

        /// 最高重量折线图的绘图区高度
        static let trendWeightChartHeight: CGFloat = 168
        /// 单次训练容量柱状图的绘图区高度。比重量图矮一点：
        /// 它是辅助信息，不该在视觉上压过重量趋势。
        static let trendVolumeChartHeight: CGFloat = 140
        /// 折线图上数据点的直径
        static let trendDotDiameter: CGFloat = 7
        /// 被选中数据点的直径。比常态大一圈，让选中态一眼可辨。
        static let trendSelectedDotDiameter: CGFloat = 11
        /// 容量柱子的最大宽度
        static let trendBarMaxWidth: CGFloat = 20
        /// 容量柱子的最小宽度：只有 1 组训练时柱子不能细成一条线
        static let trendBarMinWidth: CGFloat = 4
        /// 摘要卡数值的字号。五个字段排成两列，比统计页的四张卡再小一档。
        static let trendMetricFont: CGFloat = 18
        /// 摘要卡单格的最小高度
        static let trendMetricRowHeight: CGFloat = 56
        /// 单位切换器（kg / lb）的高度
        static let trendUnitToggleHeight: CGFloat = 30
        /// 最近记录行的最小高度
        static let trendRecordRowHeight: CGFloat = 54
        /// 折线图纵向内边距，避免最高点的圆点被裁掉
        static let trendChartVerticalPadding: CGFloat = 12

        // MARK: 身体数据（页面 12）

        /// 身体数据趋势折线图的绘图区高度
        static let bodyChartHeight: CGFloat = 180
        /// 身体数据折线图纵向内边距
        static let bodyChartVerticalPadding: CGFloat = 12
        /// 身体数据折线图数据点直径
        static let bodyDotDiameter: CGFloat = 7
        /// 被选中数据点直径
        static let bodySelectedDotDiameter: CGFloat = 11
        /// 指标 Chip 的高度
        static let bodyChipHeight: CGFloat = 32
        /// 摘要卡数值字号
        static let bodyMetricFont: CGFloat = 20
        /// 记录卡片的最小行高
        static let bodyRecordRowHeight: CGFloat = 54
    }
}

// MARK: - 十六进制颜色

extension Color {
    /// 以 0xRRGGBB 形式构造颜色
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
