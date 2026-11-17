class_name RTEngine
extends Node
## Motore delle regole di Rattus (con l'espansione Pied Piper), senza grafica.
## Ogni scelta passa da `decide()`: una richiesta {kind, text, opts: [{label, …}]} a cui si risponde con
## l'indice dell'opzione scelta. L'IA risponde subito; per le persone viene emesso `decision_requested`
## e si attende `provide_decision()`. Online le scelte viaggiano nel registro di mosse (OnlineSession):
## con lo stesso seme ogni dispositivo gioca la stessa partita. Anche i salvataggi sono registri di mosse.
##
## Le opzioni possono indicare sul tabellone: "r" regione, "e" confine, "tok" [regione, posizione] di un
## gettone, "cube" [regione, giocatore], "c" carta.

const D = preload("res://scripts/data/rt_data.gd")

signal changed
signal log_added(text: String)
signal decision_requested(req: Dictionary)
signal decision_provided(result)
signal game_ended(result: Dictionary)
signal fx(kind: String, data: Dictionary)

var players: Array = []          # [{name, ai, level, color}]
var ais: Array = []
var online = null
var ai_delay := 0.6
var anim := 1.0
var headless := false
var abort := false
var rng := RandomNumberGenerator.new()
var n := 0
var st: RTState
var replay: Array = []
var replay_i := 0
var record: Array = []
var log_lines: Array = []

var cur := -1                    # giocatore di turno
var first := 0
var turn := 0
var phase := "setup"             # "setup", "turn", "plague", "final", "over"
var took := false
var placed := false
var used := {}                   # carte usate in questo turno
var ending := false              # la riserva dei ratti è finita
var revealed: Array = []         # gettoni scoperti nella regione della Peste: [{tid, r}]
var last_reveal := {}            # ultimo gettone scoperto (per la grafica)
var final_knight := -1           # regione dove la Peste conta come due abitanti nella devastazione finale
var final_serf := -1             # giocatore con il Servo nella devastazione finale
var result := {}
var history: Array = []          # punteggi dopo ogni turno


# ================================================================ preparazione

func setup(cfg: Dictionary) -> void:
	players = cfg.get("seats", [])
	n = players.size()
	if cfg.has("seed"):
		rng.seed = int(cfg["seed"])
	else:
		rng.randomize()
	ai_delay = float(cfg.get("ai_delay", 0.6))
	anim = float(cfg.get("anim", 1.0))
	replay = cfg.get("replay", [])
	st = RTState.new()
	var cards: Array = cfg.get("cards", D.BASE_SET)
	st.init(n, cards)
	st.logger = log_msg
	ais.resize(n)


func pname(p: int) -> String:
	if p < 0 or p >= n:
		return "nessuno"
	var nm: String = str(players[p].get("name", ""))
	return nm if nm != "" else D.COLORS[pcol(p)]["name"]


func pcol(p: int) -> int:
	return int(players[p].get("color", p))


func log_msg(t: String) -> void:
	log_lines.append(t)
	log_added.emit(t)


func cname(c: String) -> String:
	return D.CARDS[c]["name"]


func _pace(sec: float) -> void:
	if headless or anim <= 0.0 or abort or not is_inside_tree():
		return
	if online != null and online.catchup:
		return
	if replay_i < replay.size():
		return
	await get_tree().create_timer(sec / anim).timeout


func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var t = a[i]
		a[i] = a[j]
		a[j] = t


# ================================================================ decisioni

func decide(seat: int, req: Dictionary) -> int:
	req["seat"] = seat
	if not req.has("text"):
		req["text"] = ""
	changed.emit()
	var r
	if replay_i < replay.size():
		r = replay[replay_i]
		replay_i += 1
	elif abort:
		r = ais[seat].decide(self, seat, req)
	elif online != null:
		r = await online.decide(self, seat, req)
	elif players[seat]["ai"]:
		if ai_delay > 0.0 and not headless and is_inside_tree():
			await get_tree().create_timer(ai_delay).timeout
		r = ais[seat].decide(self, seat, req)
	else:
		decision_requested.emit(req)
		r = await decision_provided
		if r == null:
			r = ais[seat].decide(self, seat, req)
	var k := int(r) if (r is int or r is float) else 0
	var opts: Array = req.get("opts", [])
	if opts.is_empty():
		k = -1
	else:
		k = clampi(k, 0, opts.size() - 1)
	record.append(k)
	return k


func provide_decision(r) -> void:
	decision_provided.emit(r)


## Scelta di una regione fra quelle date. Con skip l'ultima opzione è «nessuna» (restituisce -1).
func ask_region(p: int, kind: String, text: String, regs: Array, skip := "") -> int:
	var opts := []
	for r in regs:
		opts.append({"label": st.rname(r), "r": r})
	if skip != "":
		opts.append({"label": skip, "skip": true})
	if opts.is_empty():
		return -1
	var k := await decide(p, {"kind": kind, "text": text, "opts": opts})
	return -1 if k < 0 or opts[k].get("skip", false) else int(opts[k]["r"])


