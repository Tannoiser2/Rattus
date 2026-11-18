extends SceneTree
## Diagnosi del comportamento dell'IA: carte prese, cubetti aggiunti, mucchi più alti.
const D = preload("res://scripts/data/rt_data.gd")
func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var games := int(args[0]) if args.size() > 0 else 12
	var lv := int(args[1]) if args.size() > 1 else 1
	var over := {}
	for a in args.slice(2):
		var kv: PackedStringArray = a.split("=")
		over[kv[0]] = float(kv[1])
	var tot := {"take": 0, "turns": 0, "maxpop": 0, "place": 0, "card_use": 0, "reveal": 0, "out": 0, "empty": 0, "final_rev": 0}
	for g in games:
		var np := 2 + g % 3
		var seats := []
		for p in np:
			seats.append({"name": "IA%d" % p, "ai": true, "level": lv, "color": p})
		var e := RTEngine.new()
		e.headless = true
		var sets := D.SETS.keys()
		e.setup({"seats": seats, "seed": 900 + g, "ai_delay": 0.0, "anim": 0.0, "cards": D.SETS[sets[g % 4]]["cards"]})
		for p in np:
			var ai := RTAI.new(lv, 11 + g * 7 + p)
			for k in over:
				ai.K[k] = over[k]
			e.ais[p] = ai
		var mx := [0]
		e.log_added.connect(func(t):
			if t.contains("si scopre un ratto") or t.begins_with("Epidemia"):
				if e.phase == "final": tot["final_rev"] += 1
				else: tot["reveal"] += 1
			if t.begins_with("Epidemia"): tot["out"] += 1
			if t.contains("non c'è nessuno") or (t.contains("muove la Peste") and false): tot["empty"] += 1
			if t.contains("prende la carta"): tot["take"] += 1
			elif t.contains(" mette ") and t.contains("cubett") and not t.contains("Preparazione"): tot["place"] += 1
			elif t.contains(") "): tot["card_use"] += 1)
		e.changed.connect(func():
			for r in e.st.regions():
				mx[0] = maxi(mx[0], e.st.total(r)))
		root.add_child(e)
		await e.run()
		tot["turns"] += e.turn
		tot["maxpop"] = maxi(tot["maxpop"], mx[0])
		if false: print("partita %d: %d giocatori, turni %d, mucchio max %d, punti %s" % [g, np, e.turn, mx[0], str(e.result["ranking"].map(func(x): return x["score"]))])
		e.queue_free()
	print("RATTI scoperti durante la partita %d (epidemie in tutto %d), nella devastazione finale %d; Peste in regioni senza nessuno %d" % [tot["reveal"], tot["out"], tot["final_rev"], tot["empty"]])
	print("DIAG livello %d: turni %d, carte prese %d (%.2f per turno), aggiunte %d, poteri %d, mucchio max %d" % [lv, tot["turns"], tot["take"], float(tot["take"]) / tot["turns"], tot["place"], tot["card_use"], tot["maxpop"]])
	quit()
