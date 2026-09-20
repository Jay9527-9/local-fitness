"""补齐缺失的动作媒体文件。

逐文件模式下，1600+ 个文件在 160 秒内即可完成，远快于整包 zip。
之前的停顿是 GitHub raw 的临时限流，加指数退避与降并发即可绕过。

用法：
    python Tools/download_media.py
"""
import json
import os
import random
import sys
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed

PROJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SEED = os.path.join(PROJ, "Resources", "exerciseLibrary.seed.json")
MEDIA_ROOT = os.path.join(PROJ, "Resources", "ExerciseMedia")

RAW = "https://raw.githubusercontent.com/hasaneyldrm/exercises-dataset/main/"
UA = {"User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)"}

# 并发降到 6，减少被限流概率
WORKERS = 6
MAX_ATTEMPTS = 6


def log(*a):
    print(*a, flush=True)


def needed() -> list:
    seed = json.load(open(SEED, encoding="utf-8"))
    out = []
    for item in seed:
        for key in ("image", "gifUrl"):
            rel = item.get(key, "")
            if rel:
                out.append(rel)
    return sorted(out)


def is_present(rel: str) -> bool:
    p = os.path.join(MEDIA_ROOT, rel.replace("/", os.sep))
    return os.path.isfile(p) and os.path.getsize(p) > 0


def fetch(rel: str) -> str:
    if is_present(rel):
        return "skip"

    dest = os.path.join(MEDIA_ROOT, rel.replace("/", os.sep))
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    tmp = dest + ".part"

    last_err = None
    for attempt in range(MAX_ATTEMPTS):
        try:
            req = urllib.request.Request(RAW + rel, headers=UA)
            with urllib.request.urlopen(req, timeout=60) as resp, open(tmp, "wb") as f:
                while True:
                    chunk = resp.read(131072)
                    if not chunk:
                        break
                    f.write(chunk)
            if os.path.getsize(tmp) == 0:
                raise IOError("empty response")
            os.replace(tmp, dest)
            return "ok"
        except urllib.error.HTTPError as e:
            last_err = f"HTTP {e.code}"
            # 429 / 403 是限流，退避更久
            if e.code in (403, 429):
                time.sleep(min(2 ** attempt, 20) + random.uniform(0, 1.5))
            else:
                time.sleep(1.0 * (attempt + 1))
        except Exception as e:
            last_err = str(e)
            time.sleep(1.5 * (attempt + 1))

    if os.path.exists(tmp):
        try:
            os.remove(tmp)
        except OSError:
            pass
    return f"fail:{last_err}"


def main() -> int:
    if not os.path.exists(SEED):
        log(f"!! 缺少种子数据: {SEED}")
        return 1

    all_files = needed()
    pending = [r for r in all_files if not is_present(r)]
    log(f"引用总数 {len(all_files)}，待补 {len(pending)}")

    if not pending:
        log("==> 已全部就位")
        return report(all_files)

    start = time.time()
    done = failed = 0
    failures = []

    with ThreadPoolExecutor(max_workers=WORKERS) as ex:
        futs = {ex.submit(fetch, r): r for r in pending}
        for i, fut in enumerate(as_completed(futs), 1):
            res = fut.result()
            if res == "ok":
                done += 1
            elif res.startswith("fail"):
                failed += 1
                failures.append((futs[fut], res))
            if i % 100 == 0 or i == len(pending):
                log(f"[{i}/{len(pending)}] 新下 {done} 失败 {failed} "
                    f"耗时 {time.time()-start:.0f}s")

    if failures:
        log(f"!! {len(failures)} 个仍失败（最多显示 15 条）:")
        for rel, err in failures[:15]:
            log("   ", rel, err)

    return report(all_files)


def report(all_files: list) -> int:
    missing = [r for r in all_files if not is_present(r)]
    count = total = 0
    for r, _, fs in os.walk(MEDIA_ROOT):
        for f in fs:
            if f.endswith(".part"):
                continue
            count += 1
            total += os.path.getsize(os.path.join(r, f))

    log("=" * 56)
    log(f"媒体就位 {count} 个文件，{total/1024/1024:.1f} MB")
    log(f"引用缺失 {len(missing)}")
    if missing:
        return 1
    log("==> 资源校验通过，可以打包 IPA")
    return 0


if __name__ == "__main__":
    sys.exit(main())
