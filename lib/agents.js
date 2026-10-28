.pragma library

// Claude Code sessions, rebuilt from the event log the hook appends to (scripts/agent-hook.sh).
// One line per hook call: { t (ms), e (hook event), id (session), cwd, prompt?, tool?, msg? }.

var STALE_MS = 2 * 60 * 60 * 1000; // sessions without an event for this long are dropped
var DONE_ALERT_MS = 6000;
var DONE_MIN_MS = 30000; // shorter tasks finish without the "finished" pill
var ENDED_MS = 10 * 60 * 1000; // a finished session stays listed this long after it exits
// An interrupted turn fires no Stop, so a "working" session that goes this long without any hook event
// is taken to be back at the prompt. Foreground tools are capped well below it (Bash: 10 min).
var QUIET_MS = 20 * 60 * 1000;

function parseLines(text) {
    const out = [];
    for (const line of (text || "").split("\n")) {
        if (line.trim() === "")
            continue;
        try {
            const e = JSON.parse(line);
            if (e && typeof e === "object" && typeof e.id === "string" && e.id !== "" && typeof e.e === "string" && typeof e.t === "number")
                out.push(e);
        } catch (err) {
            // A line cut off mid-write is skipped; the next reload has it whole.
        }
    }
    return out;
}

function project(cwd) {
    const parts = (cwd || "").split("/").filter(p => p !== "");
    return parts.length > 0 ? parts[parts.length - 1] : "~";
}

function oneLine(text, max) {
    const s = (text || "").replace(/\s+/g, " ").trim();
    return s.length > max ? s.slice(0, max - 1) + "…" : s;
}

// Prompts sent through an envelope (Remote Control relays, harness wake-ups) start with markup; the
// preview shows the words inside. The hook cuts prompts at 400 characters, so a tag may be cut too.
function cleanPrompt(text) {
    let s = (text || "").trim();
    if (s.startsWith("<"))
        s = s.replace(/<[^>]*>/g, " ").replace(/<[^>]*$/, " ").trim() || "Automated prompt";
    return oneLine(s, 160);
}

// status: "idle" (started, no prompt yet), "working", "waiting" (needs permission or input), "done".
function apply(sessions, e) {
    const prev = sessions[e.id];
    if (e.e === "SessionEnd") {
        // A finished session stays in "Done" for a while (claude -p exits right after its Stop).
        if (prev && prev.status === "done")
            sessions[e.id] = Object.assign({}, prev, { ended: true, updatedAt: e.t });
        else
            delete sessions[e.id];
        return sessions;
    }
    const s = prev ? Object.assign({}, prev) : { id: e.id, cwd: e.cwd || "", startedAt: e.t, status: "idle", prompt: "", tool: "", message: "", promptAt: 0, doneAt: 0 };
    if (e.cwd)
        s.cwd = e.cwd;
    s.updatedAt = e.t;
    switch (e.e) {
    case "SessionStart":
        s.status = prev ? prev.status : "idle";
        break;
    case "UserPromptSubmit":
        s.status = "working";
        s.prompt = cleanPrompt(e.prompt);
        s.promptAt = e.t;
        s.tool = "";
        s.message = "";
        break;
    case "PreToolUse":
        // Started before the hooks were installed: count from the first event seen.
        if (!s.promptAt)
            s.promptAt = e.t;
        s.status = "working";
        s.tool = e.tool || "";
        s.message = "";
        break;
    case "PostToolUse":
        // A permission prompt that was answered: back to work.
        if (s.status === "waiting") {
            s.status = "working";
            s.message = "";
        }
        break;
    case "Notification":
        // Claude Code also notifies after 60 s idle at the prompt; that is not "needs you" mid-task.
        if (s.status !== "done" && s.status !== "idle") {
            s.status = "waiting";
            s.message = oneLine(e.msg, 120);
        }
        break;
    case "Stop":
        s.status = "done";
        s.tool = "";
        s.message = "";
        s.doneAt = e.t;
        break;
    }
    sessions[e.id] = s;
    return sessions;
}

function reduce(events, now) {
    let sessions = {};
    for (const e of events)
        sessions = apply(sessions, e);
    for (const id in sessions) {
        const s = sessions[id];
        if (now - s.updatedAt > (s.ended ? ENDED_MS : STALE_MS))
            delete sessions[id];
        else if (s.status === "working" && now - s.updatedAt > QUIET_MS)
            sessions[id] = Object.assign({}, s, { status: "idle", tool: "" });
    }
    return sessions;
}

var ORDER = { waiting: 0, working: 1, done: 2, idle: 3 };

// Needs-you first, then working, then finished, then idle; newest activity first within each.
function list(sessions) {
    return Object.keys(sessions).map(k => sessions[k]).sort((a, b) => (ORDER[a.status] - ORDER[b.status]) || (b.updatedAt - a.updatedAt));
}

function counts(items) {
    const c = { working: 0, waiting: 0, done: 0, idle: 0, total: items.length };
    for (const s of items)
        c[s.status]++;
    return c;
}

// Tasks that finished after `since`, oldest first: { t, id, cwd, prompt, took } as of each Stop. Each is
// replayed on its own, so a later short Stop or an ended session can't hide a long task's finish.
function finishedSince(events, since) {
    const out = [];
    let sessions = {};
    for (const e of events) {
        if (e.e === "Stop" && e.t > since) {
            const s = sessions[e.id];
            out.push({ t: e.t, id: e.id, cwd: s?.cwd || e.cwd || "", prompt: s?.prompt ?? "", took: s?.promptAt ? e.t - s.promptAt : 0 });
        }
        sessions = apply(sessions, e);
    }
    return out;
}

function ago(ms) {
    const s = Math.max(0, Math.floor(ms / 1000));
    if (s < 60)
        return "just now";
    const m = Math.floor(s / 60);
    if (m < 60)
        return `${m} min ago`;
    const h = Math.floor(m / 60);
    return `${h} h ago`;
}

function elapsed(ms) {
    const s = Math.max(0, Math.floor(ms / 1000));
    const m = Math.floor(s / 60);
    if (m < 1)
        return `${s} s`;
    if (m < 60)
        return `${m} min`;
    return `${Math.floor(m / 60)} h ${m % 60} min`;
}

// One line under the project name.
function statusText(s, now) {
    switch (s.status) {
    case "waiting":
        return s.message || "Needs your input";
    case "working": {
        const what = s.tool || "Thinking";
        return s.promptAt ? `${what} · ${elapsed(now - s.promptAt)}` : what;
    }
    case "done":
        return `Finished ${ago(now - s.doneAt)}`;
    }
    return "Ready";
}

function statusIcon(status) {
    return { waiting: "front_hand", working: "progress_activity", done: "check_circle", idle: "terminal" }[status] || "terminal";
}
