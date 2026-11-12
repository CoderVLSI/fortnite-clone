## Island terrain maths, shared by the level builder and the game.
## World units are metres; +X is east, +Z is south, Y is up; sea level is Y = 0.
## The stage 2 island (400 x 400 m) sits in the middle of a larger one, about 800 x 800 m: snowy mountains to the
## north, desert with dunes, mesas and an oasis river to the south, and green country east and west.
class_name IslandTerrain
extends RefCounted

const MAP_SCALE := 400.0 / 1157.0          # metres per pixel of the reference map
const LAKE_LEVEL := 2.2
const LAND := 4.0
const SIZE := 395.0                         # coast "radius" of the big island (a rounded square)

var n_coast := FastNoiseLite.new()
var n_big := FastNoiseLite.new()
var n_small := FastNoiseLite.new()
var river: PackedVector2Array
var river_len := 0.0
var roads: Array = []                       # Array of PackedVector2Array
var lake := Vector2.ZERO
var lake_r := 27.0
var village := Vector2.ZERO
var yard := Vector2.ZERO
var yard_rot := deg_to_rad(-25.0)
var farm := Vector2.ZERO
var towers: Array = []
var hills: Array = []
var fields: Array = []                      # [centre, half-size, colour]
var n_ridge := FastNoiseLite.new()
var n_dune := FastNoiseLite.new()
var n_edge := FastNoiseLite.new()
# the outer regions
var snow_town := Vector2(-90, -318)
var desert_town := Vector2(-150, 318)
var depot := Vector2(205, 300)
var west_hamlet := Vector2(-318, 60)
var east_cove := Vector2(318, -70)
var extra_towers: Array = [Vector2(110, -300), Vector2(-300, 250), Vector2(300, 120)]
var mesas: Array = [[Vector2(-30, 300), 26.0, 12.0], [Vector2(30, 262), 18.0, 9.0], [Vector2(-280, 340), 22.0, 14.0], [Vector2(290, 230), 20.0, 10.0]]
var flats: Array = []                       # [centre, radius, height] building plateaus in the outer regions


static func px(x: float, y: float) -> Vector2:
	return Vector2((x - 627.0) * MAP_SCALE, (y - 627.0) * MAP_SCALE)


func _init() -> void:
	n_coast.seed = 11; n_coast.frequency = 0.012
	n_big.seed = 5; n_big.frequency = 0.012
	n_small.seed = 9; n_small.frequency = 0.06
	n_ridge.seed = 21; n_ridge.frequency = 0.0055
	n_ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	n_ridge.fractal_octaves = 3
	n_dune.seed = 33; n_dune.frequency = 0.01
	n_edge.seed = 41; n_edge.frequency = 0.008
	lake = px(615, 205)
	village = px(625, 600)
	yard = px(360, 860)
	farm = px(975, 320)
	towers = [px(360, 148), px(1030, 800), px(622, 1060)]
	hills = [[towers[0], 15.0, 30.0], [px(190, 300), 8.0, 34.0], [px(760, 120), 9.0, 30.0], [px(470, 250), 5.0, 30.0],
			 [towers[1], 16.0, 27.0], [towers[2], 19.0, 32.0], [px(180, 520), 4.0, 50.0], [px(120, 700), 7.0, 40.0], [px(420, 1060), 9.0, 34.0], [px(800, 1100), 8.0, 28.0]]
	for p in [[640, 240], [690, 285], [735, 330], [760, 400], [775, 470], [830, 560], [855, 620], [835, 690], [790, 740],
			  [735, 800], [710, 860], [730, 920], [770, 970], [815, 1015], [845, 1060], [862, 1110], [880, 1190]]:
		river.append(px(p[0], p[1]))
	for q in [Vector2(96, 232), Vector2(88, 275), Vector2(108, 318), Vector2(98, 360), Vector2(112, 400), Vector2(120, 440)]:
		river.append(q)                           # on through the desert: an oasis river down to the new coast
	for i in river.size() - 1:
		river_len += river[i].distance_to(river[i + 1])
	var rd := [
		[[255, 330], [380, 345], [480, 400], [520, 445], [600, 440], [700, 420], [758, 422], [830, 430], [940, 440], [1020, 470]],
		[[360, 165], [385, 230], [370, 300], [380, 345]],
		[[440, 110], [470, 200], [500, 300], [520, 445]],
		[[475, 600], [380, 610], [300, 600], [250, 640], [200, 720], [190, 800], [210, 900], [260, 980], [400, 1010], [520, 960], [560, 860], [575, 780], [600, 750]],
		[[250, 725], [350, 740], [450, 790], [540, 840]],
		[[640, 750], [700, 770], [765, 768], [840, 780], [900, 720], [950, 640], [1010, 600], [1040, 520], [1020, 470]],
		[[1020, 470], [1050, 400], [1000, 330]],
		[[840, 780], [870, 880], [960, 900], [1040, 860], [1032, 815]],
		[[520, 960], [600, 980], [622, 1045]],
		[[830, 430], [880, 360], [940, 300]],
		[[765, 768], [760, 900], [790, 980]],
		[[520, 445], [500, 520], [475, 600]],
	]
	var ring: Array = []
	for i in 17:
		var a := TAU * i / 16.0
		ring.append([625 + cos(a) * 150, 600 + sin(a) * 150])
	rd.append(ring)
	for r in rd:
		var pl := PackedVector2Array()
		for p in r:
			pl.append(px(p[0], p[1]))
		roads.append(pl)
	fields = [[px(890, 270), Vector2(13, 13), Color(0.86, 0.72, 0.2)], [px(1045, 290), Vector2(15, 12), Color(0.3, 0.55, 0.2)],
			  [px(950, 372), Vector2(17, 13), Color(0.5, 0.36, 0.2)]]
	# roads out to the new towns
	for r2 in [[px(360, 165), Vector2(-60, -230), Vector2(-85, -290), snow_town], [px(622, 1060), Vector2(-40, 250), Vector2(-110, 300), desert_town],
			[px(1032, 815), Vector2(170, 210), depot], [px(255, 330), Vector2(-250, 40), west_hamlet], [px(1020, 470), Vector2(240, -40), east_cove]]:
		var pl2 := PackedVector2Array()
		for q2 in r2:
			pl2.append(q2)
		roads.append(pl2)
	# plateaus the outer buildings stand on (their height is the natural height at the centre)
	for c in [[snow_town, 46.0], [desert_town, 44.0], [depot, 40.0], [west_hamlet, 34.0], [east_cove, 32.0]]:
		flats.append([c[0], c[1], 0.0])
	for t in extra_towers:
		flats.append([t, 12.0, 0.0])
	for f in flats:
		f[2] = _outer_height(f[0]) - (0.6 if f[1] < 20.0 else 0.0)


