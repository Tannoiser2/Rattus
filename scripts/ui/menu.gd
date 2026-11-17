extends Control
## Menu principale: giocatori (persona o IA), carte di classe in gioco, opzioni, partite salvate e gioco online.

const D = preload("res://scripts/data/rt_data.gd")
const MODES := ["Persona", "IA facile", "IA normale", "IA difficile"]
const SET_KEYS := ["base", "prosperi", "ratti", "guerra", "classe", "caso", "libera"]
const SET_NAMES := ["Gioco base", "Tempi prosperi", "Controllo dei ratti", "Europa in guerra", "Una a caso per classe", "Sei a caso", "Scelta libera"]

var main
var page: Control
var nplayers := 2                # numero di giocatori - 2
var modes := [0, 2, 2, 2]
var names := ["", "", "", ""]
var card_set := 0
var custom := D.BASE_SET.duplicate()
var speed := 1
var anim := 1
var msg: Label
var seat_box: VBoxContainer
var cards_box: Control
var custom_box: GridContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var st: Dictionary = main.menu_state
	if not st.is_empty():
		nplayers = st["nplayers"]
		modes = st["modes"].duplicate()
		names = st["names"].duplicate()
		speed = st["speed"]
		anim = st.get("anim", 1)
		card_set = st.get("card_set", 0)
		custom = st.get("custom", custom).duplicate()
	page = Control.new()
	page.size = Vector2(1920, 1080)
	add_child(page)
	_center.call_deferred()
	get_viewport().size_changed.connect(_center)

	# a sinistra: la copertina
	var frame := PanelContainer.new()
	var fs := UI.panel_style(Color.BLACK, UI.GOLD, 3, 4)
	fs.set_content_margin_all(5)
	fs.shadow_color = Color(0, 0, 0, 0.7)
	fs.shadow_size = 20
	frame.add_theme_stylebox_override("panel", fs)
	frame.position = Vector2(80, 70)
	frame.add_child(UI.icon_rect(UI.tex("res://assets/misc/copertina.jpg"), Vector2(580, 580)))
	page.add_child(frame)
	var t2 := UI.title("Rattus", 84)
	t2.position = Vector2(90, 668)
	page.add_child(t2)
	var t3 := UI.wrap(UI.label("Åse e Henrik Berg · White Goblin Games, 2010 · con l'espansione Pied Piper (il Pifferaio magico)\nLa peste arriva dall'Oriente e in pochi anni dimezza la popolazione d'Europa. Fate crescere i vostri popoli nelle regioni del continente, fatevi aiutare da contadini, monaci, mercanti, cavalieri, streghe e re, e mandate i ratti dagli avversari. Quando la peste si ritira vince chi ha più abitanti sopravvissuti.", 22, UI.MUTED), 610)
	t3.position = Vector2(96, 790)
	page.add_child(t3)

	# a destra: giocatori e opzioni
	var col := VBoxContainer.new()
	col.position = Vector2(760, 50)
	col.custom_minimum_size = Vector2(1100, 0)
	col.add_theme_constant_override("separation", 12)
	page.add_child(col)
	col.add_child(UI.heading("Giocatori", 32))
	col.add_child(_segmented("Quanti", ["2", "3", "4"], nplayers, func(k):
		nplayers = k
		_refresh(), 90))
	seat_box = VBoxContainer.new()
	seat_box.add_theme_constant_override("separation", 8)
	col.add_child(seat_box)
	col.add_child(UI.heading("Carte di classe", 32))
	var sets_row := GridContainer.new()
	sets_row.columns = 4
	sets_row.add_theme_constant_override("h_separation", 6)
	sets_row.add_theme_constant_override("v_separation", 6)
	col.add_child(sets_row)
	var sbtns := []
	for i in SET_NAMES.size():
		var b := UI.button(SET_NAMES[i], 266, 46, 19)
		b.toggle_mode = true
		b.button_pressed = i == card_set
		sbtns.append(b)
		sets_row.add_child(b)
	for i in sbtns.size():
		var k := i
		sbtns[i].pressed.connect(func():
			for j in sbtns.size():
				sbtns[j].button_pressed = j == k
			card_set = k
			_refresh_cards())
	cards_box = HBoxContainer.new()
	cards_box.add_theme_constant_override("separation", 8)
	cards_box.custom_minimum_size.y = 150
	col.add_child(cards_box)
	custom_box = GridContainer.new()
	custom_box.columns = 9
	custom_box.add_theme_constant_override("h_separation", 6)
	custom_box.add_theme_constant_override("v_separation", 6)
	col.add_child(custom_box)
	col.add_child(UI.heading("Opzioni", 32))
	var o2 := HBoxContainer.new()
	o2.add_theme_constant_override("separation", 30)
	col.add_child(o2)
	o2.add_child(_segmented("Pausa dell'IA", ["Lunga", "Normale", "Breve", "Nessuna"], speed, func(k): speed = k, 110))
	o2.add_child(_segmented("Animazioni", ["Lente", "Normali", "Veloci"], anim, func(k): anim = k, 110))
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 16)
	col.add_child(btns)
	var play := UI.primary(UI.button("Gioca", 300, 70, 30))
	play.pressed.connect(_on_start)
	btns.add_child(play)
	var onl := UI.button("Gioca online", 250, 70, 24)
	onl.pressed.connect(_online_panel)
	btns.add_child(onl)
	var ld := UI.button("Carica partita", 230, 70, 22)
	ld.pressed.connect(_load_panel)
	btns.add_child(ld)
	var rules := UI.button("Regole", 180, 70, 24)
	rules.pressed.connect(func():
		_store()
		main.show_rules())
	btns.add_child(rules)
	msg = UI.label("", 22, UI.GOLD_L)
	col.add_child(msg)
	_refresh()
	_refresh_cards()


