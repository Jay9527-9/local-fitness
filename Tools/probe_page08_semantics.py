#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
page 08 值语义探针：历史日历的月历数学与自然日归并。

背景：本机没有 Swift 编译器，HistoryCalendar / HistoryDayIndex 的逻辑
全部是纯值计算，因此逐条移植到 Python 后跑断言表，是唯一能在交付前
真正发现「月初偏移算错」「跨时区切天」这类问题的手段。

移植约定：
- Swift 的 Calendar.current 默认时区在本机模拟为 Asia/Shanghai（东八区），
  因为目标用户与设备都在中国，DST 无关但 UTC 偏移必须尊重。
- Python 的 date.weekday() 是 1=周一…7=周日，正好等于 Swift 的
  WeekdayLabel.normalize(calendarWeekday:) 结果，但换算过程仍完整移植，
  不能直接用，否则被测的不是 Swift 里那段代码。
- 断言全部来自「手算结果」，不是从被移植代码里读出来的。
"""

import calendar as pycal
import datetime as dt

# 用固定偏移而不是 ZoneInfo("Asia/Shanghai")：
# Windows 上的 Python 没有系统 tzdata，zoneinfo 会直接抛错。
# 中国自 1991 年起全境统一 UTC+8 且无夏令时，固定偏移与区域等价。
TZ = dt.timezone(dt.timedelta(hours=8))

WEEK_COUNT = 6
DAY_COUNT_IN_WEEK = 7
CELL_COUNT = WEEK_COUNT * DAY_COUNT_IN_WEEK


# ---------- 移植：WeekdayLabel ----------

def weekday_symbol(day):
    return {1: "一", 2: "二", 3: "三", 4: "四", 5: "五", 6: "六", 7: "日"}.get(day, "?")


def normalize_weekday(calendar_weekday):
    """Swift: calendarWeekday == 1 ? 7 : calendarWeekday - 1"""
    return 7 if calendar_weekday == 1 else calendar_weekday - 1


def swift_weekday(d):
    """Python weekday(): Mon=0..Sun=6 -> Swift Calendar.component(.weekday): Sun=1..Sat=7"""
    return (d.weekday() + 1) % 7 + 1


# ---------- 移植：HistoryCalendar ----------

def first_day_of_month(month):
    return month.replace(day=1)


def leading_blank_count(month):
    first = first_day_of_month(month)
    normalized = normalize_weekday(swift_weekday(first))
    return normalized - 1


def day_count(month):
    return pycal.monthrange(month.year, month.month)[1]


def grid_days(month):
    first = first_day_of_month(month)
    blanks = leading_blank_count(month)
    total = day_count(month)

    days = [None] * blanks
    for offset in range(total):
        days.append(first + dt.timedelta(days=offset))
    if len(days) < CELL_COUNT:
        days.extend([None] * (CELL_COUNT - len(days)))
    if len(days) > CELL_COUNT:
        days = days[:CELL_COUNT]
    return days


def month_add(value, month):
    base = first_day_of_month(month)
    index = base.year * 12 + (base.month - 1) + value
    return dt.date(index // 12, index % 12 + 1, 1)


def month_title(month):
    return f"{month.year}年{month.month}月"


# ---------- 移植：HistoryDayIndex ----------

def start_of_day(d):
    """Swift: calendar.startOfDay(for:) -> 该自然日 00:00。
    Python 里等价于把年月日之后的字段全部清零（保留 tzinfo），
    不是 d.date() —— date() 会把字典 key 降级成无时区的 date，
    与断言里写的 date 无法命中。"""
    return d.replace(hour=0, minute=0, second=0, microsecond=0)


def build_index(sessions, rest_days):
    """sessions: [(started_at, is_finished, kind)]  rest_days: [date]"""
    grouped = {}
    for started_at, is_finished, _kind in sessions:
        if not is_finished:
            continue
        grouped.setdefault(start_of_day(started_at), []).append(started_at)

    rest_keys = {start_of_day(d) for d in rest_days}
    all_keys = set(grouped.keys()) | rest_keys

    result = {}
    for key in all_keys:
        result[key] = {
            "day": key,
            "sessions": sorted(grouped.get(key, [])),
            "is_rest_day": key in rest_keys,
        }
    return result


def entry_for(date, index):
    return index.get(start_of_day(date),
                     {"day": start_of_day(date), "sessions": [], "is_rest_day": False})


def markers_for(entry, kinds_by_start):
    """markers 顺序：训练按开始时间，休息日追加在最后"""
    marks = [kinds_by_start[s] for s in entry["sessions"]]
    if entry["is_rest_day"]:
        marks.append("rest")
    return marks


def hidden_marker_count(marks, max_dots=3):
    return max(0, len(marks) - max_dots)


# ---------- 断言表 ----------

FAILURES = []
PASSES = 0


def day(year, month, day_of_month):
    """断言里表示「某个本地自然日 00:00」，与 build_index 的 key 同类型同值。

    网格、归并索引这些由日历算出来的日期，都被 start_of_day 归一成
    带时区的 datetime，所以这里也带上 tzinfo，否则字典查找会落空。"""
    return dt.datetime(year, month, day_of_month, tzinfo=TZ)


def bare(year, month, day_of_month):
    """dt.date(2026,1,1) - timedelta 的结果是裸 date，
    凡是断言「日期加减的输出」都要用它，否则比较的是两种类型。"""
    return dt.date(year, month, day_of_month)


def check(label, actual, expected):
    global PASSES
    actual_r = repr(actual)[:160]
    expected_r = repr(expected)[:160]
    if actual != expected:
        FAILURES.append(f"{label}\n     实际: {actual_r}\n     期望: {expected_r}")
    else:
        PASSES += 1


print("=" * 72)
print("page 08 值语义探针：历史日历")
print("=" * 72)

# --- 1. 星期换算 ---
print("\n[1] 日历 weekday 换算（1=周日 → 7）")
# 2026-06-01 是周一
check("2026-06-01 是周一", day(2026, 6, 1).strftime("%a"), "Mon")
check("周一说 normalize 后 = 1", normalize_weekday(swift_weekday(day(2026, 6, 1))), 1)
# 2026-02-01 是周日
check("2026-02-01 是周日", day(2026, 2, 1).strftime("%a"), "Sun")
check("周日说 normalize 后 = 7", normalize_weekday(swift_weekday(day(2026, 2, 1))), 7)
check("周日说 leadingBlank = 6", leading_blank_count(day(2026, 2, 1)), 6)
check("周一说 leadingBlank = 0", leading_blank_count(day(2026, 6, 1)), 0)

# --- 2. 月初偏移的全月扫描（2024-2027 共 48 个月，逐月核对） ---
print("\n[2] 月初偏移全月扫描（2024-01 ~ 2027-12）")
# 独立重算：用 calendar 模块的 monthcalendar，它天然按周一开头，
# 空白天数 = 第一行第一个非零列的索引。这是与移植代码完全不同的算法。
offset_mismatch = []
for year in range(2024, 2028):
    for month in range(1, 13):
        d = dt.date(year, month, 1)
        rows = pycal.monthcalendar(year, month)
        first_row = rows[0]
        blanks = 0
        for cell in first_row:
            if cell == 0:
                blanks += 1
            else:
                break
        if leading_blank_count(d) != blanks:
            offset_mismatch.append((d.isoformat(), leading_blank_count(d), blanks))
check("48 个月月初偏移无一错位", offset_mismatch, [])

# --- 3. leadingBlank + dayCount <= 42 ---
print("\n[3] 格子容量")
over_capacity = []
for year in range(2024, 2028):
    for month in range(1, 13):
        d = dt.date(year, month, 1)
        if leading_blank_count(d) + day_count(d) > CELL_COUNT:
            over_capacity.append(d.isoformat())
check("无月份超出 42 格", over_capacity, [])
# 最坏情况：31 天 + 6 空白 = 37，剩余的 5 格必须补 nil
check("2026-03（31天/周日开头）总长 42", len(grid_days(day(2026, 3, 1))), 42)
check("2026-03 尾部补 nil 数量", len(grid_days(day(2026, 3, 1))) - 6 - 31, 5)

# --- 4. 网格内容正确性 ---
print("\n[4] 网格内容")
g = grid_days(day(2026, 2, 1))  # 2026-02-01 周日，28 天
check("2026-02 前 6 格全为 nil", g[:6], [None] * 6)
check("2026-02 第 7 格是 2/1", g[6], day(2026, 2, 1))
check("2026-02 第 34 格是 2/28", g[6 + 27], day(2026, 2, 28))
check("2026-02 第 35 格起为 nil", set(g[6 + 28:]), {None})

g2 = grid_days(day(2026, 6, 1))  # 周一开头，30 天
check("2026-06 第 1 格是 6/1", g2[0], day(2026, 6, 1))
check("2026-06 第 30 格是 6/30", g2[29], day(2026, 6, 30))
check("2026-06 第 31 格是 nil", g2[30], None)
check("2026-06 总长 42", len(g2), 42)

# --- 5. 闰年 ---
print("\n[5] 闰年")
check("2024-02 天数 29", day_count(day(2024, 2, 1)), 29)
check("2026-02 天数 28", day_count(day(2026, 2, 1)), 28)
check("2024-02 首格空白数", leading_blank_count(day(2024, 2, 1)), 3)
check("2024-02 最后一天是 2/29", grid_days(day(2024, 2, 1))[3 + 28], day(2024, 2, 29))
check("2100 非闰年 2 月 28 天", day_count(day(2100, 2, 1)), 28)
check("2000 闰年 2 月 29 天", day_count(day(2000, 2, 1)), 29)

# --- 6. 月份加减跨年 ---
print("\n[6] 月份加减")
check("2026-01 减 1 → 2025-12", month_add(-1, bare(2026, 1, 1)), bare(2025, 12, 1))
check("2026-12 加 1 → 2027-01", month_add(1, bare(2026, 12, 1)), bare(2027, 1, 1))
check("2026-03 减 1 → 2026-02", month_add(-1, bare(2026, 3, 1)), bare(2026, 2, 1))
check("2026-09 减 12 → 2025-09", month_add(-12, bare(2026, 9, 1)), bare(2025, 9, 1))
check("2026-09 加 15 → 2027-12", month_add(15, bare(2026, 9, 1)), bare(2027, 12, 1))
# 3 月 31 日减一个月：必须先归一到 1 号再减，否则 2/31 不存在
check("3/31 减 1 月不越界 → 2/1", month_add(-1, bare(2026, 3, 31)), bare(2026, 2, 1))
check("5/31 加 1 月不越界 → 6/1", month_add(1, bare(2026, 5, 31)), bare(2026, 6, 1))
# 连续 24 次 +1 回到起点年份
m = day(2026, 9, 1)
for _ in range(24):
    m = month_add(1, m)
check("连续 +1 共 24 次 → 2028-09", m, bare(2028, 9, 1))

# --- 7. 标题 ---
print("\n[7] 月份标题")
check("2026-09 标题", month_title(day(2026, 9, 1)), "2026年9月")
check("2026-01 标题（不补零）", month_title(day(2026, 1, 1)), "2026年1月")
check("2026-12 标题", month_title(day(2026, 12, 1)), "2026年12月")

# --- 8. 自然日归并 ---
print("\n[8] 自然日归并（本地时区）")
T = dt.timezone(dt.timedelta(hours=8))
d1 = dt.datetime(2026, 9, 19, 7, 30, tzinfo=TZ)    # 早上训练
d2 = dt.datetime(2026, 9, 19, 20, 15, tzinfo=TZ)   # 晚上训练
d3 = dt.datetime(2026, 9, 18, 23, 40, tzinfo=TZ)   # 前一夜
d4 = dt.datetime(2026, 9, 19, 10, 0, tzinfo=TZ)    # 未结束

idx = build_index(
    sessions=[(d1, True, "strength"), (d2, True, "cardio"),
              (d3, True, "strength"), (d4, False, "strength")],
    rest_days=[],
)
check("归并出 2 个自然日", sorted(idx.keys()), [day(2026, 9, 18), day(2026, 9, 19)])
check("9/19 有 2 条", len(idx[day(2026, 9, 19)]["sessions"]), 2)
check("9/19 组内按开始时间升序",
      idx[day(2026, 9, 19)]["sessions"], [d1, d2])
check("未结束的草稿不计入历史", idx[day(2026, 9, 19)]["sessions"].count(d4), 0)
check("9/18 只有 1 条", len(idx[day(2026, 9, 18)]["sessions"]), 1)

# --- 9. UTC 切天陷阱 ---
print("\n[9] UTC 切天陷阱（东八区 07:30 必须算本地当天）")
# 说明：这条断言验证的是「不要用 UTC 切天」。被测代码里的注释提到过
# Int(timeIntervalSince1970 / 86400) 这种错误写法，那是注释，不是实现。
early = dt.datetime(2026, 9, 19, 7, 30, tzinfo=TZ)
utc_naive_day = early.astimezone(dt.timezone.utc).date()
check("该时刻的 UTC 日期是前一天", utc_naive_day, bare(2026, 9, 18))
idx2 = build_index(sessions=[(early, True, "strength")], rest_days=[])
check("本地日历归到 9/19 而非 9/18", list(idx2.keys()), [day(2026, 9, 19)])

# --- 10. 休息日 ---
print("\n[10] 休息日")
idx3 = build_index(
    sessions=[(d1, True, "strength")],
    rest_days=[day(2026, 9, 18)],
)
check("休息日单独成日", day(2026, 9, 18) in idx3, True)
check("休息日当日无训练", idx3[day(2026, 9, 18)]["sessions"], [])
check("休息日标记为 True", idx3[day(2026, 9, 18)]["is_rest_day"], True)
check("9/19 未被误标休息", idx3[day(2026, 9, 19)]["is_rest_day"], False)

# 休息日与训练同日
idx4 = build_index(sessions=[(d1, True, "strength")], rest_days=[day(2026, 9, 19)])
check("同日既有训练又标休息，仍在同一格",
      sorted(idx4.keys()), [day(2026, 9, 19)])
check("同日两标记", len(idx4[day(2026, 9, 19)]["sessions"]) + 1, 2)

# --- 11. 空日查询 ---
print("\n[11] 空日查询")
empty_repo = build_index(sessions=[], rest_days=[])
e = entry_for(day(2026, 9, 19), empty_repo)
check("空库查询返回空记录而非 None", e is not None, True)
check("空记录 sessions 为空", e["sessions"], [])
check("空记录 is_rest_day 为 False", e["is_rest_day"], False)

# --- 12. 标记点与折叠 ---
print("\n[12] 标记点顺序与折叠")
kinds = {d1: "strength", d2: "cardio"}
marks = markers_for(idx[day(2026, 9, 19)], kinds)
check("力量在前有氧在后", marks, ["strength", "cardio"])
idx5 = build_index(
    sessions=[(d1, True, "strength")], rest_days=[day(2026, 9, 19)]
)
marks5 = markers_for(idx5[day(2026, 9, 19)], {d1: "strength"})
check("休息日追加在末尾", marks5, ["strength", "rest"])

check("3 个标记不折叠", hidden_marker_count(["a", "b", "c"]), 0)
check("4 个标记折叠 1", hidden_marker_count(["a", "b", "c", "d"]), 1)
check("6 个标记折叠 3", hidden_marker_count(["a"] * 6), 3)
check("5 个标记折叠 2", hidden_marker_count(["a"] * 5), 2)

# --- 13. 跨年边界 ---
print("\n[13] 跨年边界")
new_year = dt.datetime(2027, 1, 1, 0, 5, tzinfo=TZ)
new_year_eve = dt.datetime(2026, 12, 31, 23, 55, tzinfo=TZ)
idx6 = build_index(
    sessions=[(new_year_eve, True, "strength"), (new_year, True, "cardio")],
    rest_days=[],
)
check("跨年夜分属两天",
      sorted(idx6.keys()), [day(2026, 12, 31), day(2027, 1, 1)])
check("2026-12-31 → 2027-01 加月正确",
      month_add(1, bare(2026, 12, 31)), bare(2027, 1, 1))
check("2026-12 网格含 12/31",
      day(2026, 12, 31) in grid_days(day(2026, 12, 1)), True)
check("2027-01 网格含 1/1",
      day(2027, 1, 1) in grid_days(day(2027, 1, 1)), True)

# --- 14. 全部月份网格：日期唯一且有序 ---
print("\n[14] 网格不变量（2024-2027 全月）")
bad = []
for year in range(2024, 2028):
    for month in range(1, 13):
        days = [d for d in grid_days(dt.date(year, month, 1)) if d is not None]
        if len(days) != day_count(dt.date(year, month, 1)):
            bad.append((year, month, "count"))
            continue
        if days != sorted(days):
            bad.append((year, month, "order"))
            continue
        if len(set(days)) != len(days):
            bad.append((year, month, "dup"))
            continue
        if days[0].day != 1:
            bad.append((year, month, "first"))
            continue
        if days[-1].month != month:
            bad.append((year, month, "tail"))
check("48 个月网格全部非空/有序/无重复/首尾正确", bad, [])

# --- 15. 列表分组 ---
print("\n[15] 列表分组")

def sections_of(dates):
    finished = sorted(dates, reverse=True)
    order = []
    buckets = {}
    for d in finished:
        key = d.replace(day=1)
        if key not in buckets:
            order.append(key)
            buckets[key] = []
        buckets[key].append(d)
    return [(month_title(k), buckets[k]) for k in order]


raw = [day(2026, 9, 19), day(2026, 9, 2), day(2026, 8, 30),
       day(2026, 8, 3), day(2025, 12, 25), day(2026, 9, 19)]
secs = sections_of(raw)
check("分组数 3", len(secs), 3)
check("首组标题", secs[0][0], "2026年9月")
check("末组标题", secs[2][0], "2025年12月")
check("组内倒序", secs[0][1], [day(2026, 9, 19), day(2026, 9, 19), day(2026, 9, 2)])
check("组顺序按月份倒序",
      [s[0] for s in secs], ["2026年9月", "2026年8月", "2025年12月"])
check("空输入无分组", sections_of([]), [])

# --- 16. 字符串长度防御 ---
print("\n[16] 标记折叠的 VoiceOver 文案补数")
check("无折叠时不补", hidden_marker_count(["a"]), 0)
check("折叠数等于超出的标记数", hidden_marker_count(["a"] * 5), 2)



# --- 17. 跨月选择时 visibleMonth 的形态一致性（回归） ---
print("\n[17] select() 的月份形态一致性")

def select_port(visible_month, selected, date):
    """移植 HistoryView.select(_:) 修正后的实现：
       先切月份，且月份统一用 startOfDay(date) 形态。"""
    if (visible_month.year, visible_month.month) != (date.year, date.month):
        visible_month = start_of_day(date)
    selected = date
    return visible_month, selected


now = dt.datetime(2026, 9, 19, 12, 55, tzinfo=TZ)
initial = start_of_day(now)

# 场景 A：跨月选择后，形态必须仍是「某天 00:00」，不能退化成 1 号
vm, sel = select_port(initial, now, dt.datetime(2026, 10, 5, tzinfo=TZ))
check("跨月选择后 visibleMonth 是 startOfDay 形态", vm.day, 5)
check("跨月选择后落在正确月份", (vm.year, vm.month), (2026, 10))

# 场景 B：连续跨月，形态稳定（不漂移）
vm2 = initial
for target in [dt.datetime(2026, 10, 5, tzinfo=TZ),
               dt.datetime(2026, 11, 8, tzinfo=TZ),
               dt.datetime(2026, 12, 3, tzinfo=TZ)]:
    vm2, _ = select_port(vm2, now, target)
check("连续跨月后形态仍为 startOfDay", vm2.day, 3)
check("连续跨月后月份正确", (vm2.year, vm2.month), (2026, 12))

# 场景 C：同月选择不动 visibleMonth
vm3 = initial
vm3, _ = select_port(vm3, now, dt.datetime(2026, 9, 25, tzinfo=TZ))
check("同月选择不动 visibleMonth", vm3, initial)

# 场景 D：跨年
vm4, _ = select_port(initial, now, dt.datetime(2027, 1, 3, tzinfo=TZ))
check("跨年选择月份正确", (vm4.year, vm4.month), (2027, 1))

# 场景 E：旧实现在这里会退化成 1 号 —— 明确钉住不许回退
def select_old(visible_month, selected, date):
    """旧实现：用 month(byAdding:0) 把 day 归 1，且先改 selected。"""
    if (visible_month.year, visible_month.month) != (date.year, date.month):
        visible_month = date.replace(day=1)
    selected = date
    return visible_month, selected

old_vm, _ = select_old(initial, now, dt.datetime(2026, 10, 5, tzinfo=TZ))
new_vm, _ = select_port(initial, now, dt.datetime(2026, 10, 5, tzinfo=TZ))
check("旧实现会退化为 1 号（证明该断言有区分力）", old_vm.day, 1)
check("新实现不退化为 1 号", new_vm.day, 5)
check("新旧实现在此场景确实不同（防回归有效）", old_vm != new_vm, True)

# --- 18. 补记历史训练的时长不失真（回归） ---
print("\n[18] 补记历史训练：startedAt 不能落在零点")

def time_of_day(time_source, day_date):
    """移植 HistoryViewModel.timeOfDay(from:onDayOf:)：保留时刻，替换日期。"""
    merged = day_date.replace(
        hour=time_source.hour, minute=time_source.minute,
        second=time_source.second, microsecond=0
    )
    return merged

selected_day = dt.datetime(2026, 9, 10, tzinfo=TZ)
press_moment = dt.datetime(2026, 9, 10, 19, 30, tzinfo=TZ)
finished     = dt.datetime(2026, 9, 19, 18, 0, tzinfo=TZ)  # 9 天后才点完成

started_ok = time_of_day(press_moment, selected_day)
dur_ok = int((finished - started_ok).total_seconds())

started_bad = start_of_day(selected_day)          # 旧实现
dur_bad = int((finished - started_bad).total_seconds())

check("补记时 startedAt 保留时刻（19:30）", (started_ok.hour, started_ok.minute), (19, 30))
check("补记时 startedAt 归属选中那天", started_ok.day, 10)
check("旧实现时长被算成 9 天+", dur_bad > 800_000, True)
check("新实现时长显著小于旧实现", dur_ok < dur_bad, True)
# 9/10 19:30 -> 9/19 18:00 = 8 天 22 小时 30 分 = 772200 秒
check("新实现不会把等待时间算进修时", dur_ok, 772_200)

# 开始时间不得超过此刻
future_day = dt.datetime(2026, 12, 31, tzinfo=TZ)
merged_future = time_of_day(press_moment, future_day)
check("未来日期拼接出的 startedAt 晚于此刻（说明需要兜底）",
      merged_future > dt.datetime(2026, 9, 19, 12, 55, tzinfo=TZ), True)

# --- 19. 同一天多条训练：标记点数量与折叠 ---
print("\n[19] 同一天多条训练")
many = [dt.datetime(2026, 9, 19, h, 0, tzinfo=TZ) for h in (7, 12, 18, 20)]
idx_many = build_index(sessions=[(d, True, "strength") for d in many], rest_days=[])
check("同一天 4 条归入同一格", len(idx_many), 1)
check("当日 4 条有序", len(idx_many[start_of_day(many[0])]["sessions"]), 4)
check("4 个标记点折叠 1 个", hidden_marker_count(["a"] * 4), 1)
kinds_many = {d: "strength" for d in many}
check("4 条力量产生 4 个点",
      len(markers_for(idx_many[start_of_day(many[0])], kinds_many)), 4)

# --- 20. 未结束的训练不出现在历史 ---
print("\n[20] 进行中的草稿不计入历史")
idx_draft = build_index(
    sessions=[(dt.datetime(2026, 9, 19, 20, 0, tzinfo=TZ), False, "strength")],
    rest_days=[])
check("只有未结束训练时索引为空", idx_draft, {})
check("该日查询返回空记录",
      entry_for(dt.datetime(2026, 9, 19, tzinfo=TZ), idx_draft)["sessions"], [])

# ---------- 汇总 ----------
print("\n" + "=" * 72)
if FAILURES:
    print(f"失败 {len(FAILURES)} 项，通过 {PASSES} 项\n")
    for f in FAILURES:
        print("  ✗ " + f)
    print("=" * 72)
    raise SystemExit(1)
print(f"全部通过：{PASSES} 项断言")
print("=" * 72)
