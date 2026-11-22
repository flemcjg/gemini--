#!/usr/bin/env python3
"""
GPT-喵 Antigravity MCP Server & MCP App Host
Zero-dependency Python 3 stdio MCP server supporting:
- ui://gpt-miao/app.html (MCP App for aux_pane, global sidebar, & inline)
- Local Antigravity USER_INPUT usage counter + anchor calibration against real quota
- Custom catgirl quotes & shared state sync with Windows WPF desktop widget
- Start / stop / status control for the Windows transparent overlay widget
"""

import argparse
import base64
import datetime
import json
import os
import subprocess
import sys
import time
from pathlib import Path

if sys.platform == "win32":
    sys.stdin.reconfigure(encoding="utf-8", errors="replace")
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

PLUGIN_ROOT = Path(__file__).resolve().parent.parent
ASSETS_DIR = PLUGIN_ROOT / "assets"
WIDGET_DIR = PLUGIN_ROOT / "widget"
APP_HTML_PATH = Path(__file__).resolve().parent / "app_ui.html"
APP_URI = "ui://gpt-miao/app.html"

DEFAULT_CONFIG = {
    "planName": "Gemini Models · 估算",
    "shortLabel": "5 小时",
    "shortBudget": 160,        # 约 160 次用户提问 ≈ 100%（可校准）
    "weekLabel": "每周",
    "weekBudget": 650,         # 约 650 次用户提问 ≈ 100%（可校准）
    "showWeekRow": True,
    "displayMode": "follow",   # "follow" (Antigravity window) | "desktop" (free drag)
    "keepInsideScreen": True,  # 碰撞限制：不让边框离开桌面屏幕
    "topmost": True,
    "scale": 100,
    "volume": 70,
    "muted": False,
    "musicRhythm": False,
    "autoHideSeconds": 5,
    "autoHideEnabled": True,
    "autoQuoteEnabled": False,
    "autoQuoteMinutes": 5,     # 5 | 10 | 30
    "replyNotifyEnabled": True,
    # 锚点校准字段（校准后基于新 USER_INPUT 增量扣减）
    "calibratedAtUtc": "",
    "calibratedShortPct": None,
    "calibratedWeekPct": None,
    "shortResetAtUtc": "",
    "weekResetAtUtc": "",
}


def get_shared_dir(data_dir: Path) -> Path:
    # Use plugin's own data/ directory (never %LOCALAPPDATA%, which Microsoft Store Python virtualizes!)
    p = PLUGIN_ROOT / "data"
    p.mkdir(parents=True, exist_ok=True)
    return p


def parse_iso_utc(s: str):
    if not s:
        return None
    try:
        dt = datetime.datetime.fromisoformat(s.replace("Z", "+00:00"))
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=datetime.timezone.utc)
        return dt.astimezone(datetime.timezone.utc).timestamp()
    except Exception:
        return None


def fmt_remaining(sec: float) -> str:
    sec = max(0, int(sec))
    days, rem = divmod(sec, 86400)
    hrs, rem = divmod(rem, 3600)
    mins = rem // 60
    if days > 0:
        return f"{days} 天 {hrs} 小时后刷新"
    if hrs > 0:
        return f"{hrs} 小时 {mins} 分后刷新"
    return f"{mins} 分钟后刷新"


