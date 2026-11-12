## Sound effects: positional pool (AudioStreamPlayer3D), UI/2D pool, and the player's looping beds
## (skydive wind, zip line, storm rumble). game.sfx(id, pos) lands here; pos == Vector3.INF plays non-positionally.
## Everything goes through a "SFX" bus (child of "Master"), so the settings slider on Master scales it.
class_name GameAudio
extends Node3D

const POOL_3D := 24
const POOL_2D := 8
const DIR := "res://sounds/"
const NO_POS := Vector3.INF

## id -> {f: [files], db: volume, d: max distance (m), u: unit size, p: pitch multiplier, ...}
const SOUNDS := {
	"pistol": {"f": ["shot_pistol"], "db": 0.0, "d": 150.0, "u": 12.0},
	"shotgun": {"f": ["shot_shotgun"], "db": 2.0, "d": 150.0, "u": 14.0},
	"assault_rifle": {"f": ["shot_rifle"], "db": 0.0, "d": 150.0, "u": 12.0},
	"smg": {"f": ["shot_pistol"], "db": -2.0, "d": 130.0, "u": 10.0, "p": 1.3},
	"tactical_shotgun": {"f": ["shot_shotgun"], "db": 1.0, "d": 140.0, "u": 13.0, "p": 1.15},
	"burst_rifle": {"f": ["shot_rifle"], "db": -1.0, "d": 150.0, "u": 12.0, "p": 1.12},
	"hunting_rifle": {"f": ["shot_sniper"], "db": 2.0, "d": 170.0, "u": 16.0, "p": 1.18},
	"sniper_rifle": {"f": ["shot_sniper"], "db": 3.0, "d": 180.0, "u": 18.0},
	"rocket_launcher": {"f": ["shot_rocket"], "db": 2.0, "d": 150.0, "u": 14.0},
	"explosion": {"f": ["explosion"], "db": 4.0, "d": 200.0, "u": 20.0},
	"throw": {"f": ["grenade_throw"], "db": -3.0, "d": 40.0, "u": 5.0},
	"reload": {"f": ["reload_light"], "db": -4.0, "d": 40.0, "u": 5.0},
	"reload_heavy": {"f": ["reload_heavy"], "db": -3.0, "d": 45.0, "u": 6.0},
	"reload_pump": {"f": ["shell_pump"], "db": -3.0, "d": 45.0, "u": 6.0},
	"empty": {"f": ["empty_click"], "db": -4.0, "d": 30.0, "u": 4.0},
	"hit_wood": {"f": ["pickaxe_hit_wood"], "db": -2.0, "d": 50.0, "u": 6.0},
	"hit_stone": {"f": ["pickaxe_hit_stone"], "db": -2.0, "d": 50.0, "u": 6.0},
	"hit_metal": {"f": ["pickaxe_hit_metal"], "db": -2.0, "d": 50.0, "u": 6.0},
	"weak_point": {"f": ["weak_point"], "db": -2.0, "ui": true},
	"break_wood": {"f": ["break_wood"], "db": 0.0, "d": 90.0, "u": 10.0},
	"break_stone": {"f": ["break_stone"], "db": 0.0, "d": 90.0, "u": 10.0},
	"break_metal": {"f": ["break_stone"], "db": 0.0, "d": 90.0, "u": 10.0},
	"build": {"f": ["build_place"], "db": -2.0, "d": 60.0, "u": 7.0},
	"footstep": {"f": ["footstep_grass_1", "footstep_grass_2"], "db": -8.0, "d": 40.0, "u": 3.0},
	"footstep_wood": {"f": ["footstep_wood"], "db": -7.0, "d": 40.0, "u": 3.0},
	"jump": {"f": ["jump"], "db": -6.0, "d": 35.0, "u": 3.0},
	"land": {"f": ["land"], "db": -4.0, "d": 40.0, "u": 4.0},
	"swim": {"f": ["swim_stroke"], "db": -7.0, "d": 35.0, "u": 3.0},
	"splash": {"f": ["splash"], "db": -1.0, "d": 70.0, "u": 8.0},
	"glide": {"f": ["glider_open"], "db": -2.0, "d": 70.0, "u": 8.0},
	"storm_enter": {"f": ["storm_enter"], "db": 0.0, "ui": true},
	"pickup": {"f": ["pickup"], "db": -3.0, "ui": true},
	"chest_open": {"f": ["chest_open"], "db": 0.0, "d": 60.0, "u": 8.0},
	"use": {"f": ["heal_use"], "db": -2.0, "d": 40.0, "u": 5.0},
	"use_heal": {"f": ["heal_use"], "db": -2.0, "d": 40.0, "u": 5.0},
	"use_shield": {"f": ["shield_use"], "db": -2.0, "d": 40.0, "u": 5.0},
	"hit_marker": {"f": ["hit_marker"], "db": -3.0, "ui": true},
	"elimination": {"f": ["elimination"], "db": 0.0, "ui": true},
	"hurt": {"f": ["hurt"], "db": -2.0, "ui": true},
	"victory": {"f": ["victory"], "db": 0.0, "ui": true},
	"launch": {"f": ["launch_pad"], "db": 0.0, "d": 80.0, "u": 8.0},
	"rift": {"f": ["rift"], "db": 0.0, "d": 80.0, "u": 8.0},
	"supply_drop_land": {"f": ["supply_drop_land"], "db": 2.0, "d": 120.0, "u": 12.0},
	"ui_click": {"f": ["ui_click"], "db": -4.0, "ui": true},
	"ui_ready": {"f": ["ui_ready"], "db": -3.0, "ui": true},
}
const LOOPS := {"skydive_wind": "skydive_wind", "zip_line": "zip_line", "storm_loop": "storm_loop"}
const LOOP_DB := {"skydive_wind": -6.0, "zip_line": -8.0, "storm_loop": -4.0}
const STORM_FADE := 60.0                 # metres from the wall at which the rumble starts

