extends Control
## Schermata di gioco: il tabellone 3D occupa tutto lo schermo; a sinistra i giocatori, in basso le sei
## carte di classe, a destra le scelte e il diario. Le scelte si fanno con i pulsanti o toccando il
## tabellone (regioni, gettoni, cubetti e confini evidenziati da un anello dorato).

const D = preload("res://scripts/data/rt_data.gd")
const LEFT_W := 330.0
const RIGHT_W := 450.0

var main
var config := {}
var engine: RTEngine
var board3d
var top_lbl: Label
var info_lbl: Label
var players_box: VBoxContainer
var cards_box: HBoxContainer
var log_box: RichTextLabel
var prompt: PanelContainer
var prompt_title: Label
var prompt_box: VBoxContainer
var reveal_box: HBoxContainer
var popup_layer: Control
var toast_box: VBoxContainer
var wait_lbl: Label
var pending := {}
var focus_p := 0
var humans: Array = []
var save_code := ""
var top := false
var _dirty := true


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	engine = RTEngine.new()
	add_child(engine)
	if not config.has("seed"):
		config["seed"] = 1 + randi() % 2000000000
	engine.setup(config)
	for i in engine.n:
		var st: Dictionary = config["seats"][i]
		engine.ais[i] = RTAI.new(int(st.get("level", 1)), int(config["seed"]) + i * 31)
		if not st.get("ai", false):
			humans.append(i)
	focus_p = humans[0] if not humans.is_empty() else -1
	if config.has("online"):
		engine.online = config["online"]
		add_child(engine.online)
		engine.online.view = self
		focus_p = engine.online.seat
		humans = [engine.online.seat]
		engine.online.heartbeat_loop()
	_build()
	engine.changed.connect(func(): _dirty = true)
	engine.log_added.connect(_on_log)
	engine.decision_requested.connect(_on_decision)
	engine.fx.connect(_on_fx)
	engine.game_ended.connect(_on_end)
	engine.run.call_deferred()


func _exit_tree() -> void:
	if engine != null:
		engine.abort = true
		engine.provide_decision(0)


# ================================================================ struttura

