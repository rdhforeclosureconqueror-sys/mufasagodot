# MileleFit / Mufasa Cross-Repo Development Handoff

Updated: 2026-09-13

Purpose: give any future dev bot enough context to work from either GitHub repository, move changes safely across the Godot/Web boundary, preserve the systems that already work, and continue the current phone-first development flow without requiring the user to sit at the Windows PC.

## 1. The two repositories

### Web / PocketPT / server repository

- GitHub: `rdhforeclosureconqueror-sys/Mufasa.fitness.node`
- Clone: `https://github.com/rdhforeclosureconqueror-sys/Mufasa.fitness.node.git`
- Local Windows path when using the user's PC: `C:\Users\pftgu\Desktop\Mufasa.fitness.node`
- Main responsibilities:
  - account/auth/member state
  - PocketPT website and phone UI
  - push-up challenge landing page and arena shell
  - avatar/member API transport
  - multiplayer lobby server / WebSocket contract
  - Render frontend/backend deployment
  - packaged Godot Web runtime under `public/game/push-up-arena/`

### Godot runtime repository

- GitHub: `rdhforeclosureconqueror-sys/mufasagodot`
- Clone: `https://github.com/rdhforeclosureconqueror-sys/mufasagodot.git`
- Local Windows path when using the user's PC: `C:\Users\pftgu\Documents\avlobytest`
- Main scene: `Main.tscn`
- Main responsibilities:
  - 3D Lion's Den runtime
  - personalized avatar runtime
  - CharacterBody3D / NavigationAgent3D movement
  - Idle / Walk / Run / action animation state
  - Thriller action override
  - GO_TO_MAT navigation
  - visual facing / joystick movement behavior
  - runtime diagnostics
  - future multiplayer remote-player rendering
  - Godot Web exports

## 2. How a dev bot should connect

If GitHub tools/connectors are available, open both repositories by their exact full names above. A bot working from the phone does not need the user's local PC for normal source edits, PRs, reviews, or GitHub Actions.

If working locally, use the two Windows paths above. Do not initialize a new Git repository inside either project. Do not overwrite the user's existing web `origin`. The Godot project was historically connected with a separate remote named `mufasa-github`.

Local Godot Codex / MCP is useful only when a task requires the live Godot editor, scene-tree inspection, GUI playtesting, or a graphical check that cannot be proven headlessly. It is not required for ordinary source changes now that the Godot project is on GitHub.

## 3. Architecture boundary — do not blur this

**PocketPT / Web = brain and transport.**

It owns identity, account/member state, avatar descriptors, phone controls, exercise semantics, server APIs, multiplayer room membership, and deployment shell.

**Godot = body and world.**

It owns world position, collision, navigation, avatar rendering, locomotion playback, action playback, facing, remote-player rendering, and the 3D experience.

**TensorFlow / MoveNet = perception.**

It interprets camera movement. For locomotion it should provide semantic intent, not directly fight Godot for bones.

**Blender / Humanizer = animation workshop.**

Use them to author/retarget/bake animation assets. Godot remains the runtime animation owner.

Animation ownership modes:

- `LOCOMOTION` -> Godot AnimationTree owns the body
- `ACTION_OVERRIDE` -> authored workout/dance animation owns the body
- `LIVE_MOCAP` -> camera-retarget system owns required pose/bones

Never let two systems write the same bones at the same time.

## 4. Current validated production baseline

The user has physically validated the complete phone flow through the standalone Push-Up Challenge entry:

`CREATE ACCOUNT -> GET PERSONALIZED AVATAR -> ENTER GYM -> JOYSTICK MOVE -> WALK/RUN -> GO TO MAT -> THRILLER`

Validated observations after Godot PR #4 and Web PR #809:

- personalized avatar appears correctly
- one-thumb joystick works
- Walk visibly animates at the slower pace
- Run visibly animates
- avatar faces its travel direction instead of running backward
- GO_TO_MAT visibly walks
- Thriller plays successfully
- release returns to Idle
- giant internal Godot diagnostics panel is gone from the Web view
- the gym is usable from the standalone new-account flow

Current repository main checkpoints at this handoff:

