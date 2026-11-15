# Memory Keeper — A Living Character in a Frame

> An autonomous character with a private life, displayed as a portrait. Not a video playlist.

## Vision

Memory Keeper is an experiment in making a character appear to *live* inside a framed screen. The character sleeps, watches, reads, reacts, becomes curious or annoyed, settles into different postures, and develops recurring habits. Its actions should feel coherent, expressive, and responsive rather than like disconnected looping videos.

The first character is an elderly wizard seated in a chair, with a table and book nearby. The source portrait and an animated painting aesthetic are **visual references and later objectives**, not technical requirements for the first prototype. A crude cartoon or simple 3D mannequin is acceptable if its acting is convincing.

The ultimate goal is hundreds of behaviours assembled from a much smaller repertoire of reusable actions, not hundreds of separately rendered scenes.

## Priorities — in order

1. **Expressive character movement.** Articulated head, torso, arms, hands, and face; believable anticipation, pauses, weight, and follow-through.
2. **Reusable motor capabilities.** Gaze, turn, lean, reach, grasp, release, gesture, blink, posture changes, and object interaction; actions must work with varying targets.
3. **Coherent autonomy.** Internal attention, mood, habits, memory of recent events, interruptible activity selection, and non-repetitive routines.
4. **Reliable continuity.** No snapping, teleporting props, contradictory simultaneous actions, or visually impossible state transitions.
5. **Character interchangeability.** Behaviour logic and action interfaces separate from the first character's model and appearance.
6. **Rendering and painterly identity.** The supplied sleeping-wizard image and Fat Lady moving portrait reference guide eventual personality, framing, and art direction. Oil-paint texture, likeness, and detailed lighting can wait.

## Reference mood and acting

- **Sleeping wizard:** elderly, dignified, sometimes tired; seated, with long hair/beard, ornate chair, and book nearby. A plausible home position, not a requirement to reproduce the image in 3D today.
- **The Fat Lady portrait:** emphatic pantomime and emotional character; a person with independent intentions, not a subtly breathing photograph.
- **Classical theatrical animation:** readable silhouettes, anticipation, holds, exaggerated but controlled timing. Stylization and rough graphics are acceptable.
- **Silent acting:** emotional intent must read with no dialogue or sound.

## Hardware and distribution constraints

- Development machine: MacBook Air M2, 24 GB unified memory; no discrete GPU.
- Original target display: iPad Pro 9.7-inch (2016), portrait 1536 × 2048. It can remain a remote viewer; **desktop preview is enough for the first milestone**.
- Working project root: `/Users/nat/Documents/5. Experience/4. Fun stuff/Memory keeper`.
- All project-specific source, engine binaries when downloaded, assets, configurations, and helper scripts should live **under that root**, with relative paths wherever possible.
- Prefer Godot 4 standard (non-.NET) + GDScript. Avoid global package installs, Homebrew dependencies, Python virtual environments, Blender, ML weights, large animation packs, and export templates in the initial experiment.
- Prefer Godot's Compatibility renderer if it works well for the simple test. Measure before optimizing.
- Do not download a large asset before a primitive-based test proves the architecture. Keep generated caches out of Git; when practical, relocate user data and cache to project-local directories. Document any unavoidable macOS-level files.
- A project should remain portable by copying its folder to another compatible Mac, subject to any macOS permissions/quarantine prompts. Re-test on the destination machine.

## Proposed runtime architecture

```text
Event sources (timer, click; later mic / room sensors)
           |
           v
Character state (attention, mood, fatigue, recent history)
           |
           v
Behaviour selector (chooses goals and routines)
           |
           v
Action scheduler (interruptions, sequencing, resource ownership)
           |
           v
Motor API: look_at / turn / lean / blink / gesture /
           reach / grasp / release / return_to_rest
           |
           v
Animation controller (authored motion + procedural layers + IK)
           |
           v
Rig + props + camera -> renderer -> desktop / future iPad viewer
```