func _center() -> void:
	var vs := get_viewport_rect().size
	var k := minf(vs.x / 1920.0, vs.y / 1080.0)
	page.scale = Vector2(k, k)
	page.position = (vs - Vector2(1920, 1080) * k) * 0.5


func _store() -> void:
	main.menu_state = {"nplayers": nplayers, "modes": modes.duplicate(), "names": names.duplicate(), "speed": speed,
		"anim": anim, "card_set": card_set, "custom": custom.duplicate()}


func np() -> int:
	return nplayers + 2


func _refresh() -> void:
	for c in seat_box.get_children():
		c.queue_free()
	for s in np():
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 10)
		seat_box.add_child(r)
		var sw := PanelContainer.new()
		var ss := UI.panel_style(Color(D.COLORS[s]["col"], 0.95), D.COLORS[s]["dark"], 3, 6)
		ss.set_content_margin_all(2)
		sw.add_theme_stylebox_override("panel", ss)
		sw.custom_minimum_size = Vector2(170, 50)
		var lab := UI.label(D.COLORS[s]["name"], 22, D.COLORS[s]["text"], UI.font_head)
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		sw.add_child(lab)
		r.add_child(sw)
		var k := s
		r.add_child(_segmented("", MODES, modes[s], func(m): modes[k] = m, 150))
		var le := _line("Nome (facoltativo)", 18)
		le.text = names[s]
		le.custom_minimum_size = Vector2(290, 50)
		le.text_changed.connect(func(tx): names[k] = tx)
		r.add_child(le)


