#!/usr/bin/env python3
"""
Official Antigravity CLI (agy) statusLine bridge for GPT-喵.
Reads the documented JSON payload from stdin, extracts real official quota
fields (remaining_fraction, reset_time, reset_in_seconds, plan_tier), and
writes them atomically to plugins/gpt-miao/data/live_quota.json.
Never saves email or conversation text.
"""

import datetime
import json
import sys
from pathlib import Path

if sys.platform == "win32":
    sys.stdin.reconfigure(encoding="utf-8", errors="replace")
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

PLUGIN_ROOT = Path(__file__).resolve().parent.parent
DATA_DIR = PLUGIN_ROOT / "data"
LIVE_QUOTA_PATH = DATA_DIR / "live_quota.json"


def infer_label(key: str, reset_sec) -> str:
    k = key.lower()
    if "5h" in k or "five" in k or "hour" in k:
        return "5 小时"
    if "week" in k or "7d" in k:
        return "每周"
    if "month" in k or "30d" in k:
        return "30 天"
    if "day" in k or "24h" in k:
        return "24 小时"
    if isinstance(reset_sec, (int, float)):
        if reset_sec <= 6 * 3600:
            return "5 小时"
        if reset_sec <= 8 * 86400:
            return "每周"
    return key


def main():
    raw = sys.stdin.read().strip()
    if not raw:
        return
    try:
        payload = json.loads(raw)
    except Exception:
        return

    quota = payload.get("quota")
    plan_tier = payload.get("plan_tier") or "Antigravity"
    windows = []

    if isinstance(quota, dict):
        for key, item in quota.items():
            if not isinstance(item, dict) or item.get("disabled"):
                continue
            frac = item.get("remaining_fraction")
            if frac is None:
                continue
            try:
                pct = max(0, min(100, round(float(frac) * 100)))
            except Exception:
                continue
            reset_sec = item.get("reset_in_seconds")
            reset_time = item.get("reset_time") or ""
            windows.append({
                "key": key,
                "label": infer_label(key, reset_sec),
                "leftPct": pct,
                "resetTime": reset_time,
                "resetInSeconds": int(reset_sec) if isinstance(reset_sec, (int, float)) else None,
            })

    # Prioritize Gemini primary windows (gemini-5h, gemini-weekly) first, then other groups
    def sort_key(w):
        k = w["key"].lower()
        if k == "gemini-5h":
            return (0, 0)
        if k == "gemini-weekly":
            return (0, 1)
        if k.startswith("gemini"):
            return (1, w["resetInSeconds"] if w["resetInSeconds"] is not None else 10**9)
        return (2, w["resetInSeconds"] if w["resetInSeconds"] is not None else 10**9)

    windows.sort(key=sort_key)

    if windows:
        DATA_DIR.mkdir(parents=True, exist_ok=True)
        now_utc = datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00", "Z")
        out = {
            "source": "agy_statusline",
            "updatedAtUtc": now_utc,
            "planTier": str(plan_tier),
            "windows": windows,
        }
        tmp = LIVE_QUOTA_PATH.with_suffix(".json.tmp")
        tmp.write_text(json.dumps(out, ensure_ascii=False, indent=2), encoding="utf-8")
        tmp.replace(LIVE_QUOTA_PATH)

        parts = [f"{w['label']} {w['leftPct']}%" for w in windows[:2]]
        sys.stdout.write(f"GPT-喵 · {plan_tier} · " + " | ".join(parts) + "\n")
    else:
        sys.stdout.write(f"GPT-喵 · {plan_tier} · 等待额度\n")


if __name__ == "__main__":
    main()
