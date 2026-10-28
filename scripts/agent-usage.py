#!/usr/bin/env python3
"""Claude Code usage for Gutter's Agents tab: tokens and API-price value from the transcripts.

Reads ~/.claude/projects/**/*.jsonl (and ~/.config/claude/projects) incrementally: byte offsets and the
parsed records are cached in $XDG_CACHE_HOME/gutter/agent-usage.json, so a run only reads what was
appended since the last one. Prints one JSON summary on stdout (see summarise()).

Records are deduplicated by message id + request id: Claude Code writes one line per content block, each
carrying the same usage. Cost is what the tokens would cost at API list prices ("API value"), not what a
subscription costs.
"""

import calendar
import json
import os
import re
import sys
import time

CACHE_VERSION = 1
KEEP_DAYS = 92  # 13 weeks of heatmap, plus a day
HEAT_WEEKS = 13

# USD per million tokens: input, output, cache read, cache write (5 min), cache write (1 h).
PRICES = {
    "claude-fable-5": [10.0, 50.0, 1.0, 12.5, 20.0],
    "claude-fable-5-1": [10.0, 50.0, 0.25, 12.5, 20.0],
    "claude-mythos-5": [10.0, 50.0, 1.0, 12.5, 20.0],
    "claude-mythos-5-1": [10.0, 50.0, 0.25, 12.5, 20.0],
    "claude-opus-5-5": [4.0, 20.0, 0.2, 5.0, 8.0],
    "claude-opus-5": [5.0, 25.0, 0.5, 6.25, 10.0],
    "claude-opus-4-8": [5.0, 25.0, 0.5, 6.25, 10.0],
    "claude-opus-4-7": [5.0, 25.0, 0.5, 6.25, 10.0],
    "claude-opus-4-6": [5.0, 25.0, 0.5, 6.25, 10.0],
    "claude-opus-4-5": [5.0, 25.0, 0.5, 6.25, 10.0],
    "claude-opus-4-1": [15.0, 75.0, 1.5, 18.75, 30.0],
    "claude-opus-4": [15.0, 75.0, 1.5, 18.75, 30.0],
    "claude-sonnet-5-5": [2.0, 10.0, 0.1, 2.5, 4.0],
    "claude-sonnet-5": [2.0, 10.0, 0.2, 2.5, 4.0],
    "claude-sonnet-4-6": [3.0, 15.0, 0.3, 3.75, 6.0],
    "claude-sonnet-4-5": [3.0, 15.0, 0.3, 3.75, 6.0],
    "claude-sonnet-4": [3.0, 15.0, 0.3, 3.75, 6.0],
    "claude-3-7-sonnet": [3.0, 15.0, 0.3, 3.75, 6.0],
    "claude-3-5-sonnet": [3.0, 15.0, 0.3, 3.75, 6.0],
    "claude-haiku-5-5": [0.1, 0.5, 0.01, 0.125, 0.2],
    "claude-haiku-4-5": [1.0, 5.0, 0.1, 1.25, 2.0],
    "claude-3-5-haiku": [0.8, 4.0, 0.08, 1.0, 1.6],
    "claude-3-haiku": [0.25, 1.25, 0.03, 0.3, 0.5],
    "claude-3-opus": [15.0, 75.0, 1.5, 18.75, 30.0],
}


def price_for(model):
    """Exact id, then without a date suffix, then the longest known prefix; None if unknown."""
    m = re.sub(r"-\d{8}$", "", model or "")
    if m in PRICES:
        return PRICES[m]
    best = None
    for k in PRICES:
        if m.startswith(k + "-") and (best is None or len(k) > len(best)):
            best = k
    return PRICES[best] if best else None


def model_name(model):
    """claude-opus-5-5 -> Opus 5.5, claude-3-5-sonnet-20241022 -> Sonnet 3.5."""
    m = re.sub(r"-\d{8}$", "", model or "")
    m = re.sub(r"^claude-", "", m)
    parts = m.split("-")
    words = [p for p in parts if not p.isdigit()]
    nums = [p for p in parts if p.isdigit()]
    if not words:
        return model or "Unknown"
    return " ".join(w.capitalize() for w in words) + (" " + ".".join(nums) if nums else "")


def project_name(cwd):
    cwd = (cwd or "").rstrip("/")
    # Worktrees count towards the project they belong to.
    cwd = re.sub(r"/\.claude/worktrees/[^/]+.*$", "", cwd)
    return cwd.rsplit("/", 1)[-1] or "~"


