# Living character (MVP-1.1)

A primitive seated mannequin that reacts, reaches and idles from a small set of reusable motor commands. It tests the architecture in `MEMORY_KEEPER_README.md`, not the look. The WebGL portrait prototype at the repository root is untouched.

## Run

From the repository root:

```sh
experiments/living-character/scripts/run.sh
```

Options: `--seed=7` (repeatable autonomous run), `--auto` (start autonomous), `--camera=-12` (angled view; the default is straight on), `--no-overlay`, `--no-web`, `--port=8002`.

To re-record the motion review video (204 s, 30 frames a second) into `review/motion_review.mp4`:

```sh
experiments/living-character/scripts/record_review.sh
```

The script uses `local-tools/Godot.app`. To use another Godot 4 build: `GODOT=/path/to/Godot experiments/living-character/scripts/run.sh`.

## Controls

Keyboard and web remote send the same command names through one function (`run_command` in `scripts/main.gd`, then `command` in `scripts/behaviour_controller.gd`).

| Key | Remote button | Command | What happens |
| --- | --- | --- | --- |
| `1` | Curious | `curious` | Bolts upright gripping the chair, whips round, cranes toward the noise, checks with the viewer, sinks back to sleep |
| `2` | Irritated | `irritated` | Eyes stay shut while he swells, eye-roll, snaps round to glare, flings a hand at the noise, turns his back on it |
| `3` | Tired | `tired` | One eye creaks open, a glance without lifting the head, a huge yawn behind his hand, collapses deeper |
| `4` | Read book | `read_book` | Wakes, reaches, lifts the book and reads with four beats drawn from a pool, then puts it back |
| `5` | Move book | `move_book` | Slides the book to the other place on the table |
| `6` | Frame lifted | `frame_lifted` | Lurches, grabs the frame edge with his right hand, plants the left on the table, glares out, lets go |
| `Space` | Autonomous | `toggle_auto` | Autonomous mode on or off |
| `R` | Reset | `reset` | Body, book, state and scheduler back to the home state |
| `O` | | | Show or hide the debug text (it is part of the picture the iPad sees) |
| `Esc` | | | Quit |

In autonomous mode the reaction is chosen from state: the first noise gets curiosity, a second within 40 seconds gets irritation, and high fatigue gets the tired response.

## iPad remote and live view

The scene serves its own page; nothing else needs to run.

1. Start the scene on the Mac: `experiments/living-character/scripts/run.sh --no-overlay`
2. If macOS asks whether Godot may accept incoming connections, allow it.
3. On the iPad, on the same Wi-Fi, open `http://<the Mac's address>:8002` in Safari. The address is printed by `ipconfig getifaddr en0`.

The page shows the live scene and the six buttons, the autonomous toggle and reset. The picture is a stream of JPEG frames (MJPEG) sent by `scripts/web_remote.gd`: 600 × 800, 20 frames a second, about 8 Mbit/s. `STREAM_FPS`, `STREAM_QUALITY` and `WEB_PORT` are in `scripts/config.gd`.

Measured on the Mac itself (not yet on an iPad): 20.0 frames a second with even 50 ms spacing; 42 to 96 ms from sending a command to the first changed frame arriving; 4 ms to grab and encode a frame; CPU 14% without a viewer and 24% with one.

Limits: no sound, no authentication (home network only), and the picture is the window's 600 × 800 scaled up by the iPad. This server is separate from the old painting prototype's page on port 8001.

`frame_lifted` is an ordinary command. A motion sensor later only has to send that name; nothing about the reaction depends on the button.

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
| `scripts/backdrop.gd` | The painted backdrop (`assets/backgrounds/backpainting.jpeg`) and floor; the MVP-1 procedural loggia is kept behind `BACKDROP` in the config |
| `scripts/web_remote.gd`, `web/remote.html` | The in-scene web server and the iPad page |
| `scripts/record_review.sh`, `scripts/encode_movie.swift` | Render the review sequences and join the frames into an .mp4 |
| `scripts/main.gd` | Wiring, keys, overlay, self-test |

A second character replaces `character_view.gd` only. The interface it must provide is listed at the top of that file.

## Stage and appearance

- **Backdrop:** the supplied painting on a flat cloth 2.5 m behind the chair, proportions kept. It is sized so the camera sees its middle band: the painted ledge meets a plain 3D floor, and the arched top with its black corners stays above the frame.
- **Camera:** straight on by default. `CAMERA_ANGLE` in `scripts/config.gd` or `--camera=-12` gives the angled view.
- **Home pose:** fast asleep. Head lolled back and aside, mouth open, sunk in the chair, left hand on the arm rest, right arm hanging over the other.
- **Character:** eyelids are half shells that roll over real eyeballs; the moustache follows the mouth; a cape, flared sleeves and a draped lap hide the joints.
- **Review material:** `review/` holds screenshots and the recording (the recording is not in Git).

## Approximations

- **Arm:** an analytic two-segment solve with a fixed elbow direction and a reach clamp. No joint limits, no collision. The forearm can pass through the chair arm or the torso.
- **Lean for reach:** a bounded estimate from how far the target is beyond comfortable reach, not a solved pose.
- **Bracing:** the target is pulled in to 92% of arm length, so the hand on the frame edge stops a little short of the true edge of the picture.
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
