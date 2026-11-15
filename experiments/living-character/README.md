# Living character (MVP-0)

A primitive seated mannequin that reacts, reaches and idles from a small set of reusable motor commands. It tests the architecture in `MEMORY_KEEPER_README.md`, not the look. The WebGL portrait prototype at the repository root is untouched.

## Run

From the repository root:

```sh
experiments/living-character/scripts/run.sh
```

Options: `--seed=7` (repeatable autonomous run), `--auto` (start autonomous), `--autotest --shots=/absolute/dir` (scripted key sequence with measurements, then quits).

The script uses `local-tools/Godot.app`. To use another Godot 4 build: `GODOT=/path/to/Godot experiments/living-character/scripts/run.sh`.

## Keys

| Key | What happens |
| --- | --- |
| `1` | Noise from his right, first-time reaction: jolts awake wide-eyed, quick turn with shoulders following, leans in, settles |
| `2` | Same noise, irritated: face tightens first, eye-roll, snaps round to glare, huffs, turns away with eyes shut |
| `3` | Same noise, tired: one eye half opens, eyes drift over with almost no head turn, sags, sighs, sinks back |
| `4` | Looks at the book, leans if needed, reaches, grasps, lifts it to read, puts it back |
| `5` | Slides the book to the other place on the table; `4` then reaches there |
| `Space` | Autonomous mode on or off |
| `R` | Reset body, book, state and scheduler |
| `Esc` | Quit |

In autonomous mode the reaction is chosen from state: the first noise gets curiosity, a second within 40 seconds gets irritation, and high fatigue gets the tired response.

## Files

| File | Role |
| --- | --- |
| `scripts/config.gd` | All tunable numbers: movement styles per mood, expressions, limits, reach and fatigue constants |
| `scripts/character_state.gd` | Mood, fatigue, attention, remembered noises. No scene access |
| `scripts/behaviour_controller.gd` | Chooses reactions and idles; builds routines from motor commands; seeded random |
| `scripts/action_scheduler.gd` | Runs actions, queues conflicting ones, interrupts by priority, reset |
| `scripts/motor_controller.gd` | `look_at`, `turn_head`, `blink`, `express`, `lean`, `reach`, `grasp`, `release`, `return_to_rest` and a few more |
| `scripts/character_view.gd` | The primitive rig: meshes, pivots, face, arm solver, tweening of dials |
| `scripts/stage.gd` | Chair, table, book, book slots, noise sources |
| `scripts/main.gd` | Wiring, keys, overlay, self-test |

A second character replaces `character_view.gd` only. The interface it must provide is listed at the top of that file.

## Approximations

- **Arm:** an analytic two-segment solve with a fixed elbow direction and a reach clamp. No joint limits, no collision. The forearm can pass through the chair arm or the torso.
- **Lean for reach:** a bounded estimate from how far the target is beyond comfortable reach, not a solved pose.
- **Hand:** a sphere. Grasping attaches the book to the hand where it is; there are no fingers.
- **Release:** the book eases the last few millimetres onto its slot over 0.14 s.
- **Gaze:** angles are computed from the eye position ignoring torso lean.
- **Face:** shutter eyelids, bar brows, a two-bar mouth.

## Engine and footprint

- Godot 4.7.2-stable, standard build, macOS universal, from `github.com/godotengine/godot/releases/tag/4.7.2-stable`.
- SHA-512 of the zip, checked against the release's `SHA512-SUMS.txt` (kept in `local-tools/`): `38aa16e5…7bac69ca`.
- Renderer: Compatibility (OpenGL).
- Measured disk: `local-tools/Godot.app` 338 MB; this experiment 148 KB including a 24 KB `.godot` cache.
- Measured memory (resident, `ps`): 194 MB about 10 s after launch, 163 MB at about 120 s.
- `local-tools/`, `.local/` and `.godot/` are ignored by Git.

Godot writes outside the project and this cannot be redirected on macOS:

- `~/Library/Application Support/Godot/` (editor settings, and `app_userdata/Memory Keeper Living Character/` with a shader cache), 40 KB measured.
- `~/Library/Caches/Godot/`, 3.1 MB measured.

Logs from `run.sh` go to `.local/logs/run.log`.