## Le carte che andranno in gioco con la scelta attuale (per le scelte a caso: anteprima delle classi).
func _refresh_cards() -> void:
	for c in cards_box.get_children():
		c.queue_free()
	for c in custom_box.get_children():
		c.queue_free()
	var key: String = SET_KEYS[card_set]
	custom_box.visible = key == "libera"
	if D.SETS.has(key):
		for c in D.SETS[key]["cards"]:
			cards_box.add_child(_card_thumb(c, Vector2(104, 146)))
		var l := UI.wrap(UI.label(_set_note(key), 19, UI.MUTED), 360)
		cards_box.add_child(l)
	elif key == "libera":
		var l := UI.wrap(UI.label("Scegli sei carte (%d scelte). Con meno di 4 giocatori conviene tenere almeno una carta di Cavalleria." % custom.size(), 20, UI.PARCH), 1000)
		cards_box.custom_minimum_size.y = 40
		cards_box.add_child(l)
		for c in D.CARD_ORDER:
			var b := Button.new()
			b.toggle_mode = true
			b.button_pressed = c in custom
			b.custom_minimum_size = Vector2(112, 156)
			b.icon = UI.card_tex(c)
			b.expand_icon = true
			b.tooltip_text = "%s (%s): %s" % [D.CARDS[c]["name"], D.CLASSES[D.CARDS[c]["cls"]]["name"], D.CARDS[c]["text"]]
			var cc: String = c
			b.toggled.connect(func(on):
				if on and not (cc in custom):
					custom.append(cc)
				elif not on:
					custom.erase(cc)
				_refresh_cards())
			custom_box.add_child(b)
		return
	else:
		var l := UI.wrap(UI.label("Una carta per classe estratta a caso fra le tre di ogni classe (gioco base e Pifferaio magico)." if key == "classe" else "Sei carte estratte a caso fra tutte e diciotto.", 21, UI.PARCH), 900)
		cards_box.add_child(l)
	cards_box.custom_minimum_size.y = 150


func _set_note(key: String) -> String:
	match key:
		"base": return "Le sei classi del gioco base: Contadino, Mercante, Monaco, Cavaliere, Strega e Re."
		"prosperi": return "Tempi prosperi: tante carte che aggiungono cubetti, il tabellone si riempie."
		"ratti": return "Controllo dei ratti: muovere, piazzare e risolvere i ratti."
		"guerra": return "Europa in guerra: carte per attaccarsi a vicenda."
	return ""


func _card_thumb(c: String, sz: Vector2) -> Control:
	var t := UI.icon_rect(UI.card_tex(c), sz)
	t.mouse_filter = Control.MOUSE_FILTER_PASS
	t.tooltip_text = "%s (%s): %s" % [D.CARDS[c]["name"], D.CLASSES[D.CARDS[c]["cls"]]["name"], D.CARDS[c]["text"]]
	return t


func _segmented(label_text: String, items: Array, cur: int, cb: Callable, w := 120) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	if label_text != "":
		var l := UI.label(label_text, 22, UI.TEXT, UI.font_head_r)
		h.add_child(l)
		var spc := Control.new()
		spc.custom_minimum_size.x = 8
		h.add_child(spc)
	var btns := []
	for i in items.size():
		var b := UI.button(items[i], w, 48, 19)
		b.toggle_mode = true
		b.button_pressed = i == cur
		btns.append(b)
		h.add_child(b)
	for i in btns.size():
		var k := i
		btns[i].pressed.connect(func():
			for j in btns.size():
				btns[j].button_pressed = j == k
			cb.call(k))
	return h


## Le sei carte della partita (le scelte a caso si estraggono qui, così valgono per tutti online).
func _cards() -> Array:
	var key: String = SET_KEYS[card_set]
	if D.SETS.has(key):
		return D.SETS[key]["cards"].duplicate()
	var g := RandomNumberGenerator.new()
	g.randomize()
	if key == "classe":
		var out := []
		for cls in D.CLASS_ORDER:
			var opts := []
			for c in D.CARD_ORDER:
				if D.CARDS[c]["cls"] == cls:
					opts.append(c)
			out.append(opts[g.randi() % opts.size()])
		return out
	if key == "caso":
		var all := D.CARD_ORDER.duplicate()
		for i in range(all.size() - 1, 0, -1):
			var j := g.randi() % (i + 1)
			var t = all[i]
			all[i] = all[j]
			all[j] = t
		return all.slice(0, 6)
	return custom.duplicate()


