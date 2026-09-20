#!/usr/bin/env python3
"""资源完整性校验。

检查 exerciseLibrary.seed.json 中引用的每个媒体文件是否都已下载到
Resources/ExerciseMedia/ 下。用于打包 IPA 前的最后一道校验。

用法：
    python3 Tools/verify_resources.py
退出码非 0 表示有缺失，不应继续打包。
"""
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SEED = os.path.join(ROOT, "Resources", "exerciseLibrary.seed.json")
MEDIA = os.path.join(ROOT, "Resources", "ExerciseMedia")


def main() -> int:
    if not os.path.exists(SEED):
        print(f"!! 缺少种子数据: {SEED}")
        return 1
    if not os.path.isdir(MEDIA):
        print(f"!! 缺少媒体目录: {MEDIA}")
        print("   先运行: python3 Tools/download_media.py")
        return 1

    seed = json.load(open(SEED, encoding="utf-8"))
    print(f"种子记录数: {len(seed)}")

    expected = []
    for item in seed:
        for key in ("image", "gifUrl"):
            rel = item.get(key, "")
            if rel:
                expected.append(rel)

    missing = []
    present = 0
    total_bytes = 0
    for rel in expected:
        path = os.path.join(MEDIA, rel.replace("/", os.sep))
        if os.path.isfile(path) and os.path.getsize(path) > 0:
            present += 1
            total_bytes += os.path.getsize(path)
        else:
            missing.append(rel)

    img_expected = sum(1 for r in expected if r.startswith("images/"))
    gif_expected = sum(1 for r in expected if r.startswith("videos/"))

    print(f"引用总数: {len(expected)}  (图片 {img_expected} / 动画 {gif_expected})")
    print(f"已就位  : {present}")
    print(f"缺失    : {len(missing)}")
    print(f"媒体体积: {total_bytes / 1024 / 1024:.1f} MB")

    # 统计实际磁盘上的文件数，检测多余残留
    on_disk = 0
    for r, _, fs in os.walk(MEDIA):
        for f in fs:
            if f.endswith(".part"):
                continue
            on_disk += 1
    print(f"磁盘文件: {on_disk}")

    if missing:
        print()
        print("缺失清单（最多显示 30 条）:")
        for rel in missing[:30]:
            print("   ", rel)
        if len(missing) > 30:
            print(f"    ... 另有 {len(missing) - 30} 条")
        print()
        print("!! 校验失败，请重新运行 Tools/download_media.py")
        return 1

    print()
    print("==> 资源校验通过，可以打包 IPA")
    return 0


if __name__ == "__main__":
    sys.exit(main())