func ask_yes(p: int, kind: String, text: String, yes: String, no: String) -> bool:
	var k := await decide(p, {"kind": kind, "text": text, "opts": [{"label": yes, "y": true}, {"label": no, "y": false}]})
	return k == 0


# ================================================================ partita

func run() -> void:
	_setup_game()
	changed.emit()
	await _pace(0.6)
	await _setup_placement()
	if abort:
		return
	phase = "turn"
	while true:
		cur = (first + turn) % n
		await _turn(cur)
		if abort:
			return
		_snap()
		turn += 1
		if ending:
			log_msg("La riserva dei ratti è esaurita: la partita finisce.")
			break
		if st.supply(cur) <= 0 and st.baker[cur] == 0:
			log_msg("%s ha tutti i suoi cubetti sul tabellone: la partita finisce." % pname(cur))
			break
	await _final()


## Impronta della partita (per controllare che online tutti i dispositivi abbiano giocato la stessa).
func fingerprint() -> String:
	var parts := []
	for p in n:
		parts.append(str(st.score(p)))
	return "%s|%d|%s" % [",".join(parts), record.size(), str(hash(str(record)))]


func _snap() -> void:
	var row := []
	for p in n:
		row.append(st.score(p))
	history.append(row)


func _setup_game() -> void:
	var starts := []
	var normal := []
	for i in D.RATS.size():
		if i < D.START_RATS:
			starts.append(i)
		else:
			normal.append(i)
	_shuffle(starts)
	_shuffle(normal)
	# con meno di 4 giocatori si tolgono dei ratti (non quelli iniziali)
	var cut := 12 if n == 2 else (6 if n == 3 else 0)
	for i in cut:
		normal.pop_back()
	var regs := st.regions()
	for r in regs:
		st.rats[r].append(starts.pop_back())
	st.bag = normal + starts
	_shuffle(st.bag)
	st.plague = regs[rng.randi() % regs.size()]
	first = rng.randi() % n
	log_msg("La peste nera arriva in Europa, anno 1347. Regioni in gioco: %d. Carte di classe: %s." % [regs.size(), ", ".join(st.cards.map(cname))])
	log_msg("La Peste parte da %s. Comincia %s." % [st.rname(st.plague), pname(first)])


func _setup_placement() -> void:
	phase = "setup"
	var order := []
	for i in n:
		order.append((first + i) % n)
	var back := order.duplicate()
	back.reverse()
	for p in order + back:
		cur = p
		var r := await ask_region(p, "setup", "Preparazione: metti due tuoi cubetti in una regione.", st.regions())
		if abort:
			return
		st.add_cubes(p, r, 2)
		log_msg("%s mette due cubetti in %s." % [pname(p), st.rname(r)])
		fx.emit("cubes", {"r": r, "p": p})
		changed.emit()
		await _pace(0.25)


# ================================================================ turno

func _turn(p: int) -> void:
	took = false
	placed = false
	used.clear()
	revealed.clear()
	phase = "turn"
	log_msg("— Turno di %s —" % pname(p))
	while not abort:
		var opts := action_options(p)
		var k := await decide(p, {"kind": "action", "text": "Il tuo turno: scegli che cosa fare. Per finire muovi la Peste.", "opts": opts})
		if abort:
			return
		var a: Dictionary = opts[k]
		match a["a"]:
			"take":
				await _take(p)
			"place":
				await _place(p)
			"card":
				used[a["c"]] = true
				await _ability(p, a["c"], false)
			"end":
				break
		changed.emit()
	if abort:
		return
	await _plague_phase(p)


## Carte con un'azione da usare durante il turno (le altre agiscono da sole).
const ACTIVE_CARDS := ["re", "monaco", "mercante", "strega", "corriere", "vescovo", "suora", "imperatore", "pifferaio", "mago", "fornaio"]


func action_options(p: int) -> Array:
	var opts := []
	if not took and phase == "turn":
		for c in st.cards:
			if not st.holds(p, c):
				opts.append({"label": "Prendi una carta di classe", "a": "take"})
				break
	if not placed and phase == "turn" and not st.place_options(p).is_empty():
		opts.append({"label": "Aggiungi cubetti", "a": "place"})
	for c in st.held(p):
		if used.has(c):
			continue
		if can_use(p, c, phase == "final"):
			opts.append({"label": "Usa: %s" % cname(c), "a": "card", "c": c})
	if phase == "final":
		opts.append({"label": "Ho finito", "a": "end"})
	else:
		opts.append({"label": "Muovi la Peste e finisci il turno", "a": "end"})
	return opts


