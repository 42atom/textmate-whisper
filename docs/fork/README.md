# TextMate Fork MVP (Thin Patch)

## Purpose
- Keep a minimal fork for voice input compatibility.
- Fix only the app-level permission declaration first.
- Avoid large divergence from upstream `textmate/textmate`.

## What Is Included
- Patch template:
  - `docs/fork/patches/0001-add-nsmicrophoneusagedescription.patch`
- Build script skeleton:
  - `docs/fork/scripts/build_textmate_whisper_app.sh`

## Recommended Workflow
1. Create a fork repository (for example `textmate-whisper-app`).
2. Run build script skeleton.
3. Validate microphone prompt behavior on first recording.
4. Keep patch count small and rebase from upstream regularly.

## Notes
- This is an MVP path: app-level permission only.
- Keep plugin repo (`textmate-whisper`) independent from app fork.
- For legal distribution, follow GPL obligations when shipping binaries.