def roots():
    out = []
    config = os.environ.get("CLAUDE_CONFIG_DIR")
    home = os.path.expanduser("~")
    for base in ([config] if config else []) + [os.path.join(home, ".claude"), os.path.join(home, ".config", "claude")]:
        p = os.path.join(base, "projects")
        if os.path.isdir(p) and p not in out:
            out.append(p)
    return out


def parse_iso_utc(s):
    """ISO 8601 UTC timestamp ("2026-10-15T00:41:51.222Z") -> epoch ms."""
    try:
        return int(calendar.timegm(time.strptime(s[:19], "%Y-%m-%dT%H:%M:%S")) * 1000)
    except Exception:
        return None


def record_from(line):
    """(key, record) for an assistant line with usage, else None. record: [t, model, project, session, in, out, cr, cw5m, cw1h]."""
    if '"assistant"' not in line or '"usage"' not in line:
        return None
    try:
        d = json.loads(line)
    except Exception:
        return None
    if d.get("type") != "assistant" or d.get("isApiErrorMessage"):
        return None
    msg = d.get("message") or {}
    usage = msg.get("usage") or {}
    model = msg.get("model") or ""
    if not usage or model == "<synthetic>":
        return None
    t = parse_iso_utc(d.get("timestamp") or "")
    if t is None:
        return None
    key = f"{msg.get('id', '')}:{d.get('requestId', '')}"
    if key == ":":
        key = d.get("uuid") or line[:200]
    cc = usage.get("cache_creation") or {}
    cw_total = int(usage.get("cache_creation_input_tokens") or 0)
    cw1h = int(cc.get("ephemeral_1h_input_tokens") or 0)
    cw5m = int(cc.get("ephemeral_5m_input_tokens") or 0) if cc else cw_total
    if cc and cw5m + cw1h < cw_total:
        cw5m = cw_total - cw1h
    rec = [t, model, project_name(d.get("cwd")), d.get("sessionId") or "",
           int(usage.get("input_tokens") or 0), int(usage.get("output_tokens") or 0),
           int(usage.get("cache_read_input_tokens") or 0), cw5m, cw1h]
    return key, rec


def cost_of(rec):
    p = price_for(rec[1])
    if p is None:
        return 0.0
    return (rec[4] * p[0] + rec[5] * p[1] + rec[6] * p[2] + rec[7] * p[3] + rec[8] * p[4]) / 1e6


def load_cache(path):
    try:
        with open(path) as f:
            c = json.load(f)
        if c.get("version") == CACHE_VERSION:
            return c
    except Exception:
        pass
    return {"version": CACHE_VERSION, "files": {}, "records": {}}


def save_cache(path, cache):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(cache, f, separators=(",", ":"))
    os.replace(tmp, path)


def scan(cache, now_ms):
    files = cache["files"]
    records = cache["records"]
    cutoff = now_ms - KEEP_DAYS * 86400000
    seen = set()
    for root in roots():
        for dirpath, _dirs, names in os.walk(root):
            for name in names:
                if not name.endswith(".jsonl"):
                    continue
                path = os.path.join(dirpath, name)
                seen.add(path)
                try:
                    st = os.stat(path)
                except OSError:
                    continue
                if st.st_mtime * 1000 < cutoff:
                    continue
                entry = files.get(path) or {"offset": 0}
                offset = entry["offset"] if st.st_size >= entry["offset"] else 0
                if offset == st.st_size:
                    continue
                try:
                    with open(path, "rb") as f:
                        f.seek(offset)
                        chunk = f.read()
                except OSError:
                    continue
                # Only whole lines; a line still being written is read next time.
                end = chunk.rfind(b"\n")
                if end < 0:
                    continue
                for raw in chunk[:end].split(b"\n"):
                    r = record_from(raw.decode("utf-8", "replace"))
                    if r and r[1][0] >= cutoff:
                        records[r[0]] = r[1]
                files[path] = {"offset": offset + end + 1}
    for path in list(files):
        if path not in seen:
            del files[path]
    for key in [k for k, r in records.items() if r[0] < cutoff]:
        del records[key]


def day_start(ms, days_back=0):
    lt = time.localtime(ms / 1000)
    return int(time.mktime((lt.tm_year, lt.tm_mon, lt.tm_mday - days_back, 0, 0, 0, 0, 0, -1)) * 1000)


