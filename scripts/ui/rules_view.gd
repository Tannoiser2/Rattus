extends Control
## Le regole di Rattus (con il Pifferaio magico) in italiano, con le carte di classe e i gettoni ratto.

const D = preload("res://scripts/data/rt_data.gd")

var main
var popup := false

const TEXT := """[font_size=34][color=#f0d58a]Rattus in breve[/color][/font_size]
Europa, 1347: la peste nera arriva dall'Oriente e in pochi anni dimezzerà la popolazione del continente. Ogni giocatore guida un popolo (i cubetti del suo colore, 20 in tutto) che si stabilisce nelle regioni d'Europa mentre la peste si diffonde. Le classi della società medievale aiutano chi le sceglie, ma lo espongono anche al contagio. Quando la peste si ritira vince chi ha [b]più abitanti sopravvissuti[/b].

[font_size=26][color=#d4483a]Regioni in gioco[/color][/font_size]
In 2 si usano solo le 8 regioni chiare; in 3 anche le due di colore medio (Bulgaria e Turcia); in 4 tutte e 12 (anche Russia e Tartaria, le più scure). Le frecce rosse sul mare collegano regioni che si considerano confinanti.

[font_size=26][color=#d4483a]Preparazione[/color][/font_size]
In ogni regione in gioco si mette coperto uno dei ratti iniziali (quelli con il cerchio viola). Gli altri ratti formano la riserva coperta: in 2 se ne tolgono a caso 12, in 3 se ne tolgono 6 (mai di quelli iniziali). La Peste parte da una regione a caso. A turno ognuno mette due cubetti in una regione; poi, in ordine inverso, altri due.

[font_size=26][color=#d4483a]Il turno[/color][/font_size]
Nell'ordine che preferisci:
[b]A · Prendi una carta di classe[/b] (facoltativo): una di quelle accanto al tabellone oppure una davanti a un altro giocatore. Puoi farlo ogni turno anche se hai già altre carte; le carte non si restituiscono, passano di mano solo quando qualcuno le prende.
[b]B · Aggiungi cubetti[/b] in una sola regione: tanti quanti i ratti che ci sono adesso. Dove non ci sono ratti non si aggiunge niente (salvo con il Contadino).
I poteri delle carte che hai si usano una volta per turno, quando vuoi, prima di muovere la Peste.
[b]C · Muovi la Peste[/b] (sempre, alla fine): va in una regione confinante, non può restare dov'è. Poi la peste colpisce la nuova regione.

[font_size=26][color=#d4483a]La peste si diffonde[/color][/font_size]
Se nella regione della Peste c'è un ratto, chi gioca mette un ratto nuovo della riserva in una regione confinante; se ce ne sono due o tre, ne mette due (nella stessa regione o in due diverse). In nessuna regione possono esserci più di tre ratti.

[font_size=26][color=#d4483a]La peste devasta[/color][/font_size]
Se nella regione della Peste ci sono cubetti e ratti, i ratti si scoprono uno alla volta. Ogni gettone ha una [b]soglia[/b]: se gli abitanti della regione (di tutti i colori) sono almeno la soglia scoppia un'epidemia, altrimenti il ratto si toglie senza effetti. Nell'epidemia:
• ogni [b]M[/b] (maggioranza) uccide un cubetto di chi ha più cubetti nella regione (in caso di parità, uno a testa a tutti i pari) – le M si valutano per prime;
• ogni [b]simbolo di classe[/b] uccide un cubetto di chi tiene la carta di quella classe (se ha cubetti lì);
• ogni [b]A[/b] (tutti) uccide un cubetto di ogni giocatore presente.
Classi e simboli: covone = Popolani, moneta = Borghesia, croce = Clero, scudo = Cavalleria, cappello a punta = Magia, corona = Nobiltà.
I ratti scoperti escono dal gioco. Si continua finché restano ratti coperti e cubetti nella regione.

[font_size=26][color=#d4483a]Fine della partita[/color][/font_size]
La partita finisce dopo il turno in cui si esaurisce la riserva dei ratti, oppure dopo il turno in cui un giocatore ha tutti i suoi cubetti sul tabellone (succede di rado). Segue un ultimo giro in senso antiorario, che parte da chi siede a destra di chi ha giocato l'ultimo turno ed esclude quest'ultimo: si possono usare un'ultima volta i poteri delle carte che si hanno, ma non si prendono carte, non si aggiungono cubetti e non si muove la Peste, con queste eccezioni:
• Contadino: un cubetto in una regione qualsiasi. Regina: se la condizione è soddisfatta, due cubetti in una regione. Borgomastro: un cubetto dove si ha la maggioranza.
• Cavaliere: muove la Peste fino a due passi; nella devastazione finale la Peste conta come due abitanti nella sua regione. Crociato: muove la Peste fino a due passi, scopre subito i ratti di quella regione e li risolve nell'ordine che sceglie. Servo della gleba: muove la Peste di un passo e la sua carta agisce nella regione raggiunta. Chi ha più di queste carte le applica tutte nella stessa regione.
• Soldato: aggiunge un ratto in una regione confinante con la Peste (se la riserva è vuota lo prende a caso fra quelli tolti).
Poi, se c'è il Fornaio, chi siede a sinistra di chi tiene la carta mette tutti i cubetti della carta in una regione a scelta. Infine la peste devasta [b]tutte[/b] le regioni: si scoprono e si risolvono tutti i ratti rimasti.
Vince chi ha più cubetti sul tabellone, palazzo compreso. In caso di parità vince, fra i pari, chi avrebbe giocato per primo il turno successivo.
"""