func can_use(p: int, c: String, final := false) -> bool:
	match c:
		"re":
			for r in st.regions():
				if st.cubes[r][p] > 0 and st.rats[r].is_empty():
					return true
			return false
		"monaco":
			return not monk_moves().is_empty()
		"mercante":
			return not merchant_sources(p).is_empty()
		"strega":
			return _board_tokens().size() >= 1
		"corriere":
			return not courier_firsts().is_empty()
		"vescovo", "suora":
			return true
		"imperatore":
			return not st.edges().is_empty()
		"pifferaio":
			return not merchant_sources(p).is_empty()
		"mago":
			if st.potion_supply <= 0:
				return false
			for r in st.regions():
				if st.cubes[r][p] > 0:
					return true
			return false
		"fornaio":
			return st.supply(p) > 0
	if final:
		match c:
			"contadino", "borgomastro":
				return st.supply(p) > 0 and (c == "contadino" or not st.majority_regions(p).is_empty())
			"regina":
				return st.supply(p) > 0 and st.queen_ok(p)
			"soldato":
				return not st.nbrs(st.plague).filter(st.can_get_rat).is_empty()
			"cavaliere", "crociato", "servo":
				return not used.has("_plague")
	return false


func _board_tokens() -> Array:
	var out := []
	for r in st.regions():
		for i in st.rats[r].size():
			out.append([r, i])
	return out


# ---------------------------------------------------------------- prendere una carta

func _take(p: int) -> void:
	var opts := []
	for c in st.cards:
		if not st.holds(p, c):
			var o := st.holder(c)
			var lab := cname(c) + ("" if o < 0 else " (da %s)" % pname(o))
			opts.append({"label": lab, "c": c})
	opts.append({"label": "Annulla", "skip": true})
	var k := await decide(p, {"kind": "take", "text": "Scegli la carta di classe da prendere.", "opts": opts})
	if opts[k].get("skip", false):
		return
	took = true
	await take_card(p, opts[k]["c"])


func take_card(p: int, c: String) -> void:
	var o := st.holder(c)
	st.owner[c] = p
	log_msg("%s prende la carta %s%s." % [pname(p), cname(c), "" if o < 0 else " da " + pname(o)])
	fx.emit("card", {"c": c, "p": p})
	changed.emit()
	if c == "fornaio" and st.baker.reduce(func(a, b): return a + b, 0) > 0:
		await _baker_drop(p, "Fornaio: metti tutti i cubetti che erano sulla carta in una regione.")


func _baker_drop(p: int, text: String) -> void:
	var r := await ask_region(p, "baker", text, st.regions())
	if r < 0:
		return
	var parts := []
	for q in n:
		if st.baker[q] > 0:
			st.cubes[r][q] += st.baker[q]
			parts.append("%d di %s" % [st.baker[q], pname(q)])
			st.baker[q] = 0
	log_msg("I cubetti del Fornaio (%s) vanno in %s." % [", ".join(parts), st.rname(r)])
	fx.emit("cubes", {"r": r, "p": p})
	changed.emit()


# ---------------------------------------------------------------- aggiungere cubetti

func _place(p: int) -> void:
	var po := st.place_options(p)
	var opts := []
	for o in po:
		opts.append({"label": "%s: %d cubett%s" % [st.rname(o["r"]), o["k"], "o" if o["k"] == 1 else "i"], "r": o["r"], "k": o["k"]})
	var maj := st.majority_regions(p)
	if st.holds(p, "borgomastro") and not maj.is_empty():
		var tot := mini(maj.size() + st.place_bonus(p), st.supply(p))
		opts.append({"label": "Borgomastro: 1 cubetto in ognuna delle %d regioni dove hai la maggioranza (%d in tutto)" % [maj.size(), tot], "mayor": true, "k": tot})
	opts.append({"label": "Annulla", "skip": true})
	var k := await decide(p, {"kind": "place", "text": "Aggiungi cubetti: tanti quanti i ratti della regione scelta.", "opts": opts})
	var o: Dictionary = opts[k]
	if o.get("skip", false):
		return
	placed = true
	if o.get("mayor", false):
		var extra := st.place_bonus(p)
		for r in maj:
			st.add_cubes(p, r, 1)
		log_msg("%s (Borgomastro) mette un cubetto in %s." % [pname(p), ", ".join(maj.map(st.rname))])
		for i in extra:
			if st.supply(p) <= 0:
				break
			changed.emit()
			var r := await ask_region(p, "extra", "Cubetto in più: scegli una regione dove hai la maggioranza.", maj)
			if r >= 0:
				st.add_cubes(p, r, 1)
				log_msg("%s mette un cubetto in più in %s." % [pname(p), st.rname(r)])
		fx.emit("cubes", {"r": maj[0], "p": p})
	else:
		var got := st.add_cubes(p, o["r"], o["k"])
		log_msg("%s mette %d cubett%s in %s." % [pname(p), got, "o" if got == 1 else "i", st.rname(o["r"])])
		fx.emit("cubes", {"r": o["r"], "p": p})
	changed.emit()