func _config() -> Dictionary:
	var seats := []
	for s in np():
		var nm: String = names[s].strip_edges()
		if nm == "":
			nm = D.COLORS[s]["name"] if modes[s] == 0 else "%s (IA)" % D.COLORS[s]["name"]
		seats.append({"name": nm, "ai": modes[s] != 0, "level": maxi(0, modes[s] - 1), "color": s})
	var delays := [1.3, 0.7, 0.3, 0.0]
	var anims := [0.6, 1.0, 1.8]
	return {"seats": seats, "ai_delay": delays[speed], "anim": anims[anim], "cards": _cards()}


func _on_start() -> void:
	if SET_KEYS[card_set] == "libera" and custom.size() != 6:
		msg.text = "Nella scelta libera servono esattamente sei carte (ora sono %d)." % custom.size()
		return
	_store()
	main.start_game(_config())


# =================================================================== online

var on_panel: Control
var on_name: LineEdit
var on_code: LineEdit
var on_lbl: Label
var on_start: Button


func _overlay(pos: Vector2, w: float) -> VBoxContainer:
	if is_instance_valid(on_panel):
		on_panel.queue_free()
	on_panel = Control.new()
	on_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	on_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(on_panel)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.8)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	on_panel.add_child(shade)
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UI.dark_style(10, 0.98))
	box.position = page.position + pos * page.scale
	box.scale = page.scale
	box.custom_minimum_size = Vector2(w, 0)
	on_panel.add_child(box)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16)
	box.add_child(vb)
	return vb


func _online_panel() -> void:
	if SET_KEYS[card_set] == "libera" and custom.size() != 6:
		msg.text = "Nella scelta libera servono esattamente sei carte."
		return
	var vb := _overlay(Vector2(540, 110), 840)
	vb.add_child(UI.title("Gioca online", 60))
	var info := UI.wrap(UI.label("Chi crea la stanza gioca il Rosso. I posti segnati «Persona» nel menu restano liberi per gli amici, che entrano con il codice; quelli segnati IA (e i posti rimasti vuoti) li gioca il computer. Numero di giocatori e carte scelti nel menu valgono per tutti. La partita resta salvata nella stanza: si può rientrare con lo stesso codice.", 21, UI.MUTED), 800)
	vb.add_child(info)
	var ses: Dictionary = main.get_net().load_session()
	on_name = _line("Il tuo nome", 20)
	on_name.text = str(ses.get("name", ""))
	vb.add_child(on_name)
	var b_create := UI.button("Crea una stanza", 0, 56, 22)
	b_create.pressed.connect(_online_create)
	vb.add_child(b_create)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	on_code = _line("Codice", 4)
	on_code.custom_minimum_size.x = 220
	on_code.text_changed.connect(func(t):
		on_code.text = t.to_upper()
		on_code.caret_column = t.length())
	row.add_child(on_code)
	var b_join := UI.button("Entra", 200, 56, 22)
	b_join.pressed.connect(_online_join)
	row.add_child(b_join)
	vb.add_child(row)
	on_lbl = UI.wrap(UI.label("", 22, Color.WHITE), 800)
	on_lbl.custom_minimum_size.y = 120
	vb.add_child(on_lbl)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 12)
	on_start = UI.primary(UI.button("Inizia online", 420, 60, 24))
	on_start.pressed.connect(_online_start)
	on_start.visible = main.lobby.get("role", "") == "host"
	row2.add_child(on_start)
	var b_close := UI.button("Indietro", 300, 60, 22)
	b_close.pressed.connect(func(): on_panel.queue_free())
	row2.add_child(b_close)
	vb.add_child(row2)
	if not main.lobby.is_empty():
		on_code.text = main.lobby["code"]
		on_lbl.text = "Stanza %s…" % main.lobby["code"]
	elif str(ses.get("room", "")) != "":
		on_code.text = str(ses["room"])
		on_lbl.text = "Eri nella stanza %s: premi Entra per rientrare." % ses["room"]


