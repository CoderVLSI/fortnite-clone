## LAN party and session layer (autoload "Net"). One player hosts from the lobby, others find the game (UDP beacon on the
## Wi-Fi) or type its IP, everyone sees the party, the host presses PLAY and all load the same match.
## Transport: ENet (Godot high-level multiplayer). In the match, scripts/net_match.gd (a child of the game scene) carries
## the snapshots, inputs, commands and world events. LAN only: nothing here talks to the internet.
extends Node

const PORT := 24680
const DISC_PORT := 24681
const MAX_PLAYERS := 4
const GAME_SCENE := "res://scenes/game.tscn"
const MENU_SCENE := "res://scenes/menu.tscn"
const MAGIC := "island-royale-1"

signal party_changed
signal status_changed(msg: String)
signal left(reason: String)
signal found_changed

var role := "off"                       # "off" | "host" | "client"
var peers: Array = []                   # {id, name, outfit, ready}; the host is id 1
var my_name := ""
var my_outfit := 0
var status := ""
var match_info: Dictionary = {}         # {seed, mode, players: [{peer_id, name, outfit}], difficulty}
var in_match := false
var loaded := {}                        # peer id -> true once that client has built the match scene
var found := {}                         # ip -> {name, ip, port, players, t}
var last_message := ""                  # shown in the lobby after being dropped
var autostart := false                  # --net-autostart: the host starts the match once the party has two players
var autostart_t := 0.0
var auto_join_ip := ""
var _beacon: PacketPeerUDP
var _beacon_t := 0.0
var _listener: PacketPeerUDP
var _dest: Array = []


func _ready() -> void:
	my_name = "Player%d" % (100 + randi() % 900)
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		var a: String = args[i]
		if a.begins_with("--net-name="):
			my_name = a.get_slice("=", 1)
		elif a == "--net-host" or a == "--nettest-host":
			auto_join_ip = ""
			role = "pending_host"
			if a == "--nettest-host":
				autostart = true
		elif a == "--net-autostart":
			autostart = true
		elif a == "--net-join" or a == "--nettest-client":
			auto_join_ip = "127.0.0.1"
			if a == "--net-join" and i + 1 < args.size() and not String(args[i + 1]).begins_with("--"):
				auto_join_ip = args[i + 1]
				i += 1
			role = "pending_client"
		elif a.begins_with("--net-join="):
			auto_join_ip = a.get_slice("=", 1)
			role = "pending_client"
		i += 1
	var st := get_node_or_null("/root/Settings")
	if st and st.get("outfit") != null:
		my_outfit = int(st.outfit)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connect_failed)
	multiplayer.server_disconnected.connect(_on_server_gone)
	if role == "pending_host":
		role = "off"
		host_lobby.call_deferred()
	elif role == "pending_client":
		role = "off"
		join.call_deferred(auto_join_ip)


func is_active() -> bool:
	return role == "host" or role == "client"


func is_host() -> bool:
	return role == "host"


func my_id() -> int:
	return multiplayer.get_unique_id() if is_active() else 1


func _set_status(s: String) -> void:
	status = s
	status_changed.emit(s)


func local_ips() -> Array:
	## This device's LAN IPv4 addresses, private ranges first.
	var out: Array = []
	for ip in IP.get_local_addresses():
		var s := String(ip)
		if s.contains(":") or s.begins_with("127.") or s.begins_with("169.254."):
			continue
		out.append(s)
	out.sort_custom(func(a: String, b: String) -> bool:
		var pa := a.begins_with("192.168.") or a.begins_with("10.") or a.begins_with("172.")
		var pb := b.begins_with("192.168.") or b.begins_with("10.") or b.begins_with("172.")
		return pa and not pb)
	return out


func lan_ip() -> String:
	var l := local_ips()
	return l[0] if l.size() > 0 else "127.0.0.1"


# ----------------------------------------------------------------------------- hosting and joining

func host_lobby() -> bool:
	if is_active():
		return true
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_PLAYERS - 1)
	if err != OK:
		_set_status("Could not host (port %d busy?)" % PORT)
		return false
	multiplayer.multiplayer_peer = peer
	role = "host"
	in_match = false
	loaded.clear()
	peers = [{"id": 1, "name": my_name, "outfit": my_outfit, "ready": true}]
	_start_beacon()
	_stop_listener()
	_set_status("Hosting. Your IP: %s" % lan_ip())
	party_changed.emit()
	return true


func join(ip: String) -> void:
	if is_active():
		return
	ip = ip.strip_edges()
	if ip == "":
		_set_status("Type the host's IP address")
		return
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, PORT)
	if err != OK:
		_set_status("Could not connect to %s" % ip)
		return
	multiplayer.multiplayer_peer = peer
	role = "client"
	in_match = false
	_stop_listener()
	_set_status("Connecting to %s ..." % ip)


func leave(reason := "") -> void:
	var was := role
	_stop_beacon()
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	role = "off"
	peers = []
	loaded.clear()
	match_info = {}
	autostart = false
	if reason != "":
		last_message = reason
	_set_status(reason if reason != "" else "")
	party_changed.emit()
	if was != "off":
		left.emit(reason)
		if in_match:
			in_match = false
			get_tree().change_scene_to_file.call_deferred(MENU_SCENE)


func _on_peer_connected(id: int) -> void:
	if role == "host":
		if in_match or peers.size() >= MAX_PLAYERS:
			multiplayer.multiplayer_peer.disconnect_peer(id)


