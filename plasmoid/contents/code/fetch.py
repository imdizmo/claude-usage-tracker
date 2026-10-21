#!/usr/bin/env python3
"""Self-contained fetcher for the Claude Code usage plasmoid.

Default mode prints one JSON line:
  {"5h":{"pct","reset","pace","forecast","hist"},"weekly":{...},"stale":bool}
or, only when there's no cached reading to fall back on:
  {"error":"...","code":N}

`--live` prints running sessions and what each is doing:
  {"sessions":[{"name","project","busy","doing"}],"busy":N}

`--stats` prints Claude Code activity read from the local session logs:
  {"today","week","models","projects","grid"}

The /api/oauth/usage endpoint is strictly rate-limited (429s if polled too
often), so on any failure we serve the last good reading from a small cache,
flagged stale. Reset times recompute from the cached resets_at, so the
countdown stays live even while serving stale data.
"""
import json
import os
import subprocess
import time
import urllib.error
import urllib.request
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

CREDS = Path.home() / ".claude" / ".credentials.json"
LOGS = Path.home() / ".claude" / "projects"
CACHE = Path.home() / ".cache" / "claude-usage.json"
STATE = Path.home() / ".cache" / "claude-usage-state.json"   # reading history + sent alerts
STATS = Path.home() / ".cache" / "claude-usage-stats.json"   # log scan offsets + daily totals
URL = "https://api.anthropic.com/api/oauth/usage"
WINDOWS = {"5h": 5 * 3600, "weekly": 7 * 86400}  # window length, seconds
ALERTS = (75, 90, 100)
GRID_DAYS = 84  # 12 weeks of activity


def reset_text(iso):
    if not iso:
        return ""
    secs = max(0, int((datetime.fromisoformat(iso) - datetime.now(timezone.utc)).total_seconds()))
    d, h, m = secs // 86400, secs % 86400 // 3600, secs % 3600 // 60
    span = f"{d}d {h}h" if d else (f"{h}h {m}m" if h else f"{m}m")
    return f"resets in {span}"


def elapsed(iso, window, now=None):
    """Fraction (0-1) of the window already gone, from its reset time."""
    if not iso:
        return None
    now = now or datetime.now(timezone.utc).timestamp()
    left = datetime.fromisoformat(iso).timestamp() - now
    return min(1.0, max(0.0, 1 - left / window))


def forecast(pct, frac):
    """Linear projection of usage at reset. None too early in the window to mean anything."""
    # ponytail: straight-line extrapolation; bursty sessions overshoot early on
    return round(pct / frac) if frac and frac >= 0.05 else None


def pace_hint(fc):
    """One-line verdict on the forecast, with a severity the UI colours by."""
    if fc is None:
        return {"hint": "", "level": "ok", "verdict": "Too early in the window to forecast."}
    verdict = f"At this pace you'll use about {fc}% by the reset."
    if fc > 100:
        return {"hint": "Over pace: on track to hit the limit before it resets",
                "level": "bad", "verdict": verdict}
    if fc >= 80:
        return {"hint": "Close to pace", "level": "warn", "verdict": verdict}
    return {"hint": "Under pace", "level": "ok", "verdict": verdict}


def build(d):
    """API payload -> {'5h':{'pct','resets_at'}, 'weekly':{...}} (raw, cacheable)."""
    out = {}
    for key, name in (("five_hour", "5h"), ("seven_day", "weekly")):
        o = d.get(key) or {}
        out[name] = {"pct": round(o.get("utilization") or 0), "resets_at": o.get("resets_at")}
    return out


