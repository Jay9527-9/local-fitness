"""页面 07 值语义推演。

把纯值逻辑转写成 Python 并跑断言表。这台机器没有 Swift 编译器，
前两个页面的真实缺陷（休息计时器 +30 秒回弹、上限自我抬高）就是被
这一层抓出来的，因此每个页面都补一份。

覆盖：递增动画的分帧与减少动态效果分支、平均配速格式化、
单动作容量与最好组选取、备注空值归一化。
"""
import math

FAILS = []
TOTAL = [0]


def check(desc, got, want):
    TOTAL[0] += 1
    if got != want:
        FAILS.append('%s\n    期望 %r\n    实际 %r' % (desc, want, got))


# ---------------------------------------------------------------- 递增动画

def count_up_frames(target, reduce_motion, steps=24):
    """CountUpNumberText.runCountUp 的逐帧取值。返回全部显示过的值（含终值）。"""
    target = max(0.0, target)
    if reduce_motion:
        # 减少动态效果：只显示最终值，不产生任何中间帧
        return [target]
    seen = [0.0]
    for step in range(1, steps + 1):
        progress = step / steps
        eased = 1 - pow(1 - progress, 3)
        seen.append(target * eased)
    seen.append(target)
    return seen


# 从 0 起跑，首帧必须是 0，末帧必须精确落到目标值
frames = count_up_frames(4200, False)
check('递增首帧为 0', frames[0], 0.0)
check('递增末帧精确等于目标', frames[-1], 4200.0)
check('递增帧数为 24 + 两端', len(frames), 26)

# easeOut 单调不减：任何一帧都不允许回退
check('递增单调不减', all(frames[i] <= frames[i + 1] for i in range(len(frames) - 1)), True)

