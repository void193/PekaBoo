extends Node
## Talks to the relay server. Messages are JSON dictionaries with a "t" (type) field.

signal message(m: Dictionary)
signal disconnected(reason: String)

## Online servers. Render (Singapore) is the default; the Mumbai VPS is usually a little faster from Nepal.
const RENDER_SERVER := "wss://pekaboo-relay.onrender.com"
const VPS_SERVER := "ws://3.109.56.218:8787"
const DEFAULT_SERVER := RENDER_SERVER

var server_url := DEFAULT_SERVER
var ws: WebSocketPeer
var state := "idle"  # idle, connecting, open
var my_id := -1
var host_id := -1
var room := ""
var players := {}  # int id -> {name, color}
var _first := {}
var _t := 0.0
var connect_timeout := 90.0
var latency_ms := -1
var _ping_sent_ms := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func is_online() -> bool:
	return (state == "open" or state == "offline") and my_id >= 0


## A local match against a bot: no server, messages are delivered straight back to us.
func start_offline(my_name: String, my_char: int, bot_name: String, bot_char: int) -> void:
	close()
	state = "offline"
	my_id = 1
	host_id = 1
	room = "BOT"
	players = {1: {"name": my_name, "color": my_char}, 2: {"name": bot_name, "color": bot_char}}


func is_offline() -> bool:
	return state == "offline"


func is_host() -> bool:
	return my_id >= 0 and my_id == host_id


func open(first: Dictionary) -> void:
	close()
	ws = WebSocketPeer.new()
	# roomy buffers: a phone that hiccups for a moment shouldn't make messages get dropped
	ws.inbound_buffer_size = 1 << 20
	ws.outbound_buffer_size = 1 << 20
	_first = first
	_t = 0.0
	var err := ws.connect_to_url(server_url.strip_edges())
	if err != OK:
		state = "idle"
		disconnected.emit("Couldn't reach the server. Check the address in Server settings.")
		return
	state = "connecting"


var _waker: HTTPRequest


## Render's free plan sleeps when nobody plays for a while. Poke it as soon as the game opens,
## so it's awake by the time you tap Host online / Join online.
func wake_server() -> void:
	if not server_url.begins_with("wss://") and not server_url.begins_with("ws://"):
		return
	if _waker == null:
		_waker = HTTPRequest.new()
		_waker.timeout = 90.0
		add_child(_waker)
	var http := server_url.replace("wss://", "https://").replace("ws://", "http://")
	_waker.cancel_request()
	_waker.request(http)


func close() -> void:
	latency_ms = -1
	_ping_sent_ms = -1
	if ws != null and state != "idle" and state != "offline":
		ws.close()
	state = "idle"
	my_id = -1
	host_id = -1
	room = ""
	players.clear()


func send(m: Dictionary) -> void:
	if state == "open" and ws != null:
		ws.send_text(JSON.stringify(m))


## Sends to everyone else and also delivers the message to ourselves.
func broadcast(m: Dictionary) -> void:
	send(m)
	var local := m.duplicate(true)
	local["from"] = my_id
	message.emit(local)


func _process(dt: float) -> void:
	if state == "idle" or state == "offline" or ws == null:
		return
	ws.poll()
	_t += dt
	match ws.get_ready_state():
		WebSocketPeer.STATE_CONNECTING:
			if _t > connect_timeout:
				close()
				disconnected.emit("Couldn't reach that game. Make sure you're on the same hotspot or Wi-Fi." if connect_timeout < 30.0 else "The server didn't answer. Try again in a minute.")
		WebSocketPeer.STATE_OPEN:
			if state == "connecting":
				state = "open"
				_t = 0.0
				# send small messages straight away instead of bundling them (Nagle) - that adds lag
				ws.set_no_delay(true)
				send(_first)
			while state == "open" and ws.get_available_packet_count() > 0:
				var m = JSON.parse_string(ws.get_packet().get_string_from_utf8())
				if m is Dictionary:
					_handle(m)
			if _ping_sent_ms >= 0 and Time.get_ticks_msec() - _ping_sent_ms > 5000:
				latency_ms = -1
				_ping_sent_ms = -1
			if _t > 2.0 and _ping_sent_ms < 0:
				_t = 0.0
				_ping_sent_ms = Time.get_ticks_msec()
				send({"t": "ping"})
		WebSocketPeer.STATE_CLOSED:
			var was_in := my_id >= 0
			close()
			disconnected.emit("Lost connection to the server." if was_in else "Couldn't connect to the server.")


func _handle(m: Dictionary) -> void:
	match str(m.get("t", "")):
		"welcome":
			my_id = int(m["id"])
			host_id = int(m["host"])
			room = str(m["room"])
			players.clear()
			for p in m["players"]:
				players[int(p["id"])] = {"name": str(p["name"]), "color": int(p["color"])}
		"peer_join":
			players[int(m["id"])] = {"name": str(m["name"]), "color": int(m["color"])}
		"peer_leave":
			players.erase(int(m["id"]))
		"host":
			host_id = int(m["id"])
		"error":
			var reason := str(m.get("msg", "Server error."))
			close()
			disconnected.emit(reason)
			return
		"pong":
			if _ping_sent_ms >= 0:
				latency_ms = maxi(0, Time.get_ticks_msec() - _ping_sent_ms)
				_ping_sent_ms = -1
			return
	if m.has("from"):
		m["from"] = int(m["from"])
	message.emit(m)
