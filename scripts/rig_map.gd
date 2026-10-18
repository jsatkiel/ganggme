extends RefCounted
## Bone names: the skeleton the crew animations are made for (Quaternius base body / UAL) -> the user's
## Mixamo-rigged male body (assets/characters/male). Both stand in a T-pose, so poses carry over directly.

const PREFIX := "mixamorig_"
const SIDES := {"l": "Left", "r": "Right"}
const LIMBS := {"clavicle": "Shoulder", "upperarm": "Arm", "lowerarm": "ForeArm", "hand": "Hand",
	"thigh": "UpLeg", "calf": "Leg", "foot": "Foot", "ball": "ToeBase"}
const FINGERS := {"thumb": "Thumb", "index": "Index", "middle": "Middle", "ring": "Ring", "pinky": "Pinky"}
const TRUNK := {"pelvis": "Hips", "spine_01": "Spine", "spine_02": "Spine1", "spine_03": "Spine2", "neck_01": "Neck", "Head": "Head"}

static var _back := {}


static func to_mixamo(q: String) -> String:
	## "" when the bone has no counterpart (root, leaf ends)
	if TRUNK.has(q):
		return PREFIX + TRUNK[q]
	var side := q.get_slice("_", q.get_slice_count("_") - 1)
	if not SIDES.has(side):
		return ""
	var base := q.get_slice("_", 0)
	if LIMBS.has(base) and q.get_slice_count("_") == 2:
		return PREFIX + SIDES[side] + LIMBS[base]
	if FINGERS.has(base) and q.get_slice_count("_") == 3:
		var n := q.get_slice("_", 1).to_int()
		if n >= 1 and n <= 3:
			return PREFIX + SIDES[side] + "Hand" + FINGERS[base] + str(n)
	return ""


static func to_crew(m: String) -> String:
	## the animation-skeleton bone a Mixamo bone corresponds to (end bones fold into their parent)
	if _back.is_empty():
		for q in TRUNK:
			_back[PREFIX + TRUNK[q]] = q
		for s in SIDES:
			for b in LIMBS:
				_back[PREFIX + SIDES[s] + LIMBS[b]] = "%s_%s" % [b, s]
			for f in FINGERS:
				for n in range(1, 5):
					_back[PREFIX + SIDES[s] + "Hand" + FINGERS[f] + str(n)] = "%s_0%d_%s" % [f, mini(n, 3), s]
			_back[PREFIX + SIDES[s] + "Toe_End"] = "ball_" + s
			_back[PREFIX + SIDES[s] + "Eye"] = "Head"
		_back[PREFIX + "HeadTop_End"] = "Head"
	return _back.get(m, "")
