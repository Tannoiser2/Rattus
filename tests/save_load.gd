extends SceneTree
## Prova di salvataggio e caricamento (sul finto Firebase): gioca qualche turno, salva,
## ricarica dal codice e controlla che la partita ripresa sia identica (impronta) e prosegua.

var ai := RTAI.new(1, 4)

func _init() -> void:
	_run()

func _wait(s: float) -> void:
	await create_timer(s).timeout

func _play_until(g, turn: int) -> void:
	while g.engine.turn < turn or g.pending.is_empty() or g.pending["kind"] != "action":
		await process_frame
		if not g.pending.is_empty() and not (g.engine.turn >= turn and g.pending["kind"] == "action"):
			g._submit(ai.decide(g.engine, g.pending["seat"], g.pending))

func _run() -> void:
	var main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await _wait(0.5)
	var seats := [{"name": "Io", "ai": false, "level": 1, "color": 0}, {"name": "", "ai": true, "level": 1, "color": 1}, {"name": "", "ai": true, "level": 2, "color": 2}]
	main.start_game({"seats": seats, "ai_delay": 0.0, "anim": 0.0, "seed": 77, "cards": ["fornaio", "strega", "suora", "crociato", "regina", "borgomastro"]})
	var g = main.current
	await _play_until(g, 6)
	var fp1: String = g.engine.fingerprint()
	await g._save_game()
	var code: String = g.save_code
	print("RTTEST salvata ", code, " ", fp1)
	main.show_menu()
	await _wait(0.3)
	var menu = main.current
	menu._load_panel()
	menu.on_code.text = code
	await menu._do_load()
	var g2 = main.current
	while g2.pending.is_empty():
		await process_frame
	print("RTTEST ripresa ", g2.engine.fingerprint(), " ", "OK" if g2.engine.fingerprint() == fp1 else "DIVERSA")
	await _play_until(g2, 9)
	print("RTTEST prosegue fino al turno ", g2.engine.turn)
	quit()
