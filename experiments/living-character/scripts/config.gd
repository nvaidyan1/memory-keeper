extends RefCounted
## Tunable performance parameters. Nothing here knows about geometry.
##
## A style changes HOW a motor command is performed (timing and posture);
## an expression is a set of face dial values. Moods map to one of each.

const T_SINE := Tween.TRANS_SINE
const T_BACK := Tween.TRANS_BACK
const T_QUAD := Tween.TRANS_QUAD

## speed            multiplier on every duration (higher = quicker)
## turn_time        seconds for a head turn at speed 1
## eye_delay        seconds before the eyes move
## head_delay       seconds before the head follows the eyes
## head_share       how much of the gaze angle the head takes (rest goes to the eyes)
## anticipation     radians the head first moves the opposite way
## head_tilt        degrees of sideways tilt added in the turn direction
## shoulder_follow  fraction of the head turn the shoulders take
## shoulder_lag     seconds the shoulders trail the head
## gaze_dwell       seconds the look is held
## intensity        expression strength 0..1
## trans            tween transition used for the head turn
const STYLES := {
	"calm": {
		"speed": 1.25, "turn_time": 0.42, "eye_delay": 0.0, "head_delay": 0.09,
		"head_share": 0.72, "anticipation": 0.13, "head_tilt": 13.0,
		"shoulder_follow": 0.30, "shoulder_lag": 0.16, "gaze_dwell": 1.5,
		"intensity": 1.0, "trans": T_SINE,
	},
	"irritated": {
		"speed": 1.7, "turn_time": 0.40, "eye_delay": 0.0, "head_delay": 0.0,
		"head_share": 0.9, "anticipation": 0.0, "head_tilt": -5.0,
		"shoulder_follow": 0.06, "shoulder_lag": 0.0, "gaze_dwell": 1.1,
		"intensity": 1.0, "trans": T_BACK,
	},
	"tired": {
		"speed": 0.5, "turn_time": 0.5, "eye_delay": 0.25, "head_delay": 0.5,
		"head_share": 0.18, "anticipation": 0.0, "head_tilt": 3.0,
		"shoulder_follow": 0.0, "shoulder_lag": 0.0, "gaze_dwell": 0.9,
		"intensity": 0.8, "trans": T_SINE,
	},
	# Unhurried, deliberate movement used for the book.
	"task": {
		"speed": 0.9, "turn_time": 0.5, "eye_delay": 0.0, "head_delay": 0.12,
		"head_share": 0.8, "anticipation": 0.0, "head_tilt": 4.0,
		"shoulder_follow": 0.2, "shoulder_lag": 0.12, "gaze_dwell": 0.6,
		"intensity": 1.0, "trans": T_SINE,
	},
}

## Face dials: lid 0 = open, 1 = closed. "_l" is the character's own left.
const EXPRESSIONS := {
	"asleep":     {"lid_l": 1.0, "lid_r": 1.0, "brow_l": 0.0, "brow_r": 0.0, "brow_angle": 0.0, "mouth_curve": 0.0, "mouth_open": 0.45},
	"alarmed":    {"lid_l": 0.0, "lid_r": 0.0, "brow_l": 1.0, "brow_r": 1.0, "brow_angle": -0.6, "mouth_curve": -0.5, "mouth_open": 0.8},
	"indignant":  {"lid_l": 0.3, "lid_r": 0.3, "brow_l": -0.5, "brow_r": -0.5, "brow_angle": 1.0, "mouth_curve": -0.8, "mouth_open": 0.35},
	"yawn":       {"lid_l": 1.0, "lid_r": 1.0, "brow_l": 0.9, "brow_r": 0.9, "brow_angle": -0.4, "mouth_curve": 0.0, "mouth_open": 1.0},
	"absorbed":   {"lid_l": 0.45, "lid_r": 0.45, "brow_l": -0.4, "brow_r": -0.4, "brow_angle": 0.45, "mouth_curve": -0.1, "mouth_open": 0.0},
	"amused":     {"lid_l": 0.5, "lid_r": 0.5, "brow_l": 0.4, "brow_r": 0.4, "brow_angle": -0.2, "mouth_curve": 1.0, "mouth_open": 0.3},
	"astonished": {"lid_l": 0.0, "lid_r": 0.0, "brow_l": 1.0, "brow_r": 1.0, "brow_angle": 0.0, "mouth_curve": 0.1, "mouth_open": 0.6},
	"neutral":    {"lid_l": 0.25, "lid_r": 0.25, "brow_l": 0.0, "brow_r": 0.0, "brow_angle": 0.0, "mouth_curve": 0.0, "mouth_open": 0.0},
	"startled":   {"lid_l": 0.0, "lid_r": 0.0, "brow_l": 1.0, "brow_r": 1.0, "brow_angle": -0.2, "mouth_curve": 0.0, "mouth_open": 1.0},
	"curious":    {"lid_l": 0.1, "lid_r": 0.15, "brow_l": 1.0, "brow_r": 0.3, "brow_angle": 0.0, "mouth_curve": 0.25, "mouth_open": 0.15},
	"irritated":  {"lid_l": 0.42, "lid_r": 0.42, "brow_l": -0.8, "brow_r": -0.8, "brow_angle": 1.0, "mouth_curve": -1.0, "mouth_open": 0.0},
	"tired_peek": {"lid_l": 0.62, "lid_r": 1.0, "brow_l": 0.5, "brow_r": -0.2, "brow_angle": -0.3, "mouth_curve": -0.35, "mouth_open": 0.0},
	"tired":      {"lid_l": 0.75, "lid_r": 0.8, "brow_l": 0.0, "brow_r": 0.0, "brow_angle": -0.6, "mouth_curve": -0.35, "mouth_open": 0.0},
	"content":    {"lid_l": 0.4, "lid_r": 0.4, "brow_l": 0.2, "brow_r": 0.2, "brow_angle": 0.0, "mouth_curve": 0.5, "mouth_open": 0.0},
}

# Body limits, radians.
const MAX_HEAD_YAW := 1.15
const MAX_HEAD_PITCH := 0.55
const MAX_EYE_ANGLE := 0.5
const MAX_LEAN := 0.42

# Reaching.
const REACH_TIME := 0.9          # seconds for one reach at speed 1
const REACH_ARC := 0.06          # metres the hand lifts mid-reach
const REACH_COMFORT := 0.88      # fraction of arm length used before the torso leans
const LEAN_PER_METRE := 3.5      # radians of lean per metre out of comfortable reach
const GRASP_TOLERANCE := 0.06    # metres between hand and grip point for a grasp to succeed

# Internal state.
const STIMULUS_MEMORY := 40.0    # seconds a noise is remembered
const FATIGUE_PER_REACTION := 0.14
const FATIGUE_PER_TASK := 0.22
const FATIGUE_RECOVERY := 0.012  # per second at rest
const TIRED_ABOVE := 0.6

# Stage and camera.
const CLOUD_DRIFT := true        # false freezes the sky
const CLOUD_SPEED := 0.0022      # sky texture widths per second; a cloud crosses the frame in minutes
const CAMERA_ANGLE := 0.0        # degrees round the character; 0 is straight on, -12 is the angled view
const BACKDROP := "painting"     # "painting" uses assets/backgrounds/backpainting.jpeg; "procedural" builds the MVP-1 loggia
const BACKDROP_IMAGE := "res://assets/backgrounds/backpainting.jpeg"

# Web remote and live view.
const WEB_PORT := 8002
const STREAM_FPS := 20           # frames a second sent to each viewer
const STREAM_QUALITY := 0.72     # JPEG quality 0..1
