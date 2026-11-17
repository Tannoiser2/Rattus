class_name RTAI
extends RefCounted
## Giocatore artificiale di Rattus.
## Valuta le posizioni con una stima del rischio: per ogni regione simula la devastazione con i gettoni
## che conosce (quelli visti con la Strega) e con estrazioni a caso di quelli ignoti; il rischio pesa di
## più nella regione della Peste e in quelle vicine. Prova ogni mossa possibile su una copia dello stato
## e sceglie quella che allarga di più il vantaggio sugli avversari. Non sbircia mai i ratti coperti.
## Livelli: 0 facile (stime grossolane e qualche distrazione), 1 normale, 2 difficile.

const D = preload("res://scripts/data/rt_data.gd")

var level := 1
var rng := RandomNumberGenerator.new()
var plan := {}
var _cache := {}
var _samples := 10
var _final := false


func _init(lv := 1, seed_value := 0) -> void:
	level = lv
	rng.seed = seed_value if seed_value != 0 else 12345 + lv
	_samples = [5, 10, 22][clampi(lv, 0, 2)]


# ================================================================ valutazione

func _w(s: RTState, r: int, hot := -1) -> float:
	if _final:
		return 1.0
	if r == hot:
		return 1.0
	if r == s.plague:
		return 0.85
	if r in s.nbrs(s.plague):
		return 0.75
	return 0.6


func _el(s: RTState, p: int, r: int, neutral := 0, serf := -1) -> Array:
	var key := "%d|%s|%s|%s|%d|%d|%d|%s" % [r, str(s.cubes[r]), str(s.potions[r]), str(s.rats[r].map(func(t): return t if s.known[p].has(t) else -1)),
		s.nuns_in(r), neutral, serf, str(s.owner.values())]
	if _cache.has(key):
		return _cache[key]
	var v := s.expected_loss(p, r, neutral, _samples, rng, serf)
	_cache[key] = v
	return v


## Valore della posizione per p: abitanti al sicuro meno le perdite attese, confrontato con gli avversari.
func value(s: RTState, p: int, hot := -1, neutral := 0, serf := -1) -> float:
	var v := []
	for q in s.n:
		v.append(float(s.palace[q] + s.onboard(q)) + s.baker[q] * 0.6)
	for r in s.regions():
		if s.rats[r].is_empty() or s.total(r) == 0:
			continue
		var w := _w(s, r, hot)
		var el := _el(s, p, r, neutral if r == hot else 0, serf if r == hot else -1)
		for q in s.n:
			v[q] -= w * el[q]
	var mine: float = v[p]
	var best := -1e9
	var sum := 0.0
	for q in s.n:
		if q == p:
			continue
		best = maxf(best, v[q])
		sum += v[q]
	var others := best * 0.65 + (sum / maxf(1.0, s.n - 1)) * 0.35
	# piccola spinta a tenere cubetti nelle regioni con ratti (rendono di più quando si aggiunge)
	var growth := 0.0
	if not _final:
		for r in s.regions():
			if s.cubes[r][p] > 0 and s.rats[r].size() > 0:
				growth += 0.05
	return mine - others + growth


func card_bonus(s: RTState, p: int, c: String) -> float:
	match c:
		"contadino": return 0.9
		"re":
			var b := 0.35
			for r in s.regions():
				if s.cubes[r][p] > 0 and s.rats[r].is_empty():
					b += 0.15
			return minf(b, 0.9)
		"cavaliere": return 0.55
		"mercante": return 0.5
		"monaco": return 0.6
		"strega": return 0.35
		"corriere": return 0.45
		"vescovo": return 0.4
		"suora": return 0.45
		"crociato": return 0.5
		"imperatore": return 0.35
		"regina":
			var cl := s.clone()
			cl.owner["regina"] = p
			return 1.5 if cl.queen_ok(p) else 0.25
		"pifferaio": return 0.5
		"fornaio": return 0.3
		"servo": return 0.55
		"borgomastro": return minf(1.2, 0.25 * s.majority_regions(p).size())
		"mago": return 0.55 if s.potion_supply > 0 else 0.0
	return 0.3


func _noise() -> float:
	return rng.randf_range(-0.5, 0.5) if level == 0 else (rng.randf_range(-0.08, 0.08) if level == 1 else 0.0)


# ================================================================ decisioni