var game: Node
var streams := {}                        # file -> AudioStreamMP3 (or null when missing)
var pool3: Array[AudioStreamPlayer3D] = []
var pool2: Array[AudioStreamPlayer] = []
var born := {}                           # player instance id -> start time (ms)
var last_ms := {}                        # id -> last 2D play time (ms), to avoid machine-gunning
var loops := {}                          # loop id -> AudioStreamPlayer
var was_outside := false
var missing: Array = []
var enabled := true


func setup(g: Node) -> void:
	game = g
	enabled = not game.autotest                   # the 8x autotest skips all audio work
	_ensure_bus()
	for i in POOL_3D:
		var p := AudioStreamPlayer3D.new()
		p.bus = "SFX"
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p)
		pool3.append(p)
	for i in POOL_2D:
		var p2 := AudioStreamPlayer.new()
		p2.bus = "SFX"
		add_child(p2)
		pool2.append(p2)
	for id in LOOPS:
		var lp := AudioStreamPlayer.new()
		lp.bus = "SFX"
		lp.volume_db = -80.0
		var s := _stream(LOOPS[id], true)
		if s:
			lp.stream = s
		add_child(lp)
		loops[id] = lp


func _ensure_bus() -> void:
	if AudioServer.get_bus_index("SFX") >= 0:
		return
	AudioServer.add_bus()
	var i := AudioServer.bus_count - 1
	AudioServer.set_bus_name(i, "SFX")
	AudioServer.set_bus_send(i, "Master")


func _stream(file: String, loop := false) -> AudioStream:
	var key := file + ("#loop" if loop else "")
	if streams.has(key):
		return streams[key]
	var path := DIR + file + ".mp3"
	var s: AudioStream = null
	if ResourceLoader.exists(path):
		s = load(path)
		if loop and s is AudioStreamMP3:
			s = s.duplicate()
			s.loop = true
	streams[key] = s
	return s


func has_sound(id: String) -> bool:
	## True when the id is mapped and every file behind it exists.
	if not SOUNDS.has(id):
		return false
	for f in SOUNDS[id].f:
		if not ResourceLoader.exists(DIR + f + ".mp3"):
			return false
	return true


func camera_pos() -> Vector3:
	var c := get_viewport().get_camera_3d()
	return c.global_position if c else Vector3.ZERO


func near_camera(pos: Vector3, dist: float) -> bool:
	return enabled and camera_pos().distance_squared_to(pos) < dist * dist


