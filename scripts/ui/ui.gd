class_name UI
extends RefCounted
## Helper grafici condivisi. Tema «cronaca della peste»: pergamena e inchiostro bruno come la mappa del
## tabellone, cuoio scuro per i pannelli, rosso sangue per gli avvisi e verde malato per la Peste.
## Caratteri liberi (OFL): UnifrakturMaguntia per i titoli (il gotico dei cartigli delle regioni),
## Almendra per intestazioni e pulsanti, IM Fell DW Pica per i testi.

const D = preload("res://scripts/data/rt_data.gd")

const BG := Color("#140d08")
const BG_L := Color("#2a1b10")
const PANEL := Color("#231710")
const PANEL_L := Color("#3a2716")
const PARCH := Color("#ecdcb4")
const PARCH_D := Color("#cdb685")
const INK := Color("#2b1a0e")
const GOLD := Color("#c9a24a")
const GOLD_L := Color("#f0d58a")
const BLOOD := Color("#9c2418")
const BLOOD_L := Color("#d4483a")
const PLAGUE := Color("#8fb04a")
const TEXT := Color("#f3e7cc")
const MUTED := Color("#b9a585")
const GREEN := Color("#a9d26a")

static var _tex := {}
static var font_title: Font
static var font_head: Font
static var font_head_r: Font
static var font_body: Font


static func init_fonts() -> void:
	if font_title != null:
		return
	font_title = load("res://assets/fonts/UnifrakturMaguntia-Book.ttf")
	font_head = load("res://assets/fonts/Almendra-Bold.ttf")
	font_head_r = load("res://assets/fonts/Almendra-Regular.ttf")
	font_body = load("res://assets/fonts/IMFePIrm28P.ttf")


static func tex(path: String) -> Texture2D:
	if not _tex.has(path):
		_tex[path] = load(path) if ResourceLoader.exists(path) else null
	return _tex[path]


static func card_tex(c: String) -> Texture2D:
	return tex("res://assets/carte/%s.jpg" % c)


static func rat_tex(t: int) -> Texture2D:
	return tex("res://assets/ratti/r%d.png" % t)


static func pcolor(e, p: int) -> Color:
	return D.COLORS[e.pcol(p)]["col"]


static func pdark(e, p: int) -> Color:
	return D.COLORS[e.pcol(p)]["dark"]


static func panel_style(bg: Color, border: Color = GOLD, bw := 2, radius := 6) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(12)
	return sb


static func dark_style(radius := 8, alpha := 0.94) -> StyleBoxFlat:
	var sb := panel_style(Color(PANEL, alpha), Color(GOLD, 0.65), 2, radius)
	sb.shadow_color = Color(0, 0, 0, 0.6)
	sb.shadow_size = 12
	return sb


static func parch_style(radius := 6) -> StyleBoxFlat:
	var sb := panel_style(PARCH, Color(INK, 0.8), 2, radius)
	sb.set_content_margin_all(10)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 8
	return sb


static func label(text: String, size := 20, col := TEXT, font: Font = null) -> Label:
	init_fonts()
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if font != null:
		l.add_theme_font_override("font", font)
	return l


static func title(text: String, size := 48, col := GOLD_L) -> Label:
	init_fonts()
	var l := label(text, size, col, font_title)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("shadow_offset_x", maxi(2, size / 22))
	l.add_theme_constant_override("shadow_offset_y", maxi(2, size / 16))
	return l


static func heading(text: String, size := 22, col := GOLD_L) -> Label:
	init_fonts()
	return label(text, size, col, font_head)


## Etichetta che va a capo: larghezza minima fissata, così non si schiaccia mai in colonna.
static func wrap(l: Label, w: float) -> Label:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = w
	return l


static func icon_rect(t: Texture2D, sz: Vector2) -> TextureRect:
	var r := TextureRect.new()
	r.texture = t
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = sz
	r.size = sz
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func button(text: String, w := 200.0, h := 46.0, size := 20) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, h)
	b.add_theme_font_size_override("font_size", size)
	b.clip_text = false
	return b


static func primary(b: Button) -> Button:
	init_fonts()
	b.add_theme_stylebox_override("normal", _btn(BLOOD, GOLD))
	b.add_theme_stylebox_override("hover", _btn(BLOOD_L, GOLD_L))
	b.add_theme_stylebox_override("pressed", _btn(GOLD, INK))
	b.add_theme_stylebox_override("disabled", _btn(Color("#3a2420"), Color("#2a1a16")))
	b.add_theme_color_override("font_color", PARCH)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", INK)
	return b


