#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
并行分块下载 GitHub Actions 构件（适用于 Azure Blob 域名被墙 / 单连接限速的场景）。

背景：`curl -L` 跟随 302 到 `productionresultssa*.blob.core.windows.net` 后，
单连接速度可能只有 20-30 KB/s（126 MB 要 1.5 小时）。Azure Blob 支持
`Accept-Ranges: bytes`，因此可以并行分块把总带宽抬起来。

签名 URL 有效期只有约 10 分钟，所以每个分块任务在开始前**重新取一次签名**，
并在失败时重试。

用法：
    python Tools/parallel_download.py <artifact_id> <output_path> [块数]

依赖：只用标准库 + 外部 curl（本机无 requests）。
"""

import os
import subprocess
import sys
import threading
import time

TOKEN = os.environ.get("GH_TOKEN", "")
REPO = os.environ.get("GH_REPO", "Jay9527-9/local-fitness")
PROXY = os.environ.get("HTTPS_PROXY", "http://127.0.0.1:10808")
API = "https://api.github.com/repos/%s/actions/artifacts/%s/zip"

CURL = r"C:\Windows\System32\curl.exe"
if not os.path.exists(CURL):
    CURL = "curl"


def signed_url(artifact_id):
    """取一次 302 后的签名 URL。"""
    for attempt in range(5):
        p = subprocess.run(
            [CURL, "-sI", "--ssl-no-revoke", "-x", PROXY,
             "-H", "Authorization: token %s" % TOKEN,
             API % (REPO, artifact_id)],
            capture_output=True, text=True, timeout=60,
        )
        for line in p.stdout.splitlines():
            if line.lower().startswith("location:"):
                return line.split(":", 1)[1].strip()
        time.sleep(2)
    raise RuntimeError("拿不到签名 URL（检查 token / 代理）")


def head_size(url):
    p = subprocess.run(
        [CURL, "-sI", "--ssl-no-revoke", "-x", PROXY, url],
        capture_output=True, text=True, timeout=60,
    )
    for line in p.stdout.splitlines():
        if line.lower().startswith("content-length:"):
            return int(line.split(":", 1)[1].strip())
    raise RuntimeError("拿不到 content-length")


def fetch_range(artifact_id, start, end, out_path, label, results):
    """下载 [start, end] 字节到 out_path。失败重试 6 次。"""
    for attempt in range(6):
        try:
            url = signed_url(artifact_id)          # 每次重新取，避免签名过期
            p = subprocess.run(
                [CURL, "-s", "--ssl-no-revoke", "-x", PROXY,
                 "-r", "%d-%d" % (start, end),
                 "-o", out_path, "-w", "%{http_code} %{size_download}",
                 "--max-time", "900", url],
                capture_output=True, text=True, timeout=960,
            )
            parts = p.stdout.strip().split()
            if len(parts) == 2 and parts[0] == "206":
                got = int(parts[1])
                expect = end - start + 1
                if got == expect:
                    results[label] = got
                    return
                print("  [%s] 长度不符 %d/%d，重试" % (label, got, expect))
            else:
                print("  [%s] http=%s，重试" % (label, p.stdout.strip()))
        except Exception as exc:                   # noqa: BLE001
            print("  [%s] 异常 %s，重试" % (label, exc))
        time.sleep(3)
    results[label] = -1


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2

    artifact_id = sys.argv[1]
    out_path = sys.argv[2]
    parts = int(sys.argv[3]) if len(sys.argv) > 3 else 8

    if not TOKEN:
        print("!! 需要设置环境变量 GH_TOKEN")
        return 2

    url = signed_url(artifact_id)
    total = head_size(url)
    print("总大小 %d 字节（%.1f MB），分 %d 块" % (total, total / 1048576.0, parts))

    chunk = (total + parts - 1) // parts
    tmpdir = out_path + ".parts"
    os.makedirs(tmpdir, exist_ok=True)

    results = {}
    threads = []
    started = time.time()

    for i in range(parts):
        start = i * chunk
        end = min(start + chunk - 1, total - 1)
        if start > end:
            break
        seg = os.path.join(tmpdir, "%03d.bin" % i)
        t = threading.Thread(
            target=fetch_range,
            args=(artifact_id, start, end, seg, "%03d" % i, results),
        )
        t.daemon = True
        t.start()
        threads.append(t)
        time.sleep(0.3)                            # 错开握手，别把代理打爆

    for t in threads:
        t.join()

    failed = [k for k, v in results.items() if v < 0]
    if failed:
        print("!! 有分块失败：%s（重跑本脚本会续传成功的块）" % ", ".join(sorted(failed)))
        return 1

    # 按序拼接
    print("拼接…")
    with open(out_path, "wb") as out:
        for i in range(parts):
            seg = os.path.join(tmpdir, "%03d.bin" % i)
            if not os.path.exists(seg):
                continue
            with open(seg, "rb") as f:
                while True:
                    buf = f.read(1024 * 1024)
                    if not buf:
                        break
                    out.write(buf)

    final = os.path.getsize(out_path)
    elapsed = time.time() - started
    print("完成：%s  = %d 字节（期望 %d）用时 %.1f 分钟，均速 %.0f KB/s"
          % (out_path, final, total, elapsed / 60.0,
             final / 1024.0 / max(elapsed, 1)))

    if final != total:
        print("!! 长度不符，不要使用该文件")
        return 1

    for i in range(parts):
        seg = os.path.join(tmpdir, "%03d.bin" % i)
        if os.path.exists(seg):
            os.remove(seg)
    os.rmdir(tmpdir)
    return 0


if __name__ == "__main__":
    sys.exit(main())