def top(d, n):
    items = sorted(d.items(), key=lambda kv: -kv[1]["cost"])
    return [{"name": k, "cost": round(v["cost"], 4), "tokens": v["tokens"]} for k, v in items[:n]]


def summarise(records, now_ms):
    today0 = day_start(now_ms)
    starts = {"today": today0, "week": day_start(now_ms, 6), "month": day_start(now_ms, 29)}
    periods = {}
    unknown = set()
    for name, start in starts.items():
        nbins = 24 if name == "today" else (7 if name == "week" else 30)
        p = {"cost": 0.0, "tokens": 0, "cacheRead": 0, "input": 0, "output": 0, "trend": [0.0] * nbins}
        models, projects = {}, {}
        for r in records:
            if r[0] < start:
                continue
            c = cost_of(r)
            if price_for(r[1]) is None:
                unknown.add(r[1])
            tokens = r[4] + r[5] + r[6] + r[7] + r[8]
            p["cost"] += c
            p["tokens"] += tokens
            p["cacheRead"] += r[6]
            p["input"] += r[4] + r[6] + r[7] + r[8]
            p["output"] += r[5]
            if name == "today":
                i = time.localtime(r[0] / 1000).tm_hour
            else:
                i = nbins - 1 - max(0, min(nbins - 1, round((today0 - day_start(r[0])) / 86400000)))
            p["trend"][i] += c
            for bucket, key in ((models, model_name(r[1])), (projects, r[2])):
                b = bucket.setdefault(key, {"cost": 0.0, "tokens": 0})
                b["cost"] += c
                b["tokens"] += tokens
        p["cost"] = round(p["cost"], 4)
        p["trend"] = [round(x, 4) for x in p["trend"]]
        p["cachePct"] = round(100 * p["cacheRead"] / p["input"]) if p["input"] else 0
        p["models"] = top(models, 4)
        p["projects"] = top(projects, 4)
        periods[name] = p

    # Heatmap: 13 columns of Monday..Sunday, the last column holding today.
    lt = time.localtime(now_ms / 1000)
    first = day_start(now_ms, lt.tm_wday + 7 * (HEAT_WEEKS - 1))
    ndays = 7 * HEAT_WEEKS
    days = [0.0] * ndays
    for r in records:
        if r[0] >= first:
            i = round((day_start(r[0]) - first) / 86400000)
            if 0 <= i < ndays:
                days[i] += cost_of(r)
    today_i = round((today0 - first) / 86400000)
    active = [i for i in range(today_i + 1) if days[i] > 0]
    busiest = max(range(today_i + 1), key=lambda i: days[i]) if active else None
    streak = 0
    i = today_i if days[today_i] > 0 else today_i - 1
    while i >= 0 and days[i] > 0:
        streak += 1
        i -= 1
    heat = {
        "days": [round(x, 4) for x in days],
        "today": today_i,
        "total": round(sum(days), 4),
        "activeDays": len(active),
        "streak": streak,
        "busiest": None if busiest is None else {
            "label": time.strftime("%-d %b", time.localtime((first + busiest * 86400000) / 1000 + 43200)),
            "cost": round(days[busiest], 4),
        },
    }

    sessions = {}
    since = now_ms - 86400000
    for r in records:
        if r[0] < since or not r[3]:
            continue
        s = sessions.setdefault(r[3], {"cost": 0.0, "output": 0, "model": "", "project": r[2], "last": 0})
        s["cost"] += cost_of(r)
        s["output"] += r[5]
        if r[0] >= s["last"]:
            s["last"] = r[0]
            s["model"] = model_name(r[1])
    for s in sessions.values():
        s["cost"] = round(s["cost"], 4)

    return {"t": now_ms, "periods": periods, "heat": heat, "sessions": sessions, "unknown": sorted(unknown)}


def main():
    now_ms = int(time.time() * 1000)
    cache_dir = os.environ.get("XDG_CACHE_HOME") or os.path.join(os.path.expanduser("~"), ".cache")
    cache_path = os.path.join(cache_dir, "gutter", "agent-usage.json")
    cache = load_cache(cache_path)
    scan(cache, now_ms)
    try:
        save_cache(cache_path, cache)
    except OSError:
        pass
    json.dump(summarise(list(cache["records"].values()), now_ms), sys.stdout, separators=(",", ":"))
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