# ---------------------------------------------------------------- poteri delle carte

func monk_moves() -> Array:
	var out := []
	for r in st.regions():
		if st.rats[r].is_empty():
			continue
		for x in st.nbrs(r):
			if st.can_get_rat(x):
				out.append([r, x])
	return out


func merchant_sources(p: int) -> Array:
	var out := []
	for r in st.regions():
		if st.cubes[r][p] > 0 and not st.nbrs(r).is_empty():
			out.append(r)
	return out


## Primo cubetto che il Corriere può scambiare: [regione, giocatore] con almeno un altro cubetto
## di un altro colore in un'altra regione.
func courier_firsts() -> Array:
	var out := []
	for r in st.regions():
		for q in n:
			if st.cubes[r][q] <= 0:
				continue
			if not courier_seconds(r, q).is_empty():
				out.append([r, q])
	return out


func courier_seconds(r: int, q: int) -> Array:
	var out := []
	for r2 in st.regions():
		if r2 == r:
			continue
		for q2 in n:
			if q2 != q and st.cubes[r2][q2] > 0:
				out.append([r2, q2])
	return out


func token_label(p: int, r: int, i: int) -> String:
	var t: int = st.rats[r][i]
	if p >= 0 and st.known[p].has(t):
		return "%s, ratto %d (%s)" % [st.rname(r), i + 1, token_text(t)]
	return "%s, ratto %d" % [st.rname(r), i + 1]


func token_text(t: int) -> String:
	var info: Array = D.RATS[t]
	var parts := []
	for ch in info[1]:
		if ch == "M":
			parts.append("Maggioranza")
		elif ch == "A":
			parts.append("Tutti")
		else:
			parts.append(D.CLASSES[ch]["name"])
	return "soglia %d: %s" % [info[0], ", ".join(parts)]


