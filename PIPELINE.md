# Living portrait: how a character is made

This is the process for turning one painting into a portrait that appears to have a life of its own on an iPad. It is written so that any character can go through the same steps. Dumbledore asleep in his chair is the first one.

Status: step 1 is built and working. Steps 2 to 5 are the plan and will be corrected as each one is tried.

## The idea

A character is a small set of **rest poses** (stills he can stay in for a long time) joined by **transition clips** (short videos that move him from one pose to another).

- While he is in a rest pose, the iPad animates the still itself by gently warping it. This costs nothing to produce and never repeats exactly.
- When he changes pose, the iPad plays a pre-made video clip whose first frame is the pose he is leaving and whose last frame is the pose he is arriving at.

The split exists because warping can only move paint that is already on the canvas. Breathing, a swaying beard and flickering light are fine. Opening his eyes, lifting an arm or holding a book needs paint that is not in the picture, so those moments are video.

## Dumbledore's first scene

| Rest pose | What the iPad animates live |
|---|---|
| `asleep` | slow breathing, candle flicker |
| `awake` | breathing, small head movement |
| `reading` | breathing, slight book movement |

| Transition clip | From → to |
|---|---|
| `startle` | asleep → awake |
| `take-book` | awake → reading |
| `turn-page` | reading → reading |
| `doze-off` | reading → asleep |

The "noise" that startles him is a random timer at first. A real microphone trigger comes later (see Open questions).

## Steps for any character

### 1. Home pose and live idle (done for Dumbledore)

1. Create `characters/<name>/` and put the painting in it.
2. Write `character.json` with one state and its breathing regions. Each region is a soft circle that rises and swells with the breath:
   - `x`, `y`: centre, as a fraction of the image (0,0 is top left)
   - `r`: radius, as a fraction of image height
   - `dx`, `dy`: how far it shifts at full inhale (negative `dy` is up)
   - `swell`: how much it expands outward
   - `delay`: fraction of a breath it lags behind the chest
3. Open the page with `?character=<name>&debug=1` to see the regions tinted red, and adjust until they sit on the chest, shoulders and head.

Keep the movement small. If straight edges behind the figure (chair, frame, wall) visibly bend, shrink the region or its amounts.

### 1b. Head rig and routines (done for Dumbledore, as a trial)

This lets the head lift, turn and lean, and the eyes open, squint and look around, with no extra artwork.

1. Write `characters/<name>/rig.json`: two outlines in pixel coordinates of the painting.
   - `figure`: the character's outline wherever a moving part could slide over the background.
   - `head`: the part that moves rigidly. Movement fades out around it, so beard and hair stretch.
2. Run `python3 tools/build_rig.py <name>`. It writes `rig.png` (the mask and head weight) and `plate.jpg` (the painting with the head painted out, shown where the head moves away).
3. In `character.json`, set the neck pivot and the two eyes (centre on the closed lash line, half width, tilt, brightness). The open eyes are drawn by the page, not painted.
4. Write a routine as a list of keyframes. Each keyframe names a time and the dials it changes: `upright`, `lift`, `shift`, `lean`, `turn`, `eyes`, `gazeX`, `gazeY`, `brow`, `jolt`, `breathRate`. Dials are the same for every character, so a routine can be copied from one to another.
5. Open the page with `?freeze=<seconds>` to hold the routine at one moment while adjusting.

Limits found so far: the fill behind the head is a soft dark blur, so detail that was hidden behind the head (here, a gold rib of the chair) does not reappear. Drawn eyes hold up at squint and at this size; they have not been judged close up or wide open for long.

### 2. Rest-pose stills

Make one still per additional rest pose with an image-editing model, using the home pose as the reference so the face, clothes, chair and lighting stay the same. Only the figure should change. Check each new still by flipping between it and the home pose: anything in the background that jumps will show as a pop later.

All stills for a character must be the same size.

### 3. Transition clips

Generate each clip with an image-to-video model that takes a **first frame and a last frame**. Give it the two rest-pose stills and a short description of the movement, and ask for a locked camera.

- Length: 3 to 6 seconds.
- Export as H.264 MP4, no audio track, same aspect ratio as the stills, at most 1536×2048.
- Reject clips where the face changes, the camera drifts, or the background shifts.

### 4. Behaviour

Add the new states and clips to `character.json` and describe which clips can leave each state and how likely each is. The player stays in a rest pose for a random time, picks a clip, plays it, and lands in the next rest pose with a short crossfade to hide any mismatch.

### 5. On the iPad

Target device: iPad Pro 9.7-inch (2016), iPadOS 16.7, screen 1536×2048 in portrait.

1. On the Mac, in this folder: `python3 -m http.server 8001`
2. On the iPad, in Safari: `http://<Mac's IP address>:8001`
3. Share → Add to Home Screen, then open it from the home screen so it runs full screen.
4. Settings → Display & Brightness → Auto-Lock → Never. Keep it plugged in.
5. Settings → Accessibility → Guided Access, to stop stray touches leaving the page.

## Open questions

- **Offline use.** The iPad currently needs the Mac running. Hosting the folder on any static web host, with the files cached on the iPad, removes that.
- **Real noise trigger.** Safari only allows microphone access on a secure (https) page, which the Mac's local server is not. Hosting the page solves this too.
- **Clip quality.** Whether first-and-last-frame generation holds a painted likeness well enough is untested until the first `startle` clip is made.