func _build() -> void:
	board3d = preload("res://scripts/ui/board_3d.gd").new()
	board3d.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(board3d)
	board3d.setup(engine)
	board3d.viewer = focus_p
	board3d.spot_pressed.connect(_on_spot)

	# barra in alto: comandi e situazione
	var bar := HBoxContainer.new()
	bar.position = Vector2(12, 10)
	bar.add_theme_constant_override("separation", 8)
	add_child(bar)
	for it in [["Menu", _ask_menu], ["Regole", _show_rules], ["Salva", _save_game], ["Dall'alto", _toggle_top], ["Centra", func(): board3d.reset_view(); top = false]]:
		var b := UI.button(it[0], 0, 46, 19)
		b.pressed.connect(it[1])
		bar.add_child(b)
		if it[0] == "Salva":
			b.visible = not config.has("online")

	var tp := PanelContainer.new()
	tp.add_theme_stylebox_override("panel", UI.parch_style(6))
	tp.anchor_left = 0.5
	tp.anchor_right = 0.5
	tp.offset_left = -330
	tp.offset_right = 330
	tp.offset_top = 8
	tp.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(tp)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 0)
	tp.add_child(tv)
	top_lbl = UI.label("", 27, UI.INK, UI.font_head)
	top_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top_lbl.custom_minimum_size.x = 620
	tv.add_child(top_lbl)
	info_lbl = UI.label("", 20, Color("#5a3d22"), UI.font_body)
	info_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_lbl.custom_minimum_size.x = 620
	tv.add_child(info_lbl)

	# ratti scoperti nella devastazione in corso
	reveal_box = HBoxContainer.new()
	reveal_box.anchor_left = 0.5
	reveal_box.anchor_right = 0.5
	reveal_box.offset_left = -260
	reveal_box.offset_right = 260
	reveal_box.offset_top = 104
	reveal_box.alignment = BoxContainer.ALIGNMENT_CENTER
	reveal_box.add_theme_constant_override("separation", 10)
	reveal_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(reveal_box)

	# a sinistra: i giocatori
	var lp := PanelContainer.new()
	lp.add_theme_stylebox_override("panel", UI.dark_style(8, 0.9))
	lp.position = Vector2(12, 70)
	lp.custom_minimum_size = Vector2(LEFT_W, 0)
	add_child(lp)
	players_box = VBoxContainer.new()
	players_box.add_theme_constant_override("separation", 10)
	lp.add_child(players_box)

	# in basso: le carte di classe
	var cp := PanelContainer.new()
	cp.add_theme_stylebox_override("panel", UI.dark_style(8, 0.88))
	cp.anchor_left = 0.5
	cp.anchor_right = 0.5
	cp.anchor_top = 1.0
	cp.anchor_bottom = 1.0
	cp.offset_left = -340 - (RIGHT_W - LEFT_W) * 0.5
	cp.offset_right = 340 - (RIGHT_W - LEFT_W) * 0.5
	cp.offset_top = -214
	cp.offset_bottom = -10
	cp.grow_horizontal = Control.GROW_DIRECTION_BOTH
	cp.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(cp)
	cards_box = HBoxContainer.new()
	cards_box.add_theme_constant_override("separation", 8)
	cards_box.alignment = BoxContainer.ALIGNMENT_CENTER
	cp.add_child(cards_box)

	# a destra: scelte e diario
	var rp := VBoxContainer.new()
	rp.anchor_left = 1.0
	rp.anchor_right = 1.0
	rp.anchor_bottom = 1.0
	rp.offset_left = -RIGHT_W - 12
	rp.offset_right = -12
	rp.offset_top = 70
	rp.offset_bottom = -12
	rp.add_theme_constant_override("separation", 10)
	rp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rp)
	prompt = PanelContainer.new()
	var ps := UI.parch_style(8)
	ps.border_color = UI.BLOOD
	ps.set_border_width_all(3)
	prompt.add_theme_stylebox_override("panel", ps)
	prompt.visible = false
	rp.add_child(prompt)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 8)
	prompt.add_child(pv)
	prompt_title = UI.wrap(UI.label("", 23, UI.INK, UI.font_head), RIGHT_W - 30)
	pv.add_child(prompt_title)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.custom_minimum_size = Vector2(RIGHT_W - 24, 0)
	sc.name = "scroll"
	pv.add_child(sc)
	prompt_box = VBoxContainer.new()
	prompt_box.add_theme_constant_override("separation", 6)
	prompt_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(prompt_box)
	wait_lbl = UI.wrap(UI.label("", 21, UI.GOLD_L, UI.font_head_r), RIGHT_W)
	rp.add_child(wait_lbl)
	var lg := PanelContainer.new()
	lg.add_theme_stylebox_override("panel", UI.dark_style(8, 0.9))
	lg.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rp.add_child(lg)
	var lv := VBoxContainer.new()
	lg.add_child(lv)
	lv.add_child(UI.heading("Cronaca", 24))
	log_box = RichTextLabel.new()
	log_box.scroll_following = true
	log_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_box.custom_minimum_size = Vector2(RIGHT_W - 30, 120)
	log_box.add_theme_font_size_override("normal_font_size", 19)
	lv.add_child(log_box)

	toast_box = VBoxContainer.new()
	toast_box.anchor_left = 0.5
	toast_box.anchor_right = 0.5
	toast_box.offset_left = -360 - (RIGHT_W - LEFT_W) * 0.5
	toast_box.offset_right = 360 - (RIGHT_W - LEFT_W) * 0.5
	toast_box.offset_top = 250
	toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_box.add_theme_constant_override("separation", 6)
	add_child(toast_box)

	popup_layer = Control.new()
	popup_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	popup_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(popup_layer)


func _process(_dt: float) -> void:
	if _dirty:
		_dirty = false
		_refresh()


func _toggle_top() -> void:
	top = not top
	board3d.top_view(top)


