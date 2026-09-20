"""页面 07 规格审计：完成训练确认抽屉 + 训练总结页。"""
import os, io

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'FitnessApp')


def strip_comments(src):
    """去掉注释与字符串外的内容，避免把注释里的规格文字当成实现。"""
    out, i, n = [], 0, len(src)
    in_str = in_line = in_block = False
    while i < n:
        c = src[i]
        nxt = src[i + 1] if i + 1 < n else ''
        if in_line:
            if c == '\n':
                in_line = False
                out.append(c)
            i += 1
            continue
        if in_block:
            if c == '*' and nxt == '/':
                in_block = False
                i += 2
                continue
            if c == '\n':
                out.append(c)
            i += 1
            continue
        if in_str:
            out.append(c)
            if c == '\\':
                if nxt:
                    out.append(nxt)
                i += 2
                continue
            if c == '"':
                in_str = False
            i += 1
            continue
        if c == '"':
            in_str = True
            out.append(c)
            i += 1
            continue
        if c == '/' and nxt == '/':
            in_line = True
            i += 2
            continue
        if c == '/' and nxt == '*':
            in_block = True
            i += 2
            continue
        out.append(c)
        i += 1
    return ''.join(out)


files = {}
for root, dirs, fs in os.walk(ROOT):
    dirs[:] = [d for d in dirs if d not in ('.git', 'build', 'DerivedData')]
    for f in fs:
        if f.endswith('.swift'):
            p = os.path.join(root, f)
            rel = os.path.relpath(p, ROOT).replace('\\', '/')
            with io.open(p, encoding='utf-8') as fh:
                files[rel] = strip_comments(fh.read())


def find(name):
    for k, v in files.items():
        if k.endswith(name):
            return v
    return ''


summary = find('SessionSummaryView.swift')
comp = find('SessionSummaryComponents.swift')
wscomp = find('WorkoutSessionComponents.swift')
wsview = find('WorkoutSessionView.swift')
root = find('RootView.swift')
history = find('HistoryView.swift')
tokens = find('DesignTokens.swift')
repo = find('JSONFitnessRepository.swift')
vm = find('WorkoutSessionViewModel.swift')

checks = []


def c(desc, ok, note=''):
    checks.append((desc, bool(ok), note))


# —— 第一步：底部确认抽屉 ——
c('抽屉标题为「完成本次训练？」', '完成本次训练？' in wsview)
c('抽屉展示训练名称', 'session.sessionName' in wscomp)
c('抽屉展示总时长', '"总时长"' in wscomp and 'session.elapsedText' in wscomp)
c('抽屉展示完成动作数', '"完成动作"' in wscomp and 'session.completedExerciseCount' in wscomp)
c('抽屉展示完成组数', '"完成组数"' in wscomp and 'session.completedSetCount' in wscomp)
c('抽屉展示训练总容量', '"训练总容量"' in wscomp and 'session.totalVolume' in wscomp)
c('有氧训练展示距离', '"距离"' in wscomp and 'session.distanceMeters' in wscomp)
c('有氧训练展示时长', 'session.isCardio' in wscomp)
c('多行训练备注输入框', 'TextEditor(text: $session.finishNote)' in wscomp)
c('备注标签为「训练备注」', '"训练备注"' in wscomp)
c('操作一：取消', 'title: "取消"' in wscomp)
c('操作二：继续训练', 'title: "继续训练"' in wscomp)
c('操作三：完成训练', 'title: "完成训练"' in wscomp)
c('取消不改草稿（仅收起抽屉）', 'onCancel: { dismissFinishDrawer() }' in wsview)
c('继续训练不改草稿（仅收起抽屉）', 'onResume: { dismissFinishDrawer() }' in wsview)
c('仅「完成训练」写入记录', 'viewModel.confirmFinish()' in wsview)