**Key invariant:** Behaviours request actions; they do not directly manipulate arbitrary scene nodes. A second character implements the same motor API using a new rig and presentation.

Separate *what the character intends* from *how the body performs it*. In particular, `reach(target)` must be target-relative, not a video that only works for one book position. The first reach may use a crude joint solver, but it must have a replaceable interface for better IK later.

## Minimum demonstrable experiment (MVP-0)

Create a lightweight, primitive-based 3D humanoid seated in a chair, with a simple face and a book on the nearby table. The model may be deliberately rough. A fixed portrait-oriented camera is sufficient.

**Controls:**

- `1` — calm / curious response to a disturbance
- `2` — irritated response to the same disturbance
- `3` — tired / dismissive response
- `4` — look at book, lean, reach, grasp, bring book closer, release / replace it
- `Space` — toggle autonomous behaviour
- `R` — reset to known coherent home state

**Acceptance criteria:**

1. Three reactions to the *same stimulus* are visibly distinguishable by head/shoulder timing, gaze, posture, and face, not merely colour or text labels.
2. A reusable gaze controller can look toward at least two different targets without authoring separate clips.
3. A reusable reach controller can target two nearby book positions (or markers), even with crude geometry. The hand must not simply teleport to the destination.
4. The book is attached to the hand while held and returns to a stable world position when released; no visual teleport at the grab/drop handoff.
5. Reactions and interactions can start and finish from a known seated state; resetting restores a coherent pose.
6. In autonomous mode, the character varies idles and reactions based on simple persistent mood/fatigue/recent-event state, with deterministic seed option for debugging.
7. Behaviour, motor control, presentation, and model/asset code are kept in separate files.
8. It runs locally with no cloud calls or external servers; reports measured startup RAM, disk size, and any runtime errors.

Avoid claiming photorealism, perfect IK, autonomous intelligence, or fully generalized object manipulation at this stage. Clearly label approximations.

## Iteration plan

- **MVP-0 — Motion and personality:** primitive character, reusable gaze/reach, 3 emotional performances, a tiny behaviour controller.
- **MVP-1 — Solid animation system:** replace crude primitives with a real skeletal humanoid, stronger joint limits and IK, expressive face controls, animation blending, and stable prop interaction.
- **MVP-2 — A lived-in world:** richer routines, attention, mood, habits, interruption handling, object affordances, limited recent memory, more props.
- **MVP-3 — Portrait presence:** reliable unattended running, idle variety, room-triggered reactions, Mac-to-iPad delivery.
- **MVP-4 — Visual identity:** recreate the wizard and painted style, preserving all proven behavioural capabilities.

## Existing prototype

The repository currently contains a WebGL single-image warp with breathing, head deformation, procedurally drawn eyes, and a keyed startle routine. Preserve it as a baseline and fallback. Its techniques may eventually augment the painterly renderer, but do **not** extend its shader into the principal movement architecture; a 2D warp cannot produce general articulated action or uncovered geometry.

Existing entry points include `index.html`, `PIPELINE.md`, `tools/build_rig.py`, and `characters/dumbledore/`. Do not delete or overwrite these in the first experiment.

## Suggested layout

```text
Memory keeper/
  README.md
  index.html                     # original prototype retained
  PIPELINE.md                    # original experimental pipeline retained
  characters/                    # original portrait assets retained
  tools/                         # original tools retained
  experiments/
    living-character/
      project.godot
      scenes/
      scripts/
      assets/
      README.md                  # experiment-specific run instructions
  local-tools/                   # optional portable Godot binary/app
  .local/                        # optional local temp, logs, userdata
```

Use project-relative references (`res://` in Godot) and scripts that derive the project root from their own location. Keep engine version and hashes recorded. Do not commit the editor binary or generated caches.

## What counts as success?

Leave the crude character on screen for an extended period. If someone glancing at the frame several times sees different, causally coherent activities and can infer curiosity, irritation, or fatigue from motion alone, the foundation works—even if it looks like a simple geometric cartoon.
