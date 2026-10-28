import QtQuick
import QtTest
import "../lib/lock.js" as Lock

TestCase {
    name: "Lock"

    readonly property string fprintd: "found 1 devices\nDevice at /x\nFingerprints for user alice on Reader (swipe):\n - #0: right-index-finger\n"
    readonly property string locked3: "The account is locked due to 3 failed logins."

    function chr(text) {
        return { name: "char", text: text };
    }
    function bs() {
        return { name: "backspace" };
    }

    function test_keyEdit_chars() {
        compare(Lock.keyEdit("ab", chr("c")).buffer, "abc");
        // Control characters and nothing at all leave the buffer alone.
        compare(Lock.keyEdit("ab", chr("\u0007")).buffer, "ab");
        compare(Lock.keyEdit("ab", chr("\u007f")).buffer, "ab");
        compare(Lock.keyEdit("ab", chr("")).buffer, "ab");
        compare(Lock.keyEdit("ab", { name: "char" }).buffer, "ab");
        // The buffer is capped, also when one paste is far longer than the cap.
        compare([...Lock.keyEdit("x".repeat(600), chr("y")).buffer].length, 256);
        compare([...Lock.keyEdit("", chr("z".repeat(1000))).buffer].length, 256);
        // The cap counts graphemes, so 300 emoji leave 256 of them (Array.from would count 512 halves).
        compare([...Lock.keyEdit("", chr("\u{1F600}".repeat(300))).buffer].length, 256);
        // One character is one grapheme: an accent or an emoji is not two.
        compare(Lock.keyEdit("a", chr("é")).buffer, "aé");
        compare(Lock.keyEdit("x".repeat(255), chr("\u{1F600}")).buffer, "x".repeat(255) + "\u{1F600}");
        compare(Lock.keyEdit("x".repeat(256), chr("\u{1F600}")).buffer, "x".repeat(256));
    }
    // The cap counts graphemes and never cuts one in half.
    function test_keyEdit_cap_graphemes() {
        // A grapheme that spans the buffer and the typed text counts once.
        var flagBuffer = Lock.keyEdit("x".repeat(255) + "\u{1F1E6}", chr("\u{1F1E7}")).buffer;
        compare(flagBuffer, "x".repeat(255) + "\u{1F1E6}\u{1F1E7}");
        compare(Lock.graphemes(flagBuffer).length, 256);
        // A mark typed alone after a full buffer joins the last character.
        compare(Lock.keyEdit("x".repeat(256), chr("\u0301")).buffer, "x".repeat(255) + "x\u0301");
        var family = "\u{1F468}\u200D\u{1F469}\u200D\u{1F467}\u200D\u{1F466}";
        var cap = Lock.keyEdit("", chr(family.repeat(150))).buffer;
        compare(cap, family.repeat(150));
        compare(Lock.keyEdit("x".repeat(255), chr(family)).buffer, "x".repeat(255) + family);
        compare(Lock.keyEdit("x".repeat(256), chr(family)).buffer, "x".repeat(256));
        var accent = "e\u0301";
        compare(Lock.keyEdit(accent.repeat(255), chr(accent + accent)).buffer, accent.repeat(256));
        compare(Lock.keyEdit("", chr("\u{1F1E7}\u{1F1EA}".repeat(300))).buffer, "\u{1F1E7}\u{1F1EA}".repeat(256));
    }
    // A flood of marks or joiners cannot grow the buffer without end: a paste is cut to the unit limit after a whole
    // grapheme, and a flood that would grow the last character past it leaves the buffer as it was.
    function test_keyEdit_unit_limit() {
        var full = "x".repeat(256);
        compare(Lock.keyEdit(full, chr("\u0301".repeat(5000))).buffer, full);
        compare(Lock.keyEdit(full, chr("\u200Dx".repeat(3000))).buffer, full);
        var family = "\u{1F468}\u200D\u{1F469}\u200D\u{1F467}\u200D\u{1F466}";
        compare(Lock.keyEdit("", chr(family.repeat(300))).buffer, family.repeat(186));
        compare(Lock.keyEdit("", chr("z".repeat(3000))).buffer, "z".repeat(256));
        compare(Lock.keyEdit("x".repeat(255), chr("\u0301".repeat(5000))).buffer, "x".repeat(255));
        // A huge paste is cut before it is segmented, and still ends on a whole grapheme.
        compare(Lock.keyEdit("", chr("z".repeat(1000000))).buffer, "z".repeat(256));
        compare(Lock.keyEdit("", chr("\u{1F600}".repeat(1000000))).buffer, "\u{1F600}".repeat(256));
        compare(Lock.keyEdit("x".repeat(300), chr(family.repeat(1000000))).buffer, "x".repeat(256));
        compare(Lock.keyEdit("", chr(family.repeat(1000000))).buffer, family.repeat(186));
        var marks = Lock.keyEdit(full, chr("\u0301".repeat(1000))).buffer;
        compare(marks.length, 1256);
        compare(Lock.keyEdit(marks, chr("\u0301".repeat(1000))).buffer, marks);
    }
    // Where the grapheme borders fall, without a buffer round trip.
    function test_graphemes() {
        compare(Lock.graphemes(""), []);
        compare(Lock.graphemes("ab"), ["a", "b"]);
        compare(Lock.graphemes("e\u0301x"), ["e\u0301", "x"]);
        compare(Lock.graphemes("\u{1F44D}\u{1F3FD}!"), ["\u{1F44D}\u{1F3FD}", "!"]);
        compare(Lock.graphemes("\u2764\uFE0F"), ["\u2764\uFE0F"]);
        compare(Lock.graphemes("1\uFE0F\u20E3"), ["1\uFE0F\u20E3"]);
        compare(Lock.graphemes("\r\n\n"), ["\r\n", "\n"]);
        // Flags pair up from the left: three indicators are a flag and a lone one.
        compare(Lock.graphemes("\u{1F1E7}\u{1F1EA}\u{1F1EB}"), ["\u{1F1E7}\u{1F1EA}", "\u{1F1EB}"]);
        compare(Lock.graphemes("\u{1F469}\u{1F3FD}\u200D\u{1F4BB}"), ["\u{1F469}\u{1F3FD}\u200D\u{1F4BB}"]);
        // Nothing joins a control character, also not after CRLF.
        compare(Lock.graphemes("\n\u0301"), ["\n", "\u0301"]);
        compare(Lock.graphemes("\r\n\u0301"), ["\r\n", "\u0301"]);
        compare(Lock.graphemes("\u0007\u200D\u{1F600}"), ["\u0007", "\u200D", "\u{1F600}"]);
        compare(Lock.graphemes("a\u200D\n"), ["a\u200D", "\n"]);
        // Hangul: jamo L+V+T is one, so is a precomposed syllable with a trailing jamo; L+L+V too.
        compare(Lock.graphemes("\u1100\u1161\u11A8"), ["\u1100\u1161\u11A8"]);
        compare(Lock.graphemes("\uAC01\u1100"), ["\uAC01", "\u1100"]);
        compare(Lock.graphemes("\uAC00\u11A8"), ["\uAC00\u11A8"]);
        compare(Lock.graphemes("\uAC01\u11A8"), ["\uAC01\u11A8"]);
        compare(Lock.graphemes("\u1100\u1100\u1161"), ["\u1100\u1100\u1161"]);
        compare(Lock.graphemes("\u11A8\u1161"), ["\u11A8", "\u1161"]);
        compare(Lock.graphemes("\u1161\u1100"), ["\u1161", "\u1100"]);
        compare(Lock.graphemes("a\u1161"), ["a", "\u1161"]);
        // Bengali and kana marks.
        compare(Lock.graphemes("\u0995\u09BE\u0995\u09CD"), ["\u0995\u09BE", "\u0995\u09CD"]);
        compare(Lock.graphemes("\u304B\u3099"), ["\u304B\u3099"]);
        compare(Lock.graphemes("\u0995\u09E2\u0995\u09FE"), ["\u0995\u09E2", "\u0995\u09FE"]);
        // Hangul Jamo Extended-A and -B.
        compare(Lock.graphemes("\uA960\u1161\uD7CB"), ["\uA960\u1161\uD7CB"]);
        compare(Lock.graphemes("\u1100\uD7B0\u11A8"), ["\u1100\uD7B0\u11A8"]);
    }
    // A paste often ends with a newline; the rest is taken and nothing submits.
    function test_keyEdit_paste_trailing_newline() {
        compare(Lock.keyEdit("ab", chr("hunter2\n")), { buffer: "abhunter2", submit: false });
        compare(Lock.keyEdit("ab", chr("hunter2\r\n")), { buffer: "abhunter2", submit: false });
        compare(Lock.keyEdit("", chr("hunter2\n\n\r\n")).buffer, "hunter2");
        // Only newlines type nothing.
        compare(Lock.keyEdit("ab", chr("\n")).buffer, "ab");
        compare(Lock.keyEdit("ab", chr("\r\n\r\n")).buffer, "ab");
        // A newline or another control character inside still rejects the whole paste.
        compare(Lock.keyEdit("ab", chr("hun\nter2")).buffer, "ab");
        compare(Lock.keyEdit("ab", chr("hun\r\nter2\n")).buffer, "ab");
        compare(Lock.keyEdit("ab", chr("hunter2\t\n")).buffer, "ab");
        // A long run of newlines in front of text is a mid-paste newline, and is rejected without a stall.
        compare(Lock.keyEdit("ab", chr("\n".repeat(1000000) + "a")).buffer, "ab");
        // A leading newline is not trailing.
        compare(Lock.keyEdit("ab", chr("\nhunter2")).buffer, "ab");
    }
    function test_keyEdit_editing() {
        compare(Lock.keyEdit("abc", bs()).buffer, "ab");
        compare(Lock.keyEdit("aé", bs()).buffer, "a");
        compare(Lock.keyEdit("a\u{1F600}", bs()).buffer, "a");
        // One backspace takes a whole visible character.
        compare(Lock.keyEdit("a\u{1F468}\u200D\u{1F469}\u200D\u{1F467}\u200D\u{1F466}", bs()).buffer, "a");
        compare(Lock.keyEdit("a\u{1F1E7}\u{1F1EA}", bs()).buffer, "a");
        compare(Lock.keyEdit("ae\u0301", bs()).buffer, "a");
        compare(Lock.keyEdit("a\u{1F44D}\u{1F3FD}", bs()).buffer, "a");
        compare(Lock.keyEdit("a\u2764\uFE0F", bs()).buffer, "a");
        compare(Lock.keyEdit("a1\uFE0F\u20E3", bs()).buffer, "a");
        compare(Lock.keyEdit("\u{1F1E7}\u{1F1EA}\u{1F1EB}\u{1F1EA}", bs()).buffer, "\u{1F1E7}\u{1F1EA}");
        // A Korean syllable spelled in jamo, and a Bengali vowel sign.
        compare(Lock.keyEdit("a\u1100\u1161\u11A8", bs()).buffer, "a");
        compare(Lock.keyEdit("a\u0995\u09BE", bs()).buffer, "a");
        compare(Lock.keyEdit("", bs()).buffer, "");
        compare(Lock.keyEdit("abc", { name: "backspace", ctrl: true }).buffer, "");
        compare(Lock.keyEdit("abc", { name: "escape" }).buffer, "");
    }
    function test_keyEdit_submit() {
        compare(Lock.keyEdit("abc", { name: "enter" }), { buffer: "abc", submit: true });
        compare(Lock.keyEdit("", { name: "enter" }).submit, false);
        compare(Lock.keyEdit("abc", { name: "enter", repeat: true }).submit, false);
        compare(Lock.keyEdit("abc", chr("d")).submit, false);
        compare(Lock.keyEdit("abc", bs()).submit, false);
        compare(Lock.keyEdit("abc", { name: "escape" }).submit, false);
    }
    function test_parseFaillock() {
        compare(Lock.parseFaillock(locked3), { locked: true, minutes: 0 });
        compare(Lock.parseFaillock("(10 minutes left to unlock)"), { locked: false, minutes: 10 });
        compare(Lock.parseFaillock(locked3 + "\n(10 minutes left to unlock)"), { locked: true, minutes: 10 });
        compare(Lock.parseFaillock("(1 minute left to unlock)").minutes, 1);
        compare(Lock.parseFaillock(""), { locked: false, minutes: 0 });
        compare(Lock.parseFaillock("hello"), { locked: false, minutes: 0 });
    }
    function test_parseDeny() {
        compare(Lock.parseDeny("# deny = 5\ndeny = 4\n"), 4);
        compare(Lock.parseDeny("deny=7"), 7);
        compare(Lock.parseDeny("dir = /var/run/faillock\n"), 3);
        compare(Lock.parseDeny(""), 3);
        compare(Lock.parseDeny("deny = 0"), 3);
        compare(Lock.parseDeny("deny = x"), 3);
        compare(Lock.parseDeny("deny = 100000"), 3);
        // libpam reads top to bottom and a later line overrides: the last numeric deny wins, even one out of range.
        compare(Lock.parseDeny("deny = 5\ndeny = 4\n"), 4);
        compare(Lock.parseDeny("deny = 5\n# deny = 9\n"), 5);
        compare(Lock.parseDeny("deny = 5\n  deny=6  \n"), 6);
        // A line whose value is not a number is skipped; the last numeric line counts, then the range decides.
        compare(Lock.parseDeny("deny = 4\n deny = x"), 4);
        compare(Lock.parseDeny("deny = 4\ndeny = 0\n"), 3);
        compare(Lock.parseDeny("deny = 4\ndeny = 100000\n"), 3);
        compare(Lock.parseDeny("deny = x\ndeny = 4\n"), 4);
        // A trailing comment is dropped; a commented-out line never counts.
        compare(Lock.parseDeny("deny = 4 # lock sooner\n"), 4);
        compare(Lock.parseDeny("deny = 4 # c\r\n"), 4);
        compare(Lock.parseDeny("deny = 5\r\ndeny = 4 # c\r\n"), 4);
        compare(Lock.parseDeny("deny = 5\ndeny = 4 #\n# deny = 9\n"), 4);
        compare(Lock.parseDeny("deny = # 5\n"), 3);
        compare(Lock.parseDeny("deny = 4\u00a0\n"), 3);
        compare(Lock.parseDeny("deny = 4\r\ndeny = 6\r\n"), 6);
        // Blanks stop at the line end: a value on the next line is not this one.
        compare(Lock.parseDeny("deny =\n5"), 3);
        compare(Lock.parseDeny("deny\n= 5"), 3);
        compare(Lock.parseDeny("deny = 4\n\n\n"), 4);
    }
    function test_triesLeft() {
        compare(Lock.triesLeft(3, 0), 3);
        compare(Lock.triesLeft(3, 2), 1);
        compare(Lock.triesLeft(3, 3), 0);
        compare(Lock.triesLeft(3, 9), 0);
    }
    function test_authState_wrong() {
        compare(Lock.authState("failed", { message: "", deny: 3, failures: 1 }), { kind: "wrong", text: "Wrong password · 2 left" });
        compare(Lock.authState("failed", { message: "", deny: 3, failures: 3 }), { kind: "wrong", text: "Wrong password" });
    }
    function test_authState_locked() {
        compare(Lock.authState("maxtries", { message: locked3 + "\n(7 minutes left to unlock)", deny: 3, failures: 3 }), { kind: "locked", text: "Locked · 7 min" });
        compare(Lock.authState("maxtries", { message: "", deny: 3, failures: 3 }), { kind: "locked", text: "Locked" });
        // PAM can report the lock as an ordinary failure; the message decides.
        compare(Lock.authState("failed", { message: locked3, deny: 3, failures: 3 }).kind, "locked");
    }
    function test_authState_error() {
        compare(Lock.authState("error", { message: "", deny: 3, failures: 0 }), { kind: "error", text: "Could not check the password" });
        compare(Lock.authState("bogus", { message: "", deny: 3, failures: 0 }), { kind: "error", text: "Could not check the password" });
    }
    function test_hasPrints() {
        verify(Lock.hasPrints(fprintd));
        verify(!Lock.hasPrints("User alice has no fingerprints enrolled for Reader."));
        verify(!Lock.hasPrints(""));
        verify(!Lock.hasPrints("Impossible to establish a connection"));
    }
    function test_lockDecision() {
        compare(Lock.lockDecision({ enabled: true, locked: false }), "lock");
        compare(Lock.lockDecision({ enabled: true, locked: true }), "ignore");
    }
    // A request while the lock is being unlocked is queued, not dropped: the lock is about to go.
    function test_lockDecision_queues_during_unlock() {
        compare(Lock.lockDecision({ enabled: true, locked: true, unlocking: true }), "queue");
        compare(Lock.lockDecision({ enabled: true, locked: true, unlocking: false }), "ignore");
        // Nothing to queue behind when the session is not locked, and nothing at all with the lock screen off.
        compare(Lock.lockDecision({ enabled: true, locked: false, unlocking: true }), "lock");
        compare(Lock.lockDecision({ enabled: false, locked: true, unlocking: true }), "ignore");
    }
    function test_pendingStep() {
        // Nothing queued: nothing to do, whatever the lock does.
        compare(Lock.pendingStep({ pending: false, unlocking: false, locked: false, preview: false }), "none");
        compare(Lock.pendingStep({ pending: false, unlocking: true, locked: true, preview: false }), "none");
        // Queued: wait while the unlock runs, and while the lock or the preview is still there when it ended
        // (`locked` follows the release a moment later).
        compare(Lock.pendingStep({ pending: true, unlocking: true, locked: true, preview: false }), "wait");
        compare(Lock.pendingStep({ pending: true, unlocking: true, locked: false, preview: false }), "wait");
        compare(Lock.pendingStep({ pending: true, unlocking: false, locked: true, preview: false }), "wait");
        compare(Lock.pendingStep({ pending: true, unlocking: false, locked: false, preview: true }), "wait");
        // Gone: ask again. (request() decides afresh, so a lock screen disabled meanwhile ignores it: lockDecision.)
        compare(Lock.pendingStep({ pending: true, unlocking: false, locked: false, preview: false }), "retry");
        compare(Lock.lockDecision({ enabled: false, locked: false, unlocking: false }), "ignore");
    }
    // With the lock screen off a lock request does nothing, locked or not: no other lock screen takes over.
    function test_lockDecision_disabled_does_nothing() {
        compare(Lock.lockDecision({ enabled: false, locked: false }), "ignore");
        compare(Lock.lockDecision({ enabled: false, locked: true }), "ignore");
        compare(Lock.lockDecision({ enabled: false }), "ignore");
        verify(Lock.fallbackCommand === undefined);
    }
    function test_batteryChip() {
        compare(Lock.batteryChip(null), { visible: false, text: "" });
        compare(Lock.batteryChip({ isPresent: false, percentage: 0.8, charging: false }), { visible: false, text: "" });
        compare(Lock.batteryChip({ isPresent: true, percentage: 0.8, charging: false }), { visible: true, text: "80 %" });
        compare(Lock.batteryChip({ isPresent: true, percentage: 0.8, charging: true }), { visible: true, text: "80 % ⚡" });
        compare(Lock.batteryChip({ isPresent: true, percentage: 1.4, charging: false }).text, "100 %");
        compare(Lock.batteryChip({ isPresent: true, percentage: -1, charging: false }).text, "0 %");
        compare(Lock.batteryChip({ isPresent: true, percentage: NaN, charging: false }), { visible: false, text: "" });
    }
    function test_parseLockedHint() {
        verify(Lock.parseLockedHint("b true\n"));
        verify(Lock.parseLockedHint("true\n"));
        verify(!Lock.parseLockedHint("b false\n"));
        verify(!Lock.parseLockedHint("false"));
        verify(!Lock.parseLockedHint(""));
        verify(!Lock.parseLockedHint("Failed to get property LockedHint"));
    }
    function test_stateAccent() {
        compare(Lock.stateAccent("wrong", false), "coral");
        compare(Lock.stateAccent("error", false), "coral");
        compare(Lock.stateAccent("locked", false), "sun");
        compare(Lock.stateAccent("", false), "");
        compare(Lock.stateAccent("nonsense", false), "");
        compare(Lock.stateAccent(undefined, false), "");
    }
    // While a check runs the bubble shows "…" on paper, whatever the last state was.
    function test_stateAccent_checking_wins() {
        compare(Lock.stateAccent("wrong", true), "");
        compare(Lock.stateAccent("locked", true), "");
        compare(Lock.stateAccent("error", true), "");
    }
    // A preview opens only with no real lock held, wanted or confirmed.
    function test_previewAllowed() {
        verify(Lock.previewAllowed(false, false, false));
        verify(!Lock.previewAllowed(true, false, false));
        verify(!Lock.previewAllowed(false, true, false));
        verify(!Lock.previewAllowed(false, false, true));
        verify(!Lock.previewAllowed(true, true, true));
    }
}