class GptMiaoStore:
    def __init__(self, data_dir: Path):
        self.data_dir = data_dir
        self.data_dir.mkdir(parents=True, exist_ok=True)
        self.shared_dir = get_shared_dir(data_dir)
        self.config_path = self.shared_dir / "config.json"
        self.quotes_path = self.shared_dir / "quotes.json"
        self.snapshot_path = self.shared_dir / "snapshot.json"
        self.live_quota_path = self.shared_dir / "live_quota.json"
        self.pid_path = self.shared_dir / "widget.pid"
        self._ensure_defaults()

    def _ensure_defaults(self):
        if not self.config_path.exists():
            self._write_json(self.config_path, DEFAULT_CONFIG)
        if not self.quotes_path.exists():
            default_quotes = ASSETS_DIR / "quotes.json"
            if default_quotes.exists():
                self.quotes_path.write_text(default_quotes.read_text(encoding="utf-8"), encoding="utf-8")
            else:
                self._write_json(self.quotes_path, {"version": 1, "quotes": [{"text": "我是啥喵？", "weight": 3.0}]})

    def _read_json(self, path: Path, fallback):
        try:
            return json.loads(path.read_text(encoding="utf-8-sig"))
        except Exception:
            return fallback

    def _write_json(self, path: Path, obj):
        tmp = path.with_suffix(path.suffix + ".tmp")
        tmp.write_text(json.dumps(obj, ensure_ascii=False, indent=2), encoding="utf-8")
        tmp.replace(path)

    def get_config(self) -> dict:
        cfg = dict(DEFAULT_CONFIG)
        cfg.update(self._read_json(self.config_path, {}))
        return cfg

    def update_config(self, patch: dict) -> dict:
        cfg = self.get_config()
        for k, v in patch.items():
            if k in DEFAULT_CONFIG and v is not None:
                cfg[k] = v
        cfg["shortBudget"] = max(10, min(10000, int(cfg.get("shortBudget", 160))))
        cfg["weekBudget"] = max(20, min(100000, int(cfg.get("weekBudget", 650))))
        cfg["scale"] = max(60, min(250, int(cfg.get("scale", 100))))
        cfg["volume"] = max(0, min(100, int(cfg.get("volume", 70))))
        if int(cfg.get("autoQuoteMinutes", 5)) not in (5, 10, 30):
            cfg["autoQuoteMinutes"] = 5
        else:
            cfg["autoQuoteMinutes"] = int(cfg["autoQuoteMinutes"])
        self._write_json(self.config_path, cfg)
        return cfg

    def calibrate(self, short_pct: int, week_pct: int, short_reset_minutes: int = 300, week_reset_hours: int = 168) -> dict:
        now = datetime.datetime.now(datetime.timezone.utc)
        patch = {
            "calibratedAtUtc": now.isoformat().replace("+00:00", "Z"),
            "calibratedShortPct": max(0, min(100, int(short_pct))),
            "calibratedWeekPct": max(0, min(100, int(week_pct))),
            "shortResetAtUtc": (now + datetime.timedelta(minutes=max(1, int(short_reset_minutes)))).isoformat().replace("+00:00", "Z"),
            "weekResetAtUtc": (now + datetime.timedelta(hours=max(1, int(week_reset_hours)))).isoformat().replace("+00:00", "Z"),
        }
        return self.update_config(patch)

    def get_quotes(self) -> list:
        data = self._read_json(self.quotes_path, {"version": 1, "quotes": []})
        quotes = data.get("quotes", [])
        return quotes if quotes else [{"text": "我是啥喵？", "weight": 3.0}]

    def add_quote(self, text: str, weight: float = 1.0) -> list:
        text = text.strip()
        if not text:
            return self.get_quotes()
        quotes = self.get_quotes()
        quotes.append({"text": text, "weight": max(0.1, float(weight))})
        self._write_json(self.quotes_path, {"version": 1, "quotes": quotes})
        return quotes

    def reset_quotes(self) -> list:
        default_quotes = ASSETS_DIR / "quotes.json"
        if default_quotes.exists():
            self.quotes_path.write_text(default_quotes.read_text(encoding="utf-8"), encoding="utf-8")
        return self.get_quotes()

    def read_live_agy_quota(self):
        if not self.live_quota_path.exists():
            return None
        data = self._read_json(self.live_quota_path, None)
        if not isinstance(data, dict) or not data.get("windows"):
            return None
        now = time.time()
        upd_ts = parse_iso_utc(data.get("updatedAtUtc", ""))
        stale = (upd_ts is None) or ((now - upd_ts) > 900)
        tier = data.get("planTier") or "Antigravity"
        header = f"{tier} · agy {'缓存' if stale else '实时'}"
        wins = data["windows"]

        def build_row(w):
            rt = parse_iso_utc(w.get("resetTime", ""))
            if rt is not None:
                rtxt = fmt_remaining(rt - now)
            elif w.get("resetInSeconds") is not None:
                rtxt = fmt_remaining(float(w["resetInSeconds"]))
            else:
                rtxt = "官方实时额度"
            return {
                "label": w.get("label") or w.get("key") or "额度",
                "used": 0,
                "budget": 100,
                "leftPct": max(0, min(100, int(w.get("leftPct", 0)))),
                "resetText": rtxt,
            }

        short_row = build_row(wins[0])
        if len(wins) >= 2:
            week_row = build_row(wins[1])
            week_row["visible"] = True
        else:
            week_row = {"label": "每周", "used": 0, "budget": 100, "leftPct": 100, "resetText": "", "visible": False}

        return {
            "updatedAt": datetime.datetime.now().strftime("%H:%M:%S"),
            "planName": header,
            "source": "agy_statusline",
            "calibrated": True,
            "short": short_row,
            "week": week_row,
            "conversations7d": 0,
        }

    def scan_local_usage(self) -> dict:
        """
        Prefers official agy CLI statusLine live_quota.json when present;
        otherwise falls back to privacy-safe local USER_INPUT counter + calibration anchor.
        """
        live = self.read_live_agy_quota()
        if live is not None:
            self._write_json(self.snapshot_path, live)
            return live

        cfg = self.get_config()
        now = time.time()
        short_cutoff = now - 5 * 3600
        week_cutoff = now - 7 * 24 * 3600
        cal_ts = parse_iso_utc(cfg.get("calibratedAtUtc", ""))
        short_reset_ts = parse_iso_utc(cfg.get("shortResetAtUtc", ""))
        week_reset_ts = parse_iso_utc(cfg.get("weekResetAtUtc", ""))

        brain_dir = Path.home() / ".gemini" / "antigravity" / "brain"
        short_turns = []
        week_turns = 0
        delta_after_cal = 0
        conversations_7d = 0

        if brain_dir.exists():
            try:
                for conv in brain_dir.iterdir():
                    if not conv.is_dir():
                        continue
                    log_file = conv / ".system_generated" / "logs" / "transcript.jsonl"
                    if not log_file.exists():
                        continue
                    try:
                        if log_file.stat().st_mtime < week_cutoff:
                            continue
                    except OSError:
                        continue
                    conversations_7d += 1
                    try:
                        with log_file.open("r", encoding="utf-8", errors="ignore") as f:
                            for line in f:
                                if '"USER_INPUT"' not in line:
                                    continue
                                ts_idx = line.find('"created_at"')
                                if ts_idx < 0:
                                    continue
                                q1 = line.find('"', ts_idx + 12)
                                if q1 < 0:
                                    continue
                                q2 = line.find('"', q1 + 1)
                                if q2 < 0:
                                    continue
                                ts = parse_iso_utc(line[q1 + 1 : q2])
                                if ts is None:
                                    continue
                                if ts >= week_cutoff:
                                    week_turns += 1
                                    if ts >= short_cutoff:
                                        short_turns.append(ts)
                                    if cal_ts is not None and ts > cal_ts:
                                        delta_after_cal += 1
                    except OSError:
                        continue
            except OSError:
                pass

        short_budget = cfg["shortBudget"]
        week_budget = cfg["weekBudget"]

        # Short window percentage
        if cal_ts is not None and cfg.get("calibratedShortPct") is not None and (short_reset_ts is None or now < short_reset_ts):
            base_s = float(cfg["calibratedShortPct"])
            short_left_pct = max(0, min(100, round(base_s - (delta_after_cal / max(1, short_budget)) * 100.0)))
            short_reset = fmt_remaining(short_reset_ts - now) if short_reset_ts else "已校准 · 5 小时窗口"
        else:
            short_left_pct = max(0, min(100, round((1.0 - len(short_turns) / max(1, short_budget)) * 100.0)))
            if short_turns:
                short_reset = fmt_remaining((min(short_turns) + 5 * 3600) - now)
            else:
                short_reset = "当前 5 小时窗口满额"

        # Weekly window percentage
        if cal_ts is not None and cfg.get("calibratedWeekPct") is not None and (week_reset_ts is None or now < week_reset_ts):
            base_w = float(cfg["calibratedWeekPct"])
            week_left_pct = max(0, min(100, round(base_w - (delta_after_cal / max(1, week_budget)) * 100.0)))
            week_reset = fmt_remaining(week_reset_ts - now) if week_reset_ts else "已校准 · 每周窗口"
        else:
            week_left_pct = max(0, min(100, round((1.0 - week_turns / max(1, week_budget)) * 100.0)))
            week_reset = f"近 7 天 {conversations_7d} 会话 · {week_turns} 轮"

        snap = {
            "updatedAt": datetime.datetime.now().strftime("%H:%M:%S"),
            "planName": cfg["planName"],
            "calibrated": cal_ts is not None,
            "short": {
                "label": cfg["shortLabel"],
                "used": len(short_turns),
                "budget": short_budget,
                "leftPct": short_left_pct,
                "resetText": short_reset,
            },
            "week": {
                "label": cfg["weekLabel"],
                "used": week_turns,
                "budget": week_budget,
                "leftPct": week_left_pct,
                "resetText": week_reset,
                "visible": bool(cfg.get("showWeekRow", True)),
            },
            "conversations7d": conversations_7d,
        }
        self._write_json(self.snapshot_path, snap)
        return snap

    def is_widget_running(self) -> bool:
        if not self.pid_path.exists():
            return False
        try:
            pid = int(self.pid_path.read_text(encoding="utf-8").strip())
            if pid <= 0:
                return False
            if sys.platform == "win32":
                out = subprocess.check_output(
                    ["tasklist", "/FI", f"PID eq {pid}", "/NH"],
                    creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
                    text=True,
                    errors="ignore",
                )
                return str(pid) in out
        except Exception:
            return False
        return False

    def start_widget(self) -> dict:
        self.scan_local_usage()
        if self.is_widget_running():
            return {"running": True, "message": "Windows 透明悬浮挂件已在运行中喵～"}
        launch_vbs = WIDGET_DIR / "launch.vbs"
        if sys.platform == "win32" and launch_vbs.exists():
            subprocess.Popen(
                ["wscript.exe", str(launch_vbs)],
                cwd=str(WIDGET_DIR),
                creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0) | getattr(subprocess, "DETACHED_PROCESS", 0),
            )
            time.sleep(0.5)
            return {"running": True, "message": "已启动 Windows 透明悬浮挂件（含屏幕边界碰撞限制）喵！"}
        return {"running": False, "message": "当前环境不支持 Windows WPF 悬浮挂件。"}

    def stop_widget(self) -> dict:
        stopped = False
        if self.pid_path.exists():
            try:
                pid = int(self.pid_path.read_text(encoding="utf-8").strip())
                if pid > 0 and sys.platform == "win32":
                    subprocess.run(
                        ["taskkill", "/PID", str(pid), "/F"],
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL,
                        creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
                    )
                    stopped = True
            except Exception:
                pass
            try:
                self.pid_path.unlink(missing_ok=True)
            except Exception:
                pass
        return {
            "running": False,
            "message": "已关闭 Windows 透明悬浮挂件喵。" if stopped else "悬浮挂件当前未运行。",
        }

    def get_full_state(self) -> dict:
        return {
            "usage": self.scan_local_usage(),
            "config": self.get_config(),
            "quotes": self.get_quotes(),
            "widgetRunning": self.is_widget_running(),
            "pluginRoot": str(PLUGIN_ROOT),
        }