- Godot main merge commit: `508b1045ebb1b4c1e412fa1275e2a15173d0b167` (merged PR #4)
- Web main merge commit: `0b9acdda6f108199796595c8c79f976bf0fe255a` (merged PR #809)
- Exact Godot source used to build the currently packaged Web candidate: `b12f28f365bb5b0b4e5d82146263dcfb68d9bcce`
- Current packaged PCK SHA256: `efbf394cd50de2fe2483ab9281921d2923cea0eadb25406ef13e8cbdbf179e4a`
- Current packaged PCK bytes: `47,573,608`

Do not assume a later main branch still matches these SHAs. Always re-read the current manifest and current PR heads before modifying or deploying.

## 5. Protected working systems

Do not casually rewrite these while working on another feature:

- source personalized avatar pipeline
- saved 20/20 Gym Compatibility mapping authority
- `rashad1.glb` source avatar
- CharacterBody3D world-position authority
- NavigationAgent3D GO_TO_MAT projection and physical arrival threshold
- joystick vector semantics and release-to-STOP behavior
- Walk / Run locomotion state machine
- current target-native Run and Thriller assets
- Walk currently uses a slower-cadence copy of the proven gait to eliminate glide; a truly custom polished Walk can be authored later without changing locomotion architecture
- ACTION_OVERRIDE and Thriller return-to-locomotion behavior
- MoveNet / TensorFlow exercise systems
- Push-Up Arena rep detection, timer, scoring, and leaderboard
- consolidated diagnostics / FIRST FAILURE philosophy

No locomotion root-motion world translation unless the architecture is explicitly redesigned. CharacterBody3D / NavigationAgent3D remain the translation authority.

## 6. FIRST FAILURE rule

Every dev bot should report the earliest verified break in the chain, not the last symptom.

Examples:

- body moving but Walk looks Idle -> inspect actual Walk clip motion before rewriting state selection
- movement goes left but avatar faces right -> preserve movement vector and fix only visual facing
- Web looks stale -> verify exact packaged PCK/source hash before changing gameplay logic

Do not trust a trailing `PASS` if an earlier command failed. Missing evidence is `FIRST UNVERIFIED`, not automatically a technical failure.

Automated/headless PASS is not the same as production visual acceptance. Avatar animation and mobile UX require the user's physical-device visual confirmation when relevant.

## 7. Cross-repo change workflow

When a feature touches Godot and Web, use this order:

1. Identify which repository owns the first failure.
2. Make the engine/runtime change in `mufasagodot` on a feature branch.
3. Add focused Godot regressions for the failure.
4. Run Godot 4.5.1 headless tests when possible.
5. Produce a Web export tied to an exact Godot source commit.
6. Record hashes/provenance. Never deploy a PCK with unknown source lineage.
7. Stage the exact exported runtime into `Mufasa.fitness.node` under `public/game/push-up-arena/`.
8. Update `public/game/push-up-arena/pocketpt-world-build.json` with source commit, sizes, hashes, and acceptance status.
9. Run focused Web/phone tests.
10. Open/review two PRs if both repositories changed.
11. Merge Godot PR first, then the Web deployment PR.
12. Wait for Render deployment.
13. Perform phone visual acceptance.

Do not merge a Web binary built from an older Godot branch over a newer Godot fix. If the Godot PR changes after the Web package was staged, regenerate/restage the Web package.

## 8. Godot Web export / artifact flow

The Godot repo contains GitHub Actions support for Godot 4.5.1 Web exports. The standard export produces:

- `index.html`
- `index.js`
- `index.pck`
- `index.wasm`
- `BUILD_PROVENANCE.txt`

The generated candidate is published through the Godot repo's export workflow / generated candidate branch. The web repository serves the runtime from:

`public/game/push-up-arena/`

For every deployment, preserve exact source provenance and SHA256 values in the build manifest.

## 9. Render topology

Frontend:

- service: `Mufasafitsite`
- public host: `https://mufasafitsite.onrender.com`
- frontend build: `npm run build:frontend`
- publish directory: `dist`

Backend:

- service: `Mufasa.fitness.node`
- public host: `https://mufasa-fitness-node.onrender.com`
- backend start: `npm start`
- backend env includes `FRONTEND_PUBLIC_URL=https://mufasafitsite.onrender.com`

The arena shell/API is backend-hosted; Exit Arena returns to the frontend host.

## 10. Current next milestone: two people in the Lion's Den

The next development target is no longer locomotion. It is multiplayer presence.

### Server side already exists in the Web repo

Canonical server contract:

- room: `lions_den`
- config: `GET /api/game/lobby/config`
- WebSocket: `/api/game/lobby/ws`
- server messages:
  - `ROOM_SNAPSHOT`
  - `PLAYER_JOINED`
  - `PLAYER_STATE`
  - `PLAYER_LEFT`
  - `SESSION_REPLACED`
  - `ERROR`
- client state message:
  - `{type:"PLAYER_STATE", seq, position:[x,y,z], yaw, locomotion}`
- allowed locomotion:
  - `IDLE`
  - `WALK`
  - `RUN`
  - `STOP`
  - `ACTION_OVERRIDE`
- recommended send rate: 10-15 Hz
- server maximum: 30 Hz
- server owns identity; Godot sends movement/state only
- remote players should be non-blocking for the first milestone

The Web repo already contains server tests proving a second player can join and room snapshots can contain multiple players.

### Current first missing runtime layer

Godot still needs the production multiplayer client/runtime layer.

Create one `LobbyClient` authority after PocketPT bootstrap succeeds. Keep exactly one live lobby connection. It should:

- obtain lobby config
- open/authenticate the WebSocket
- track `self_presence_id`
- parse snapshot/join/state/leave/session-replaced/error messages
- publish the local player's final post-collision position, facing yaw, and locomotion state with monotonically increasing sequence numbers
- never send raw joystick/keyboard inputs as authoritative network state

Add one `RemotePlayers: Node3D` container and maintain:

`presence_id -> RemotePlayer`

Never spawn the local player's own presence as a remote clone.

Each remote player should:

- use the avatar information supplied by the server
- reuse the existing personalized-avatar loading/mapping path
- store target position/yaw/locomotion and last accepted sequence
- ignore stale sequence numbers
- interpolate toward target transforms instead of teleporting every packet
- play remote Idle/Walk/Run/Action state without gaining local control authority
- despawn on `PLAYER_LEFT`

Local ownership remains:

`INPUT -> PHYSICS/COLLISION -> FINAL TRANSFORM -> LOCOMOTION -> NETWORK SEND`

## 11. Multiplayer diagnostics

Do not create another visible diagnostics panel. Extend the consolidated diagnostics data model and keep the internal Godot Web panel hidden.

Required multiplayer fields:

- MULTIPLAYER TRANSPORT
- WS URL
- CONNECTION STATE
- ROOM ID
- SELF PRESENCE ID
- LOCAL MEMBER ID
- ROOM PLAYER COUNT
- REMOTE PLAYER COUNT
- REMOTE AVATARS LOADED
- LAST STATE SENT SEQ
- LAST STATE RECEIVED SEQ
- LAST STATE AGE MS
- RECONNECT COUNT
- FIRST FAILURE

First-failure multiplayer pipeline:

`BOOTSTRAP -> LOBBY_CONFIG -> WS_CONNECT -> ROOM_SNAPSHOT -> LOCAL_PLAYER_BIND -> REMOTE_PLAYER_SPAWN -> REMOTE_AVATAR_LOAD -> STATE_SEND -> STATE_RECEIVE -> REMOTE_MOVE -> LEAVE_DESPAWN`

## 12. Multiplayer acceptance order

### First proof: two people

Use two separate accounts/devices.

Acceptance:

- A enters the Lion's Den
- B enters the Lion's Den
- A sees A + B
- B sees B + A
- A controls only A
- B controls only B
- movement/facing from A is visible on B
- movement/facing from B is visible on A
- remote Walk/Run states are visible
- B leaving despawns B from A
- B reconnecting creates one B, not a ghost duplicate
- `FIRST FAILURE: NONE`

### Then expand to three devices

The previously defined Milestone 1 final acceptance is three separate physical devices/accounts with correct avatars, movement/facing visible across all clients, late join, leave/despawn, and reconnect without duplicates.

Out of scope until that passes: chat, friends, parties, matchmaking, spectators, synchronized challenge competition, player-to-player collision, and multiplayer Mufasa behavior.

## 13. Useful existing handoff

Web repo:

`docs/review-handoffs/living-lobby-milestone1-godot-handoff.md`

Read it before implementing multiplayer. This file is the broader cross-repo operating handoff; the Living Lobby handoff is the specific multiplayer contract.

## 14. Security / repository hygiene

Never commit credentials, tokens, cookies, API secrets, Render secrets, signing keys, or private member data.

Treat large generated/binary assets carefully. Do not `git add -A` blindly in the user's local Godot working tree; it has historically contained unrelated experiments and large assets. Stage only intended files.

Before any sensitive work, verify repository visibility and permissions rather than assuming they are private.

## 15. Dev-bot working style requested by the user

- Be action-oriented.
- Identify and report `FIRST FAILURE`.
- Preserve already-proven systems unless the evidence points there.
- If a change crosses repos, say which repo owns each change.
- For computer handoffs, label instructions clearly as `GODOT CODEX`, `GODOT POWERSHELL`, `REPO CODEX`, or `REPO POWERSHELL`.
- For phone validation, use `PHONE TEST`.
- Do not oversell automated tests as visual acceptance.
- Proactively flag stale binaries, conflicting branches, regressions, or unexpected files before merge.

The user is architecting the system while learning the technical vocabulary. Explain important new terms in plain language, but do not bury the next action in a long lecture.