func _ability(p: int, c: String, final: bool) -> void:
	match c:
		"re":
			var regs := []
			for r in st.regions():
				if st.cubes[r][p] > 0 and st.rats[r].is_empty():
					regs.append(r)
			var r := await ask_region(p, "king", "Re: scegli la regione (senza ratti) da cui portare un cubetto al palazzo.", regs, "Annulla")
			if r < 0:
				used.erase(c)
				return
			st.take_cubes(p, r, 1)
			st.palace[p] += 1
			log_msg("%s (Re) porta un cubetto da %s al palazzo." % [pname(p), st.rname(r)])
			fx.emit("palace", {"r": r, "p": p})
		"monaco":
			var moves := monk_moves()
			var srcs := []
			for m in moves:
				if not (m[0] in srcs):
					srcs.append(m[0])
			var a := await ask_region(p, "monk_src", "Monaco: da quale regione sposti un ratto?", srcs, "Annulla")
			if a < 0:
				used.erase(c)
				return
			var i := 0
			if st.rats[a].size() > 1:
				var topts := []
				for k in st.rats[a].size():
					topts.append({"label": token_label(p, a, k), "tok": [a, k]})
				i = await decide(p, {"kind": "monk_tok", "text": "Monaco: quale gettone sposti?", "opts": topts})
			var dsts := []
			for m in moves:
				if m[0] == a:
					dsts.append(m[1])
			var b := await ask_region(p, "monk_dst", "Monaco: in quale regione confinante lo porti?", dsts)
			var t: int = st.rats[a][i]
			st.rats[a].remove_at(i)
			st.rats[b].append(t)
			log_msg("%s (Monaco) sposta un ratto da %s a %s." % [pname(p), st.rname(a), st.rname(b)])
			fx.emit("rat", {"from": a, "r": b})
		"mercante", "pifferaio":
			var srcs := merchant_sources(p)
			var a := await ask_region(p, "merch_src" if c == "mercante" else "piper_src",
				("Mercante: da quale regione sposti fino a 3 tuoi cubetti?" if c == "mercante" else "Pifferaio: da quale regione parte il tuo cubetto (con i ratti)?"), srcs, "Annulla")
			if a < 0:
				used.erase(c)
				return
			var b := await ask_region(p, "merch_dst" if c == "mercante" else "piper_dst", "In quale regione confinante?", st.nbrs(a))
			if c == "mercante":
				var mx := mini(3, st.cubes[a][p])
				var k := 1
				if mx > 1:
					var nopts := []
					for j in range(1, mx + 1):
						nopts.append({"label": "%d cubett%s" % [j, "o" if j == 1 else "i"], "k": j})
					k = int(nopts[await decide(p, {"kind": "merch_n", "text": "Mercante: quanti cubetti sposti?", "opts": nopts})]["k"])
				st.move_cubes(p, a, b, k)
				log_msg("%s (Mercante) sposta %d cubett%s da %s a %s." % [pname(p), k, "o" if k == 1 else "i", st.rname(a), st.rname(b)])
				fx.emit("cubes", {"r": b, "p": p})
			else:
				var moved := piper(p, a, b)
				log_msg("%s (Pifferaio) porta un cubetto da %s a %s%s." % [pname(p), st.rname(a), st.rname(b),
					"" if moved == 0 else " con %d ratt%s" % [moved, "o" if moved == 1 else "i"]])
				fx.emit("rat", {"from": a, "r": b})
		"strega":
			var toks := _board_tokens()
			var o1 := []
			for t in toks:
				o1.append({"label": token_label(p, t[0], t[1]), "tok": t})
			o1.append({"label": "Annulla", "skip": true})
			var k1 := await decide(p, {"kind": "witch1", "text": "Strega: quale gettone ratto guardi?", "opts": o1})
			if o1[k1].get("skip", false):
				used.erase(c)
				return
			var t1: Array = o1[k1]["tok"]
			var id1: int = st.rats[t1[0]][t1[1]]
			st.known[p][id1] = true
			log_msg("%s (Strega) guarda di nascosto un ratto in %s." % [pname(p), st.rname(t1[0])])
			fx.emit("peek", {"p": p, "tok": t1})
			changed.emit()
			var o2 := []
			for t in toks:
				if t != t1:
					o2.append({"label": token_label(p, t[0], t[1]), "tok": t})
			o2.append({"label": "Basta così", "skip": true})
			var k2 := await decide(p, {"kind": "witch2", "text": "Strega: guardi un secondo gettone? (Visto: %s)" % token_text(id1), "opts": o2})
			if o2[k2].get("skip", false):
				return
			var t2: Array = o2[k2]["tok"]
			var id2: int = st.rats[t2[0]][t2[1]]
			st.known[p][id2] = true
			log_msg("%s (Strega) guarda di nascosto un ratto in %s." % [pname(p), st.rname(t2[0])])
			fx.emit("peek", {"p": p, "tok": t2})
			changed.emit()
			if t1[0] != t2[0]:
				var sw := await decide(p, {"kind": "witch_swap", "a": t1, "b": t2,
					"text": "Strega: %s in %s e %s in %s. Li scambi?" % [token_text(id1), st.rname(t1[0]), token_text(id2), st.rname(t2[0])],
					"opts": [{"label": "Scambiali", "y": true}, {"label": "Lasciali dove sono", "y": false}]})
				if sw == 0:
					st.rats[t1[0]][t1[1]] = id2
					st.rats[t2[0]][t2[1]] = id1
					log_msg("%s (Strega) scambia i due ratti fra %s e %s." % [pname(p), st.rname(t1[0]), st.rname(t2[0])])
					fx.emit("rat", {"from": t1[0], "r": t2[0]})
		"corriere":
			var f := courier_firsts()
			var o1 := []
			for x in f:
				o1.append({"label": "Cubetto %s in %s" % [D.COLORS[pcol(x[1])]["name"].to_lower(), st.rname(x[0])], "cube": x, "r": x[0]})
			o1.append({"label": "Annulla", "skip": true})
			var k1 := await decide(p, {"kind": "courier1", "text": "Corriere: scegli il primo cubetto da scambiare.", "opts": o1})
			if o1[k1].get("skip", false):
				used.erase(c)
				return
			var a: Array = o1[k1]["cube"]
			var o2 := []
			for x in courier_seconds(a[0], a[1]):
				o2.append({"label": "Cubetto %s in %s" % [D.COLORS[pcol(x[1])]["name"].to_lower(), st.rname(x[0])], "cube": x, "r": x[0]})
			var b: Array = o2[await decide(p, {"kind": "courier2", "text": "Corriere: con quale cubetto lo scambi?", "opts": o2})]["cube"]
			courier(a, b)
			log_msg("%s (Corriere) scambia un cubetto %s in %s con uno %s in %s." % [pname(p), D.COLORS[pcol(a[1])]["name"].to_lower(), st.rname(a[0]), D.COLORS[pcol(b[1])]["name"].to_lower(), st.rname(b[0])])
			fx.emit("cubes", {"r": b[0], "p": a[1]})
		"vescovo":
			var which := 0
			if st.bishops[0] >= 0 and st.bishops[1] >= 0:
				which = await decide(p, {"kind": "bishop_which", "text": "Vescovo: quale vescovo sposti?", "opts": [
					{"label": "Il vescovo in %s" % st.rname(st.bishops[0]), "r": st.bishops[0]},
					{"label": "Il vescovo in %s" % st.rname(st.bishops[1]), "r": st.bishops[1]}]})
			elif st.bishops[0] >= 0:
				which = 1
			var r := await ask_region(p, "bishop", "Vescovo: in quale regione lo metti? Lì non entrano più ratti.", st.regions(), "Annulla")
			if r < 0:
				used.erase(c)
				return
			st.bishops[which] = r
			log_msg("%s mette un vescovo in %s." % [pname(p), st.rname(r)])
			fx.emit("piece", {"r": r})
		"suora":
			var moved := 0
			for i in 3:
				changed.emit()
				var txt := "Suora %d di 3: dove la metti? Ogni suora conta un abitante in meno." % (i + 1)
				var r := await ask_region(p, "nun", txt, st.regions(), "Lasciala dov'è" if st.nuns[i] >= 0 else "Non metterla")
				if r >= 0:
					st.nuns[i] = r
					moved += 1
					fx.emit("piece", {"r": r})
			log_msg("%s (Suora) sistema le suore: %s." % [pname(p), ", ".join(st.nuns.filter(func(x): return x >= 0).map(st.rname))])
		"imperatore":
			for i in 3:
				changed.emit()
				var opts := []
				for e in st.edges():
					if not (e in st.walls):
						var ab: PackedStringArray = e.split("-")
						opts.append({"label": "%s / %s" % [st.rname(int(ab[0])), st.rname(int(ab[1]))], "e": e})
				opts.append({"label": "Lascialo dov'è" if st.walls[i] != "" else "Non metterlo", "skip": true})
				var k := await decide(p, {"kind": "wall", "text": "Muro %d di 3: su quale confine lo metti? Niente lo attraversa." % (i + 1), "opts": opts})
				if not opts[k].get("skip", false):
					st.walls[i] = opts[k]["e"]
					fx.emit("piece", {"e": opts[k]["e"]})
			var ws := []
			for w in st.walls:
				if w != "":
					var ab: PackedStringArray = w.split("-")
					ws.append("%s/%s" % [st.rname(int(ab[0])), st.rname(int(ab[1]))])
			log_msg("%s (Imperatore) sistema i muri: %s." % [pname(p), ", ".join(ws)])
		"mago":
			var regs := []
			for r in st.regions():
				if st.cubes[r][p] > 0:
					regs.append(r)
			var r := await ask_region(p, "wizard", "Mago: su un tuo cubetto di quale regione metti la pozione?", regs, "Annulla")
			if r < 0:
				used.erase(c)
				return
			st.potions[r][p] += 1
			st.potion_supply -= 1
			log_msg("%s (Mago) mette una pozione su un cubetto in %s." % [pname(p), st.rname(r)])
			fx.emit("piece", {"r": r})
		"fornaio":
			st.baker[p] += 1
			log_msg("%s (Fornaio) mette un cubetto sulla carta del Fornaio." % pname(p))
		# --- solo nel giro finale
		"contadino":
			var r := await ask_region(p, "f_peasant", "Contadino: aggiungi un cubetto in una regione.", st.regions(), "Annulla")
			if r < 0:
				used.erase(c)
				return
			st.add_cubes(p, r, 1)
			log_msg("%s (Contadino) aggiunge un cubetto in %s." % [pname(p), st.rname(r)])
			fx.emit("cubes", {"r": r, "p": p})
		"regina":
			var r := await ask_region(p, "f_queen", "Regina: aggiungi due cubetti in una regione.", st.regions(), "Annulla")
			if r < 0:
				used.erase(c)
				return
			var k := st.add_cubes(p, r, 2)
			log_msg("%s (Regina) aggiunge %d cubetti in %s." % [pname(p), k, st.rname(r)])
			fx.emit("cubes", {"r": r, "p": p})
		"borgomastro":
			var r := await ask_region(p, "f_mayor", "Borgomastro: aggiungi un cubetto dove hai la maggioranza.", st.majority_regions(p), "Annulla")
			if r < 0:
				used.erase(c)
				return
			st.add_cubes(p, r, 1)
			log_msg("%s (Borgomastro) aggiunge un cubetto in %s." % [pname(p), st.rname(r)])
			fx.emit("cubes", {"r": r, "p": p})
		"soldato":
			var r := await ask_region(p, "f_soldier", "Soldato: aggiungi un ratto in una regione confinante con la Peste.", st.nbrs(st.plague).filter(st.can_get_rat), "Annulla")
			if r < 0:
				used.erase(c)
				return
			var t := -1
			if not st.bag.is_empty():
				t = st.bag.pop_back()
			elif not st.removed.is_empty():
				t = st.removed.pop_at(rng.randi() % st.removed.size())
			if t >= 0:
				st.rats[r].append(t)
				log_msg("%s (Soldato) aggiunge un ratto in %s." % [pname(p), st.rname(r)])
				fx.emit("rat", {"from": st.plague, "r": r})
		"cavaliere", "crociato", "servo":
			await _final_plague(p)
	changed.emit()


