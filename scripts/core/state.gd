class_name RTState
extends RefCounted
## Stato di una partita di Rattus e tutte le operazioni immediate sulle pedine (senza attese né scelte).
## Lo usa il motore (che chiede le decisioni e scrive il diario) e lo copia l'IA per provare le mosse.

const D = preload("res://scripts/data/rt_data.gd")

var n := 0
var active: Array = []           # bool per regione
var cubes: Array = []            # [regione][giocatore] -> cubetti
var potions: Array = []          # [regione][giocatore] -> pozioni sui cubetti
var potion_supply := D.POTIONS
var palace: Array = []           # cubetti al sicuro nel palazzo
var baker: Array = []            # cubetti sulla carta del Fornaio, per colore
var rats: Array = []             # [regione] -> id dei gettoni (coperti)
var bag: Array = []              # riserva di ratti coperti
var removed: Array = []          # ratti scoperti e tolti dal gioco
var plague := 0                  # regione della Peste
var cards: Array = []            # le 6 carte in gioco
var owner := {}                  # carta -> giocatore (-1 = accanto al tabellone)
var nuns: Array = [-1, -1, -1]
var bishops: Array = [-1, -1]
var walls: Array = ["", "", ""]  # confini bloccati ("a-b")
var known: Array = []            # [giocatore] -> {id gettone: true} visti con la Strega
var logger: Callable             # diario (solo nel motore)


func init(players: int, card_list: Array) -> void:
	n = players
	active.clear()
	cubes.clear()
	potions.clear()
	rats.clear()
	for r in D.REGIONS.size():
		active.append(int(D.REGIONS[r]["tier"]) <= maxi(2, n))
		var row := []
		var pr := []
		for p in n:
			row.append(0)
			pr.append(0)
		cubes.append(row)
		potions.append(pr)
		rats.append([])
	palace.clear()
	baker.clear()
	known.clear()
	for p in n:
		palace.append(0)
		baker.append(0)
		known.append({})
	cards = card_list.duplicate()
	owner.clear()
	for c in cards:
		owner[c] = -1


func clone() -> RTState:
	var s := RTState.new()
	s.n = n
	s.active = active.duplicate()
	s.cubes = cubes.duplicate(true)
	s.potions = potions.duplicate(true)
	s.potion_supply = potion_supply
	s.palace = palace.duplicate()
	s.baker = baker.duplicate()
	s.rats = rats.duplicate(true)
	s.bag = bag.duplicate()
	s.removed = removed.duplicate()
	s.plague = plague
	s.cards = cards.duplicate()
	s.owner = owner.duplicate()
	s.nuns = nuns.duplicate()
	s.bishops = bishops.duplicate()
	s.walls = walls.duplicate()
	s.known = known.duplicate(true)
	return s


func _log(t: String) -> void:
	if logger.is_valid():
		logger.call(t)


# ================================================================ letture

func regions() -> Array:
	var out := []
	for r in active.size():
		if active[r]:
			out.append(r)
	return out


func rname(r: int) -> String:
	return D.REGIONS[r]["name"]


func total(r: int) -> int:
	var t := 0
	for p in n:
		t += cubes[r][p]
	return t


func onboard(p: int) -> int:
	var t := 0
	for r in cubes.size():
		t += cubes[r][p]
	return t


func supply(p: int) -> int:
	return D.CUBES - onboard(p) - palace[p] - baker[p]


func score(p: int) -> int:
	return onboard(p) + palace[p]


func walled(a: int, b: int) -> bool:
	return D.edge_key(a, b) in walls


## Regioni confinanti in gioco, senza muri in mezzo.
func nbrs(r: int) -> Array:
	var out := []
	for x in D.neighbors_all(r):
		if active[x] and not walled(r, x):
			out.append(x)
	return out


## Confini fra regioni in gioco (per i muri dell'Imperatore).
func edges() -> Array:
	var out := []
	for e in D.EDGES:
		if active[e[0]] and active[e[1]]:
			out.append(D.edge_key(e[0], e[1]))
	return out


func has_bishop(r: int) -> bool:
	return r in bishops


func nuns_in(r: int) -> int:
	var k := 0
	for x in nuns:
		if x == r:
			k += 1
	return k


func can_get_rat(r: int) -> bool:
	return active[r] and rats[r].size() < 3 and not has_bishop(r)


