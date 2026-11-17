extends SceneTree
## Fotografie dell'interfaccia (serve un display, anche virtuale: xvfb-run).
## Uso: xvfb-run -s "-screen 0 1920x1080x24" godot --path . -s tests/shot.gd -- <cartella> [giocatori] [larghezza] [altezza] [carte]
## La persona (Rosso) lascia decidere all'IA; si fotografano le varie decisioni la prima volta che compaiono.

const D = preload("res://scripts/data/rt_data.gd")

var out := "/tmp/shots"
var taken := {}


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	var np := int(args[1]) if args.size() > 1 else 4
	var w := int(args[2]) if args.size() > 2 else 1920
	var h := int(args[3]) if args.size() > 3 else 1080
	var set_key := args[4] if args.size() > 4 else "base"
	DirAccess.make_dir_recursive_absolute(out)
	_run(np, w, h, set_key)


func _snap(name: String) -> void:
	await process_frame
	await process_frame
	await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [out, name])
	print("foto ", name)


func _run(np: int, w: int, h: int, set_key: String) -> void:
	root.size = Vector2i(w, h)
	DisplayServer.window_set_size(Vector2i(w, h))
	var main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await create_timer(1.0).timeout
	await _snap("menu")
	main.current.card_set = 6
	main.current.nplayers = 2
	main.current._refresh()
	main.current._refresh_cards()
	await create_timer(0.3).timeout
	await _snap("menu_libera")
	main.show_rules()
	await create_timer(0.5).timeout
	await _snap("regole")
	main.current._show(["Le carte di classe", ""])
	await create_timer(0.5).timeout
	await _snap("regole_carte")
	var seats := []
	for i in np:
		seats.append({"name": "Stefano" if i == 0 else "", "ai": i != 0, "level": 1, "color": i})
		if i != 0:
			seats[i]["name"] = "%s (IA)" % D.COLORS[i]["name"]
	var cards: Array = D.SETS[set_key]["cards"] if D.SETS.has(set_key) else D.CARD_ORDER.slice(0, 6)
	if set_key == "mix":
		cards = ["contadino", "strega", "vescovo", "suora", "imperatore", "mago"]
	main.start_game({"seats": seats, "seed": 4242, "ai_delay": 0.05, "anim": 6.0, "cards": cards})
	var view = main.current
	var e: RTEngine = view.engine
	var ai := RTAI.new(1, 99)
	var t0 := Time.get_ticks_msec()
	var shots := 0
	while e.phase != "over" and Time.get_ticks_msec() - t0 < 240000:
		await process_frame
		var req: Dictionary = view.pending
		if req.is_empty():
			continue
		var k: String = req.get("kind", "")
		var key := k
		if k == "action" and e.turn >= 6:
			key = "action_tardi"
		if not taken.has(key) and shots < 24:
			taken[key] = true
			shots += 1
			await create_timer(0.4).timeout
			await _snap("%02d_%s" % [shots, key])
		if view.pending.is_empty():
			continue
		view._submit(ai.decide(e, req["seat"], req))
	await create_timer(1.5).timeout
	await _snap("fine")
	view.board3d.top_view(true)
	var dl = view.popup_layer.get_children()
	for c in dl:
		c.queue_free()
	await create_timer(0.5).timeout
	await _snap("fine_alto")
	quit(0)