## Pifferaio: sposta un cubetto da a a b e porta con sé più ratti possibile. Restituisce i ratti spostati.
func piper(p: int, a: int, b: int) -> int:
	st.move_cubes(p, a, b, 1)
	if st.has_bishop(b):
		return 0
	var k := mini(st.rats[a].size(), 3 - st.rats[b].size())
	for i in k:
		st.rats[b].append(st.rats[a].pop_back())
	return k


## Corriere: scambia di posto due cubetti (con le loro pozioni).
func courier(a: Array, b: Array) -> void:
	st.move_cubes(a[1], a[0], b[0], 1)
	st.move_cubes(b[1], b[0], a[0], 1)


# ================================================================ fase C: la Peste

func plague_moves(p: int, steps: int) -> Array:
	var out := []
	var frontier := [st.plague]
	var seen := {st.plague: true}
	for s in steps:
		var nxt := []
		for r in frontier:
			for x in st.nbrs(r):
				if not seen.has(x):
					seen[x] = true
					nxt.append(x)
					out.append(x)
		frontier = nxt
	return out


func knight_cards(p: int) -> bool:
	return st.holds(p, "cavaliere") or st.holds(p, "crociato") or st.holds(p, "soldato")


func _plague_phase(p: int) -> void:
	phase = "plague"
	var steps := 2 if knight_cards(p) else 1
	var dests := plague_moves(p, steps)
	if dests.is_empty():
		log_msg("La Peste è circondata dai muri e resta in %s." % st.rname(st.plague))
	else:
		var r := await ask_region(p, "plague", "Muovi la Peste in una regione confinante%s." % (" (fino a due passi)" if steps == 2 else ""), dests)
		if abort:
			return
		var from := st.plague
		st.plague = r
		log_msg("%s muove la Peste da %s a %s." % [pname(p), st.rname(from), st.rname(r)])
		fx.emit("plague", {"from": from, "r": r})
		changed.emit()
		await _pace(0.5)
	var neutral := 0
	if st.holds(p, "cavaliere") and st.total(st.plague) > 0 and not st.rats[st.plague].is_empty():
		if await ask_yes(p, "knight", "Cavaliere: la Peste conta come due abitanti in più in %s?" % st.rname(st.plague), "Sì, due abitanti in più", "No"):
			neutral = 2
			log_msg("%s (Cavaliere): la Peste conta come due abitanti." % pname(p))
	await _spread(p)
	if abort:
		return
	await _ravage(p, st.plague, neutral, st.holds(p, "servo"), st.holds(p, "crociato"))