func decide(e, p: int, req: Dictionary) -> int:
	_cache.clear()
	_final = e.phase == "final"
	var opts: Array = req.get("opts", [])
	if opts.is_empty():
		return 0
	var kind: String = req.get("kind", "")
	var s: RTState = e.st
	match kind:
		"action", "final":
			return _action(e, p, opts)
		"setup":
			return _best(opts, func(o): return _setup_score(s, p, o["r"]))
		"take", "place", "extra", "king", "monk_src", "monk_tok", "monk_dst", "merch_src", "merch_dst", "merch_n", \
		"piper_src", "piper_dst", "courier1", "courier2", "bishop_which", "bishop", "nun", "wall", "wizard", \
		"f_peasant", "f_queen", "f_mayor", "f_soldier":
			return _follow(e, p, kind, opts)
		"baker":
			return _best(opts, func(o):
				var cl := s.clone()
				for q in cl.n:
					cl.cubes[o["r"]][q] += cl.baker[q]
					cl.baker[q] = 0
				return value(cl, p))
		"plague", "f_plague":
			return _plague(e, p, opts, kind == "f_plague")
		"knight":
			var hot: int = s.plague
			var a := value(s, p, hot, 2)
			var b := value(s, p, hot, 0)
			return 0 if a > b + 0.01 else 1
		"spread":
			return _best(opts, func(o):
				if o.get("skip", false):
					return value(s, p, s.plague)
				var cl := s.clone()
				cl.rats[o["r"]].append(_fake_token(cl, p))
				return value(cl, p, s.plague))
		"crusader":
			return 0
		"order":
			return _order(e, p, opts)
		"witch1":
			return _witch1(e, p, opts)
		"witch2":
			return _witch2(e, p, opts)
		"witch_swap":
			return _witch_swap(e, p, req)
	return 0


func _best(opts: Array, f: Callable) -> int:
	var bi := 0
	var bv := -1e9
	for i in opts.size():
		var v: float = f.call(opts[i]) + _noise() * 0.3
		if v > bv:
			bv = v
			bi = i
	return bi


## Un gettone che p non conosce, per simulare un ratto nuovo senza sbirciare.
func _fake_token(s: RTState, p: int) -> int:
	var pool := s.unknown_pool(p)
	if pool.is_empty():
		return 0
	return pool[rng.randi() % pool.size()]


func _setup_score(s: RTState, p: int, r: int) -> float:
	var cl := s.clone()
	cl.add_cubes(p, r, 2)
	var v := value(cl, p)
	v += 0.25 * s.rats[r].size()
	if r == s.plague:
		v -= 0.6
	elif r in s.nbrs(s.plague):
		v -= 0.3
	# meglio non ammucchiarsi dove ci sono già gli altri
	v -= 0.1 * (s.total(r))
	return v


# ---------------------------------------------------------------- scelta dell'azione

func _action(e, p: int, opts: Array) -> int:
	var s: RTState = e.st
	var base := value(s, p)
	var best_i := opts.size() - 1
	var best_gain := 0.04 if level > 0 else 0.25
	var best_plan := {}
	for i in opts.size():
		var o: Dictionary = opts[i]
		var cand := {}
		match o["a"]:
			"take":
				cand = _plan_take(e, p, base)
			"place":
				cand = _plan_place(e, p, base)
			"card":
				cand = _plan_card(e, p, o["c"], base)
		if cand.is_empty():
			continue
		var g: float = cand["gain"] + _noise()
		if g > best_gain:
			best_gain = g
			best_i = i
			best_plan = cand
	plan = best_plan
	return best_i


func _plan_take(e, p: int, base: float) -> Dictionary:
	var s: RTState = e.st
	var best := {}
	for c in s.cards:
		if s.holds(p, c):
			continue
		var cl := s.clone()
		var o := cl.holder(c)
		cl.owner[c] = p
		var g := value(cl, p) - base + card_bonus(cl, p, c)
		if o >= 0:
			g += 0.45 * card_bonus(s, o, c)
		# tenere carte espone ai simboli di quella classe sui ratti futuri
		var exposed := 0
		for r in s.regions():
			if s.cubes[r][p] > 0:
				exposed += s.cubes[r][p]
		g -= 0.025 * exposed
		if best.is_empty() or g > best["gain"]:
			best = {"gain": g, "kind": "take", "c": c}
	return best


