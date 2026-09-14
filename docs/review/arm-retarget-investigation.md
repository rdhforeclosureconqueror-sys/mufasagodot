# Personal avatar arm/elbow retarget investigation

Physically observed: personal avatar loads and local turn/run/Thriller work, but elbow/forearm bends are oriented incorrectly. This is a visual retargeting defect, not an avatar-loading failure.

Current runtime copies canonical animation rotation quaternions to the personalized skeleton after changing only track paths. That assumes source and target bones share identical rest-basis orientation/bone roll. The personalized skeleton does not reliably satisfy that assumption, so lower-arm rotations can bend around the wrong local axis.

Repair target: apply source-rest -> target-rest basis conversion to rotation tracks in the one shared animation-copy path used by local and remote personalized avatars. Preserve translation/root-motion behavior. Physical visual acceptance remains required after export.