func _spread(p: int) -> void:
	var r := st.plague
	var k: int = st.rats[r].size()
	if k == 0:
		return
	var add := 1 if k == 1 else 2
	var extra := st.holds(p, "soldato")
	for i in add + (1 if extra else 0):
		var dsts: Array = st.nbrs(r).filter(st.can_get_rat)
		if dsts.is_empty():
			if i == 0:
				log_msg("Nessuna regione confinante può ricevere ratti.")
			break
		if st.bag.is_empty():
			ending = true
			break
		var is_extra := i >= add
		var x := await ask_region(p, "spread", ("Soldato: un ratto in più? Scegli dove." if is_extra else "La peste si diffonde: metti un ratto nuovo in una regione confinante (%d di %d)." % [i + 1, add]), dsts, "Nessun ratto in più" if is_extra else "")
		if abort or x < 0:
			break
		st.rats[x].append(st.bag.pop_back())
		log_msg("Un ratto si sposta in %s." % st.rname(x))
		fx.emit("rat", {"from": r, "r": x})
		changed.emit()
		await _pace(0.25)
		if st.bag.is_empty():
			ending = true


## Devastazione della regione r: si scoprono i ratti uno alla volta finché ci sono ratti e cubetti.
func _ravage(p: int, r: int, neutral: int, serf: bool, crusader: bool) -> void:
	revealed.clear()
	if st.total(r) == 0 or st.rats[r].is_empty():
		if not st.rats[r].is_empty():
			log_msg("In %s non c'è nessuno: i ratti restano coperti." % st.rname(r))
		return
	var order: Array = st.rats[r].duplicate()
	if crusader and order.size() > 1:
		if await ask_yes(p, "crusader", "Crociato: scopri insieme tutti i ratti di %s e scegli tu l'ordine?" % st.rname(r), "Sì, scoprili tutti", "No"):
			for t in order:
				revealed.append({"tid": t, "r": r, "done": false})
			log_msg("%s (Crociato) scopre tutti i ratti di %s." % [pname(p), st.rname(r)])
			fx.emit("reveal_all", {"r": r})
			changed.emit()
			var left := order.duplicate()
			order.clear()
			while left.size() > 1:
				var opts := []
				for t in left:
					opts.append({"label": token_text(t), "t": t})
				var k := await decide(p, {"kind": "order", "text": "Crociato: quale ratto colpisce adesso?", "opts": opts})
				order.append(left[k])
				left.remove_at(k)
			order.append(left[0])
	for t in order:
		if st.total(r) == 0 or abort:
			break
		st.rats[r].erase(t)
		st.removed.append(t)
		var res := st.resolve_token(r, t, neutral, p if serf else -1)
		last_reveal = {"tid": t, "r": r, "res": res}
		var found := false
		for x in revealed:
			if x["tid"] == t:
				x["done"] = true
				found = true
		if not found:
			revealed.append({"tid": t, "r": r, "done": true})
		_log_reveal(r, t, res)
		fx.emit("reveal", {"r": r, "tid": t, "res": res})
		changed.emit()
		await _pace(1.0)
	for q in n:
		for t in st.known[q].keys():
			if t in st.removed:
				st.known[q].erase(t)