def render(data, stale=False, history=()):
    now = datetime.now(timezone.utc).timestamp()
    out = {}
    for n, window in WINDOWS.items():
        if n not in data:
            continue
        pct, iso = data[n]["pct"], data[n].get("resets_at")
        frac = elapsed(iso, window, now)
        start = datetime.fromisoformat(iso).timestamp() - window if iso else now
        fc = forecast(pct, frac)
        fmt = "%H:%M" if n == "5h" else "%a %d/%m %H:%M"
        out[n] = {
            "pct": pct,
            "reset": reset_text(iso),
            "reset_at": datetime.fromisoformat(iso).astimezone().strftime(fmt) if iso else "",
            "start_at": datetime.fromtimestamp(start).strftime(fmt),
            "pace": round(frac * 100) if frac is not None else None,   # where even use would be
            "now": round(frac, 4) if frac is not None else None,       # chart x of now (pace is rounded)
            "forecast": fc,
            **pace_hint(fc),
            # [x as fraction of the window, pct] for readings inside the current window
            "hist": [[round((t - start) / window, 4), v[n]] for t, v in history if t >= start],
        }
    out["stale"] = stale
    at = data.get("at")
    out["updated"] = datetime.fromtimestamp(at).strftime("%H:%M") if at else ""
    return out


def minute(iso):
    """resets_at jitters by microseconds between calls; compare to the minute."""
    return iso and datetime.fromisoformat(iso).strftime("%Y-%m-%dT%H:%M")


def alerts(data, sent, levels=ALERTS, reset_alert=True):
    """Messages for newly crossed thresholds / reset windows; updates `sent` in place."""
    msgs = []
    for n in WINDOWS:
        pct, win = data[n]["pct"], minute(data[n]["resets_at"])
        prev = sent.get(n, {"win": win, "level": 0})
        if prev["win"] != win:
            if prev["level"] and reset_alert:  # only worth a ping if we'd warned during that window
                msgs.append(f"{n} limit reset — back to {pct}%")
            prev = {"win": win, "level": 0}
        level = max((a for a in levels if pct >= a), default=0)
        if level > prev["level"]:
            msgs.append(f"{n} limit at {pct}%" + (" — limit reached" if pct >= 100 else ""))
            prev["level"] = level
        sent[n] = prev
    return msgs


def notify(msg):
    try:
        subprocess.run(["notify-send", "-a", "Claude Code usage", "-i", "utilities-system-monitor",
                        "Claude Code usage", msg], timeout=5, check=False)
    except OSError:  # no notify-send: the panel still shows the numbers
        pass


def load(path, default):
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return default


def save(path, obj):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(f".{os.getpid()}.tmp")
    tmp.write_text(json.dumps(obj))
    tmp.replace(path)  # atomic: a concurrent reader never sees half a file


class NoLogin(Exception):
    pass


def fetch():
    raw = CREDS.read_text()  # FileNotFoundError → not signed in at all
    try:
        token = json.loads(raw)["claudeAiOauth"]["accessToken"]
    except (ValueError, KeyError, TypeError) as e:
        raise NoLogin from e
    req = urllib.request.Request(URL, headers={
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
        "anthropic-beta": "oauth-2025-04-20",
        "User-Agent": "claude-usage-plasmoid/1.0",
    })
    with urllib.request.urlopen(req, timeout=8) as r:
        return build(json.load(r))


def explain(e):
    """Turn a fetch failure into something a person can act on."""
    code = getattr(e, "code", None)
    if isinstance(e, FileNotFoundError):
        return "Claude Code isn't signed in on this machine — run `claude` and log in"
    if isinstance(e, NoLogin):
        return "No Claude.ai login in ~/.claude/.credentials.json (API-key logins have no plan limits)"
    if code in (401, 403):
        return "Login expired — open Claude Code once to refresh it"
    if code == 429:
        return "Usage endpoint is rate-limiting — will retry on the next poll"
    if isinstance(code, int) and code >= 500:
        return f"Anthropic's API is having trouble (HTTP {code}) — will retry"
    if isinstance(e, (urllib.error.URLError, TimeoutError, OSError)):
        return "Can't reach api.anthropic.com — offline?"
    return f"Unexpected error: {e}"