func _phase_text() -> String:
	var e := engine
	match e.phase:
		"setup": return "Preparazione: %s mette i primi cubetti" % e.pname(e.cur)
		"turn": return "Turno di %s" % e.pname(e.cur)
		"plague": return "La Peste colpisce · turno di %s" % e.pname(e.cur)
		"final": return "Ultimo giro · %s" % e.pname(e.cur)
		"over": return "Fine della partita"
	return ""


func _refresh() -> void:
	var e := engine
	if e.st == null:
		return
	top_lbl.text = _phase_text()
	info_lbl.text = "La Peste è in %s · ratti nella riserva: %d · tolti: %d" % [e.st.rname(e.st.plague), e.st.bag.size(), e.st.removed.size()]
	board3d.viewer = focus_p
	board3d.refresh()
	for c in players_box.get_children():
		c.queue_free()
	players_box.add_child(UI.heading("Popoli d'Europa", 26))
	for p in e.n:
		players_box.add_child(_player_row(p))
	for c in cards_box.get_children():
		c.queue_free()
	for c in e.st.cards:
		cards_box.add_child(_card_slot(c))
	_reveals()


func _player_row(p: int) -> Control:
	var e := engine
	var pc := PanelContainer.new()
	var on := p == e.cur and e.phase != "over"
	var sb := UI.panel_style(Color(UI.pdark(e, p), 0.55 if not on else 0.95), UI.GOLD_L if on else Color(UI.pcolor(e, p), 0.6), 3 if on else 2, 6)
	sb.set_content_margin_all(8)
	pc.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	pc.add_child(v)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	v.add_child(h)
	var sw := ColorRect.new()
	sw.color = UI.pcolor(e, p)
	sw.custom_minimum_size = Vector2(24, 24)
	h.add_child(sw)
	var nm := UI.label(e.pname(p) + (" ·IA" if e.players[p]["ai"] and not e.pname(p).ends_with("(IA)") else ""), 23, Color.WHITE, UI.font_head)
	nm.clip_text = true
	nm.custom_minimum_size.x = 200
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(nm)
	var sc := UI.label(str(e.st.score(p)), 30, UI.GOLD_L, UI.font_head)
	sc.tooltip_text = "Abitanti sopravvissuti (tabellone + palazzo)"
	sc.mouse_filter = Control.MOUSE_FILTER_PASS
	h.add_child(sc)
	var parts := ["in riserva %d" % e.st.supply(p)]
	if e.st.palace[p] > 0:
		parts.append("palazzo %d" % e.st.palace[p])
	if e.st.baker[p] > 0:
		parts.append("sul Fornaio %d" % e.st.baker[p])
	var pots := 0
	for r in e.st.regions():
		pots += e.st.potions[r][p]
	if pots > 0:
		parts.append("pozioni %d" % pots)
	v.add_child(UI.wrap(UI.label(", ".join(parts), 19, UI.PARCH, UI.font_body), LEFT_W - 30))
	var held := e.st.held(p)
	if not held.is_empty():
		var hc := HFlowContainer.new()
		hc.add_theme_constant_override("h_separation", 4)
		hc.custom_minimum_size.x = LEFT_W - 30
		v.add_child(hc)
		for c in held:
			var b := Button.new()
			b.custom_minimum_size = Vector2(46, 64)
			b.icon = UI.card_tex(c)
			b.expand_icon = true
			b.tooltip_text = "%s: %s" % [e.cname(c), D.CARDS[c]["text"]]
			var cc: String = c
			b.pressed.connect(func(): _card_zoom(cc))
			hc.add_child(b)
	return pc


func _card_slot(c: String) -> Control:
	var e := engine
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	var b := Button.new()
	b.custom_minimum_size = Vector2(100, 140)
	b.icon = UI.card_tex(c)
	b.expand_icon = true
	b.tooltip_text = "%s (%s): %s" % [e.cname(c), D.CLASSES[D.CARDS[c]["cls"]]["name"], D.CARDS[c]["text"]]
	b.pressed.connect(func(): _card_zoom(c))
	var o := e.st.holder(c)
	if o >= 0:
		var sb := StyleBoxFlat.new()
		sb.bg_color = UI.pcolor(e, o)
		sb.set_corner_radius_all(4)
		sb.set_content_margin_all(4)
		b.add_theme_stylebox_override("normal", sb)
	v.add_child(b)
	var l := UI.label(e.cname(c) if o < 0 else e.pname(o), 17, UI.PARCH if o < 0 else UI.pcolor(e, o).lightened(0.3), UI.font_head)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.clip_text = true
	l.custom_minimum_size.x = 100
	v.add_child(l)
	return v


