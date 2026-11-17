extends Control
## Il tabellone in 3D: la mappa d'Europa su un tavolo di legno, con cubetti di legno, gettoni ratto,
## la Peste (una figura incappucciata con un alone verde), suore, vescovi, muri e pozioni modellati qui.
## Comandi: un dito o il tasto sinistro trascinano; due dita pizzicano per lo zoom e ruotano;
## il tasto destro (o due dita in verticale) inclina la vista; rotella per lo zoom. Toccando una regione,
## un gettone o un confine evidenziato si sceglie l'opzione corrispondente.

const D = preload("res://scripts/data/rt_data.gd")
const PX := 500.0                # pixel del tabellone (scala 2000) per unità 3D
const CUBE := 0.064
const RAT_R := 0.05
const Y0 := 0.02                 # superficie del tabellone

signal spot_pressed(idx: int)

var e
var viewer := -1                 # chi guarda: vede le facce dei gettoni visti con la Strega
var hot: Array = []              # opzioni toccabili: [{pos: Vector2 (pixel), idx, r}]
var svc: SubViewportContainer
var vp: SubViewport
var cam: Camera3D
var pieces: Node3D
var marks: Node3D
var plague_node: Node3D
var plague_light: OmniLight3D
var yaw := 0.0
var pitch := 1.05
var dist := 5.0
var target := Vector3(0.14, 0, 0.24)
var _touches := {}
var _pinch := {}
var _press := Vector2.ZERO
var _moved := false
var _t := 0.0
var _plague_from := Vector3.ZERO
var _plague_to := Vector3.ZERO
var _plague_k := 1.0
var _mats := {}
var _font: Font


func setup(eng) -> void:
	e = eng
	_font = load("res://assets/fonts/Almendra-Bold.ttf")
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	svc = SubViewportContainer.new()
	svc.stretch = true
	svc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(svc)
	vp = SubViewport.new()
	vp.msaa_3d = Viewport.MSAA_2X
	vp.own_world_3d = true
	svc.add_child(vp)
	var env := WorldEnvironment.new()
	var en := Environment.new()
	en.background_mode = Environment.BG_COLOR
	en.background_color = Color("#0e0906")
	en.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	en.ambient_light_color = Color("#e8dcc8")
	en.ambient_light_energy = 0.26
	en.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	en.fog_enabled = false
	env.environment = en
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.light_energy = 0.78
	sun.light_color = Color("#ffe9c8")
	sun.shadow_enabled = true
	sun.shadow_bias = 0.03
	sun.directional_shadow_max_distance = 12.0
	vp.add_child(sun)
	cam = Camera3D.new()
	cam.fov = 38
	vp.add_child(cam)
	# tavolo
	var table := MeshInstance3D.new()
	var tm := PlaneMesh.new()
	tm.size = Vector2(12, 12)
	table.mesh = tm
	var tmat := StandardMaterial3D.new()
	tmat.albedo_texture = UI.tex("res://assets/misc/tavolo.jpg")
	tmat.uv1_scale = Vector3(3, 3, 1)
	tmat.albedo_color = Color(0.55, 0.5, 0.48)
	tmat.roughness = 0.8
	table.material_override = tmat
	vp.add_child(table)
	# tabellone
	var bw := D.BOARD_W / PX
	var bh := D.BOARD_H / PX
	var edge := MeshInstance3D.new()
	var em := BoxMesh.new()
	em.size = Vector3(bw + 0.03, Y0, bh + 0.03)
	edge.mesh = em
	edge.position.y = Y0 * 0.5
	edge.material_override = _mat(Color("#3b2312"), 0.7)
	vp.add_child(edge)
	var board := MeshInstance3D.new()
	var bm := PlaneMesh.new()
	bm.size = Vector2(bw, bh)
	board.mesh = bm
	var bmat := StandardMaterial3D.new()
	bmat.albedo_texture = UI.tex("res://assets/tabellone/tabellone.jpg")
	bmat.roughness = 0.85
	bmat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	board.material_override = bmat
	board.position.y = Y0 + 0.001
	vp.add_child(board)
	pieces = Node3D.new()
	vp.add_child(pieces)
	marks = Node3D.new()
	vp.add_child(marks)
	plague_node = _plague_figure()
	plague_node.scale = Vector3.ONE * 1.6
	vp.add_child(plague_node)
	plague_light = OmniLight3D.new()
	plague_light.light_color = Color("#9fdc4a")
	plague_light.light_energy = 1.6
	plague_light.omni_range = 0.55
	plague_light.shadow_enabled = false
	vp.add_child(plague_light)
	var p0 := _plague_spot(e.st.plague)
	plague_node.position = p0
	_plague_to = p0
	_cam()
	refresh()
	(func(): reset_view()).call_deferred()


