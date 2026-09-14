# Handcar World Tour Preview

This is a standalone Godot visual prototype. It is intentionally **not** wired into `Main.tscn` and does not modify the live Push-Up Arena startup path.

## Preview in Godot

1. Check out branch `preview/handcar-world-tour-v1`.
2. Open `scenes/previews/handcar_world_tour_preview.tscn`.
3. Use **Run Current Scene** (F6).

## Controls

- **SPACE** — simulate one valid push-up / handcar pump
- **A** — toggle autoplay demo
- **R** — reset to the start
- **C** — switch camera view

## V1 concept

The 60-rep route is a visual sampler:

- 0–20 reps: **Subway Grind**
- 20–40 reps: **City Breakout**
- 40–60 reps: **Mountain Climb**
- milestone gates: **20 / 30 / 40 / 50 / 60**

Every simulated rep advances the handcar and animates the pump lever. This preview uses only procedural Godot primitives and materials so it can be reviewed before any Blender assets, textures, TensorFlow, or live push-up detection are added.

## Scope lock

Not included yet:

- TensorFlow / MoveNet
- real push-up rep detector
- personalized avatar riding the handcar
- production sound/VFX
- realistic city/landmark texture packs
- live gym/elevator integration
- backend scoring or unlock persistence

Owner visual approval comes before production integration or merge.
