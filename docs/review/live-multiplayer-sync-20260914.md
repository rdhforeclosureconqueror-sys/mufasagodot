# Live multiplayer state synchronization repair

Status: draft review evidence only. Do not claim physical acceptance from this document.

## Physically observed boundary before this repair

- authenticated local personal avatar: PASS
- local joystick locomotion: PASS
- two distinct users present in one Lion's Den room: PASS
- remote avatar spawn/load: PASS
- remote live movement updates: FAIL

The web relay already has a real two-client WebSocket regression proving PLAYER_STATE from one client is broadcast to the other. The remaining unproven Godot link was authoritative local movement -> outbound PLAYER_STATE publication.

## Repair

- bind multiplayer publication to `GymPlayerController.locomotion_sampled`, the same authoritative CharacterBody loop already proven to move the local player
- preserve a 12.5 Hz send cap and add a 500 ms heartbeat
- identify browser WebSocket generations so events from a replaced socket cannot close/freeze a newer connection
- remove stale remote puppets on a real current-socket close; the reconnect snapshot respawns authoritative presences
- expose send attempts/successes, receive count, remote movement count, state sequences, state age, and connection generation in the consolidated diagnostics
- add a focused regression proving an eligible authoritative movement sample emits PLAYER_STATE containing the final CharacterBody transform

## Physical acceptance still required

After a reviewed Web export is staged, use two distinct accounts. Move A while watching B, then move B while watching A. Both remote avatars must continuously update position/facing and despawn/reconnect without ghosts. Diagnostics must show sent sequence, receive sequence, and remote move count increasing.
