# Underwater Vowel Treasure — Developer Handoff

## Purpose

This branch adds a phonics game to the existing avatar-safe underwater learning world without changing the proven avatar loader, locomotion, oxygen bubbles, return portal, reef geometry, or unicorn visual.

The active lesson is **SHORT A vs LONG A**. Nia searches the reef for 20 lost word cards, automatically picks up one word at a time, carries it back to one of two sorting boxes, and sorts it into **SHORT A** or **LONG A**. The round tracks time, mistakes, score, carried word, and oxygen.

Mounting/riding work is intentionally out of scope for this PR.

## Branch relationship

- Base branch: `feature/underwater-learning-world`
- Feature branch: `feature/underwater-vowel-treasure`
- Base source before this work: `2b66e98292e9e55814985337f204eef4a2d5fd1d`

The base underwater implementation remains in `scripts/games/underwater_learning_preview.gd` and is not rewritten. The phonics experience is layered on top through a wrapper so the known-good Make-10 world remains available for regression and rollback.

## Architecture

### 1. Base underwater world remains intact

`res://scripts/games/underwater_learning_preview.gd`

Still owns:

- avatar/player binding
- reef geometry
- collision boundaries
- air bubbles and oxygen drain/refill
- fish and environmental visuals
- gym entry/return portals
- unicorn visual
- FIRST FAILURE behavior
- existing Make-10 implementation for regression

### 2. New phonics component

`res://scripts/games/underwater_phonics_component.gd`

Owns:

- 20 word cards
- 10 short-A targets
- 10 long-A targets
- automatic one-word pickup
- carried-word following behavior
- SHORT A sorting box
- LONG A sorting box
- correct/wrong sorting feedback
- mistake count
- elapsed timer
- child-facing vowel HUD
- oxygen display supplied by the parent underwater world
- phonics diagnostic snapshot and FIRST FAILURE

Word bank in this first lesson:

**Short A**

`cap, tap, mad, can, hat, map, rat, jam, bat, plan`

**Long A**

`cape, tape, made, cane, late, name, rake, game, bake, plane`

### 3. New underwater wrapper

`res://scripts/games/underwater_vowel_treasure_preview.gd`

This extends the known-good underwater preview instead of replacing it.

It:

- changes the entry sign to `VOWEL TREASURE QUEST`
- preserves the reef, bubbles, avatar, unicorn, locomotion, and return portal
- removes the active Make-10 pearls/chest from the phonics session
- mounts `UnderwaterPhonicsComponent`
- starts the phonics timer when the player enters the reef
- pauses the timer when the player returns to the gym
- passes oxygen percentage into the phonics HUD
- mirrors phonics state into the parent diagnostic snapshot

### 4. Runtime route

`res://scripts/games/pushup_maze_diagnostic_bridge.gd`

The bridge now loads:

`res://scripts/games/underwater_vowel_treasure_preview.gd`

instead of loading the base underwater script directly.

This is intentionally a one-line routing change. The base underwater script is preserved.

### 5. Web export

`export_presets.cfg` explicitly includes both new runtime scripts:

- `underwater_phonics_component.gd`
- `underwater_vowel_treasure_preview.gd`

Do not remove them from the Web export resource list.

## Game loop

1. Player enters the same underwater portal.
2. Same avatar teleports to the known reef spawn.
3. Phonics timer starts.
4. Player searches the reef for a lost word card.
5. Touching a word automatically picks it up if no word is already being carried.
6. Carried word follows the player.
7. Player returns to either SHORT A or LONG A box.
8. Correct box removes the card and advances score.
9. Wrong box records one mistake, keeps the word in hand, and tells the player to try the other chest.
10. Oxygen continues to drain exactly as in the existing underwater world; the three safe-air bubbles remain usable.
11. After all 20 words are sorted, timer stops and the HUD reports completion time and mistakes.

## HUD contract

The phonics HUD intentionally replaces the plain Make-10 HUD during this lesson. It displays:

- `VOWEL TREASURE QUEST`
- `SHORT A vs LONG A`
- SHORT A score out of 10
- LONG A score out of 10
- total found out of 20
- elapsed time
- oxygen percentage + simple visual air meter
- currently carried word
- immediate feedback / completion result

The old parent HUD still exists in the base implementation but is hidden by the wrapper during phonics mode.

## Tests

### Existing base regression

`res://tests/underwater_learning_preview_test.gd`

This still validates the original Make-10 underwater world independently.

### New component test

`res://tests/underwater_phonics_component_test.gd`

Checks:

- exactly 20 word cards
- exactly 10 short-A + 10 long-A targets
- both sorting boxes
- pickup behavior
- wrong-box behavior
- correct scoring
- oxygen handoff
- timer start/pause
- no phonics FIRST FAILURE

Expected terminal marker:

`UNDERWATER_PHONICS_COMPONENT_TEST: PASS`

### New integrated preview test

`res://tests/underwater_vowel_treasure_preview_test.gd`

Checks:

- reef ready
- existing locomotion contract preserved
- all three air bubbles preserved
- unicorn preserved
- Make-10 active objects removed from phonics session
- phonics component mounted
- 20-word/10+10 content contract
- same player enters/re-enters reef
- timer starts on entry
- a real word can be picked up and sorted
- same player returns to gym
- timer pauses on return
- no parent FIRST FAILURE

Expected terminal marker:

`UNDERWATER_VOWEL_TREASURE_PREVIEW_TEST: PASS`

## CI

`.github/workflows/pushup-maze-ci.yml` was extended so the PR gate:

- parses both new scripts with Godot 4.5.1
- runs both new tests
- keeps startup isolation, live mocap, phone control, multiplayer, visual-facing, maze, and original underwater regressions
- finishes with a Web export smoke test

A reviewer should not approve the PR if either new PASS marker is missing or if Web export smoke fails.

## Reviewer checklist

1. Confirm `underwater_learning_preview.gd` itself was not rewritten by this feature.
2. Confirm bridge route points to the vowel wrapper, not a duplicate world implementation.
3. Confirm `export_presets.cfg` includes both new runtime scripts.
4. Confirm exactly 20 cards exist and content is 10 short-A / 10 long-A.
5. Confirm only one word can be carried at a time.
6. Confirm wrong sorting does not delete or score the word.
7. Confirm correct sorting deletes the card and increments the correct category.
8. Confirm timer runs only during active phonics play and pauses on gym return.
9. Confirm oxygen still comes from the parent underwater system and safe-air bubbles remain unchanged.
10. Confirm avatar loader, locomotion, multiplayer, phone controls, mocap, and unicorn asset were not changed.
11. Confirm no mount/rider behavior was introduced in this PR.
12. Confirm FIRST FAILURE remains `NONE` in normal test flow.
13. Confirm the Web export includes the new scripts.

## Known intentional limitations

- This first playable lesson is A only: SHORT A vs LONG A.
- No speech/pronunciation audio is introduced in this PR.
- No persistent personal-best time is stored yet.
- Word pickup is proximity/touch based so it works with existing phone controls without adding a new action button.
- The long/short word cards use the same neutral visual treatment so color does not reveal the answer.
- E/I/O/U can be added as additional lesson banks without rebuilding the reef or sorting mechanic.

## Do not change during review fixes unless a failing test proves it is necessary

- avatar startup / READY contract
- `player.gd` locomotion
- phone control bridge
- live mocap ownership
- multiplayer
- underwater oxygen/bubble positions
- unicorn GLB
- unicorn mounting/riding
- normal production arena route

Keep fixes scoped to the phonics wrapper/component, its tests, export inclusion, or the one-line underwater route.