def build_app_html() -> str:
    html = APP_HTML_PATH.read_text(encoding="utf-8")
    png_path = ASSETS_DIR / "catgirl-bust.png"
    if png_path.exists():
        b64 = base64.b64encode(png_path.read_bytes()).decode("ascii")
        html = html.replace("__CATGIRL_DATA_URI__", f"data:image/png;base64,{b64}")
    return html


def send_response(obj: dict):
    sys.stdout.write(json.dumps(obj, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--data-dir", default=str(Path.home() / ".gemini" / "config" / "plugins" / "gpt-miao" / "data"))
    args = parser.parse_args()
    store = GptMiaoStore(Path(args.data_dir))

    tools_def = [
        {
            "name": "open_gpt_miao",
            "title": "GPT-喵",
            "description": "打开「GPT-喵」紫发猫娘交互面板，展示「我是啥喵？」思考气泡、Antigravity 额度估算与校准，并可一键启停 Windows 透明悬浮挂件。",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "view": {"type": "string", "enum": ["quote", "quota"]},
                },
            },
            "_meta": {
                "ui": {"resourceUri": APP_URI},
                "com.google.antigravity/ui": {
                    "entrypoints": [
                        {"type": "aux_pane", "title": "GPT-喵"},
                        {"type": "global", "title": "GPT-喵"},
                    ]
                },
            },
        },
        {
            "name": "toggle_desktop_widget",
            "title": "启停 Windows 桌面悬浮挂件",
            "description": "启动、关闭或查询 Windows 透明桌面猫娘悬浮挂件。",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "action": {"type": "string", "enum": ["start", "stop", "status"]},
                },
            },
        },
        {
            "name": "update_gpt_miao_config",
            "title": "更新 GPT-喵 预算、校准与语录",
            "description": "更新 5 小时 / 每周额度校准值、预算上限、屏幕碰撞限制或添加猫娘语录。",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "shortPct": {"type": "integer", "description": "校准当前 5 小时剩余百分比 (0-100)"},
                    "weekPct": {"type": "integer", "description": "校准当前每周剩余百分比 (0-100)"},
                    "shortResetMinutes": {"type": "integer", "description": "距离 5 小时额度刷新的分钟数"},
                    "weekResetHours": {"type": "integer", "description": "距离每周额度刷新的小时数"},
                    "shortBudget": {"type": "integer"},
                    "weekBudget": {"type": "integer"},
                    "scale": {"type": "integer", "description": "挂件缩放百分比（60-250）"},
                    "keepInsideScreen": {"type": "boolean"},
                    "displayMode": {"type": "string", "enum": ["follow", "desktop"]},
                    "addQuote": {"type": "string"},
                },
            },
        },
        {
            "name": "gpt_miao_app_action",
            "title": "GPT-喵 面板内部交互",
            "description": "供 GPT-喵 MCP App 前端调用的内部状态读写与挂件控制工具。",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "action": {"type": "string"},
                    "payload": {"type": "object"},
                },
                "required": ["action"],
            },
            "_meta": {"ui": {"visibility": ["app"]}},
        },
    ]

    for raw in sys.stdin:
        line = raw.strip()
        if not line:
            continue
        try:
            req = json.loads(line)
        except Exception:
            continue

        req_id = req.get("id")
        method = req.get("method", "")
        params = req.get("params") or {}
        if req_id is None:
            continue

        try:
            if method == "initialize":
                proto = params.get("protocolVersion", "2024-11-05")
                send_response({
                    "jsonrpc": "2.0",
                    "id": req_id,
                    "result": {
                        "protocolVersion": proto,
                        "capabilities": {
                            "tools": {"listChanged": False},
                            "resources": {"subscribe": False, "listChanged": False},
                        },
                        "serverInfo": {"name": "gpt-miao", "version": "1.1.0"},
                    },
                })
            elif method == "ping":
                send_response({"jsonrpc": "2.0", "id": req_id, "result": {}})
            elif method == "resources/list":
                send_response({
                    "jsonrpc": "2.0",
                    "id": req_id,
                    "result": {
                        "resources": [{
                            "uri": APP_URI,
                            "name": "GPT-喵 交互面板",
                            "description": "Antigravity 紫发猫娘额度与语录挂件界面",
                            "mimeType": "text/html;profile=mcp-app",
                            "_meta": {"ui": {"prefersBorder": False}},
                        }]
                    },
                })
            elif method == "resources/read":
                if params.get("uri") == APP_URI:
                    send_response({
                        "jsonrpc": "2.0",
                        "id": req_id,
                        "result": {
                            "contents": [{
                                "uri": APP_URI,
                                "mimeType": "text/html;profile=mcp-app",
                                "text": build_app_html(),
                            }]
                        },
                    })
                else:
                    send_response({"jsonrpc": "2.0", "id": req_id, "error": {"code": -32602, "message": "Unknown resource"}})
            elif method == "tools/list":
                send_response({"jsonrpc": "2.0", "id": req_id, "result": {"tools": tools_def}})
            elif method == "tools/call":
                tname = params.get("name")
                targs = params.get("arguments") or {}

                if tname == "open_gpt_miao":
                    state = store.get_full_state()
                    state["initialView"] = targs.get("view", "quote")
                    u = state["usage"]
                    summary = (
                        f"已打开 GPT-喵 面板：5 小时剩余 {u['short']['leftPct']}% ({u['short']['resetText']})，"
                        f"每周剩余 {u['week']['leftPct']}% ({u['week']['resetText']})。"
                    )
                    send_response({
                        "jsonrpc": "2.0",
                        "id": req_id,
                        "result": {"content": [{"type": "text", "text": summary}], "structuredContent": state},
                    })
                elif tname == "toggle_desktop_widget":
                    act = targs.get("action", "start")
                    res = store.start_widget() if act == "start" else store.stop_widget() if act == "stop" else {
                        "running": store.is_widget_running(),
                        "message": "悬浮挂件运行中" if store.is_widget_running() else "悬浮挂件未启动",
                    }
                    send_response({
                        "jsonrpc": "2.0",
                        "id": req_id,
                        "result": {"content": [{"type": "text", "text": res["message"]}], "structuredContent": res},
                    })
                elif tname == "update_gpt_miao_config":
                    if targs.get("shortPct") is not None or targs.get("weekPct") is not None:
                        cfg = store.get_config()
                        store.calibrate(
                            short_pct=targs.get("shortPct", cfg.get("calibratedShortPct") or 100),
                            week_pct=targs.get("weekPct", cfg.get("calibratedWeekPct") or 100),
                            short_reset_minutes=targs.get("shortResetMinutes", 300),
                            week_reset_hours=targs.get("weekResetHours", 168),
                        )
                    patch = {k: v for k, v in targs.items() if k not in ("addQuote", "shortPct", "weekPct", "shortResetMinutes", "weekResetHours")}
                    if patch:
                        store.update_config(patch)
                    if targs.get("addQuote"):
                        store.add_quote(str(targs["addQuote"]))
                    state = store.get_full_state()
                    send_response({
                        "jsonrpc": "2.0",
                        "id": req_id,
                        "result": {"content": [{"type": "text", "text": "已更新 GPT-喵 校准与设置。"}], "structuredContent": state},
                    })
                elif tname == "gpt_miao_app_action":
                    act = targs.get("action", "refresh")
                    payload = targs.get("payload") or {}
                    msg = ""
                    if act == "refresh":
                        msg = "已刷新本地估算"
                    elif act == "calibrate":
                        store.calibrate(
                            short_pct=int(payload.get("shortPct", 100)),
                            week_pct=int(payload.get("weekPct", 100)),
                            short_reset_minutes=int(payload.get("shortResetMinutes", 300)),
                            week_reset_hours=int(payload.get("weekResetHours", 168)),
                        )
                        msg = "已校准额度锚点并同步悬浮窗"
                    elif act == "save_config":
                        store.update_config(payload)
                        msg = "已保存设置"
                    elif act == "add_quote":
                        store.add_quote(str(payload.get("text", "")), float(payload.get("weight", 1.0)))
                        msg = "已添加自定义语录"
                    elif act == "reset_quotes":
                        store.reset_quotes()
                        msg = "已恢复默认猫娘语录"
                    elif act == "start_widget":
                        msg = store.start_widget()["message"]
                    elif act == "stop_widget":
                        msg = store.stop_widget()["message"]
                    state = store.get_full_state()
                    state["actionMessage"] = msg
                    send_response({
                        "jsonrpc": "2.0",
                        "id": req_id,
                        "result": {"content": [{"type": "text", "text": msg}], "structuredContent": state},
                    })
                else:
                    send_response({"jsonrpc": "2.0", "id": req_id, "error": {"code": -32601, "message": f"Unknown tool: {tname}"}})
            else:
                send_response({"jsonrpc": "2.0", "id": req_id, "error": {"code": -32601, "message": f"Method not found: {method}"}})
        except Exception as exc:
            send_response({"jsonrpc": "2.0", "id": req_id, "error": {"code": -32603, "message": str(exc)}})


if __name__ == "__main__":
    main()