func _log_reveal(r: int, t: int, res: Dictionary) -> void:
	if not res["out"]:
		log_msg("In %s si scopre un ratto (%s): popolazione %d, nessuna epidemia." % [st.rname(r), token_text(t), res["pop"]])
		return
	var parts := []
	for q in n:
		if res["dead"][q] > 0:
			parts.append("%s perde %d" % [pname(q), res["dead"][q]])
		if res["saved"][q] > 0:
			parts.append("%s si salva con %d pozion%s" % [pname(q), res["saved"][q], "e" if res["saved"][q] == 1 else "i"])
	var s := "Epidemia in %s (%s, popolazione %d): %s." % [st.rname(r), token_text(t), res["pop"], ", ".join(parts) if not parts.is_empty() else "nessuno colpito"]
	if res["serf"] > 0:
		s += " Il Servo della gleba aggiunge un cubetto."
	log_msg(s)


# ================================================================ fine partita

func _final() -> void:
	phase = "final"
	var last := cur
	log_msg("Ultimo giro, in senso antiorario: si possono usare ancora una volta i poteri delle carte.")
	for i in range(1, n):
		var p := (last - i + n * 4) % n
		cur = p
		used.clear()
		while not abort:
			var opts := action_options(p)
			if opts.size() <= 1:
				break
			var k := await decide(p, {"kind": "final", "text": "Ultimo giro: usi i poteri delle tue carte?", "opts": opts})
			if abort:
				return
			var a: Dictionary = opts[k]
			if a["a"] == "end":
				break
			used[a["c"]] = true
			await _ability(p, a["c"], true)
			changed.emit()
	if abort:
		return
	var bh := st.holder("fornaio")
	if bh >= 0 and st.baker.reduce(func(a, b): return a + b, 0) > 0:
		cur = (bh + 1) % n
		await _baker_drop(cur, "Fine partita: metti i cubetti del Fornaio in una regione.")
	log_msg("La peste devasta tutte le regioni.")
	for r in st.regions():
		if abort:
			return
		if st.rats[r].is_empty() or st.total(r) == 0:
			continue
		var serf := final_serf if r == st.plague else -1
		var neutral := 2 if r == final_knight else 0
		await _ravage(serf, r, neutral, serf >= 0, false)
	_end_game(last)


## Ultimo giro: Cavaliere, Crociato e Servo muovono la Peste (una volta sola per giocatore; se ne ha più
## d'una agiscono tutte nella stessa regione).
func _final_plague(p: int) -> void:
	used["_plague"] = true
	for c in ["cavaliere", "crociato", "servo"]:
		if st.holds(p, c):
			used[c] = true
	var steps := 2 if (st.holds(p, "cavaliere") or st.holds(p, "crociato")) else 1
	var dests := plague_moves(p, steps)
	var r := await ask_region(p, "f_plague", "Muovi la Peste (ultimo giro).", dests, "Lasciala dov'è")
	if r >= 0:
		var from := st.plague
		st.plague = r
		log_msg("%s muove la Peste da %s a %s." % [pname(p), st.rname(from), st.rname(r)])
		fx.emit("plague", {"from": from, "r": r})
		changed.emit()
	if st.holds(p, "cavaliere"):
		final_knight = st.plague
		log_msg("Cavaliere: nella devastazione finale la Peste conta come due abitanti in %s." % st.rname(st.plague))
	if st.holds(p, "servo"):
		final_serf = p
	if st.holds(p, "crociato") and not st.rats[st.plague].is_empty() and st.total(st.plague) > 0:
		await _ravage(p, st.plague, 2 if final_knight == st.plague else 0, st.holds(p, "servo"), true)


func _end_game(last: int) -> void:
	phase = "over"
	var ranking := []
	for i in n:
		var p := (last + 1 + i) % n
		ranking.append({"p": p, "score": st.score(p), "palace": st.palace[p], "tie": i})
	ranking.sort_custom(func(a, b):
		if a["score"] != b["score"]:
			return a["score"] > b["score"]
		return a["tie"] < b["tie"])
	_snap()
	result = {"ranking": ranking, "winner": ranking[0]["p"]}
	log_msg("Fine della partita. Vince %s con %d abitanti sopravvissuti." % [pname(ranking[0]["p"]), ranking[0]["score"]])
	changed.emit()
	game_ended.emit(result)