func play(id: String, pos := NO_POS) -> void:
	if not enabled:
		return
	var def = SOUNDS.get(id)
	if def == null:
		return
	var file: String = def.f[randi() % def.f.size()]
	var s := _stream(file)
	if s == null:
		return
	var pitch := randf_range(0.92, 1.08) * float(def.get("p", 1.0))      # "p": base pitch of this id
	if pos == NO_POS or def.get("ui", false):
		var now := Time.get_ticks_msec()
		if now - int(last_ms.get(id, -1000)) < 60:
			return
		last_ms[id] = now
		var p2: AudioStreamPlayer = _pick(pool2)
		p2.stream = s
		p2.volume_db = def.db
		p2.pitch_scale = pitch
		p2.play()
		born[p2.get_instance_id()] = now
		return
	var dist: float = def.d
	if camera_pos().distance_squared_to(pos) > dist * dist:
		return
	var p: AudioStreamPlayer3D = _pick(pool3)
	p.stream = s
	p.global_position = pos
	p.volume_db = def.db
	p.max_distance = dist
	p.unit_size = def.u
	p.pitch_scale = pitch
	p.play()
	born[p.get_instance_id()] = Time.get_ticks_msec()


func _pick(pool: Array) -> Node:
	var oldest = pool[0]
	var oldest_t := 1 << 60
	for p in pool:
		if not p.playing:
			return p
		var t: int = born.get(p.get_instance_id(), 0)
		if t < oldest_t:
			oldest_t = t
			oldest = p
	return oldest


func _process(delta: float) -> void:
	if not enabled or game == null:
		return
	var pl: Actor = game.player
	var live: bool = pl != null and pl.alive() and not game.over
	_loop("skydive_wind", live and pl.state == Actor.State.SKYDIVE and not pl.launched, 0.0, delta)
	_loop("zip_line", live and pl.zip != null, 0.0, delta)
	var k := 0.0
	if live and game.storm.active:
		var out: float = game.storm.outside(pl.global_position)
		k = clampf((out + STORM_FADE) / STORM_FADE, 0.0, 1.0)
		k = k * k
		var now_out := out > 0.0
		if now_out and not was_outside:
			play("storm_enter")
		was_outside = now_out
	_loop("storm_loop", k > 0.01, k, delta)


func _loop(id: String, on: bool, level: float, delta: float) -> void:
	var lp: AudioStreamPlayer = loops[id]
	if lp.stream == null:
		return
	var target := -80.0
	if on:
		target = LOOP_DB[id] + (linear_to_db(maxf(level, 0.001)) if id == "storm_loop" else 0.0)
	lp.volume_db = move_toward(lp.volume_db, target, delta * 60.0)
	if lp.volume_db > -70.0 and not lp.playing:
		lp.play()
	elif lp.volume_db <= -70.0 and lp.playing:
		lp.stop()


# ----------------------------------------------------------------------------- helpers called by actors

func footstep(a: Actor, speed: float) -> void:
	## One step; quieter when crouched, a wooden thud on built pieces. Skipped for far-away actors.
	if not near_camera(a.global_position, 60.0):
		return
	var id := "footstep"
	var res: Dictionary = game.ray(a.global_position + Vector3(0, 0.3, 0), a.global_position + Vector3(0, -1.2, 0), a, 1)
	if not res.is_empty() and res.collider != null:
		var e = game.structures.lookup(res.collider, res.get("shape", 0))
		if e != null and e.kind == "build" and e.mat == "wood":
			id = "footstep_wood"
	var def = SOUNDS[id]
	var s := _stream(def.f[randi() % def.f.size()])
	if s == null:
		return
	var p: AudioStreamPlayer3D = _pick(pool3)
	p.stream = s
	p.global_position = a.global_position
	p.volume_db = def.db + (-6.0 if a.crouched else 0.0) + (3.0 if speed > 7.0 else 0.0)
	p.max_distance = def.d
	p.unit_size = def.u
	p.pitch_scale = randf_range(0.92, 1.08)
	p.play()
	born[p.get_instance_id()] = Time.get_ticks_msec()


func material_sound(prefix: String, mat: String) -> String:
	return prefix + ("wood" if mat == "wood" else ("metal" if mat == "metal" else "stone"))