func _reveals() -> void:
	for c in reveal_box.get_children():
		c.queue_free()
	for x in engine.revealed:
		var t := UI.icon_rect(UI.rat_tex(x["tid"]), Vector2(92, 92))
		t.modulate = Color.WHITE if x["done"] else Color(1, 1, 1, 0.55)
		reveal_box.add_child(t)


func _card_zoom(c: String) -> void:
	var dlg := _dialog(engine.cname(c), 760)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	dlg["box"].add_child(h)
	h.add_child(UI.icon_rect(UI.card_tex(c), Vector2(300, 420)))
	var v := VBoxContainer.new()
	h.add_child(v)
	v.add_child(UI.heading("Classe: %s" % D.CLASSES[D.CARDS[c]["cls"]]["name"], 24))
	v.add_child(UI.wrap(UI.label(D.CARDS[c]["text"], 23, UI.PARCH), 380))
	var o := engine.st.holder(c)
	v.add_child(UI.wrap(UI.label("La tiene %s." % engine.pname(o) if o >= 0 else "È ancora accanto al tabellone.", 21, UI.MUTED), 380))
	v.add_child(UI.wrap(UI.label("Chi tiene la carta perde un cubetto per ogni simbolo della sua classe sui ratti che scatenano un'epidemia dove ha cubetti.", 19, UI.MUTED), 380))
	var cl := UI.button("Chiudi", 200, 52, 20)
	cl.pressed.connect(func(): dlg["root"].queue_free())
	v.add_child(cl)


func _on_log(t: String) -> void:
	if t.begins_with("—"):
		log_box.append_text("\n[color=#f0d58a]%s[/color]\n" % t)
	elif t.begins_with("Epidemia"):
		log_box.append_text("[color=#ff8a6a]%s[/color]\n" % t)
	else:
		log_box.append_text(t + "\n")


func toast(t: String, col := UI.PARCH, sec := 3.0) -> void:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UI.dark_style(6, 0.95))
	var l := UI.wrap(UI.label(t, 23, col, UI.font_head_r), 680)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pc.add_child(l)
	toast_box.add_child(pc)
	var tw := create_tween()
	tw.tween_interval(sec)
	tw.tween_property(pc, "modulate:a", 0.0, 0.5)
	tw.tween_callback(pc.queue_free)


func _on_fx(kind: String, d: Dictionary) -> void:
	_dirty = true
	match kind:
		"reveal":
			var res: Dictionary = d["res"]
			if res["out"]:
				var parts := []
				for q in engine.n:
					if res["dead"][q] > 0:
						parts.append("%s perde %d" % [engine.pname(q), res["dead"][q]])
				toast("Epidemia in %s! %s" % [engine.st.rname(d["r"]), ", ".join(parts) if not parts.is_empty() else "nessuno colpito"], UI.BLOOD_L, 2.2)
			else:
				toast("In %s: nessuna epidemia (popolazione %d, soglia %d)." % [engine.st.rname(d["r"]), res["pop"], res["lim"]], UI.PARCH, 1.8)
		"peek":
			if d["p"] == focus_p and focus_p in humans:
				var tok: Array = d["tok"]
				var tid: int = engine.st.rats[tok[0]][tok[1]]
				var dlg := _dialog("La Strega vede…", 520)
				var h := HBoxContainer.new()
				h.add_theme_constant_override("separation", 14)
				h.add_child(UI.icon_rect(UI.rat_tex(tid), Vector2(160, 160)))
				h.add_child(UI.wrap(UI.label("%s\n%s" % [engine.st.rname(tok[0]), engine.token_text(tid)], 22, UI.PARCH), 300))
				dlg["box"].add_child(h)
				var cl := UI.button("Ho visto", 200, 52, 20)
				cl.pressed.connect(func(): dlg["root"].queue_free())
				dlg["box"].add_child(cl)


