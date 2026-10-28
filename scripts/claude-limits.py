#!/usr/bin/env python3
"""Claude plan limits for Gutter's Agents tab, from Anthropic's usage endpoint.

The status-line bridge (agent-statusline.sh) only hears from the Claude Code CLI. This asks the endpoint behind
the usage card of the Claude apps instead (GET https://api.anthropic.com/api/oauth/usage; undocumented, so every
field is read defensively), using the OAuth login Claude Code already keeps in ~/.claude/.credentials.json.

The token is read here, held in memory, sent to api.anthropic.com over HTTPS and nowhere else: never printed,
logged, written, put in argv or the environment, and the credentials file is only read, never refreshed. An
expired token counts as unavailable (Claude Code renews it the next time it runs).

On success the reading is written to $XDG_STATE_HOME/gutter/claude-limits-api.json in the shape of the bridge's
claude-limits.json ({ t, rate_limits: { five_hour, seven_day, seven_day_model? } }, resets_at in epoch seconds).
Prints one JSON status line on stdout: {"ok": true} or {"ok": false, "reason": ..., "retryAfter": s}.
"""

import json
import os
import sys
import tempfile
import time
import urllib.error
import urllib.request
from datetime import datetime

URL = "https://api.anthropic.com/api/oauth/usage"
TIMEOUT = 10


def config_dir():
    return os.environ.get("CLAUDE_CONFIG_DIR") or os.path.join(os.path.expanduser("~"), ".claude")


def state_path():
    state = os.environ.get("XDG_STATE_HOME") or os.path.join(os.path.expanduser("~"), ".local", "state")
    return os.path.join(state, "gutter", "claude-limits-api.json")


def read_token(path, now_ms):
    """The access token in the credentials file, or None when it is missing, unreadable or expired."""
    try:
        with open(path) as fh:
            oauth = json.load(fh).get("claudeAiOauth")
    except (OSError, ValueError, AttributeError):
        return None
    if not isinstance(oauth, dict):
        return None
    token = oauth.get("accessToken")
    expires = oauth.get("expiresAt")
    if not isinstance(token, str) or not token:
        return None
    if isinstance(expires, (int, float)) and expires <= now_ms:
        return None
    return token


def epoch(iso):
    """Seconds since the epoch of an ISO 8601 time with an offset, or 0."""
    try:
        at = datetime.fromisoformat(iso)
    except (TypeError, ValueError):
        return 0
    return round(at.timestamp()) if at.tzinfo else 0


def percent(v):
    return float(v) if isinstance(v, (int, float)) and not isinstance(v, bool) else None


def window(used, resets):
    used = percent(used)
    at = epoch(resets)
    if used is None or at <= 0:
        return None
    return {"used_percentage": used, "resets_at": at}


def normalise(payload, now_ms):
    """The usage endpoint's JSON as { t, rate_limits }, or None when neither the session nor the week is in it."""
    if not isinstance(payload, dict):
        return None
    out = {}
    for key in ("five_hour", "seven_day"):
        raw = payload.get(key)
        w = window(raw.get("utilization"), raw.get("resets_at")) if isinstance(raw, dict) else None
        if w:
            out[key] = w
    if not out:
        return None
    # The weekly limit of one model (the card shows it beside the week): the busiest if there are several.
    best = None
    for raw in payload.get("limits") or []:
        if not isinstance(raw, dict) or raw.get("kind") != "weekly_scoped":
            continue
        scope = raw.get("scope") if isinstance(raw.get("scope"), dict) else {}
        model = scope.get("model") if isinstance(scope.get("model"), dict) else {}
        w = window(raw.get("percent"), raw.get("resets_at"))
        if w and isinstance(model.get("display_name"), str) and (best is None or w["used_percentage"] > best["used_percentage"]):
            best = dict(w, name=model["display_name"])
    if best:
        out["seven_day_model"] = best
    return {"t": int(now_ms), "rate_limits": out}


class NoRedirect(urllib.request.HTTPRedirectHandler):
    """A redirect would carry the Authorization header along; the endpoint has no business redirecting."""

    def redirect_request(self, *args, **kwargs):
        return None


def fetch(token):
    """(payload, None, 0), or (None, why, retryAfter): why is the HTTP status, "network" or "schema"."""
    req = urllib.request.Request(URL, headers={
        "Authorization": f"Bearer {token}",
        "anthropic-beta": "oauth-2025-04-20",
        "User-Agent": "gutter-shell",
        "Accept": "application/json",
    })
    opener = urllib.request.build_opener(NoRedirect)
    try:
        with opener.open(req, timeout=TIMEOUT) as resp:
            return json.loads(resp.read().decode("utf-8")), None, 0
    except urllib.error.HTTPError as e:
        try:
            retry = int(e.headers.get("Retry-After") or 0)
        except ValueError:
            retry = 0
        return None, e.code, retry
    except ValueError:
        return None, "schema", 0
    except (OSError, urllib.error.URLError):
        return None, "network", 0


def write_atomic(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix="claude-limits-api.json.")
    try:
        with os.fdopen(fd, "w") as fh:
            json.dump(data, fh, separators=(",", ":"))
            fh.write("\n")
        os.replace(tmp, path)
    except OSError:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def run(creds_path, out_path, now_ms):
    token = read_token(creds_path, now_ms)
    if token is None:
        return {"ok": False, "reason": "unavailable"}
    payload, failure, retry = fetch(token)
    del token
    if failure is not None:
        return {"ok": False, "reason": str(failure), "retryAfter": retry}
    data = normalise(payload, now_ms)
    if data is None:
        return {"ok": False, "reason": "schema"}
    try:
        write_atomic(out_path, data)
    except OSError:
        return {"ok": False, "reason": "write"}
    return {"ok": True}


def main():
    result = run(os.path.join(config_dir(), ".credentials.json"), state_path(), int(time.time() * 1000))
    json.dump(result, sys.stdout, separators=(",", ":"))
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