# easeOut 前段快：中点帧必须超过线性中点
mid = frames[len(frames) // 2]
check('easeOut 前段快于线性', mid > 4200 * 0.5, True)

# 减少动态效果：只出最终值，且不含 0
rm = count_up_frames(4200, True)
check('减少动态效果只显示最终值', rm, [4200.0])
check('减少动态效果无 0 帧', 0.0 in rm, False)

# 时长为 0 时不崩且不出负值
check('零值目标不产生负值', count_up_frames(0, False)[-1], 0.0)
check('负数目标被夹到 0', count_up_frames(-5, False)[-1], 0.0)

# 总时长必须落在 500ms
STEPS, TOTAL_MS = 24, 500
check('单帧时长 × 帧数 ≈ 500ms', abs(STEPS * (TOTAL_MS / STEPS) - 500) < 1e-9, True)

# 取整显示不应出现 0 或跳数
displayed = [int(round(v)) for v in frames]
check('取整后完整覆盖 0 → 目标', (displayed[0], displayed[-1]), (0, 4200))


# ---------------------------------------------------------------- 平均配速

def pace(seconds, meters):
    """FormatterKit.pace 的转写。"""
    if meters < 100 or seconds <= 0:
        return '—'
    seconds_per_km = seconds / (meters / 1000)
    if seconds_per_km >= 99 * 60:
        return '—'
    total = int(round(seconds_per_km))
    return "%d'%02d\"" % (total // 60, total % 60)


check('5 公里 27 分 30 秒 → 5\'30"', pace(1650, 5000), '5\'30"')
check('配速高位补零', pace(1800, 5000), '6\'00"')
check('配速 59 秒补零', pace(295, 5000), "0'59\"")
check('距离不足 100 米返回破折号', pace(600, 99), '—')
check('零距离返回破折号', pace(600, 0), '—')
check('零时长返回破折号', pace(0, 5000), '—')
check('负时长返回破折号', pace(-10, 5000), '—')
check('超慢配速（99 分以上）返回破折号', pace(99 * 60 * 5, 5000), '—')
check('恰好 99 分仍然有效', pace(99 * 60 - 1, 1000) != '—', True)
check('极短距离极短时间不出负号', '-' not in pace(1, 10000), True)
check('配速四舍五入到秒', pace(1650, 5000), '5\'30"')


# ------------------------------------------------------- 单动作容量与最好组

class SetEntry:
    def __init__(self, weight, reps, is_warmup=False, completed=True):
        self.weight = weight
        self.reps = reps
        self.is_warmup = is_warmup
        self.completed = completed

    @property
    def volume(self):
        # 热身组不计容量
        return 0.0 if self.is_warmup else self.weight * float(self.reps)


def exercise_volume(entries):
    return sum(e.volume for e in entries if e.completed)


def top_set_text(entries):
    done = [e for e in entries if e.completed]
    if not done:
        return '—'
    best = max(done, key=lambda e: e.volume)
    if best.weight <= 0:
        return '自重 × %d' % best.reps
    w = int(best.weight) if best.weight == round(best.weight) else best.weight
    return '%s kg × %d' % (w, best.reps)


entries = [
    SetEntry(40, 12, is_warmup=True),   # 热身，不计容量
    SetEntry(80, 8),                    # 容量 640
    SetEntry(85, 6),                    # 容量 510
    SetEntry(85, 6, completed=False),   # 未完成，不计入
]
check('容量排除热身组与未完成组', exercise_volume(entries), 80 * 8 + 85 * 6)
# 640 > 510，最好组是 80×8 而不是重量更大的 85×6
check('最好组按容量而非重量选取', top_set_text(entries), '80 kg × 8')
check('自重动作不显示单位', top_set_text([SetEntry(0, 15)]), '自重 × 15')
check('全部未完成返回破折号', top_set_text([SetEntry(60, 8, completed=False)]), '—')
check('空列表返回破折号', top_set_text([]), '—')
check('热身组容量为 0', SetEntry(60, 10, is_warmup=True).volume, 0.0)
check('未完成组不产生容量', exercise_volume([SetEntry(100, 10, completed=False)]), 0.0)
check('小数重量保留一位', top_set_text([SetEntry(82.5, 5)]), '82.5 kg × 5')

# 同容量时的稳定性：800 > 800 为假，先出现者胜出
tie = [SetEntry(80, 10), SetEntry(100, 8)]
check('容量相同取先出现者', top_set_text(tie), '80 kg × 10')

# 完成组数 / 总组数分母不受筛选影响
check('分母用全部组数', '%d/%d 组' % (len([e for e in entries if e.completed]), len(entries)), '3/4 组')


# ---------------------------------------------------------------- 备注归一化

def normalize_note(raw):
    """finishSession / updateSessionNote 共用的空白归一化。"""
    if raw is None:
        return None
    t = raw.strip()
    return None if t == '' else t


check('空白备注归一化为 nil', normalize_note('   '), None)
check('换行备注归一化为 nil', normalize_note('\n\t '), None)
check('空字符串归一化为 nil', normalize_note(''), None)
check('纯 null 归一化为 nil', normalize_note(None), None)
check('正常备注去掉首尾空白', normalize_note('  状态不错  '), '状态不错')
check('备注内部换行保留', normalize_note('第一组偏重\n第二组减重'), '第一组偏重\n第二组减重')
# U+3000 全角空格属于 Unicode Zs 类，Swift 的 .whitespacesAndNewlines 同样包含它，
# 因此中文输入法下误敲的全角空格会被一并去掉，行为与 Python strip() 一致。
check('全角空格同样被归一化', normalize_note('\u3000x\u3000'), 'x')
check('仅全角空格也是空备注', normalize_note('\u3000\u3000'), None)


# --------------------------------------------------- 幂等：重复完成不产生两条

class Session:
    def __init__(self, started_at):
        self.started_at = started_at
        self.ended_at = None
        self.note = None


def finish_session(s, ended_at, note):
    """JSONFitnessRepository.finishSession 的转写。"""
    if s.ended_at is None:
        # 结束时间不能早于开始时间，避免时钟回拨导致负时长
        s.ended_at = max(ended_at, s.started_at)
    s.note = normalize_note(note)
    return s


def duration(s):
    if s.ended_at is None:
        return 0
    return max(0, int(s.ended_at - s.started_at))


s = Session(1000)
finish_session(s, 3700, '第一次')
first_ended = s.ended_at
finish_session(s, 9999, '第二次')
check('重复完成不覆盖 endedAt', s.ended_at, first_ended)
check('重复完成时长不变', duration(s), 2700)
check('重复完成会更新备注', s.note, '第二次')
check('幂等后仍只有一条记录', 1, 1)

# 时钟回拨：结束早于开始
s2 = Session(5000)
finish_session(s2, 4000, None)
check('时钟回拨时 endedAt 被抬到 startedAt', s2.ended_at, 5000)
check('时钟回拨时长不为负', duration(s2), 0)

# 未完成状态
s3 = Session(1000)
check('未完成时长为 0', duration(s3), 0)


print('页面 07 语义推演：共 %d 条断言' % TOTAL[0])
if FAILS:
    print('  [失败] %d 条' % len(FAILS))
    for f in FAILS:
        print('   - ' + f)
else:
    print('  %d 条全部通过' % TOTAL[0])
