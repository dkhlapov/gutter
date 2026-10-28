import importlib.util, json, os, tempfile, unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("claude_limits", ROOT / "scripts" / "claude-limits.py")
cl = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cl)

TOKEN = "fake-token-for-tests"
NOW = 1_792_900_000_000  # ms
PAYLOAD = {  # the shape the endpoint returned, trimmed
    "five_hour": {"utilization": 27.0, "resets_at": "2026-10-25T06:39:59.907177+00:00", "limit_dollars": None},
    "seven_day": {"utilization": 57.0, "resets_at": "2026-10-29T04:59:59.907199+00:00"},
    "seven_day_opus": None,
    "extra_usage": {"is_enabled": False},
    "limits": [
        {"kind": "session", "percent": 27, "resets_at": "2026-10-25T06:39:59.907177+00:00", "scope": None},
        {"kind": "weekly_all", "percent": 57, "resets_at": "2026-10-29T04:59:59.907199+00:00", "scope": None},
        {"kind": "weekly_scoped", "percent": 4, "resets_at": "2026-10-29T04:59:59.907363+00:00",
         "scope": {"model": {"id": None, "display_name": "Fable"}, "surface": None}},
    ],
}


def creds(directory, **oauth):
    path = Path(directory) / ".credentials.json"
    path.write_text(json.dumps({"claudeAiOauth": dict({"accessToken": TOKEN, "expiresAt": NOW + 60_000}, **oauth)}))
    return str(path)


class ReadToken(unittest.TestCase):
    def test_valid(self):
        with tempfile.TemporaryDirectory() as d:
            self.assertEqual(cl.read_token(creds(d), NOW), TOKEN)

    def test_expired_is_unavailable(self):
        with tempfile.TemporaryDirectory() as d:
            self.assertIsNone(cl.read_token(creds(d, expiresAt=NOW - 1), NOW))

    def test_missing_or_malformed(self):
        with tempfile.TemporaryDirectory() as d:
            self.assertIsNone(cl.read_token(str(Path(d) / "none.json"), NOW))
            bad = Path(d) / "bad.json"
            bad.write_text("{nope")
            self.assertIsNone(cl.read_token(str(bad), NOW))
            bad.write_text(json.dumps({"mcpOAuth": {}}))
            self.assertIsNone(cl.read_token(str(bad), NOW))
            bad.write_text(json.dumps({"claudeAiOauth": {"accessToken": ""}}))
            self.assertIsNone(cl.read_token(str(bad), NOW))


class Normalise(unittest.TestCase):
    def test_windows(self):
        out = cl.normalise(PAYLOAD, NOW)
        self.assertEqual(out["t"], NOW)
        rl = out["rate_limits"]
        self.assertEqual(rl["five_hour"], {"used_percentage": 27.0, "resets_at": 1792910400})
        self.assertEqual(rl["seven_day"]["used_percentage"], 57.0)
        self.assertEqual(rl["seven_day"]["resets_at"], 1793250000)
        self.assertEqual(rl["seven_day_model"]["name"], "Fable")
        self.assertEqual(rl["seven_day_model"]["used_percentage"], 4)

    def test_session_only(self):
        out = cl.normalise({"five_hour": {"utilization": 3, "resets_at": "2026-10-25T06:39:59+00:00"}, "seven_day": None}, NOW)
        self.assertEqual(list(out["rate_limits"]), ["five_hour"])

    def test_busiest_model_wins(self):
        extra = {"kind": "weekly_scoped", "percent": 40, "resets_at": "2026-10-29T04:59:59+00:00",
                 "scope": {"model": {"display_name": "Opus"}}}
        out = cl.normalise(dict(PAYLOAD, limits=PAYLOAD["limits"] + [extra]), NOW)
        self.assertEqual(out["rate_limits"]["seven_day_model"]["name"], "Opus")

    def test_odd_limits_are_ignored(self):
        out = cl.normalise(dict(PAYLOAD, limits=["x", {"kind": "weekly_scoped"}, {"kind": "weekly_scoped", "scope": 3}]), NOW)
        self.assertNotIn("seven_day_model", out["rate_limits"])

    def test_schema_changes_give_nothing(self):
        for bad in (None, [], "x", {}, {"five_hour": {"utilization": "27"}}, {"five_hour": {"utilization": 5, "resets_at": "soon"}},
                    {"five_hour": {"utilization": True, "resets_at": "2026-10-25T06:39:59+00:00"}},
                    {"five_hour": {"utilization": 5, "resets_at": "2026-10-25T06:39:59"}}):
            self.assertIsNone(cl.normalise(bad, NOW), bad)


class Run(unittest.TestCase):
    def run_with(self, fetched, **oauth):
        with tempfile.TemporaryDirectory() as d:
            out = str(Path(d) / "state" / "gutter" / "claude-limits-api.json")
            with mock.patch.object(cl, "fetch", return_value=fetched) as f:
                result = cl.run(creds(d, **oauth), out, NOW)
            wrote = json.loads(Path(out).read_text()) if os.path.exists(out) else None
            return result, wrote, f

    def test_success_writes_the_file(self):
        result, wrote, f = self.run_with((PAYLOAD, None, 0))
        self.assertEqual(result, {"ok": True})
        self.assertEqual(wrote["rate_limits"]["five_hour"]["used_percentage"], 27.0)
        f.assert_called_once_with(TOKEN)

    def test_expired_token_does_not_call_out(self):
        result, wrote, f = self.run_with((PAYLOAD, None, 0), expiresAt=NOW - 1)
        self.assertEqual(result, {"ok": False, "reason": "unavailable"})
        self.assertIsNone(wrote)
        f.assert_not_called()

    def test_failures_write_nothing(self):
        for failure, reason, retry in ((401, "401", 0), (429, "429", 90), ("network", "network", 0)):
            result, wrote, _ = self.run_with((None, failure, retry))
            self.assertEqual(result, {"ok": False, "reason": reason, "retryAfter": retry})
            self.assertIsNone(wrote)

    def test_schema_change(self):
        result, wrote, _ = self.run_with(({"five_hour": 1}, None, 0))
        self.assertEqual(result, {"ok": False, "reason": "schema"})
        self.assertIsNone(wrote)

    def test_token_stays_out_of_results_and_file(self):
        result, wrote, _ = self.run_with((PAYLOAD, None, 0))
        self.assertNotIn(TOKEN, json.dumps(result) + json.dumps(wrote))


class Network(unittest.TestCase):
    def test_only_anthropic_over_https(self):
        self.assertTrue(cl.URL.startswith("https://api.anthropic.com/"))

    def test_redirects_are_refused(self):
        self.assertIsNone(cl.NoRedirect().redirect_request(None, None, 302, "Found", {}, "https://example.com/"))


if __name__ == "__main__":
    unittest.main()
