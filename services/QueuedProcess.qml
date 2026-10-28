import QtQuick
import Quickshell.Io

// A Process that never drops a run: run() while one is still going queues the latest command (with its
// context) and starts it on exit; setting `running` on a busy Process would just be ignored. `finished`
// carries stdout and the context the command was run with; a run superseded by a queued one reports nothing.
Process {
    id: root

    property var context: null
    property var queued: null

    signal finished(string text, var context)

    function run(cmd: var, ctx: var): void {
        if (running) {
            queued = { command: cmd, context: ctx ?? null };
            return;
        }
        start(cmd, ctx ?? null);
    }

    function start(cmd: var, ctx: var): void {
        command = cmd;
        context = ctx;
        running = true;
    }

    stdout: StdioCollector {
        onStreamFinished: {
            if (root.queued === null)
                root.finished(text, root.context);
        }
    }

    onExited: {
        if (queued === null)
            return;
        const q = queued;
        queued = null;
        start(q.command, q.context);
    }
}