static func seg_dist(p: Vector2, a: Vector2, b: Vector2) -> Vector2:
	## Returns (distance, t along the segment).
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return Vector2(p.distance_to(a + ab * t), t)


func river_info(p: Vector2) -> Vector2:
	## (distance to the river centre line, fraction 0..1 from the lake to the sea)
	var best := 1e9
	var best_t := 0.0
	var acc := 0.0
	for i in river.size() - 1:
		var l := river[i].distance_to(river[i + 1])
		var d := seg_dist(p, river[i], river[i + 1])
		if d.x < best:
			best = d.x
			best_t = (acc + l * d.y) / river_len
		acc += l
	return Vector2(best, best_t)


func river_point(t: float) -> Vector2:
	var want := clampf(t, 0.0, 1.0) * river_len
	var acc := 0.0
	for i in river.size() - 1:
		var l := river[i].distance_to(river[i + 1])
		if acc + l >= want:
			return river[i].lerp(river[i + 1], (want - acc) / l)
		acc += l
	return river[river.size() - 1]


func water_level(t: float) -> float:
	return LAKE_LEVEL * (1.0 - smoothstep(0.0, 0.9, t))


func road_dist(p: Vector2) -> float:
	var best := 1e9
	for pl in roads:
		for i in pl.size() - 1:
			if absf(p.x - pl[i].x) > 60.0 and absf(p.x - pl[i + 1].x) > 60.0:
				continue
			best = minf(best, seg_dist(p, pl[i], pl[i + 1]).x)
	return best


func coast(p: Vector2) -> float:
	## Signed distance to the coast: positive on land.
	var a := atan2(p.y, p.x)
	var c := absf(cos(a))
	var s := absf(sin(a))
	var sq := 1.0 / pow(pow(c, 4.0) + pow(s, 4.0), 0.25)
	var r := SIZE * sq + 26.0 * n_coast.get_noise_2d(cos(a) * 90.0, sin(a) * 90.0) + 8.0 * sin(a * 5.0 + 1.0)
	return r - p.length()


func snow(p: Vector2) -> float:
	## 0..1: how far into the snowy north this is (with a ragged edge).
	return smoothstep(-185.0, -245.0, p.y + n_edge.get_noise_2d(p.x, 0.0) * 25.0)


func desert(p: Vector2) -> float:
	## 0..1: how far into the southern desert this is.
	return smoothstep(200.0, 250.0, p.y + n_edge.get_noise_2d(p.x, 500.0) * 25.0)