static func _btn(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(5)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 3
	sb.content_margin_bottom = 5
	return sb


static func make_theme() -> Theme:
	init_fonts()
	var th := Theme.new()
	th.default_font = font_body
	th.default_font_size = 22
	th.set_stylebox("normal", "Button", _btn(Color("#3b2614"), Color("#7a5a30")))
	th.set_stylebox("hover", "Button", _btn(Color("#553719"), GOLD))
	th.set_stylebox("pressed", "Button", _btn(GOLD, GOLD_L))
	th.set_stylebox("hover_pressed", "Button", _btn(GOLD_L, GOLD_L))
	th.set_stylebox("disabled", "Button", _btn(Color("#24170d"), Color("#3a2a1a")))
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	th.set_color("font_color", "Button", TEXT)
	th.set_color("font_hover_color", "Button", GOLD_L)
	th.set_color("font_pressed_color", "Button", INK)
	th.set_color("font_hover_pressed_color", "Button", INK)
	th.set_color("font_disabled_color", "Button", Color("#6b5a44"))
	th.set_font("font", "Button", font_head)
	th.set_font_size("font_size", "Button", 21)
	th.set_color("font_color", "Label", TEXT)
	var pn := StyleBoxFlat.new()
	pn.bg_color = PANEL
	th.set_stylebox("panel", "Panel", pn)
	th.set_stylebox("panel", "PanelContainer", pn)
	th.set_font("normal_font", "RichTextLabel", font_body)
	th.set_font("bold_font", "RichTextLabel", font_head)
	th.set_font("italics_font", "RichTextLabel", font_head_r)
	th.set_font("mono_font", "RichTextLabel", font_head_r)
	for k in ["normal_font_size", "bold_font_size", "italics_font_size", "mono_font_size"]:
		th.set_font_size(k, "RichTextLabel", 22)
	th.set_color("default_color", "RichTextLabel", TEXT)
	th.set_font("font", "LineEdit", font_head_r)
	th.set_font_size("font_size", "LineEdit", 24)
	th.set_color("font_color", "LineEdit", INK)
	th.set_color("font_placeholder_color", "LineEdit", Color("#8a7a5c"))
	th.set_color("caret_color", "LineEdit", INK)
	th.set_stylebox("normal", "LineEdit", panel_style(PARCH, GOLD, 2, 4))
	th.set_stylebox("focus", "LineEdit", panel_style(Color("#fbf1d6"), GOLD_L, 2, 4))
	th.set_font("font", "TooltipLabel", font_body)
	th.set_font_size("font_size", "TooltipLabel", 20)
	th.set_color("font_color", "TooltipLabel", INK)
	var tp := panel_style(PARCH, INK, 2, 4)
	tp.set_content_margin_all(8)
	th.set_stylebox("panel", "TooltipPanel", tp)
	var sc := StyleBoxFlat.new()
	sc.bg_color = Color(GOLD, 0.85)
	sc.set_corner_radius_all(3)
	for k in ["grabber", "grabber_highlight", "grabber_pressed"]:
		th.set_stylebox(k, "VScrollBar", sc)
		th.set_stylebox(k, "HScrollBar", sc)
	var sct := StyleBoxFlat.new()
	sct.bg_color = Color(1, 1, 1, 0.06)
	th.set_stylebox("scroll", "VScrollBar", sct)
	th.set_stylebox("scroll", "HScrollBar", sct)
	return th


## Sfondo: cuoio scuro con una vignettatura e un'ombra di mappa (disegnato).
class Backdrop extends Control:
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		resized.connect(queue_redraw)

	func _draw() -> void:
		var n := 30
		for i in n:
			var c := UI.BG_L.lerp(UI.BG, absf(float(i) / n - 0.4) * 1.6)
			draw_rect(Rect2(0, size.y * i / n, size.x, size.y / n + 1), c)
		var col := Color(UI.GOLD, 0.05)
		for k in 7:
			var pts := PackedVector2Array()
			var y0 := size.y * (0.12 + k * 0.13)
			for i in 41:
				var x := size.x * i / 40.0
				pts.append(Vector2(x, y0 + sin(i * 0.31 + k) * 16.0 + cos(i * 0.17 + k * 2.0) * 22.0))
			draw_polyline(pts, col, 2.0)