# —— 全屏训练总结页 ——
c('进入全屏总结页', 'SessionSummaryView' in summary)
c('顶部完成图标', 'SummaryCheckGlyph()' in summary)
c('图标为代码绘制 Shape', 'struct CheckmarkShape: Shape' in comp and 'func path(in rect: CGRect)' in comp)
c('标题「训练完成」', '"训练完成"' in summary)
c('展示本次训练日期', 'FormatterKit.fullDate(session.startedAt)' in summary)
c('展示总时长', 'FormatterKit.duration(seconds: session.durationSeconds)' in summary)

# —— 统计卡片 ——
c('统计卡横向展示', 'HStack(alignment: .top, spacing: DS.Spacing.item)' in summary)
c('训练时长卡', '"训练时长"' in summary)
c('总组数卡', '"总组数"' in summary)
c('总容量卡', '"总容量"' in summary)
c('有氧：距离', '"距离"' in summary and 'session.distanceKilometers' in summary)
c('有氧：平均配速', '"平均配速"' in summary and 'FormatterKit.pace(' in summary)
c('有氧：消耗估算', '"消耗估算"' in summary and 'session.kilocalories' in summary)
c('500ms 递增动画', '0.5 / Double(steps)' in comp)
c('减少动态效果直接显示最终值', 'accessibilityReduceMotion' in comp and 'displayed = target' in comp)

# —— 动作完成情况 ——
c('第二部分「动作完成情况」', '"动作完成情况"' in summary)
c('列出完成组数', 'completed.count)/\\(entries.count) 组' in comp)
c('列出实际重量 × 次数', 'FormatterKit.weight(best.weight)' in comp)
c('列出单动作容量', 'exerciseVolume' in comp)
c('点击展开每组记录', 'expandedExerciseIDs' in comp)

# —— 训练笔记 ——
c('第三部分「训练笔记」', '"训练笔记"' in comp)
c('空备注显示「未记录训练笔记」', '"未记录训练笔记"' in comp)
c('空备注提供编辑入口', '"添加笔记"' in comp)
c('有备注提供编辑入口', 'hasNote && !isEditing ? "编辑"' in comp)
c('编辑后立即更新本地记录', 'updateSessionNote' in summary)

# —— 底部按钮 ——
c('主按钮「返回训练首页」', 'title: "返回训练首页"' in summary)
c('次按钮「查看历史记录」', 'title: "查看历史记录"' in summary)
c('返回首页刷新最近训练', 'sessionSummaryReloadToken' in root)
c('查看历史跳转历史 Tab', 'selection = .history' in root)
# 页面 08 之后这条失效了一次：当时实现从「拿到 id 再主动滚过去」
# （scrollToHighlight）改成了「把 id 作为 highlightSessionID 一路传下去，
# 由列表项自己决定高亮」。断言跟着改成按现在的实现判。
c('历史页定位到本次训练',
  'pendingHistorySessionID' in root
  and 'highlightSessionID: pendingHistorySessionID' in root
  and 'highlightSessionID' in history
  and 'isHighlighted' in history)

# —— VoiceOver ——
c('总结标题为页面标题', '.accessibilityAddTraits(.isHeader)' in summary)
c('统计卡合并为完整语句', 'summaryAccessibilityText' in summary)
c('展开/收起有状态描述', '"已展开"' in comp and '"已收起"' in comp)

# —— 幂等与清理 ——
c('幂等：finishSession 守卫 endedAt', 'if session.endedAt == nil' in repo)
c('原子写入本地记录', '.atomic' in repo)
c('清理进行中训练状态', 'stopTicking()' in vm)
c('清理组间休息状态', 'RestNotification.cancelPending()' in vm)
c('无分享 / 社交 / 排行榜 / 云同步',
  not any(k in summary + comp + wscomp
          for k in ['UIActivityViewController', 'shareSheet', '排行榜', 'CloudKit',
                    'NSUbiquitousKeyValueStore']))

passed = sum(1 for _, ok, _ in checks if ok)
print('页面 07 规格审计：%d 项，%d 通过，%d 缺口' % (len(checks), passed, len(checks) - passed))
print('-' * 50)
for desc, ok, note in checks:
    if not ok:
        print('  [缺口] %s %s' % (desc, note))
if passed == len(checks):
    print('  全部通过')