func to3(p: Vector2, y := Y0) -> Vector3:
	return Vector3((p.x - D.BOARD_W * 0.5) / PX, y, (p.y - D.BOARD_H * 0.5) / PX)


func _cam() -> void:
	var off := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * dist
	cam.position = target + off
	cam.look_at(target, Vector3.UP)


func top_view(on: bool) -> void:
	pitch = 1.5 if on else 1.05
	yaw = 0.0
	_cam()


func reset_view() -> void:
	yaw = 0.0
	pitch = 1.05
	dist = _fit_dist()
	target = Vector3(0.14, 0, 0.24)
	_cam()


## Distanza che fa stare tutta la mappa fra i pannelli anche sugli schermi più stretti (iPad 4:3).
func _fit_dist() -> float:
	var a := size.x / maxf(1.0, size.y)
	return 5.0 * clampf(pow(1.7778 / maxf(0.5, a), 1.6), 1.0, 1.9)


func _mat(col: Color, rough := 0.6, tex_path := "") -> StandardMaterial3D:
	var key := "%s|%.2f|%s" % [col.to_html(), rough, tex_path]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	if tex_path != "":
		m.albedo_texture = UI.tex(tex_path)
	_mats[key] = m
	return m


func _mesh(mesh: Mesh, at: Vector3, mat: Material, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = at
	mi.material_override = mat
	(parent if parent != null else pieces).add_child(mi)
	return mi


# ================================================================ modelli

## La Peste: figura incappucciata scura con gli occhi verdi.
func _plague_figure() -> Node3D:
	var n := Node3D.new()
	var dark := _mat(Color("#1b1714"), 0.9)
	var robe := CylinderMesh.new()
	robe.top_radius = 0.022
	robe.bottom_radius = 0.06
	robe.height = 0.15
	_mesh(robe, Vector3(0, 0.075, 0), dark, n)
	var hood := SphereMesh.new()
	hood.radius = 0.034
	hood.height = 0.075
	_mesh(hood, Vector3(0, 0.168, 0), dark, n)
	var tip := CylinderMesh.new()
	tip.top_radius = 0.0
	tip.bottom_radius = 0.026
	tip.height = 0.05
	var t := _mesh(tip, Vector3(0, 0.205, -0.012), dark, n)
	t.rotation.x = -0.45
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color("#b6ff5a")
	glow.emission_enabled = true
	glow.emission = Color("#9be33f")
	glow.emission_energy_multiplier = 3.0
	var eye := SphereMesh.new()
	eye.radius = 0.006
	eye.height = 0.012
	_mesh(eye, Vector3(-0.011, 0.17, 0.03), glow, n)
	_mesh(eye, Vector3(0.011, 0.17, 0.03), glow, n)
	# alone di miasma sul tabellone
	var halo := MeshInstance3D.new()
	var hm := PlaneMesh.new()
	hm.size = Vector2(0.5, 0.5)
	halo.mesh = hm
	var hmat := StandardMaterial3D.new()
	hmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hmat.albedo_texture = _radial_tex(Color("#8fd13a"))
	halo.material_override = hmat
	halo.position.y = 0.004
	halo.name = "alone"
	n.add_child(halo)
	return n


func _radial_tex(col: Color) -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(col, 0.55))
	g.set_color(1, Color(col, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 128
	gt.height = 128
	return gt


func _cube(at: Vector3, col: Color) -> void:
	var b := BoxMesh.new()
	b.size = Vector3(CUBE, CUBE, CUBE) * 0.92
	var mi := _mesh(b, at + Vector3(0, CUBE * 0.46, 0), _mat(col, 0.75, "res://assets/misc/venatura.png"))
	mi.rotation.y = sin(at.x * 37.0 + at.z * 11.0) * 0.12


func _pawn(at: Vector3, col: Color) -> void:
	var m := _mat(col, 0.55)
	var body := CylinderMesh.new()
	body.top_radius = 0.012
	body.bottom_radius = 0.036
	body.height = 0.09
	_mesh(body, at + Vector3(0, 0.045, 0), m)
	var head := SphereMesh.new()
	head.radius = 0.024
	head.height = 0.048
	_mesh(head, at + Vector3(0, 0.105, 0), m)


func _bishop(at: Vector3) -> void:
	var m := _mat(Color("#7b3fa0"), 0.5)
	var w := _mat(Color("#efe6d2"), 0.6)
	var base := CylinderMesh.new()
	base.top_radius = 0.033
	base.bottom_radius = 0.042
	base.height = 0.02
	_mesh(base, at + Vector3(0, 0.01, 0), m)
	var body := CylinderMesh.new()
	body.top_radius = 0.018
	body.bottom_radius = 0.03
	body.height = 0.1
	_mesh(body, at + Vector3(0, 0.07, 0), m)
	var mitre := CylinderMesh.new()
	mitre.top_radius = 0.0
	mitre.bottom_radius = 0.024
	mitre.height = 0.06
	_mesh(mitre, at + Vector3(0, 0.15, 0), w)


func _wall(key: String) -> void:
	var ab := key.split("-")
	var a: Vector2 = D.REGIONS[int(ab[0])]["pos"]
	var b: Vector2 = D.REGIONS[int(ab[1])]["pos"]
	var at := to3(D.edge_pos(key))
	var dir := (b - a).normalized()
	var root := Node3D.new()
	root.position = at
	root.rotation.y = -atan2(dir.y, dir.x) + PI * 0.5
	pieces.add_child(root)
	var m := _mat(Color("#d8c8a8"), 0.85, "res://assets/pezzi/muro.jpg")
	var bx := BoxMesh.new()
	bx.size = Vector3(0.17, 0.045, 0.028)
	_mesh(bx, Vector3(0, 0.0225, 0), m, root)
	var mer := BoxMesh.new()
	mer.size = Vector3(0.026, 0.02, 0.028)
	for i in 4:
		_mesh(mer, Vector3(-0.0725 + i * 0.0483, 0.055, 0), m, root)


func _potion(at: Vector3) -> void:
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.3, 0.6, 0.95, 0.85)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.1
	glass.emission_enabled = true
	glass.emission = Color("#2a6fd0")
	glass.emission_energy_multiplier = 0.6
	var s := SphereMesh.new()
	s.radius = 0.022
	s.height = 0.044
	_mesh(s, at + Vector3(0, 0.022, 0), glass)
	var neck := CylinderMesh.new()
	neck.top_radius = 0.007
	neck.bottom_radius = 0.009
	neck.height = 0.024
	_mesh(neck, at + Vector3(0, 0.05, 0), glass)


func _rat(at: Vector3, face: Texture2D) -> void:
	var c := CylinderMesh.new()
	c.top_radius = RAT_R
	c.bottom_radius = RAT_R
	c.height = 0.012
	_mesh(c, at + Vector3(0, 0.006, 0), _mat(Color("#3a2414"), 0.8))
	var top := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(RAT_R * 2.0, RAT_R * 2.0)
	top.mesh = pm
	var tm := StandardMaterial3D.new()
	tm.albedo_texture = face
	tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	tm.alpha_scissor_threshold = 0.3
	tm.roughness = 0.7
	top.material_override = tm
	top.position = at + Vector3(0, 0.0125, 0)
	pieces.add_child(top)


func _label(at: Vector3, text: String, col: Color, size := 46) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.0016
	l.modulate = col
	l.outline_modulate = Color(0.08, 0.05, 0.02, 1)
	l.outline_size = 12
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.position = at
	pieces.add_child(l)


# ================================================================ disposizione

func rat_pos(r: int, i: int, k: int) -> Vector2:
	var c: Vector2 = D.REGIONS[r]["pos"]
	return c + Vector2(-0.5 * (k - 1) * 54.0 + i * 54.0, -48)


## Colonna di cubetti di ogni giocatore nella regione (in pixel della mappa).
func cube_pos(r: int, p: int) -> Vector2:
	var c: Vector2 = D.REGIONS[r]["pos"]
	var present := []
	for q in e.n:
		if e.st.cubes[r][q] > 0 or q == p:
			present.append(q)
	var i := present.find(p)
	var w := 80.0
	return c + Vector2(-0.5 * (present.size() - 1) * w + i * w, 22)


func _plague_spot(r: int) -> Vector3:
	return to3(D.REGIONS[r]["pos"] + Vector2(-95, -10))


func refresh() -> void:
	if e == null:
		return
	for ch in pieces.get_children():
		ch.queue_free()
	var st: RTState = e.st
	for r in st.regions():
		var k: int = st.rats[r].size()
		for i in k:
			var t: int = st.rats[r][i]
			var face: Texture2D = UI.rat_tex(t) if (viewer >= 0 and st.known[viewer].has(t)) else UI.tex("res://assets/ratti/dorso.png")
			_rat(to3(rat_pos(r, i, k)), face)
		for p in e.n:
			var nc: int = st.cubes[r][p]
			if nc <= 0:
				continue
			var base := cube_pos(r, p)
			var col: Color = UI.pcolor(e, p)
			for j in nc:
				var layer := j / 4
				var cell := j % 4
				var off := Vector2((cell % 2) * CUBE * PX * 1.02 - CUBE * PX * 0.51, (cell / 2) * CUBE * PX * 1.02 - CUBE * PX * 0.51)
				_cube(to3(base + off, Y0 + layer * CUBE * 0.94), col)
			var top := Y0 + ((nc - 1) / 4 + 1) * CUBE * 0.94 + 0.04
			_label(to3(base, top), str(nc), col.lightened(0.25))
			for j in st.potions[r][p]:
				_potion(to3(base + Vector2(42, 30 + j * 20)))
		var c: Vector2 = D.REGIONS[r]["pos"]
		for i in 3:
			if st.nuns[i] == r:
				_pawn(to3(c + Vector2(88 + i * 18, -40)), Color("#d86fb4"))
		for i in 2:
			if st.bishops[i] == r:
				_bishop(to3(c + Vector2(92 + i * 26, 30)))
	for w in st.walls:
		if w != "":
			_wall(w)
	# palazzo
	var col0 := 0
	for p in e.n:
		var k: int = st.palace[p]
		for j in k:
			var at := D.PALACE + Vector2(-80 + p * 54, 60 - (j % 5) * 0) + Vector2(0, 0)
			_cube(to3(at + Vector2((j % 2) * 26 - 13, 0), Y0 + (j / 2) * CUBE * 0.94), UI.pcolor(e, p))
		if k > 0:
			_label(to3(D.PALACE + Vector2(-80 + p * 54, 60), Y0 + ((k - 1) / 2 + 1) * CUBE + 0.04), str(k), UI.pcolor(e, p).lightened(0.25))
		col0 += 1
	# la Peste
	var dest := _plague_spot(st.plague)
	if dest.distance_to(_plague_to) > 0.001:
		_plague_from = plague_node.position
		_plague_to = dest
		_plague_k = 0.0
	_marks()


func _marks() -> void:
	for ch in marks.get_children():
		ch.queue_free()
	for h in hot:
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		var rad: float = h.get("rad", 0.17)
		tm.inner_radius = rad
		tm.outer_radius = rad + 0.018
		ring.mesh = tm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color("#ffd86a")
		m.emission_enabled = true
		m.emission = Color("#ffc53a")
		m.emission_energy_multiplier = 1.6
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ring.material_override = m
		ring.position = to3(h["pos"], Y0 + (0.03 if rad < 0.1 else 0.012))
		marks.add_child(ring)


func set_hot(spots: Array) -> void:
	hot = spots
	_marks()


func _process(dt: float) -> void:
	_t += dt
	if plague_node == null:
		return
	if _plague_k < 1.0:
		_plague_k = minf(1.0, _plague_k + dt * 1.4)
		var k := _plague_k * _plague_k * (3.0 - 2.0 * _plague_k)
		var p := _plague_from.lerp(_plague_to, k)
		p.y += sin(k * PI) * 0.35
		plague_node.position = p
	else:
		plague_node.position = _plague_to
	plague_node.rotation.y = sin(_t * 0.7) * 0.25
	plague_light.position = plague_node.position + Vector3(0, 0.12, 0)
	plague_light.light_energy = 1.4 + sin(_t * 2.3) * 0.35
	var s := 1.0 + sin(_t * 3.0) * 0.06
	for ch in marks.get_children():
		ch.scale = Vector3(s, 1, s)


# ================================================================ input

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventScreenTouch:
		if ev.pressed:
			_touches[ev.index] = ev.position
			_press = ev.position
			_moved = false
		else:
			var tap: bool = _touches.size() == 1 and not _moved
			_touches.erase(ev.index)
			_pinch = {}
			if tap:
				_click(ev.position)
		accept_event()
		return
	if ev is InputEventScreenDrag:
		_touches[ev.index] = ev.position
		if ev.position.distance_to(_press) > 10:
			_moved = true
		if _touches.size() == 1:
			_pan(ev.relative)
		elif _touches.size() >= 2:
			var ks := _touches.keys()
			var a: Vector2 = _touches[ks[0]]
			var b: Vector2 = _touches[ks[1]]
			var d := a.distance_to(b)
			var ang := (b - a).angle()
			var mid := (a + b) * 0.5
			if not _pinch.is_empty():
				dist = clampf(dist * _pinch["d"] / maxf(1.0, d), 0.8, 8.0)
				yaw -= ang - _pinch["ang"]
				pitch = clampf(pitch + (mid.y - _pinch["mid"].y) * 0.004, 0.3, 1.52)
				_cam()
			_pinch = {"d": d, "ang": ang, "mid": mid}
		accept_event()
		return
	if ev is InputEventMagnifyGesture:
		dist = clampf(dist / ev.factor, 0.8, 8.0)
		_cam()
		accept_event()
		return
	if ev is InputEventPanGesture:
		_pan(-ev.delta * 10.0)
		accept_event()
		return
	if ev is InputEventMouseButton:
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP and ev.pressed:
			dist = clampf(dist * 0.9, 0.8, 8.0)
			_cam()
		elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN and ev.pressed:
			dist = clampf(dist / 0.9, 0.8, 8.0)
			_cam()
		elif ev.pressed:
			_press = ev.position
			_moved = false
		elif ev.button_index == MOUSE_BUTTON_LEFT and not _moved and _touches.is_empty():
			_click(ev.position)
		accept_event()
	elif ev is InputEventMouseMotion and ev.button_mask != 0 and _touches.is_empty():
		if ev.position.distance_to(_press) > 6:
			_moved = true
		if ev.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			yaw -= ev.relative.x * 0.006
			pitch = clampf(pitch + ev.relative.y * 0.004, 0.3, 1.52)
			_cam()
		else:
			_pan(ev.relative)
		accept_event()


func _pan(rel: Vector2) -> void:
	var k := dist * 0.0009
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	target += (-right * rel.x + fwd * rel.y) * k
	target.x = clampf(target.x, -2.2, 2.2)
	target.z = clampf(target.z, -1.5, 1.5)
	_cam()


## Punto della mappa (pixel in scala 2000) sotto un punto dello schermo.
func board_point(s: Vector2) -> Vector2:
	var sc := s * Vector2(vp.size) / size
	var o := cam.project_ray_origin(sc)
	var dir := cam.project_ray_normal(sc)
	if absf(dir.y) < 0.0001:
		return Vector2(-9999, -9999)
	var t := (Y0 - o.y) / dir.y
	var hit := o + dir * t
	return Vector2(hit.x * PX + D.BOARD_W * 0.5, hit.z * PX + D.BOARD_H * 0.5)


## Punto dello schermo di un punto della mappa (per le etichette 2D sopra il 3D).
func screen_point(b: Vector2, y := Y0) -> Vector2:
	var p := cam.unproject_position(to3(b, y))
	return p * size / Vector2(vp.size)


func _click(s: Vector2) -> void:
	if hot.is_empty():
		return
	var b := board_point(s)
	var best := -1
	var bd := 1e9
	for h in hot:
		var r: float = h.get("hit", 150.0)
		var dd: float = b.distance_to(h["pos"])
		if dd < r and dd < bd:
			bd = dd
			best = h["idx"]
	if best >= 0:
		spot_pressed.emit(best)