func holder(card: String) -> int:
	return int(owner.get(card, -1))


func holds(p: int, card: String) -> bool:
	return owner.has(card) and int(owner[card]) == p


func held(p: int) -> Array:
	var out := []
	for c in cards:
		if holds(p, c):
			out.append(c)
	return out


## Quante carte della classe ha il giocatore (ogni carta uccide un cubetto per simbolo).
func class_cards(p: int, cls: String) -> int:
	var k := 0
	for c in cards:
		if D.CARDS[c]["cls"] == cls and holds(p, c):
			k += 1
	return k


## Area collegata più grande del giocatore (numero di regioni confinanti con i suoi cubetti).
func largest_area(p: int) -> int:
	var seen := {}
	var best := 0
	for r in regions():
		if cubes[r][p] <= 0 or seen.has(r):
			continue
		var stack := [r]
		seen[r] = true
		var size := 0
		while not stack.is_empty():
			var x: int = stack.pop_back()
			size += 1
			for y in D.neighbors_all(x):
				if active[y] and cubes[y][p] > 0 and not seen.has(y):
					seen[y] = true
					stack.append(y)
		best = maxi(best, size)
	return best


func queen_ok(p: int) -> bool:
	if not holds(p, "regina"):
		return false
	var mine := largest_area(p)
	for q in n:
		if q != p and largest_area(q) >= mine:
			return false
	return mine > 0


func has_majority(p: int, r: int) -> bool:
	if cubes[r][p] <= 0:
		return false
	for q in n:
		if q != p and cubes[r][q] >= cubes[r][p]:
			return false
	return true


func majority_regions(p: int) -> Array:
	var out := []
	for r in regions():
		if has_majority(p, r):
			out.append(r)
	return out


## Cubetti in più quando si aggiungono (Contadino +1, Regina +2).
func place_bonus(p: int) -> int:
	return (1 if holds(p, "contadino") else 0) + (2 if queen_ok(p) else 0)


## Dove si possono aggiungere cubetti: [{r, k}] (k = quanti, già limitato dalla riserva).
func place_options(p: int) -> Array:
	var out := []
	var sup := supply(p)
	if sup <= 0:
		return out
	var bonus := place_bonus(p)
	for r in regions():
		var k: int = rats[r].size()
		if k == 0 and not holds(p, "contadino"):
			continue
		k += bonus
		if k > 0:
			out.append({"r": r, "k": mini(k, sup)})
	return out


# ================================================================ operazioni sui cubetti

func add_cubes(p: int, r: int, k: int) -> int:
	k = mini(k, supply(p))
	if k > 0:
		cubes[r][p] += k
	return k


## Toglie cubetti senza peste (spostamenti): le pozioni in più tornano nella riserva.
func take_cubes(p: int, r: int, k: int) -> int:
	k = mini(k, cubes[r][p])
	cubes[r][p] -= k
	var extra: int = potions[r][p] - cubes[r][p]
	if extra > 0:
		potions[r][p] -= extra
		potion_supply += extra
	return k


## Sposta cubetti (con le loro pozioni, finché bastano).
func move_cubes(p: int, a: int, b: int, k: int) -> int:
	k = mini(k, cubes[a][p])
	var pot := mini(k, potions[a][p])
	cubes[a][p] -= k
	potions[a][p] -= pot
	cubes[b][p] += k
	potions[b][p] += pot
	return k


## La peste uccide un cubetto: se c'è una pozione si toglie quella. true se il cubetto muore davvero.
func plague_kill(p: int, r: int) -> bool:
	if cubes[r][p] <= 0:
		return false
	if potions[r][p] > 0:
		potions[r][p] -= 1
		potion_supply += 1
		return false
	cubes[r][p] -= 1
	return true


# ================================================================ ratti

