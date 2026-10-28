-- Curves and timings for what the generated look does not set (it sets windows, workspaces and fade). Speeds are in
-- deciseconds. Curve names differ from the generated "gutterOut" so neither file redefines the other's.
hl.curve("panelOut", { type = "bezier", points = { { 0.16, 1.0 }, { 0.3, 1.0 } } })
hl.curve("panelIn",  { type = "bezier", points = { { 0.7, 0.0 }, { 0.84, 0.0 } } })
hl.curve("softBoth", { type = "bezier", points = { { 0.45, 0.0 }, { 0.55, 1.0 } } })

-- The shell's panels (layer surfaces) fade; they move themselves inside their windows
hl.animation({ leaf = "layersIn",  enabled = true, speed = 3, bezier = "panelOut", style = "fade" })
hl.animation({ leaf = "layersOut", enabled = true, speed = 2, bezier = "panelIn",  style = "fade" })
hl.animation({ leaf = "fadeLayersIn",  enabled = true, speed = 3, bezier = "panelOut" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 2, bezier = "panelIn" })

-- The special workspaces (scratch, game) rise from below and drop away again
hl.animation({ leaf = "specialWorkspaceIn",  enabled = true, speed = 4, bezier = "panelOut", style = "slidevert" })
hl.animation({ leaf = "specialWorkspaceOut", enabled = true, speed = 3, bezier = "panelIn",  style = "slidevert" })

-- Dim and border changes
hl.animation({ leaf = "fadeDim", enabled = true, speed = 3, bezier = "softBoth" })
hl.animation({ leaf = "border",  enabled = true, speed = 3, bezier = "softBoth" })