def poll(levels=ALERTS, reset_alert=True, max_age=0):
    """One poll: fetch (or fall back to cache), record history, send alerts. Returns render().
    levels=None (the tray) only refreshes the cache: no alerts, no history, STATE untouched,
    so it can't race the applet's read-modify-write of STATE.
    max_age > 0 reuses a cached reading younger than that many seconds instead of fetching,
    so two front-ends running side by side make one request per interval, not two."""
    state = load(STATE, {"history": [], "sent": {}})
    cached = load(CACHE, None) if max_age else None
    if isinstance(cached, dict) and time.time() - (cached.get("at") or 0) < max_age:
        return render(cached, history=state["history"])
    try:
        data = fetch()
    except Exception as e:  # rate-limited / offline / auth → fall back to cache
        cached = load(CACHE, None)
        if cached:
            out = render(cached, stale=True, history=state["history"])
            out["why"] = explain(e)
            return out
        return {"error": explain(e), "code": getattr(e, "code", None)}
    data["at"] = time.time()
    save(CACHE, data)
    if levels is None:
        return render(data, history=state["history"])
    state["history"] = [h for h in state["history"] if h[0] > data["at"] - WINDOWS["weekly"]]
    state["history"].append([data["at"], {n: data[n]["pct"] for n in WINDOWS}])
    for msg in alerts(data, state["sent"], levels, reset_alert):
        notify(msg)
    save(STATE, state)
    return render(data, history=state["history"])


# ---- live Claude Code sessions ----

SESSIONS = Path.home() / ".claude" / "sessions"
TAIL = 256 * 1024  # enough of a transcript's end to find the pending tool call


def proc_start(pid):
    """Process start time (clock ticks since boot): pairs with pid to rule out pid reuse."""
    try:
        return Path(f"/proc/{pid}/stat").read_text().rsplit(")", 1)[1].split()[19]
    except (OSError, IndexError):
        return None


def describe(name, inp):
    """Short, human label for a tool call."""
    base = lambda p: Path(p).name if p else ""
    if name == "Read":
        return f"reading {base(inp.get('file_path'))}"
    if name in ("Edit", "Write", "MultiEdit", "NotebookEdit"):
        return f"editing {base(inp.get('file_path') or inp.get('notebook_path'))}"
    if name == "Bash":
        return "running: " + (inp.get("description") or inp.get("command") or "")[:60]
    if name in ("Grep", "Glob"):
        return "searching code"
    if name in ("WebFetch", "WebSearch"):
        return "on the web"
    if name in ("Agent", "Task", "Workflow"):
        return "running subagents"
    if name.startswith("mcp__"):
        _, server, tool = (name.split("__", 2) + ["", ""])[:3]
        return f"{tool} ({server})"
    return name


def kind(name):
    """Coarse tool category for the session icon."""
    if name in ("Edit", "Write", "MultiEdit", "NotebookEdit"):
        return "edit"
    if name == "Bash":
        return "shell"
    if name in ("Read", "Grep", "Glob"):
        return "read"
    if name in ("WebFetch", "WebSearch"):
        return "web"
    if name in ("Agent", "Task", "Workflow"):
        return "agents"
    return "tool"


def pending_tool(transcript):
    """(label, kind) of the tool call a session is waiting on: last tool_use with no
    tool_result after it."""
    try:
        with transcript.open("rb") as f:
            f.seek(max(0, transcript.stat().st_size - TAIL))
            lines = f.read().splitlines()
    except OSError:
        return None
    done = set()
    for line in reversed(lines):
        if b"tool_" not in line:
            continue
        try:
            d = json.loads(line)
            content = d["message"]["content"]
        except (ValueError, KeyError, TypeError):
            continue  # first line is usually cut mid-way by the seek
        if not isinstance(content, list):
            continue
        for block in reversed(content):
            if not isinstance(block, dict):
                continue
            if block.get("type") == "tool_result":
                done.add(block.get("tool_use_id"))
            elif block.get("type") == "tool_use" and block.get("id") not in done:
                name = block.get("name", "?")
                return describe(name, block.get("input") or {}), kind(name)
        if d.get("type") == "assistant" and any(b.get("type") == "tool_use" for b in content if isinstance(b, dict)):
            return None  # newest tool round already answered
    return None


