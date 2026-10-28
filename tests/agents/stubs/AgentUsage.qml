pragma Singleton

import QtQuick
import Quickshell

// Stand-in for services/AgentUsage.qml in the agents check: every card full (the three limit rows, the longest
// figures, four projects, a busy heatmap), so each shows as much as it ever will.
Singleton {
    readonly property bool failed: false
    readonly property var limits: ({
            session: { pct: 62, resetsIn: 2 * 3600 + 1500, renewed: false },
            week: { pct: 88, resetsIn: 3 * 86400 + 4 * 3600, renewed: false },
            model: { pct: 41, resetsIn: 3 * 86400 + 4 * 3600, renewed: false, name: "Opus" },
            seenAt: 0
        })
    readonly property var data: {
        const period = (cost, tokens, output) => ({
                cost: cost,
                tokens: tokens,
                cacheRead: tokens * 0.96,
                input: tokens,
                output: output,
                cachePct: 96,
                trend: Array.from({ length: 24 }, (_, i) => (i % 5) * 11 + 3),
                models: [
                    { name: "Sonnet 5.5", cost: cost * 0.6, tokens: tokens },
                    { name: "Opus 5.5", cost: cost * 0.3, tokens: tokens },
                    { name: "Fable 5.1", cost: cost * 0.1, tokens: tokens },
                    { name: "Haiku 5.5", cost: 1, tokens: tokens }
                ],
                projects: [
                    { name: "gutter", cost: cost * 0.5, tokens: tokens },
                    { name: "a-project-with-a-much-longer-name", cost: cost * 0.3, tokens: tokens },
                    { name: "scratch", cost: cost * 0.1, tokens: tokens },
                    { name: "dotfiles", cost: 1, tokens: tokens }
                ]
            });
        return {
            periods: {
                today: period(117.43, 407756251, 1912490),
                week: period(875.94, 2747263952, 8482868),
                month: period(3245.05, 10272229738, 18041817)
            },
            heat: {
                days: Array.from({ length: 91 }, (_, i) => (i * 37) % 11 * 20),
                today: 85,
                total: 3254.19,
                activeDays: 24,
                streak: 6,
                busiest: { label: "15 Oct", cost: 692.98 }
            },
            sessions: {},
            unknown: []
        };
    }
}