# ================================================================ online

func online_waiting(s: int, slow: bool) -> void:
	if s < 0:
		wait_lbl.text = ""
	else:
		wait_lbl.text = "Aspetto %s…%s" % [engine.pname(s), " (ci mette un po')" if slow else ""]


func online_mine() -> bool:
	return engine.online != null and engine.online._mine_pending


func online_status(t: String) -> void:
	toast(t, UI.BLOOD_L)


func online_caught_up() -> void:
	toast("Partita ripresa: sei di nuovo al tavolo.", UI.GREEN)


func online_cancel_decision(t: String) -> void:
	_clear_prompt()
	toast(t, UI.BLOOD_L)


# ================================================================ decisioni

func _clear_prompt() -> void:
	pending = {}
	prompt.visible = false
	for c in prompt_box.get_children():
		c.queue_free()
	board3d.set_hot([])


func _submit(i: int) -> void:
	var req := pending
	_clear_prompt()
	if req.is_empty():
		return
	engine.provide_decision(i)


func _on_spot(i: int) -> void:
	if not pending.is_empty():
		_submit(i)


func _on_decision(req: Dictionary) -> void:
	pending = req
	var p: int = req["seat"]
	focus_p = p
	_dirty = true
	_refresh()
	_show_decision(req)


func _show_decision(req: Dictionary) -> void:
	var e := engine
	var p: int = req["seat"]
	prompt.visible = true
	prompt_title.text = "%s — %s" % [e.pname(p), req.get("text", "")]
	for c in prompt_box.get_children():
		c.queue_free()
	var opts: Array = req["opts"]
	var spots := []
	var kind: String = req.get("kind", "")
	for i in opts.size():
		var o: Dictionary = opts[i]
		var b: Button
		if kind == "take" and o.has("c"):
			b = UI.button(o["label"], 0, 64, 20)
			b.icon = UI.card_tex(o["c"])
			b.expand_icon = false
			b.add_theme_constant_override("icon_max_width", 40)
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.tooltip_text = D.CARDS[o["c"]]["text"]
		else:
			b = UI.button(o["label"], 0, 50, 20)
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.x = RIGHT_W - 50
		if o.get("a", "") == "end" or i == 0 and opts.size() == 1:
			UI.primary(b)
		var k := i
		b.pressed.connect(func(): _submit(k))
		prompt_box.add_child(b)
		# punti toccabili sul tabellone
		if o.has("tok"):
			var t: Array = o["tok"]
			spots.append({"pos": board3d.rat_pos(t[0], t[1], e.st.rats[t[0]].size()), "idx": i, "rad": 0.06, "hit": 34.0})
		elif o.has("cube"):
			var c: Array = o["cube"]
			spots.append({"pos": board3d.cube_pos(c[0], c[1]), "idx": i, "rad": 0.07, "hit": 36.0})
		elif o.has("e"):
			spots.append({"pos": D.edge_pos(o["e"]), "idx": i, "rad": 0.05, "hit": 45.0})
		elif o.has("r") and kind != "bishop_which":
			spots.append({"pos": D.REGIONS[o["r"]]["pos"], "idx": i, "rad": 0.17, "hit": 150.0})
	board3d.set_hot(spots)
	var sc: ScrollContainer = prompt.find_child("scroll", true, false)
	var h := mini(opts.size(), 9) * 56 + 4
	sc.custom_minimum_size.y = clampi(h, 56, int(get_viewport_rect().size.y * 0.5))


## Finestra al centro: {root, box}.
func _dialog(title: String, w := 760.0) -> Dictionary:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	popup_layer.add_child(root)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(shade)
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(cc)
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UI.dark_style(10, 0.98))
	pc.custom_minimum_size.x = w
	cc.add_child(pc)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	pc.add_child(box)
	box.add_child(UI.title(title, 46))
	return {"root": root, "box": box}


func _row() -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 12)
	return r