func _on_peer_disconnected(id: int) -> void:
	if role != "host":
		return
	for p in peers:
		if p.id == id:
			peers.erase(p)
			break
	loaded.erase(id)
	_push_party()
	var game := _game()
	if game and game.nm:
		game.nm.on_peer_left(id)
	_set_status("A player left the party")


func _on_connected() -> void:
	_set_status("Connected. Waiting for the host ...")
	rpc_id(1, "_r_hello", my_name, my_outfit)


func _on_connect_failed() -> void:
	leave("Could not connect to the host")


func _on_server_gone() -> void:
	leave("The host left the game")


func _game() -> Node:
	var s := get_tree().current_scene
	return s if s != null and s.has_method("alive_count") else null


# ----------------------------------------------------------------------------- party

@rpc("any_peer", "reliable")
func _r_hello(pname: String, outfit: int) -> void:
	if role != "host":
		return
	var id := multiplayer.get_remote_sender_id()
	for p in peers:
		if p.id == id:
			return
	peers.append({"id": id, "name": pname.substr(0, 16), "outfit": outfit, "ready": true})
	_push_party()
	_set_status("%s joined" % pname)


func _push_party() -> void:
	party_changed.emit()
	if role == "host" and multiplayer.get_peers().size() > 0:
		rpc("_r_party", peers)


@rpc("authority", "reliable")
func _r_party(list: Array) -> void:
	peers = list
	_set_status("In %s's party" % (peers[0].name if peers.size() > 0 else "the"))
	party_changed.emit()


func set_outfit(i: int) -> void:
	my_outfit = i
	if role == "host":
		peers[0].outfit = i
		_push_party()


# ----------------------------------------------------------------------------- starting the match

func start_match(mode := "") -> void:
	## Host only: pick the seed, tell everyone, everyone loads the match scene.
	if role != "host" or in_match:
		return
	var st := get_node_or_null("/root/Settings")
	if mode == "":
		mode = String(st.get("mode")) if st and st.get("mode") != null else "solo"
	var diff := "normal"
	if st and st.get("bot_difficulty") != null:
		diff = String(st.bot_difficulty)
	var plist: Array = []
	for p in peers:
		plist.append({"peer_id": p.id, "name": p.name, "outfit": p.outfit})
	var info := {"seed": int(Time.get_unix_time_from_system()) ^ (randi() & 0xFFFF), "mode": mode, "players": plist, "difficulty": diff}
	rpc("_r_begin", info)


@rpc("authority", "reliable", "call_local")
func _r_begin(info: Dictionary) -> void:
	match_info = info
	in_match = true
	loaded.clear()
	get_tree().change_scene_to_file(GAME_SCENE)


## A client says its match scene is built (the host waits for all of them before the warm-up runs).
@rpc("any_peer", "reliable")
func _r_loaded() -> void:
	if role == "host":
		loaded[multiplayer.get_remote_sender_id()] = true


func all_loaded() -> bool:
	if role != "host":
		return true
	for p in peers:
		if p.id != 1 and not loaded.get(p.id, false):
			return false
	return true


func match_over_cleanup() -> void:
	## Back from the match to the lobby: the party stays up (host keeps hosting) but a new match can be started.
	in_match = false
	loaded.clear()
	match_info = {}


# ----------------------------------------------------------------------------- LAN discovery

func _start_beacon() -> void:
	_stop_beacon()
	_beacon = PacketPeerUDP.new()
	_beacon.set_broadcast_enabled(true)
	_dest = ["255.255.255.255"]
	for ip in local_ips():
		var parts: PackedStringArray = String(ip).split(".")
		if parts.size() == 4:
			var d := "%s.%s.%s.255" % [parts[0], parts[1], parts[2]]
			if not _dest.has(d):
				_dest.append(d)
	_beacon_t = 0.0


func _stop_beacon() -> void:
	if _beacon:
		_beacon.close()
		_beacon = null


func start_find() -> void:
	## Listen for hosts' beacons (the lobby's Find games).
	if _listener != null or is_active():
		return
	_listener = PacketPeerUDP.new()
	_listener.set_broadcast_enabled(true)
	var err := _listener.bind(DISC_PORT)
	if err != OK:
		_listener = null
		_set_status("Cannot listen for games here: type the host's IP")
		return
	found.clear()


func _stop_listener() -> void:
	if _listener:
		_listener.close()
		_listener = null


func stop_find() -> void:
	_stop_listener()


func _process(delta: float) -> void:
	if _beacon != null and role == "host" and not in_match:
		_beacon_t -= delta
		if _beacon_t <= 0.0:
			_beacon_t = 1.0
			var pkt := JSON.stringify({"g": MAGIC, "name": my_name, "players": peers.size(), "port": PORT}).to_utf8_buffer()
			for d in _dest:
				_beacon.set_dest_address(d, DISC_PORT)
				_beacon.put_packet(pkt)
	if _listener != null:
		var changed := false
		while _listener.get_available_packet_count() > 0:
			var data := _listener.get_packet().get_string_from_utf8()
			var ip := _listener.get_packet_ip()
			var j = JSON.parse_string(data)
			if j is Dictionary and j.get("g", "") == MAGIC:
				found[ip] = {"name": String(j.get("name", "?")), "ip": ip, "port": int(j.get("port", PORT)), "players": int(j.get("players", 1)), "t": Time.get_ticks_msec()}
				changed = true
		var now := Time.get_ticks_msec()
		for ip in found.keys():
			if now - int(found[ip].t) > 4000:
				found.erase(ip)
				changed = true
		if changed:
			found_changed.emit()
	if autostart and role == "host" and not in_match and peers.size() >= 2:
		autostart_t += delta
		if autostart_t > 1.5:
			start_match()