func _line(ph: String, maxlen: int) -> LineEdit:
	var le := LineEdit.new()
	le.placeholder_text = ph
	le.max_length = maxlen
	le.custom_minimum_size = Vector2(0, 56)
	le.add_theme_font_size_override("font_size", 24)
	return le


func _say(t: String) -> void:
	if is_instance_valid(on_lbl):
		on_lbl.text = t


func _seats_text(room: Dictionary) -> String:
	var seats := Net._as_dict(room.get("seats", {}))
	var parts := []
	for idx in room.get("open", []):
		var k := str(int(idx))
		var who := str(seats[k].get("name", "?")) if seats.has(k) and seats[k] is Dictionary else "libero"
		parts.append("%s: %s" % [D.COLORS[int(idx)]["name"], who])
	return ", ".join(parts)


func _online_create() -> void:
	var nm := on_name.text.strip_edges()
	if nm == "":
		_say("Scrivi il tuo nome.")
		return
	var seats := [0]
	for s in range(1, np()):
		if modes[s] == 0:
			seats.append(s)
	if seats.size() < 2:
		_say("Segna «Persona» nel menu almeno un posto oltre al tuo, per l'amico.")
		return
	modes[0] = 0
	_store()
	_say("Creo la stanza…")
	var net: Net = main.get_net()
	var code := await net.create_room(nm, seats)
	if code == "":
		_say("Non riesco a creare la stanza.\n%s" % net.last_error)
		return
	main.lobby = {"role": "host", "code": code, "seat": 0}
	net.remember_room(code, 0)
	net._save({"name": nm})
	if is_instance_valid(on_code):
		on_code.text = code
	if is_instance_valid(on_start):
		on_start.visible = true
	_lobby_poll(code)


func _online_join() -> void:
	var code := on_code.text.strip_edges().to_upper()
	var nm := on_name.text.strip_edges()
	if nm == "" or code.length() != 4:
		_say("Scrivi il tuo nome e il codice di 4 lettere.")
		return
	_say("Entro nella stanza %s…" % code)
	var net: Net = main.get_net()
	var seat := await net.join_room(code, nm)
	if seat == -2:
		_say("Stanza %s non trovata, oppure la partita è già iniziata.%s" % [code, ("\n" + net.last_error) if net.last_error != "" else ""])
		return
	if seat == -1:
		_say("Nella stanza %s non ci sono posti liberi." % code)
		return
	var room: Dictionary = net.last_room
	main.lobby = {"role": "host" if room.get("host", "") == net.uid else "guest", "code": code, "seat": seat}
	net.remember_room(code, seat)
	net._save({"name": nm})
	if room.get("status", "") in ["playing", "over"] and room.has("game"):
		_say("Rientro nella partita della stanza %s…" % code)
		_begin(room["game"], true)
		return
	if is_instance_valid(on_start):
		on_start.visible = main.lobby["role"] == "host"
	_lobby_poll(code)


func _lobby_poll(code: String) -> void:
	var net: Net = main.get_net()
	while is_inside_tree() and main.lobby.get("code", "") == code:
		var room := await net.room(code)
		if not is_inside_tree() or main.lobby.get("code", "") != code:
			return
		if room.is_empty():
			_say("La stanza %s non esiste più." % code)
			main.lobby = {}
			return
		if main.lobby["role"] == "host":
			_say("Stanza [ %s ]: dai il codice agli amici.\nPosti: %s.\nQuando ci sono premi Inizia online (i posti rimasti liberi li gioca l'IA)." % [code, _seats_text(room)])
		else:
			if room.get("status", "") == "playing" and room.has("game"):
				_begin(room["game"], false)
				return
			_say("Sei nella stanza [ %s ] (giochi il %s).\nAspetta che chi l'ha creata avvii la partita." % [code, D.COLORS[int(main.lobby["seat"])]["name"]])
		await get_tree().create_timer(2.0).timeout


