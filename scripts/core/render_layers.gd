class_name RenderLayers
extends RefCounted

## Canonical draw order for the battle scene.
## Background < terrain < buildings < units < effects < world UI < screen HUD.

const BACKGROUND := -100
const TERRAIN := -50
const BUILDINGS := 5
const UNITS := 10
const PROJECTILES := 20
const WORLD_OVERLAY := 30
const HUD_CANVAS := 100