func _show_rules() -> void:
	var t := preload("res://scripts/ui/rules_view.gd").new()
	t.main = main
	t.popup = true
	popup_layer.add_child(t)


func _ask_menu() -> void:
	var dlg := _dialog("Tornare al menu?", 640)
	var box: VBoxContainer = dlg["box"]
	box.add_child(UI.wrap(UI.label("La partita in corso si chiude." + (" Online puoi rientrare con lo stesso codice." if engine.online != null else " Se vuoi riprenderla più tardi, salvala prima con «Salva»."), 22, UI.PARCH), 580))
	var r := _row()
	var y := UI.primary(UI.button("Torna al menu", 0, 56, 20))
	y.pressed.connect(func(): main.show_menu())
	r.add_child(y)
	var n := UI.button("Continua a giocare", 0, 56, 20)
	n.pressed.connect(func(): dlg["root"].queue_free())
	r.add_child(n)
	box.add_child(r)


func _save_game() -> void:
	if engine.online != null:
		toast("La partita online è già salvata nella stanza: per rientrare usa il codice della stanza.", UI.GREEN)
		return
	var cfg := config.duplicate(true)
	cfg.erase("online")
	cfg.erase("replay")
	var data := {"cfg": var_to_str(cfg), "moves": var_to_str(engine.record), "label": "Turno %d" % (engine.turn + 1),
		"names": ", ".join(range(engine.n).map(func(x): return engine.pname(x)))}
	toast("Salvataggio in corso…")
	var net: Net = main.get_net()
	var code := await net.save_game(data, save_code)
	if code == "":
		toast("Salvataggio non riuscito: %s" % net.last_error, UI.BLOOD_L)
		return
	save_code = code
	var dlg := _dialog("Partita salvata", 640)
	dlg["box"].add_child(UI.wrap(UI.label("Per riprenderla scegli «Carica partita» nel menu e scrivi questo codice (vale da qualsiasi dispositivo):", 22, UI.PARCH), 580))
	var cl0 := UI.label(code, 64, UI.GOLD_L, UI.font_head)
	dlg["box"].add_child(cl0)
	var cl := UI.button("Chiudi", 200, 54, 20)
	cl.pressed.connect(func(): dlg["root"].queue_free())
	dlg["box"].add_child(cl)


func _on_end(res: Dictionary) -> void:
	_clear_prompt()
	if engine.online != null:
		engine.online.finish()
	_dirty = true
	var e := engine
	var dlg := _dialog("La peste si ritira", 900)
	var box: VBoxContainer = dlg["box"]
	box.add_child(UI.heading("Vince %s con %d abitanti sopravvissuti" % [e.pname(res["winner"]), e.st.score(res["winner"])], 30))
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 26)
	grid.add_theme_constant_override("v_separation", 6)
	box.add_child(grid)
	for hd in ["", "Sul tabellone", "Nel palazzo", "Totale", "Carte in mano"]:
		grid.add_child(UI.label(hd, 20, UI.MUTED, UI.font_head_r))
	for x in res["ranking"]:
		var p: int = x["p"]
		var nm := UI.label(e.pname(p), 23, UI.pcolor(e, p).lightened(0.3), UI.font_head)
		nm.custom_minimum_size.x = 200
		grid.add_child(nm)
		for v in [e.st.onboard(p), e.st.palace[p], e.st.score(p)]:
			var l := UI.label(str(v), 24, UI.PARCH, UI.font_head)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			grid.add_child(l)
		grid.add_child(UI.label(", ".join(e.st.held(p).map(e.cname)), 19, UI.MUTED))
	box.add_child(UI.wrap(UI.label("A parità vince chi avrebbe giocato per primo il turno successivo.", 19, UI.MUTED), 840))
	var r := _row()
	var again := UI.primary(UI.button("Nuova partita", 0, 56, 22))
	again.pressed.connect(func(): main.show_menu())
	r.add_child(again)
	var look := UI.button("Guarda il tabellone", 0, 56, 20)
	look.pressed.connect(func(): dlg["root"].queue_free())
	r.add_child(look)
	box.add_child(r)