## Chi ha creato la stanza avvia: giocatori, carte e seme valgono per tutti.
func _online_start() -> void:
	var code: String = main.lobby["code"]
	var net: Net = main.get_net()
	var room := await net.room(code)
	if room.is_empty():
		_say("La stanza %s non esiste più." % code)
		main.lobby = {}
		return
	var seats_db := Net._as_dict(room.get("seats", {}))
	var cfg := _config()
	for i in np():
		var k := str(i)
		if seats_db.has(k) and seats_db[k] is Dictionary:
			cfg["seats"][i]["name"] = str(seats_db[k].get("name", cfg["seats"][i]["name"]))
			cfg["seats"][i]["ai"] = false
		else:
			cfg["seats"][i]["ai"] = true
			cfg["seats"][i]["level"] = maxi(1, modes[i] - 1)
			if modes[i] == 0:
				cfg["seats"][i]["name"] = "%s (IA)" % D.COLORS[i]["name"]
	cfg["seed"] = 1 + randi() % 2000000000
	var g := {"cfg": var_to_str(cfg)}
	if not await net.start_room(code, g):
		_say("Non riesco ad avviare la partita (%s)." % net.last_error)
		return
	_begin(g, false)


func _begin(g: Dictionary, rejoin: bool) -> void:
	var net: Net = main.get_net()
	var lob: Dictionary = main.lobby
	var backlog: Array = []
	if rejoin:
		backlog = await net.get_acts(lob["code"])
		net.set_away(lob["code"], int(lob["seat"]), false)
	var cfg = str_to_var(str(g.get("cfg", "")))
	if not (cfg is Dictionary):
		_say("Configurazione della partita non valida.")
		return
	var ses := OnlineSession.new()
	ses.setup(net, lob["code"], int(lob["seat"]), lob["role"], backlog)
	cfg["online"] = ses
	main.lobby = {}
	main.start_game(cfg)


# =================================================================== partite salvate

func _load_panel() -> void:
	var vb := _overlay(Vector2(560, 180), 800)
	vb.add_child(UI.title("Carica partita", 60))
	vb.add_child(UI.wrap(UI.label("Scrivi il codice di 6 lettere ottenuto con «Salva» durante la partita. Le partite salvate stanno su Firebase e si riprendono da qualsiasi dispositivo.", 21, UI.MUTED), 760))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	on_code = _line("Codice", 6)
	on_code.custom_minimum_size.x = 260
	on_code.text_changed.connect(func(t):
		on_code.text = t.to_upper()
		on_code.caret_column = t.length())
	row.add_child(on_code)
	var b := UI.primary(UI.button("Carica", 220, 56, 22))
	b.pressed.connect(_do_load)
	row.add_child(b)
	vb.add_child(row)
	on_lbl = UI.wrap(UI.label("", 22, Color.WHITE), 760)
	on_lbl.custom_minimum_size.y = 80
	vb.add_child(on_lbl)
	var cl := UI.button("Indietro", 260, 56, 22)
	cl.pressed.connect(func(): on_panel.queue_free())
	vb.add_child(cl)


func _do_load() -> void:
	var code := on_code.text.strip_edges().to_upper()
	if code.length() != 6:
		_say("Il codice ha 6 lettere.")
		return
	_say("Carico la partita %s…" % code)
	var net: Net = main.get_net()
	var data := await net.load_game(code)
	if data.is_empty():
		_say("Partita %s non trovata.%s" % [code, ("\n" + net.last_error) if net.last_error != "" else ""])
		return
	var cfg = str_to_var(str(data.get("cfg", "")))
	var moves = str_to_var(str(data.get("moves", "[]")))
	if not (cfg is Dictionary) or not (moves is Array):
		_say("Salvataggio non valido.")
		return
	cfg["replay"] = moves
	main.start_game(cfg)
	if main.current != null:
		main.current.save_code = code
