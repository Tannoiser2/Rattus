extends SceneTree
## Confronto fra l'IA nuova (posto a rotazione) e la vecchia (tests/ai_old.gd) o fra due tarature.
## Uso: godot --headless --path . --script res://tests/tara_ia.gd -- <partite> [chiave=valore ...]
## Stampa la quota di vittorie dell'IA nuova rispetto a quella attesa (1/giocatori).

const D = preload("res://scripts/data/rt_data.gd")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var games := int(args[0]) if args.size() > 0 else 60
	var over := {}
	for a in args.slice(1):
		var kv: PackedStringArray = a.split("=")
		over[kv[0]] = float(kv[1])
	var won := 0.0
	var expect := 0.0
	var margin := 0.0
	for g in games:
		var np := 2 + g % 3
		var sets := D.SETS.keys()
		var cards: Array = D.SETS[sets[(g / 3) % sets.size()]]["cards"]
		var me := g % np
		var seats := []
		for p in np:
			seats.append({"name": "IA %d" % p, "ai": true, "level": 1, "color": p})
		var e := RTEngine.new()
		e.headless = true
		e.setup({"seats": seats, "seed": 5000 + g, "ai_delay": 0.0, "anim": 0.0, "cards": cards})
		for p in np:
			if p == me:
				var a := RTAI.new(int(over.get("level", 1)), 300 + g)
				for k in over:
					if k == "level":
						continue
					if k == "samples":
						a._samples = int(over[k])
					else:
						a.K[k] = over[k]
				e.ais[p] = a
			else:
				e.ais[p] = RTAIOld.new(1, 77 + g * 10 + p)
		root.add_child(e)
		await e.run()
		var top: int = e.result["ranking"][0]["score"]
		var ties := 0
		for x in e.result["ranking"]:
			if x["score"] == top:
				ties += 1
		if e.st.score(me) == top:
			won += 1.0 / ties
		expect += 1.0 / np
		var best_other := 0
		for p in np:
			if p != me:
				best_other = maxi(best_other, e.st.score(p))
		margin += e.st.score(me) - best_other
		e.queue_free()
	print("TARA %s vittorie %.1f su %d (attese %.1f) quota %.2f, scarto medio %.2f" % [str(over), won, games, expect, won / expect, margin / games])
	quit(0)