def live(sessions=SESSIONS, logs=LOGS):
    """Running Claude Code sessions with what each is doing right now."""
    out = []
    for f in sessions.glob("*.json"):
        s = load(f, None)
        if not isinstance(s, dict) or "pid" not in s:
            continue
        if proc_start(s["pid"]) != s.get("procStart"):
            continue  # stale file: process exited (or pid reused)
        status = s.get("status") or "?"
        doing, what = ("waiting for you", "idle") if status == "idle" else (status, "tool")
        if status == "busy":
            t = next(logs.glob(f"*/{s.get('sessionId')}.jsonl"), None)
            doing, what = (t and pending_tool(t)) or ("thinking", "thinking")
        out.append({"name": s.get("name") or str(s["pid"]), "project": Path(s.get("cwd") or "?").name,
                    "busy": status == "busy", "doing": doing, "kind": what})
    out.sort(key=lambda s: (not s["busy"], s["name"]))
    return {"sessions": out, "busy": sum(s["busy"] for s in out)}


# ---- Claude Code activity from local session logs ----

def bump(bucket, model, proj, tok):
    for field, key in (("models", model), ("projects", proj)):
        bucket[field][key] = bucket[field].get(key, 0) + tok


def scan(st, root=LOGS, today=None):
    """Fold new log lines into st['days'] (last GRID_DAYS) and st['all'] (lifetime),
    resuming from per-file byte offsets. The logs run to GBs, so only bytes
    appended since the last scan are read."""
    today = today or date.today()
    if st.get("v") != 2:  # older cache layout: rebuild from scratch
        st = {"v": 2}
    files, days = st.setdefault("files", {}), st.setdefault("days", {})
    lifetime = st.setdefault("all", {"models": {}, "projects": {}, "sess": {}})
    for p in root.rglob("*.jsonl"):
        try:
            size = p.stat().st_size
        except OSError:
            continue
        key = str(p)
        off, last_id = files.get(key, [0, None])
        if size < off:  # rewritten
            off, last_id = 0, None
        if size == off:
            continue
        seen = set()  # (day, project, session): sessions are counted per file, not per line
        with p.open("rb") as f:
            f.seek(off)
            for line in f:
                if not line.endswith(b"\n"):
                    break  # still being written; pick it up next time
                off += len(line)
                if b'"usage"' not in line or b'"assistant"' not in line:
                    continue  # cheap pre-filter: most bytes are tool output
                try:
                    d = json.loads(line)
                    msg = d["message"]
                    u = msg["usage"]
                except (ValueError, KeyError, TypeError):
                    continue
                if d.get("type") != "assistant" or msg.get("id") == last_id:
                    continue  # one API message is logged once per content block
                last_id = msg.get("id")
                day = datetime.fromisoformat(d["timestamp"]).astimezone().date().isoformat()
                tok = sum(u.get(k) or 0 for k in ("input_tokens", "cache_creation_input_tokens",
                                                  "cache_read_input_tokens", "output_tokens"))
                model, proj = msg.get("model") or "?", Path(d.get("cwd") or "?").name
                if model == "<synthetic>":
                    continue  # client-side placeholder, not a model
                b = days.setdefault(day, {"tok": 0, "out": 0, "msgs": 0, "models": {}, "projects": {}, "sess": {}})
                b["tok"] += tok
                b["out"] += u.get("output_tokens") or 0
                b["msgs"] += 1
                bump(b, model, proj, tok)
                bump(lifetime, model, proj, tok)
                seen.add((day, proj, d.get("sessionId") or key))
        for day, proj, sid in seen:
            for sess in (days[day]["sess"], lifetime["sess"]):
                if sid not in sess.setdefault(proj, []):
                    sess[proj].append(sid)
        files[key] = [off, last_id]
    first = (today - timedelta(days=GRID_DAYS)).isoformat()
    for day in [k for k in days if k < first]:
        del days[day]
    return st


def human(n):
    for unit, size in (("B", 1e9), ("M", 1e6), ("k", 1e3)):
        if n >= size:
            return f"{n / size:.1f}{unit}"
    return str(n)