func outer(p: Vector2) -> float:
	## 0 on the stage 2 island, 1 out in the new country around it (where the old coast used to be).
	var a := atan2(p.y, p.x)
	var sq := 1.0 / pow(pow(absf(cos(a)), 4.0) + pow(absf(sin(a)), 4.0), 0.25)
	return smoothstep(175.0 * sq, 215.0 * sq, p.length())


func _outer_height(p: Vector2) -> float:
	## The relief of the new country: mountains in the north, dunes and mesas in the south, rolling hills between.
	var sn := snow(p)
	var de := desert(p)
	var h := LAND + n_big.get_noise_2d(p.x * 0.7, p.y * 0.7) * 3.0
	# snowy mountains: ridges that grow towards the north edge
	var ridge := (n_ridge.get_noise_2d(p.x, p.y) * 0.5 + 0.5)
	h += sn * (6.0 + ridge * 26.0 * smoothstep(-200.0, -320.0, p.y))
	# desert: long dunes, and flat-topped mesas with steep sides
	var dune := sin(p.x * 0.045 + n_dune.get_noise_2d(p.x, p.y) * 4.0) * 0.5 + 0.5
	h += de * (dune * 3.2 + n_dune.get_noise_2d(p.x * 2.0, p.y * 2.0) * 1.2)
	for m in mesas:
		var d: float = p.distance_to(m[0])
		h += de * m[2] * (1.0 - smoothstep(m[1] - 5.0, m[1] + 3.0, d))
	return h


func raw_height(p: Vector2) -> float:
	var land := smoothstep(-22.0, 14.0, coast(p))
	var ow := outer(p)
	var h := lerpf(-7.0, lerpf(LAND, _outer_height(p), ow), land)
	var bumps := 0.0
	for hl in hills:
		var d: float = p.distance_to(hl[0])
		bumps += hl[1] * exp(-d * d / (2.0 * hl[2] * hl[2]))
	h += bumps * smoothstep(-6.0, 22.0, coast(p))
	h += (n_big.get_noise_2d(p.x, p.y) * 1.3 + n_small.get_noise_2d(p.x, p.y) * 0.25) * land
	# beaches: the land slopes gently into the sea all round
	h = lerpf(h, minf(h, 0.4 + maxf(coast(p), -20.0) * 0.07), 1.0 - smoothstep(10.0, 40.0, coast(p)))
	return h


func height(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var h := raw_height(p)
	for zone in [[village, 62.0, LAND], [yard, 64.0, LAND], [farm, 62.0, LAND + 0.3]]:
		var w := 1.0 - smoothstep(zone[1] * 0.62, zone[1], p.distance_to(zone[0]))
		h = lerpf(h, zone[2], w)
	for f in flats:
		var d0: float = p.distance_to(f[0])
		if d0 < f[1]:
			var wf := 1.0 - smoothstep(f[1] * 0.6, f[1], d0)
			h = lerpf(h, f[2], wf)
	for t in towers:
		var w2 := 1.0 - smoothstep(7.0, 15.0, p.distance_to(t))
		if w2 > 0.0:
			h = lerpf(h, raw_height(t) - 0.6, w2)
	var dl := p.distance_to(lake)
	h = lerpf(h, LAKE_LEVEL - 2.6, 1.0 - smoothstep(lake_r - 6.0, lake_r + 9.0, dl))
	var ri := river_info(p)
	if ri.x < 14.0:
		h = lerpf(h, minf(h, water_level(ri.y) - 1.7), 1.0 - smoothstep(4.0, 12.0, ri.x))
	return h


func in_yard(p: Vector2, margin := 0.0) -> bool:
	var q := (p - yard).rotated(-yard_rot)
	return absf(q.x) < 50.0 + margin and absf(q.y) < 37.0 + margin


func water_surface(x: float, z: float) -> float:
	## Height of the water surface here, or -1000 where there is none (sea, lake and river).
	var h := height(x, z)
	var best := -1000.0
	if h < 0.0:
		best = 0.0
	var p := Vector2(x, z)
	if p.distance_to(lake) < lake_r + 9.0:
		best = maxf(best, LAKE_LEVEL)
	var ri := river_info(p)
	if ri.x < 11.5:
		best = maxf(best, water_level(ri.y) + 0.02)
	return best if best > h else -1000.0


func is_water(x: float, z: float) -> bool:
	var p := Vector2(x, z)
	if p.distance_to(lake) < lake_r + 4.0:
		return true
	return river_info(p).x < 9.0 or height(x, z) < 0.6