func _plan_place(e, p: int, base: float) -> Dictionary:
	var s: RTState = e.st
	var best := {}
	for o in s.place_options(p):
		var cl := s.clone()
		cl.add_cubes(p, o["r"], o["k"])
		var g := value(cl, p) - base
		if best.is_empty() or g > best["gain"]:
			best = {"gain": g, "kind": "place", "r": o["r"]}
	if s.holds(p, "borgomastro"):
		var maj := s.majority_regions(p)
		if not maj.is_empty():
			var cl := s.clone()
			for r in maj:
				cl.add_cubes(p, r, 1)
			var extra := []
			for i in s.place_bonus(p):
				var br: int = maj[0]
				var bv := -1e9
				for r in maj:
					var c2 := cl.clone()
					c2.add_cubes(p, r, 1)
					var v := value(c2, p)
					if v > bv:
						bv = v
						br = r
				cl.add_cubes(p, br, 1)
				extra.append(br)
			var g := value(cl, p) - base
			if best.is_empty() or g > best["gain"]:
				best = {"gain": g, "kind": "place", "mayor": true, "extra": extra}
	return best


func _plan_card(e, p: int, c: String, base: float) -> Dictionary:
	var s: RTState = e.st
	var best := {}
	match c:
		"re":
			for r in s.regions():
				if s.cubes[r][p] > 0 and s.rats[r].is_empty():
					var cl := s.clone()
					cl.take_cubes(p, r, 1)
					cl.palace[p] += 1
					var g := value(cl, p) - base + (0.25 if not _final else 0.0)
					best = _better(best, {"gain": g, "r": r})
		"monaco":
			for m in e.monk_moves():
				for i in s.rats[m[0]].size():
					if i > 0 and not _any_known(s, p, m[0]):
						break
					var cl := s.clone()
					var t: int = cl.rats[m[0]][i]
					cl.rats[m[0]].remove_at(i)
					cl.rats[m[1]].append(t)
					best = _better(best, {"gain": value(cl, p) - base, "src": m[0], "i": i, "dst": m[1]})
		"mercante":
			for a in e.merchant_sources(p):
				for b in s.nbrs(a):
					for k in range(1, mini(3, s.cubes[a][p]) + 1):
						var cl := s.clone()
						cl.move_cubes(p, a, b, k)
						best = _better(best, {"gain": value(cl, p) - base, "src": a, "dst": b, "k": k})
		"pifferaio":
			for a in e.merchant_sources(p):
				for b in s.nbrs(a):
					var cl := s.clone()
					cl.move_cubes(p, a, b, 1)
					if not cl.has_bishop(b):
						for j in mini(cl.rats[a].size(), 3 - cl.rats[b].size()):
							cl.rats[b].append(cl.rats[a].pop_back())
					best = _better(best, {"gain": value(cl, p) - base, "src": a, "dst": b})
		"corriere":
			for x in e.courier_firsts():
				for y in e.courier_seconds(x[0], x[1]):
					if x[1] != p and y[1] != p:
						continue
					var cl := s.clone()
					cl.move_cubes(x[1], x[0], y[0], 1)
					cl.move_cubes(y[1], y[0], x[0], 1)
					best = _better(best, {"gain": value(cl, p) - base, "a": x, "b": y})
		"mago":
			for r in s.regions():
				if s.cubes[r][p] > 0:
					var cl := s.clone()
					cl.potions[r][p] += 1
					cl.potion_supply -= 1
					best = _better(best, {"gain": value(cl, p) - base + 0.15, "r": r})
		"fornaio":
			if s.supply(p) >= 4 and not _final:
				best = {"gain": 0.2, "kind": "card"}
		"strega":
			var g := 0.0
			for r in s.regions():
				if s.cubes[r][p] > 0 and not s.rats[r].is_empty() and _w(s, r) > 0.5 and not _all_known(s, p, r):
					g = 0.3
			if g > 0.0:
				best = {"gain": g}
		"vescovo":
			var which := 0
			if s.bishops[0] >= 0 and s.bishops[1] >= 0:
				which = 0 if _bishop_h(s, p, s.bishops[0]) < _bishop_h(s, p, s.bishops[1]) else 1
			elif s.bishops[0] >= 0:
				which = 1
			var cur_h := _bishop_h(s, p, s.bishops[which]) if s.bishops[which] >= 0 else 0.0
			for r in s.regions():
				if r in s.bishops:
					continue
				var g := _bishop_h(s, p, r) - cur_h
				best = _better(best, {"gain": g, "which": which, "r": r})
		"suora":
			var cl := s.clone()
			var nun_plan := []
			var tot := 0.0
			for i in 3:
				var bv := value(cl, p)
				var br := -1
				for r in cl.regions():
					var c2 := cl.clone()
					c2.nuns[i] = r
					var v := value(c2, p)
					if v > bv + 0.02:
						bv = v
						br = r
				if br >= 0:
					cl.nuns[i] = br
				nun_plan.append(br)
			tot = value(cl, p) - base
			best = {"gain": tot, "nuns": nun_plan}
		"imperatore":
			var walls := s.walls.duplicate()
			var wall_plan := []
			var gain := 0.0
			for i in 3:
				var cur_h := _wall_h(s, p, walls[i]) if walls[i] != "" else 0.0
				var be := ""
				var bh := cur_h
				for ek in s.edges():
					if ek in walls:
						continue
					var h := _wall_h(s, p, ek)
					if h > bh + 0.05:
						bh = h
						be = ek
				if be != "":
					walls[i] = be
					gain += bh - cur_h
				wall_plan.append(be)
			best = {"gain": gain, "walls": wall_plan}
		# --- ultimo giro
		"contadino", "regina", "borgomastro":
			var k := 2 if c == "regina" else 1
			var regs: Array = s.majority_regions(p) if c == "borgomastro" else s.regions()
			for r in regs:
				var cl := s.clone()
				cl.add_cubes(p, r, k)
				best = _better(best, {"gain": value(cl, p) - base + 0.01, "r": r})
		"soldato":
			for r in s.nbrs(s.plague).filter(s.can_get_rat):
				var cl := s.clone()
				cl.rats[r].append(_fake_token(cl, p))
				best = _better(best, {"gain": value(cl, p) - base, "r": r})
		"cavaliere", "crociato", "servo":
			best = {"gain": 0.3}
	if not best.is_empty():
		best["kind"] = "card"
		best["c"] = c
	return best


