#!/usr/bin/env python3
"""The Deezer-specific part of the app theme (rendered by apps.render_deezer from theme/templates/deezer.css).

Deezer (deezer-linux) takes one custom CSS file. Its `--color-*` variables are only the first layer: most of the chrome
reads the app's "tempo" tokens (`--tempo-colors-<kind>-<group>-<surface>-<state>`), which the app defines with literal
colours, so `tempo_block` points the mode-following ones back at the `--color-*` variables the template sets. Tokens
that do not follow the mode (the branded tiles, the black and white overlays on coloured surfaces) are left alone.
`extra` adds the placeholder values the template needs on top of apps.half_values.
"""

import palette

STRONG_L = 0.06         # hover/pressed accent: moved away from the paper by this much OKLab lightness
WEAK_L = 0.08           # the weak accent: moved towards the paper
LIGHT_L = 0.15          # the light accent
TERTIARY_L = 0.08       # the tertiary background: the paper moved towards the text, twice paper_alt's shift
HOVER_L = 0.12          # and its hover colour
SECONDARY_TEXT_L = 0.35  # secondary text: the text moved towards the paper
DISABLED_TEXT_L = 0.5
MIX_HOVER = "12%"       # a feedback colour's hover and pressed states: the colour mixed with the text colour
MIX_PRESSED = "20%"

KINDS = ("background", "text", "icon", "border")
STATES = ("default", "disabled", "hovered", "pressed", "selected")
BORDER_STATES = ("default", "disabled", "hovered", "pressed", "focused")

NEUTRAL_BG = {"primary": "bg-main", "secondary": "bg-secondary", "tertiary": "bg-tertiary", "inverse": "text-main"}
NEUTRAL_FG = {"primary": "text-main", "secondary": "text-secondary", "tertiary": "text-disabled",
              "inverse": "text-inverse"}
FEEDBACK = {"error": "feedback-error", "success": "feedback-success", "warning": "feedback-warning"}


def _var(name):
    return "var(--color-%s)" % name


def _mix(name, share):
    return "color-mix(in oklab, %s, %s %s)" % (_var(name), _var("text-main"), share)


def _neutral(kind, surface, state):
    if kind == "border":
        base = "border-neutral-primary"
    else:
        base = (NEUTRAL_BG if kind == "background" else NEUTRAL_FG)[surface]
    if state in ("selected", "focused"):
        return _var("accent-main")
    if state == "disabled":
        return _var("bg-tertiary" if kind == "background" else "text-disabled")
    if state in ("hovered", "pressed") and kind == "background" and surface != "inverse":
        return _var("bg-tertiary-hover")
    return _var(base)


def _accent(kind, surface, state):
    if state == "disabled":
        return _var("bg-tertiary" if kind == "background" else "text-disabled")
    if surface == "onAccent":
        return _var("on-accent")
    if state == "focused":
        return _var("text-main")
    if kind != "background":
        return _var("accent-text")
    if surface == "secondary":
        return _var("accent-weak" if state == "default" else "accent-main")
    return _var("accent-main" if state == "default" else "accent-strong")


def _feedback(kind, surface, state):
    name = FEEDBACK[surface]
    if state == "disabled":
        return _var("bg-tertiary" if kind == "background" else "text-disabled")
    if state == "focused":
        return _var("accent-main")
    base = name if kind == "background" else name + "-text"
    if state == "hovered":
        return _mix(base, MIX_HOVER)
    if state == "pressed":
        return _mix(base, MIX_PRESSED)
    return _var(base)


def _surfaces(kind):
    """[(group, surfaces, function)] the app defines for one kind of token."""
    neutral = {"background": NEUTRAL_BG, "border": ("primary",)}.get(kind, NEUTRAL_FG)
    accent = {"background": ("primary", "secondary"), "border": ("primary",)}.get(kind, ("primary", "onAccent"))
    return [("neutral", neutral, _neutral), ("accent", accent, _accent), ("feedback", FEEDBACK, _feedback)]


def tokens():
    """[(token name, value)] for every mode-following semantic token, in a fixed order."""
    return [("--tempo-colors-%s-%s-%s-%s" % (kind, group, surface, state), make(kind, surface, state))
            for kind in KINDS for group, surfaces, make in _surfaces(kind)
            for surface in surfaces for state in (BORDER_STATES if kind == "border" else STATES)]


def tempo_block():
    """The CSS declarations that wire the tempo tokens; !important because the app's dark mode block is more specific."""
    return "\n".join("  %s: %s !important;" % (name, value) for name, value in tokens())


def extra(v):
    """Placeholder values for deezer.css from apps.half_values `v`: the accent ramp, the surface and text steps."""
    paper, text, active = v["paper"], v["text"], v["active"]
    away = -1 if palette.oklab_l(paper) > 0.5 else 1    # away from the paper
    out = {
        "accent_strong": palette.shift_l(active, away * STRONG_L),
        "accent_weak": palette.shift_l(active, -away * WEAK_L),
        "accent_light": palette.shift_l(active, -away * LIGHT_L),
        "bg_tertiary": palette.shift_l(paper, away * TERTIARY_L),
        "bg_tertiary_hover": palette.shift_l(paper, away * HOVER_L),
        "text_secondary": palette.shift_l(text, -away * SECONDARY_TEXT_L),
        "text_disabled": palette.shift_l(text, -away * DISABLED_TEXT_L),
        "on_accent": v["on_active"],
        "accent_alt_text": v["neutral_alt_text"],    # the accents as text that also reads on paper_alt
        "error_text": v["urgent_alt_text"],
        "success_text": v["ok_alt_text"],
        "warning_text": v["visited_alt_text"],
        "tempo": tempo_block(),
    }
    return out