const CARDS_NOTE := """Ogni carta appartiene a una delle sei classi: chi la tiene ne ha i vantaggi, ma ogni simbolo di quella classe sui ratti che scatenano un'epidemia gli uccide un cubetto. Se nella partita ci sono più carte della stessa classe, ogni simbolo uccide un cubetto per ciascuna carta di quella classe che si possiede.
I poteri si usano solo nel proprio turno, una volta per carta, prima di muovere la Peste (Cavaliere, Crociato, Soldato e Servo agiscono proprio quando si muove la Peste).
Il gioco base usa le sei carte classiche (Contadino, Mercante, Monaco, Cavaliere, Strega, Re). Con il Pifferaio magico ogni classe ha tre carte: se ne usano sei per partita, a scelta o a caso."""

const STRATEGY := """[font_size=34][color=#f0d58a]Consigli di strategia[/color][/font_size]
[b]Crescere costa.[/b] Più ratti ci sono in una regione, più cubetti puoi aggiungere lì; ma più abitanti ci sono, più facile è superare le soglie dei ratti. Le regioni affollate sono una bomba a orologeria: tieni i cubetti divisi in più regioni.
[b]Guarda dove può andare la Peste.[/b] Si muove di un passo per turno (due con Cavaliere, Crociato o Soldato): le regioni vicine alla Peste sono le più a rischio, quelle lontane hanno qualche turno di respiro.
[b]Le carte sono un'arma a doppio taglio.[/b] Prendere una carta a un avversario gli toglie il vantaggio e gli toglie anche il rischio: a volte conviene lasciargli una classe che sta per essere colpita.
[b]Le maggioranze attirano le M.[/b] Essere i primi in una regione con molti ratti significa prendersi i colpi delle M. Una presenza piccola accanto a un avversario grosso è spesso più sicura.
[b]Pensa alla fine.[/b] Alla fine tutti i ratti rimasti si scoprono in ogni regione: i cubetti in regioni piene di ratti sono a rischio anche se la Peste non ci passa mai. Il Re (palazzo) e il Mercante (fuga) sono preziosi nelle ultime fasi.
[b]La Strega e i ratti noti.[/b] Un ratto visto con la Strega resta segnato per te sul tabellone (vedi la sua faccia): sfruttalo per decidere dove crescere o dove mandare la Peste.
"""

