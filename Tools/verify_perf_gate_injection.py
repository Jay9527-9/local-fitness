#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""L8 新增断言（第 6 组）的注入回归验证。

对每条新断言注入一次真实回归（改源码），确认门禁精确报红；再还原确认全绿。
全程用 Python 读写文件，不经 shell。
"""
import shutil
import subprocess
import sys

ROOT = r"C:\Users\yangj\WorkBuddy\2026-09-19-12-55-00\FitnessApp"
GATE = ["python", "Tools/audit_exercise_library_perf.py"]

FILES = {
    "root": ROOT + r"\FitnessApp\Features\RootView.swift",
    "vm": ROOT + r"\FitnessApp\Features\Exercises\ExerciseLibraryViewModel.swift",
    "rep": ROOT + r"\FitnessApp\Data\JSONFitnessRepository.swift",
}

# (标签, 文件key, 旧串, 新串, 期望报红的断言关键词)
INJECTIONS = [
    (
        "VM 退回 Tab 内 StateObject",
        "root",
        "    @ObservedObject var viewModel: ExerciseLibraryViewModel",
        "    @StateObject private var viewModel: ExerciseLibraryViewModel",
        "不再自建 StateObject VM",
    ),
    (
        "load() 无条件打回 loading",
        "vm",
        "        if allExercises.isEmpty { loadState = .loading }",
        "        loadState = .loading",
        "静默刷新",
    ),
    (
        "exercises 缓存失效钩子被删",
        "rep",
        "    private var exercises: [ExerciseLibraryItem] = [] {\n        didSet { invalidateExerciseCaches() }\n    }",
        "    private var exercises: [ExerciseLibraryItem] = []",
        "didSet",
    ),
    (
        "底栏渐隐被删",
        "root",
        "        .overlay(alignment: .top) {\n            LinearGradient(",
        "        .overlay(alignment: .top) {\n            FadeUnused(",
        "渐隐过渡",
    ),
]


def run_gate():
    p = subprocess.run(GATE, cwd=ROOT, capture_output=True)
    return p.returncode, p.stdout.decode("utf-8", errors="replace")


def main():
    failures = []
    for label, key, old, new, expect in INJECTIONS:
        path = FILES[key]
        backup = path + ".bak"
        shutil.copyfile(path, backup)
        try:
            with open(path, encoding="utf-8") as f:
                src = f.read()
            if old not in src:
                failures.append("%s：注入锚点未找到（old 串不匹配）" % label)
                continue
            with open(path, "w", encoding="utf-8", newline="") as f:
                f.write(src.replace(old, new, 1))

            rc, out = run_gate()
            red_ok = rc != 0 and expect in out
            if not red_ok:
                failures.append(
                    "%s：注入后期望报红「%s」，实际 rc=%d，报红内容=%s"
                    % (label, expect, rc, out[-400:])
                )
        finally:
            shutil.move(backup, path)

    rc, out = run_gate()
    if rc != 0:
        failures.append("还原后门禁仍报红：\n" + out[-600:])

    print("=" * 60)
    if failures:
        print("注入验证失败 %d 项：" % len(failures))
        for f in failures:
            print("  ✗ " + f)
        return 1
    print("注入验证 %d 项全部通过：每条新断言都能精确报红，还原后全绿。" % len(INJECTIONS))
    return 0


if __name__ == "__main__":
    sys.exit(main())
