#!/usr/bin/env python3
"""内层 IPA 结构断言：交付验收用。

层级说明（容易踩）：
  GitHub Actions 构件 zip  →  内含 FitnessApp-unsigned.ipa（真 IPA）
                            →  内含 Payload/FitnessApp.app/**（app 包内容）
本脚本自动逐层剥开，直到看见 `Payload/` 前缀，再对 app 包内容做断言。

修正历史：
  - v1 用 `n.count("/") == 1` 判 Info.plist / 可执行文件，对
    `Payload/FitnessApp.app/Info.plist`（两层斜杠）永不成立 → 误报「未找到」。
  - v2 又漏了「外层构件 zip 还包了一层」→ 报「条目总数 1」。
  本版两者都修：先递归剥壳，再按 `Payload/FitnessApp.app/` 前缀 + 精确层数匹配。
"""
import io
import os
import plistlib
import struct
import sys
import zipfile

APP_PREFIX = "Payload/FitnessApp.app/"
EXPECTED_BUNDLE_ID = "com.local.fitness.trainnote"
EXPECTED_MIN_OS = "16.0"
EXPECTED_MEDIA_EACH = 1324

MACHO_64_LE = 0xFEEDFACF
CPU_ARM64 = 12

FAILED = 0


def fail(msg: str) -> None:
    global FAILED
    FAILED += 1
    print(f"   !! {msg}")


def unwrap(path: str, max_depth: int = 4):
    """逐层剥 zip，直到某层的 namelist 含 `Payload/` 前缀。

    返回 (zipfile.ZipFile, names, chain)。
    """
    data = open(path, "rb").read()
    chain = [os.path.basename(path)]
    for _ in range(max_depth):
        zf = zipfile.ZipFile(io.BytesIO(data))
        names = zf.namelist()
        if any(n.startswith("Payload/") for n in names):
            return zf, names, chain
        # 找到唯一的 .ipa 条目，继续下钻
        ipas = [n for n in names if n.lower().endswith(".ipa")]
        if not ipas:
            return zf, names, chain
        inner = ipas[0]
        data = zf.read(inner)
        chain.append(f"{inner} ({len(data)} 字节)")
    return zf, names, chain


def is_direct_child(name: str) -> bool:
    return name.startswith(APP_PREFIX) and name.count("/") == 2


