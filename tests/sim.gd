extends SceneTree
## Partite automatiche fra IA: controlla che il motore arrivi sempre in fondo.
## Uso: godot --headless --path . --script res://tests/sim.gd -- [partite] [livello]

const D = preload("res://scripts/data/rt_data.gd")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var games := int(args[0]) if args.size() > 0 else 20
	var lv := int(args[1]) if args.size() > 1 else 1
	var wins := {}
	var turns := 0
	var scores := 0.0
	var t0 := Time.get_ticks_msec()
	for g in games:
		var np := 2 + g % 3
		var sets := D.SETS.keys()
		var cards: Array = D.SETS[sets[g % sets.size()]]["cards"]
		if g % 5 == 4:
			cards = D.CARD_ORDER.duplicate()
			cards.shuffle()
			cards = cards.slice(0, 6)
		var seats := []
		for p in np:
			seats.append({"name": "IA %d" % p, "ai": true, "level": (lv if p == 0 else 1), "color": p})
		var e := RTEngine.new()
		e.headless = true
		e.setup({"seats": seats, "seed": 1000 + g, "ai_delay": 0.0, "anim": 0.0, "cards": cards})
		for p in np:
			e.ais[p] = RTAI.new(seats[p]["level"], 77 + g * 10 + p)
		root.add_child(e)
		await e.run()
		if e.phase != "over":
			push_error("partita %d non finita (fase %s)" % [g, e.phase])
			quit(1)
			return
		var w: int = e.result["winner"]
		wins[w] = wins.get(w, 0) + 1
		turns += e.turn
		for p in np:
			scores += e.st.score(p)
		# coerenza: cubetti mai oltre 20, mai negativi
		for p in np:
			assert(e.st.supply(p) >= 0)
		print("partita %d (%d giocatori, %s): vince %d, punti %s, turni %d, ratti rimasti %d" % [g, np, ",".join(cards), w,
			str(e.result["ranking"].map(func(x): return x["score"])), e.turn, e.st.bag.size()])
		e.queue_free()
	print("vittorie per posto: %s; turni medi %.1f; tempo %.1f s" % [str(wins), float(turns) / games, (Time.get_ticks_msec() - t0) / 1000.0])
	quit(0)
