# Canonical local-rest profile

`generate_canonical_rest_profile.gd` regenerates the PocketPT canonical avatar rest profile from the source Rashad skeleton using each bone's local rest transform. Runtime animation rotation tracks are bone-local/rest-relative, so the generated profile must remain in `BONE_LOCAL_REST` space.