def model_name(m):
    """claude-opus-5-5 -> Opus 5.5, claude-3-5-sonnet-20241022 -> Sonnet 3.5; others unchanged."""
    parts = [p for p in m.split("-") if not (p.isdigit() and len(p) == 8)]  # drop date stamps
    if len(parts) < 3 or parts[0] != "claude":
        return m
    words = [p for p in parts[1:] if not p.isdigit()]
    digits = [p for p in parts[1:] if p.isdigit()]
    if len(words) != 1 or not digits:
        return m
    return f"{words[0].capitalize()} {'.'.join(digits)}"


def ranked(tokens, sess=None, top=8):
    """[{name, tok, pct, sessions}] sorted by tokens, pct of this range's total."""
    total = sum(tokens.values()) or 1
    rows = sorted(tokens.items(), key=lambda kv: -kv[1])[:top]
    return [{"name": k, "tok": human(v), "pct": round(v * 100 / total),
             "sessions": len((sess or {}).get(k, ()))} for k, v in rows]


def named(models):
    """Merge token counts under readable model names (dated variants of one model collapse)."""
    out = {}
    for k, v in models.items():
        out[model_name(k)] = out.get(model_name(k), 0) + v
    return out


def summarize(st, today=None):
    today = today or date.today()
    days = st["days"]

    def window(n_days):
        bs = [days.get((today - timedelta(days=i)).isoformat(), {}) for i in range(n_days)]
        agg = {"models": {}, "projects": {}, "sess": {}}
        for b in bs:
            for field in ("models", "projects"):
                for k, v in b.get(field, {}).items():
                    agg[field][k] = agg[field].get(k, 0) + v
            for k, ids in b.get("sess", {}).items():
                agg["sess"].setdefault(k, set()).update(ids)
        totals = {k: human(sum(b.get(k, 0) for b in bs)) for k in ("tok", "out")} | \
                 {"msgs": sum(b.get("msgs", 0) for b in bs)}
        return totals, agg

    ranges, totals = {}, {}
    for name, n_days in (("today", 1), ("7", 7), ("30", 30)):
        totals[name], agg = window(n_days)
        ranges[name] = {"models": ranked(named(agg["models"])), "projects": ranked(agg["projects"], agg["sess"])}
    life = st.get("all", {})
    ranges["all"] = {"models": ranked(named(life.get("models", {}))),
                     "projects": ranked(life.get("projects", {}), life.get("sess", {}))}

    # grid starts on a Monday so each column is one week; level 0-4 by quartile of active days
    start = today - timedelta(days=today.weekday() + 7 * (GRID_DAYS // 7 - 1))
    vals = [days.get((start + timedelta(days=i)).isoformat(), {}).get("tok", 0)
            for i in range((today - start).days + 1)]
    active = sorted(v for v in vals if v)
    cuts = [active[len(active) * q // 4] for q in (1, 2, 3)] if active else []
    grid = [0 if not v else 1 + sum(v > c for c in cuts) for v in vals]
    return {"today": totals["today"], "week": totals["7"], "month": totals["30"],
            "ranges": ranges, "grid": grid, "active_days": len(active)}


def stats():
    st = scan(load(STATS, {}))
    save(STATS, st)
    return summarize(st)


def _selftest():
    import tempfile
    assert reset_text(None) == ""
    assert reset_text("2099-01-01T00:00:00+00:00").startswith("resets in ")
    r = render(build({"five_hour": {"utilization": 4.0, "resets_at": "2099-01-01T00:00:00+00:00"},
                      "seven_day": {}}))
    assert r["5h"]["pct"] == 4 and r["weekly"]["pct"] == 0 and r["stale"] is False, r
    # pace: 1h into a 5h window → 20% elapsed; 30% used → forecast 150%
    reset = datetime.fromtimestamp(time.time() + 4 * 3600, timezone.utc).isoformat()
    r = render({"5h": {"pct": 30, "resets_at": reset}, "weekly": {"pct": 0, "resets_at": None}},
               history=[[time.time() - 1800, {"5h": 20, "weekly": 0}], [0, {"5h": 99, "weekly": 0}]])
    assert r["5h"]["pace"] == 20 and r["5h"]["forecast"] == 150 and abs(r["5h"]["now"] - 0.2) < 0.001, r
    assert len(r["5h"]["hist"]) == 1 and r["5h"]["hist"][0][1] == 20, r  # old window dropped
    assert forecast(10, 0.01) is None
    assert r["5h"]["level"] == "bad" and pace_hint(50)["level"] == "ok" and pace_hint(None)["hint"] == ""
    # alerts: crossing 75 then 90 fires once each; a new window after a warning says reset
    sent, w1 = {}, "2099-01-01T00:00:00.1+00:00"
    mk = lambda p, w: {"5h": {"pct": p, "resets_at": w}, "weekly": {"pct": 0, "resets_at": None}}
    assert alerts(mk(50, w1), sent) == []
    assert alerts(mk(80, w1), sent) == ["5h limit at 80%"]
    assert alerts(mk(81, "2099-01-01T00:00:00.9+00:00"), sent) == []  # jitter isn't a new window
    assert alerts(mk(95, w1), sent) == ["5h limit at 95%"]
    assert alerts(mk(3, "2099-01-01T05:00:00+00:00"), sent) == ["5h limit reset — back to 3%"]
    # scan: dedupes repeated message ids, resumes from offsets, skips partial lines
    with tempfile.TemporaryDirectory() as tmp:
        log = Path(tmp) / "p" / "s.jsonl"
        log.parent.mkdir()
        rec = lambda i, out: json.dumps({"type": "assistant", "timestamp": datetime.now(timezone.utc).isoformat(),
                                         "cwd": "/x/proj", "message": {"id": i, "model": "m", "usage": {
                                             "input_tokens": 1, "output_tokens": out}}}) + "\n"
        log.write_text(rec("a", 10) + rec("a", 10) + '{"type":"user"}\n' + rec("b", 5)[:-1])
        st = scan({}, Path(tmp))
        b = st["days"][date.today().isoformat()]
        assert (b["tok"], b["out"], b["msgs"]) == (11, 10, 1), b
        with log.open("a") as f:
            f.write("\n" + rec("c", 1))
        b = scan(st, Path(tmp))["days"][date.today().isoformat()]
        assert (b["msgs"], b["projects"]) == (3, {"proj": 19}), b
        s = summarize(st)
        assert s["ranges"]["all"]["projects"] == [{"name": "proj", "tok": "19", "pct": 100, "sessions": 1}], s
        assert s["ranges"]["7"]["models"][0]["name"] == "m" and s["ranges"]["7"]["projects"][0]["sessions"] == 1
        assert s["today"]["msgs"] == 3 and s["grid"][-1] > 0 and len(s["grid"]) % 7 == (date.today().weekday() + 1) % 7
    assert human(1_234_567) == "1.2M" and human(999) == "999"
    # errors: each failure maps to an actionable message
    assert explain(FileNotFoundError()).startswith("Claude Code isn't signed in")
    assert explain(NoLogin()).startswith("No Claude.ai login")
    http = lambda c: urllib.error.HTTPError(URL, c, "", {}, None)
    assert explain(http(401)).startswith("Login expired") and explain(http(429)).startswith("Usage endpoint")
    assert "HTTP 503" in explain(http(503)) and explain(urllib.error.URLError("x")).startswith("Can't reach")
    # alerts honour custom levels and the reset toggle
    sent = {}
    assert alerts(mk(60, w1), sent, levels=(50,)) == ["5h limit at 60%"]
    assert alerts(mk(1, "2099-01-02T00:00:00+00:00"), sent, levels=(50,), reset_alert=False) == []
    # live: pending tool is the last tool_use without a result; dead pids are dropped
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        (tmp / "logs" / "p").mkdir(parents=True)
        (tmp / "sess").mkdir()
        msg = lambda t, *blocks: json.dumps({"type": t, "message": {"content": list(blocks)}}) + "\n"
        use = lambda i, name, inp: {"type": "tool_use", "id": i, "name": name, "input": inp}
        res = lambda i: {"type": "tool_result", "tool_use_id": i}
        log = tmp / "logs" / "p" / "S.jsonl"
        log.write_text("garbage-cut-line\n" + msg("assistant", use("1", "Read", {"file_path": "/a/b.py"}))
                       + msg("user", res("1")) + msg("assistant", use("2", "Edit", {"file_path": "/a/c.py"})))
        assert pending_tool(log) == ("editing c.py", "edit")
        with log.open("a") as f:
            f.write(msg("user", res("2")))
        assert pending_tool(log) is None
        me = {"pid": os.getpid(), "procStart": proc_start(os.getpid()), "sessionId": "S", "cwd": "/x/proj", "name": "me"}
        (tmp / "sess" / "1.json").write_text(json.dumps(me | {"status": "busy"}))
        (tmp / "sess" / "2.json").write_text(json.dumps(me | {"procStart": "0", "name": "dead"}))
        r = live(tmp / "sess", tmp / "logs")
        assert r == {"sessions": [{"name": "me", "project": "proj", "busy": True, "doing": "thinking", "kind": "thinking"}], "busy": 1}, r
    assert model_name("claude-opus-5-5") == "Opus 5.5" and model_name("claude-haiku-4-5-20251001") == "Haiku 4.5"
    assert model_name("claude-3-5-sonnet-20241022") == "Sonnet 3.5" and model_name("gpt-x") == "gpt-x"
    assert named({"claude-opus-4-1": 2, "claude-opus-4-1-20250805": 3}) == {"Opus 4.1": 5}
    assert describe("mcp__github__create_issue", {}) == "create_issue (github)"
    # poll: offline falls back to the cache (stale); levels=None never writes STATE
    global CREDS, CACHE, STATE
    saved = CREDS, CACHE, STATE
    with tempfile.TemporaryDirectory() as tmp:
        CREDS, CACHE, STATE = (Path(tmp) / n for n in ("creds", "cache", "state"))
        assert "error" in poll(levels=None)
        CACHE.write_text("garbage")
        assert "error" in poll()
        save(CACHE, {"5h": {"pct": 42, "resets_at": None}, "weekly": {"pct": 7, "resets_at": None}, "at": 0})
        r = poll(levels=None)
        assert r["stale"] and r["5h"]["pct"] == 42 and r["why"], r
        CREDS.write_text('{"claudeAiOauth": {"accessToken": "t"}}')
        globals()["fetch"], real = (lambda: {"5h": {"pct": 1, "resets_at": None},
                                             "weekly": {"pct": 2, "resets_at": None}}), fetch
        try:
            assert not poll(levels=None)["stale"] and not STATE.exists()
            assert load(CACHE, {})["5h"]["pct"] == 1
            poll(levels=())
            assert load(STATE, {})["history"][-1][1] == {"5h": 1, "weekly": 2}
            # max_age: a fresh cache is served without a request; an old one is refetched
            def boom():
                raise AssertionError("fetched despite a fresh cache")
            globals()["fetch"] = boom
            r = poll(levels=None, max_age=60)
            assert r["5h"]["pct"] == 1 and not r["stale"], r
            save(CACHE, load(CACHE, {}) | {"at": time.time() - 120})
            assert poll(levels=None, max_age=60)["stale"]  # old → tried to fetch → boom → cache fallback
        finally:
            globals()["fetch"] = real
    CREDS, CACHE, STATE = saved
    print("selftest ok")


if __name__ == "__main__":
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--stats", action="store_true")
    ap.add_argument("--live", action="store_true")
    ap.add_argument("--alerts", default=",".join(map(str, ALERTS)),
                    help="comma-separated alert thresholds in %%; empty disables")
    ap.add_argument("--no-reset-alert", action="store_true")
    a = ap.parse_args()
    if a.selftest:
        _selftest()
    elif a.stats:
        print(json.dumps(stats()))
    elif a.live:
        print(json.dumps(live()))
    else:
        levels = tuple(int(x) for x in a.alerts.split(",") if x.strip().isdigit())
        print(json.dumps(poll(levels, not a.no_reset_alert)))
