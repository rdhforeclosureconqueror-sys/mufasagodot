# Underwater Learning World — Safety Contract

## Purpose
Build an educational underwater experience without destabilizing the known-good PocketPT avatar, lobby, locomotion, camera, or Push-Up Arena startup path.

## Non-negotiable baseline
- `Main.tscn` remains the avatar-safe startup scene.
- No Underwater Learning World, Learning Pool, or other game-preview node is statically added to `Main.tscn`.
- New worlds load dynamically only after the PocketPT parent handshake is READY and the personal avatar state is settled (`MOUNTED`, intentional `FALLBACK`, or diagnosable `ERROR`).
- Existing avatar loader, lobby, locomotion, and camera paths are dependencies to reuse, not files to rewrite for this feature.
- FIRST FAILURE diagnostics remain visible for every preview.

## Branch / deployment isolation
- Godot development branch: `feature/underwater-learning-world`.
- Web preview branch: `preview/underwater-learning-world`.
- Stable recovery branch: `stable/avatar-safe-baseline-20260915`.
- Do not replace `/game/push-up-arena/` to preview this world.
- When a Web preview is needed, stage it at a separate path such as `/game/underwater-learning-preview/` so the current arena package remains untouched.

## World concept
The player swims through a stylized reef environment. Oxygen is a soft pacing mechanic, not a punishment mechanic.

### Core loop
1. Swim/explore toward the next air pocket.
2. Rising bubble trails and sea-life guide the player.
3. Entering an air pocket pauses oxygen drain and refills air.
4. A learning question appears inside the pocket.
5. The exit membrane remains closed until the learner answers correctly or completes a guided hint/retry path.
6. Correct completion opens the bubble and awards progress toward the next pocket.
7. If oxygen reaches zero outside a pocket, return the learner to the previous safe pocket; do not use death/shame language.

## First prototype assets
All can be procedural/simple before external art is added:
- Seabed, rocks, arches, reef columns: primitive meshes.
- Seaweed: tapered meshes/cards with sway animation or shader.
- Bubble vents: `GPUParticles3D`.
- Air pockets: translucent sphere/dome mesh + `Area3D`.
- Fish: simple low-poly body + tail/fins, moved on waypoint loops; no skeletal animation required for MVP.
- Underwater feel: blue/green environment tint, depth fog, light shafts/caustic-style projection, particles, muffled ambience.

## Avatar / animation integration
- The current personalized avatar must mount first.
- Swim clips are added as optional animation states after the avatar exists.
- Target states: `SWIM_IDLE`, `SWIM_FORWARD`, later `SWIM_TURN` / `SWIM_DIVE` if needed.
- Retarget through the existing canonical humanoid pipeline; do not create a second avatar loader.
- Until swim clips are installed, a preview world may use controlled test movement only on the feature branch and must never be promoted as production-ready.

## Acceptance gates before any live merge
1. Existing personal avatar loads in the normal gym.
2. Push-Up Arena still loads and existing thumb movement works.
3. Lobby/multiplayer startup regression remains green.
4. Underwater world loads only after avatar readiness.
5. Returning from the underwater world restores the same avatar and control state.
6. Mobile visual acceptance on iPhone passes.
7. Rollback commit/branch is recorded before promotion.

Any failure in gates 1–3 blocks the preview from being staged over an existing live package.
