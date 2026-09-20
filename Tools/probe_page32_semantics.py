#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""页面 32 值语义推演（有氧总结：模板名 + 配速）。"""


def save_as_template(name, note):
    n = name.strip()
    if not n:
        return False
    return True


def pace_text(seconds_per_km):
    if not seconds_per_km or seconds_per_km <= 0:
        return None
    m = int(seconds_per_km) // 60
    s = int(seconds_per_km) % 60
    return f"{m}′{s:02d}″/公里"


ok = True
count = 0


def expect(label, got, want):
    global ok, count
    count += 1
    good = (got == want)
    ok = ok and good
    print(f"  {'[ok]  ' if good else '[FAIL]'} {label}: 得 {got!r}, 期望 {want!r}")


print("[1 保存为模板]")
expect("空名拒绝", save_as_template("   ", None), False)
expect("有名字允许", save_as_template("晨跑 5 公里", None), True)

print("[2 配速]")
expect("配速文案", pace_text(330), "5′30″/公里")
expect("无配速 nil", pace_text(None), None)

print("\n" + "=" * 72)
print(f"全部{'通过' if ok else '存在失败'}：{count} 项断言")
import sys
sys.exit(0 if ok else 1)