## Risolve un gettone già scoperto nella regione r. neutral = abitanti in più (Cavaliere).
## serf = giocatore con il Servo della gleba che gioca il turno (-1 nessuno).
## Restituisce {out: epidemia sì/no, dead: [morti per giocatore], saved: [pozioni usate], serf: cubetti aggiunti}.
func resolve_token(r: int, tid: int, neutral := 0, serf := -1) -> Dictionary:
	var info: Array = D.RATS[tid]
	var lim: int = info[0]
	var sym: String = info[1]
	var dead := []
	var saved := []
	for p in n:
		dead.append(0)
		saved.append(0)
	var pop: int = total(r) + neutral - nuns_in(r)
	var res := {"out": pop >= lim, "dead": dead, "saved": saved, "serf": 0, "pop": pop, "lim": lim}
	if pop < lim:
		return res
	# prima le M (maggioranza), valutate sui cubetti presenti al momento
	var hits := []
	for p in n:
		hits.append(0)
	var nm := sym.count("M")
	for i in nm:
		var mx := 0
		for p in n:
			mx = maxi(mx, cubes[r][p])
		if mx <= 0:
			break
		for p in n:
			if cubes[r][p] == mx:
				_hit(p, r, dead, saved)
	for ch in sym:
		if ch == "M" or ch == "A":
			continue
		for p in n:
			var k := class_cards(p, ch)
			for j in k:
				_hit(p, r, dead, saved)
	for i in sym.count("A"):
		for p in n:
			if cubes[r][p] > 0:
				_hit(p, r, dead, saved)
	if serf >= 0:
		for p in n:
			if p != serf and dead[p] > 0:
				res["serf"] = add_cubes(serf, r, 1)
				break
	return res


func _hit(p: int, r: int, dead: Array, saved: Array) -> void:
	if cubes[r][p] <= 0:
		return
	if plague_kill(p, r):
		dead[p] += 1
	else:
		saved[p] += 1


## Tutti i gettoni che il giocatore non conosce (riserva + coperti non visti): per stimare il rischio.
func unknown_pool(p: int) -> Array:
	var out := bag.duplicate()
	for r in rats.size():
		for t in rats[r]:
			if not (p >= 0 and known[p].has(t)):
				out.append(t)
	return out


## Perdite attese di ciascun giocatore se la peste colpisse adesso la regione r, dal punto di vista di p
## (conosce solo i gettoni visti con la Strega). Simulazione con estrazioni a caso dei gettoni ignoti.
func expected_loss(p: int, r: int, neutral: int, samples: int, rng: RandomNumberGenerator, serf := -1) -> Array:
	var out := []
	for q in n:
		out.append(0.0)
	var toks: Array = rats[r]
	if toks.is_empty() or total(r) == 0:
		return out
	var pool := unknown_pool(p)
	for s in samples:
		var c: Array = cubes[r].duplicate()
		var pot: Array = potions[r].duplicate()
		var used := {}
		for t in toks:
			if c.reduce(func(a, b): return a + b, 0) == 0:
				break
			var tid: int = t
			if not (p >= 0 and known[p].has(t)):
				if pool.is_empty():
					continue
				var guard := 0
				tid = pool[rng.randi() % pool.size()]
				while used.has(tid) and guard < 8:
					tid = pool[rng.randi() % pool.size()]
					guard += 1
				used[tid] = true
			_sim_token(c, pot, r, tid, neutral, serf, out)
	for q in n:
		out[q] /= float(samples)
	return out


func _sim_token(c: Array, pot: Array, r: int, tid: int, neutral: int, serf: int, out: Array) -> void:
	var info: Array = D.RATS[tid]
	var pop: int = c.reduce(func(a, b): return a + b, 0) + neutral - nuns_in(r)
	if pop < int(info[0]):
		return
	var sym: String = info[1]
	var dead := []
	for q in n:
		dead.append(0)
	for i in sym.count("M"):
		var mx: int = c.max()
		if mx <= 0:
			break
		for q in n:
			if c[q] == mx:
				_sim_hit(c, pot, q, dead)
	for ch in sym:
		if ch == "M" or ch == "A":
			continue
		for q in n:
			for j in class_cards(q, ch):
				_sim_hit(c, pot, q, dead)
	for i in sym.count("A"):
		for q in n:
			if c[q] > 0:
				_sim_hit(c, pot, q, dead)
	for q in n:
		out[q] += dead[q]
	if serf >= 0:
		for q in n:
			if q != serf and dead[q] > 0:
				out[serf] -= 1.0
				c[serf] += 1
				break


func _sim_hit(c: Array, pot: Array, q: int, dead: Array) -> void:
	if c[q] <= 0:
		return
	if pot[q] > 0:
		pot[q] -= 1
		return
	c[q] -= 1
	dead[q] += 1