func _better(a: Dictionary, b: Dictionary) -> Dictionary:
	if a.is_empty() or b["gain"] > a["gain"]:
		return b
	return a


func _any_known(s: RTState, p: int, r: int) -> bool:
	for t in s.rats[r]:
		if s.known[p].has(t):
			return true
	return false


func _all_known(s: RTState, p: int, r: int) -> bool:
	for t in s.rats[r]:
		if not s.known[p].has(t):
			return false
	return true


## Utilità di un vescovo nella regione r: protegge i propri cubetti dai ratti nuovi.
func _bishop_h(s: RTState, p: int, r: int) -> float:
	if r < 0:
		return 0.0
	var opp := 0
	for q in s.n:
		if q != p:
			opp = maxi(opp, s.cubes[r][q])
	var h: float = 0.12 * (s.cubes[r][p] - opp * 0.8)
	if r in s.nbrs(s.plague) or r == s.plague:
		h *= 2.0
	if s.rats[r].size() >= 3:
		h *= 0.3
	return h


## Utilità di un muro sul confine: tiene lontana la Peste dalle proprie regioni (e la lascia agli altri).
func _wall_h(s: RTState, p: int, ek: String) -> float:
	var ab := ek.split("-")
	var a := int(ab[0])
	var b := int(ab[1])
	var h := 0.0
	for pair in [[a, b], [b, a]]:
		var near: int = pair[0]
		var far: int = pair[1]
		var opp := 0
		for q in s.n:
			if q != p:
				opp += s.cubes[far][q]
		var side: float = s.cubes[far][p] - 0.7 * opp
		if near == s.plague:
			h += 0.18 * side
		elif near in s.nbrs(s.plague):
			h += 0.05 * side
	return h


# ---------------------------------------------------------------- seguire il piano

func _follow(e, p: int, kind: String, opts: Array) -> int:
	var s: RTState = e.st
	var pl := plan
	var want := -2
	match kind:
		"take":
			for i in opts.size():
				if opts[i].get("c", "") == pl.get("c", ""):
					return i
			return opts.size() - 1
		"place":
			for i in opts.size():
				if pl.get("mayor", false) and opts[i].get("mayor", false):
					return i
				if not pl.get("mayor", false) and opts[i].get("r", -9) == pl.get("r", -1):
					return i
			return 0
		"extra":
			var ex: Array = pl.get("extra", [])
			if not ex.is_empty():
				want = ex.pop_front()
		"king", "wizard", "f_peasant", "f_queen", "f_mayor", "f_soldier":
			want = pl.get("r", -2)
		"monk_src", "merch_src", "piper_src":
			want = pl.get("src", -2)
		"monk_dst", "merch_dst", "piper_dst":
			want = pl.get("dst", -2)
		"monk_tok":
			var i: int = pl.get("i", 0)
			return clampi(i, 0, opts.size() - 1)
		"merch_n":
			for i in opts.size():
				if opts[i].get("k", 0) == pl.get("k", 1):
					return i
			return 0
		"courier1", "courier2":
			var key := "a" if kind == "courier1" else "b"
			for i in opts.size():
				if opts[i].get("cube", []) == pl.get(key, []):
					return i
			return 0
		"bishop_which":
			return clampi(int(pl.get("which", 0)), 0, opts.size() - 1)
		"bishop":
			want = pl.get("r", -2)
		"nun":
			var np: Array = pl.get("nuns", [])
			if np.is_empty():
				return opts.size() - 1
			want = np.pop_front()
			if want < 0:
				return opts.size() - 1
		"wall":
			var wp: Array = pl.get("walls", [])
			var w := "" if wp.is_empty() else str(wp.pop_front())
			if w == "":
				return opts.size() - 1
			for i in opts.size():
				if opts[i].get("e", "") == w:
					return i
			return opts.size() - 1
	if want != -2:
		for i in opts.size():
			if opts[i].get("r", -9) == want and not opts[i].get("skip", false):
				return i
	# senza piano: la regione migliore per il valore (o la prima)
	for i in opts.size():
		if not opts[i].get("skip", false):
			return i
	return 0