const DIGITAL := """[font_size=34][color=#f0d58a]Note della versione digitale[/color][/font_size]
• Le scelte si fanno con i pulsanti a destra o toccando il tabellone: regioni, gettoni, cubetti e confini selezionabili hanno un anello dorato.
• Sul tabellone: un dito trascina, due dita pizzicano per lo zoom e ruotano la vista, il trascinamento verticale con due dita (o il tasto destro) la inclina; «Dall'alto» guarda la mappa dritta, «Centra» rimette la vista iniziale.
• Accanto a ogni colonna di cubetti c'è il numero dei cubetti; i ratti visti con la Strega mostrano la faccia solo a chi li ha visti.
• Quando si aggiungono cubetti si mettono sempre tutti quelli concessi (al massimo quelli rimasti nella riserva).
• La preparazione mette i due cubetti di ogni giro nella stessa regione.
• Una pozione del Mago si usa sempre al posto del cubetto che dovrebbe morire.
• I ratti nuovi non attraversano i muri dell'Imperatore e non entrano nelle regioni con un vescovo; l'area collegata della Regina conta le regioni confinanti anche oltre i muri.
• La Peste di cartone del gioco qui è una figura incappucciata con un alone verde.
"""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if popup:
		z_index = 30
		mouse_filter = Control.MOUSE_FILTER_STOP
		var shade := ColorRect.new()
		shade.color = Color(0, 0, 0, 0.82)
		shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(shade)
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UI.dark_style(8, 0.97))
	pc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pc.offset_left = 60
	pc.offset_right = -60
	pc.offset_top = 36
	pc.offset_bottom = -36
	add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	pc.add_child(vb)
	var hh := HBoxContainer.new()
	vb.add_child(hh)
	var t := UI.title("Il regolamento", 54)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hh.add_child(t)
	var back := UI.primary(UI.button("Chiudi" if popup else "Torna al menu", 240, 52, 22))
	back.pressed.connect(func():
		if popup:
			queue_free()
		else:
			main.show_menu())
	hh.add_child(back)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	vb.add_child(body)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	list.custom_minimum_size.x = 340
	body.add_child(list)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(sc)
	inner = VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 18)
	sc.add_child(inner)
	scroller = sc
	var chapters := [["Le regole in breve", TEXT], ["Le carte di classe", ""], ["I gettoni ratto", ""], ["Consigli di strategia", STRATEGY], ["Note della versione digitale", DIGITAL]]
	var btns := []
	for k in chapters.size():
		var b := UI.button(chapters[k][0], 340, 54, 20)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		b.button_pressed = k == 0
		btns.append(b)
		var kk: int = k
		b.pressed.connect(func():
			for j in btns.size():
				btns[j].button_pressed = j == kk
			_show(chapters[kk]))
		list.add_child(b)
	_show(chapters[0])


var inner: VBoxContainer
var scroller: ScrollContainer


func _show(ch: Array) -> void:
	for c in inner.get_children():
		c.queue_free()
	scroller.scroll_vertical = 0
	if ch[0] == "Le carte di classe":
		_cards()
		return
	if ch[0] == "I gettoni ratto":
		_rats()
		return
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rt.add_theme_font_size_override("normal_font_size", 23)
	rt.add_theme_font_size_override("bold_font_size", 23)
	rt.text = ch[1]
	inner.add_child(rt)


func _cards() -> void:
	inner.add_child(UI.title("Le carte di classe", 40))
	inner.add_child(UI.wrap(UI.label(CARDS_NOTE, 22, UI.PARCH), 1200))
	for cls in D.CLASS_ORDER:
		inner.add_child(UI.heading(D.CLASSES[cls]["name"], 28, D.CLASSES[cls]["col"]))
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 18)
		flow.add_theme_constant_override("v_separation", 14)
		inner.add_child(flow)
		for c in D.CARD_ORDER:
			if D.CARDS[c]["cls"] != cls:
				continue
			var h := HBoxContainer.new()
			h.add_theme_constant_override("separation", 10)
			h.add_child(UI.icon_rect(UI.card_tex(c), Vector2(150, 210)))
			var v := VBoxContainer.new()
			v.add_child(UI.label(D.CARDS[c]["name"], 24, UI.GOLD_L, UI.font_head))
			v.add_child(UI.label("Pifferaio magico" if D.CARDS[c]["exp"] else "Gioco base", 18, UI.MUTED, UI.font_head_r))
			v.add_child(UI.wrap(UI.label(D.CARDS[c]["text"], 20, UI.PARCH), 220))
			h.add_child(v)
			flow.add_child(h)


func _rats() -> void:
	inner.add_child(UI.title("I gettoni ratto", 40))
	inner.add_child(UI.wrap(UI.label("I 49 gettoni: il numero in alto è la soglia di popolazione, sotto ci sono i simboli. I primi 12 (bordo viola) sono i ratti iniziali.", 22, UI.PARCH), 1200))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 10)
	flow.add_theme_constant_override("v_separation", 10)
	inner.add_child(flow)
	for i in D.RATS.size():
		flow.add_child(UI.icon_rect(UI.rat_tex(i), Vector2(110, 110)))