def main(path: str) -> int:
    print(f"校验目标: {path}  ({os.path.getsize(path)} 字节)")

    try:
        zf, names, chain = unwrap(path)
    except zipfile.BadZipFile as e:
        fail(f"不是有效 zip: {e}")
        print("\n结论：1 项断言失败 ❌")
        return 1

    print(f"0. 层级剥壳               : {' → '.join(chain)}")
    print(f"   条目总数               : {len(names)}")
    if not any(n.startswith("Payload/") for n in names):
        fail("剥壳后仍未见 Payload/ 前缀，构件结构异常")
        print("\n结论：1 项断言失败 ❌")
        return 1

    bad = zf.testzip()
    print(f"1. 内层 zip 完整性        : {'通过' if bad is None else '损坏 → ' + bad}")
    if bad is not None:
        fail("zip 完整性失败")

    jpg = [n for n in names if n.lower().endswith(".jpg")]
    gif = [n for n in names if n.lower().endswith(".gif")]
    ok_media = len(jpg) == EXPECTED_MEDIA_EACH and len(gif) == EXPECTED_MEDIA_EACH
    print(f"2. 媒体 jpg / gif         : {len(jpg)} / {len(gif)}"
          f"  (期望 {EXPECTED_MEDIA_EACH} / {EXPECTED_MEDIA_EACH})"
          f"{'' if ok_media else '  ← 不符'}")
    if not ok_media:
        fail("媒体条目数不符")

    # ---- 3. Info.plist ----
    plist_path = APP_PREFIX + "Info.plist"
    if plist_path not in names:
        fail("Info.plist 未找到")
        print(f"   疑似: {[n for n in names if 'Info.plist' in n][:5]}")
        return _report()

    data = zf.read(plist_path)
    info = plistlib.loads(data)
    bid = info.get("CFBundleIdentifier")
    minos = info.get("MinimumOSVersion")
    family = info.get("UIDeviceFamily")
    exe_name = info.get("CFBundleExecutable")
    print(f"3. Info.plist             : {plist_path} ({len(data)} 字节)")
    print(f"   CFBundleIdentifier     : {bid}{'' if bid == EXPECTED_BUNDLE_ID else '  ← 不符'}")
    print(f"   MinimumOSVersion       : {minos}{'' if minos == EXPECTED_MIN_OS else '  ← 不符'}")
    print(f"   UIDeviceFamily         : {family}{'' if family == [1, 2] else '  ← 不符'}")
    print(f"   CFBundleExecutable     : {exe_name}")
    if bid != EXPECTED_BUNDLE_ID:
        fail("CFBundleIdentifier 不符")
    if minos != EXPECTED_MIN_OS:
        fail(f"MinimumOSVersion 不符（应为 {EXPECTED_MIN_OS}）")
    if family != [1, 2]:
        fail("UIDeviceFamily 不符（应为 [1, 2]）")

    # ---- 4. 可执行文件 Mach-O ----
    exe_path = APP_PREFIX + (exe_name or "FitnessApp")
    if exe_path not in names:
        fail(f"可执行文件未找到: {exe_path}")
        print(f"4. 可执行条目             : !! 未找到 {exe_path}")
    else:
        blob = zf.read(exe_path)
        magic = struct.unpack("<I", blob[:4])[0]
        cputype = struct.unpack("<I", blob[4:8])[0]
        is_macho = magic == MACHO_64_LE
        is_arm64 = (cputype & 0xFFFFFF) == CPU_ARM64
        print(f"4. 可执行条目             : {exe_path}")
        print(f"   大小 / Mach-O magic    : {len(blob)} 字节 / "
              f"0x{magic:08x} ({'MH_MAGIC_64' if is_macho else '未知'})")
        print(f"   cputype                : {cputype & 0xFFFFFF} "
              f"({'arm64' if is_arm64 else '非 arm64'})")
        if not is_macho:
            fail("不是 64 位 Mach-O")
        if not is_arm64:
            fail("不是 arm64")

    # ---- 5. 未签名断言 ----
    codesig = [n for n in names if "_CodeSignature" in n]
    mobile = [n for n in names if n.lower().endswith(".mobileprovision")]
    print(f"5. _CodeSignature 条目    : {len(codesig)}  (期望 0，未签名)"
          f"{'' if not codesig else '  ← 不符'}")
    print(f"   mobileprovision 条目   : {len(mobile)}  (期望 0)"
          f"{'' if not mobile else '  ← 不符'}")
    if codesig:
        fail("存在 _CodeSignature，不是未签名包")
    if mobile:
        fail("存在 mobileprovision")

    # ---- 6. 种子数据 ----
    seed = [n for n in names if n.endswith("exerciseLibrary.seed.json")]
    print(f"6. 种子数据条目           : {seed}")
    if not seed:
        fail("种子数据缺失")
    elif "Payload/FitnessApp.app/exerciseLibrary.seed.json" not in seed:
        fail("种子数据路径不在 app 包根")

    return _report()


def _report() -> int:
    print()
    if FAILED == 0:
        print("结论：全部结构断言通过 ✅")
        return 0
    print(f"结论：{FAILED} 项断言失败 ❌")
    return 1


if __name__ == "__main__":
    target = sys.argv[1] if len(sys.argv) > 1 else "FitnessApp-unsigned-v2.ipa"
    if not os.path.exists(target):
        print(f"找不到 {target}")
        sys.exit(2)
    sys.exit(main(target))