# ---------------------------------------------------------------- la Peste

func _plague(e, p: int, opts: Array, final: bool) -> int:
	var s: RTState = e.st
	var knight := s.holds(p, "cavaliere")
	var serf := p if s.holds(p, "servo") else -1
	return _best(opts, func(o):
		var cl := s.clone()
		if not o.get("skip", false):
			cl.plague = o["r"]
		var d: int = cl.plague
		if not final:
			# diffusione: i ratti nuovi vanno dove fanno più danni agli altri
			var k: int = cl.rats[d].size()
			var add := 0 if k == 0 else (1 if k == 1 else 2)
			if cl.holds(p, "soldato") and k > 0:
				add += 1
			for i in add:
				var dsts: Array = cl.nbrs(d).filter(cl.can_get_rat)
				if dsts.is_empty() or cl.bag.is_empty():
					break
				var br: int = dsts[0]
				var bh := -1e9
				for x in dsts:
					var opp := 0
					for q in cl.n:
						if q != p:
							opp += cl.cubes[x][q]
					var h: float = opp - 1.4 * cl.cubes[x][p]
					if h > bh:
							bh = h
							br = x
				cl.rats[br].append(_fake_token(cl, p))
		var v := value(cl, p, d, 0, serf)
		if knight:
			v = maxf(v, value(cl, p, d, 2, serf))
		return v)


func _order(e, p: int, opts: Array) -> int:
	var s: RTState = e.st
	var r: int = s.plague
	var bi := 0
	var bv := -1e9
	for i in opts.size():
		var cl := s.clone()
		var seq := [opts[i]["t"]]
		for j in opts.size():
			if j != i:
				seq.append(opts[j]["t"])
		var before := []
		for q in s.n:
			before.append(cl.cubes[r][q])
		for t in seq:
			if cl.total(r) == 0:
				break
			cl.resolve_token(r, t, 0, p if s.holds(p, "servo") else -1)
		var v := 0.0
		for q in s.n:
			var lost: int = before[q] - cl.cubes[r][q]
			v += (-1.3 * lost) if q == p else lost
		if v > bv:
			bv = v
			bi = i
	return bi


# ---------------------------------------------------------------- la Strega

func _witch1(e, p: int, opts: Array) -> int:
	var s: RTState = e.st
	return _best(opts, func(o):
		if o.get("skip", false):
			return -1.0
		var t: Array = o["tok"]
		var id: int = s.rats[t[0]][t[1]]
		if s.known[p].has(id):
			return -0.5
		return _w(s, t[0]) * (s.cubes[t[0]][p] + 0.3 * s.total(t[0])))


func _witch2(e, p: int, opts: Array) -> int:
	var s: RTState = e.st
	return _best(opts, func(o):
		if o.get("skip", false):
			return 0.2
		var t: Array = o["tok"]
		var id: int = s.rats[t[0]][t[1]]
		if s.known[p].has(id):
			return -0.5
		var opp := 0
		for q in s.n:
			if q != p:
				opp += s.cubes[t[0]][q]
		return 0.3 + 0.1 * (opp - s.cubes[t[0]][p]) + 0.2 * _w(s, t[0]))


func _witch_swap(e, p: int, req: Dictionary) -> int:
	var s: RTState = e.st
	var a: Array = req.get("a", [])
	var b: Array = req.get("b", [])
	if a.is_empty() or b.is_empty():
		return 1
	var cl := s.clone()
	var x: int = cl.rats[a[0]][a[1]]
	cl.rats[a[0]][a[1]] = cl.rats[b[0]][b[1]]
	cl.rats[b[0]][b[1]] = x
	return 0 if value(cl, p) > value(s, p) + 0.05 else 1
