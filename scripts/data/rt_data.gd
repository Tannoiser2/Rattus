extends RefCounted
## Dati di Rattus (White Goblin Games, 2010) e dell'espansione Pied Piper (il Pifferaio magico):
## regioni dell'Europa medievale, gettoni ratto, carte di classe, colori dei giocatori.
## Le coordinate sono in pixel del tabellone ridotto a 2000 × 1283 (l'immagine vera è 4096 × 2629).

const BOARD_W := 2000.0
const BOARD_H := 1283.0

## Regioni. tier: 2 = chiare (usate sempre), 3 = medie (dai 3 giocatori), 4 = scure (solo in 4).
const REGIONS := [
	{"id": "scandia", "name": "Scandia", "tier": 2, "pos": Vector2(1150, 230)},
	{"id": "anglia", "name": "Anglia", "tier": 2, "pos": Vector2(700, 400)},
	{"id": "germania", "name": "Germania", "tier": 2, "pos": Vector2(1060, 625)},
	{"id": "gallia", "name": "Gallia", "tier": 2, "pos": Vector2(740, 800)},
	{"id": "hispania", "name": "Hispania", "tier": 2, "pos": Vector2(420, 990)},
	{"id": "italia", "name": "Italia", "tier": 2, "pos": Vector2(1050, 890)},
	{"id": "polonia", "name": "Polonia", "tier": 2, "pos": Vector2(1430, 530)},
	{"id": "hungaria", "name": "Hungaria", "tier": 2, "pos": Vector2(1310, 810)},
	{"id": "bulgaria", "name": "Bulgaria", "tier": 3, "pos": Vector2(1620, 720)},
	{"id": "turcia", "name": "Turcia", "tier": 3, "pos": Vector2(1680, 1010)},
	{"id": "russia", "name": "Russia", "tier": 4, "pos": Vector2(1700, 260)},
	{"id": "tartaria", "name": "Tartaria", "tier": 4, "pos": Vector2(1800, 500)},
]

## Confini (anche quelli segnati dalle frecce sul mare): [regione a, regione b, punto del confine].
const EDGES := [
	[1, 0, Vector2(890, 240)], [1, 2, Vector2(870, 375)], [1, 3, Vector2(685, 535)], [1, 4, Vector2(460, 610)],
	[0, 2, Vector2(1080, 380)], [0, 6, Vector2(1290, 250)], [0, 10, Vector2(1465, 75)],
	[2, 3, Vector2(900, 640)], [2, 5, Vector2(960, 740)], [2, 7, Vector2(1200, 650)], [2, 6, Vector2(1240, 460)],
	[3, 4, Vector2(640, 830)], [3, 5, Vector2(870, 800)], [4, 5, Vector2(740, 1070)],
	[5, 7, Vector2(1215, 900)], [5, 9, Vector2(1310, 1150)],
	[7, 6, Vector2(1290, 590)], [7, 8, Vector2(1470, 640)], [7, 9, Vector2(1380, 880)],
	[6, 8, Vector2(1560, 500)], [6, 10, Vector2(1490, 235)], [6, 11, Vector2(1580, 380)],
	[10, 11, Vector2(1750, 290)], [8, 11, Vector2(1780, 600)], [8, 9, Vector2(1550, 830)], [11, 9, Vector2(1830, 815)],
]

## Area del palazzo (lo stemma con il castello, a sinistra).
const PALACE := Vector2(272, 400)

## Simboli delle classi sui gettoni ratto: P popolani, B borghesia, C clero, K cavalleria, W magia, R nobiltà;
## M = maggioranza, A = tutti.
const CLASSES := {
	"P": {"name": "Popolani", "col": Color("#d9a43a")},
	"B": {"name": "Borghesia", "col": Color("#b9bcc0")},
	"C": {"name": "Clero", "col": Color("#d9802e")},
	"K": {"name": "Cavalleria", "col": Color("#c8463a")},
	"W": {"name": "Magia", "col": Color("#c98bd6")},
	"R": {"name": "Nobiltà", "col": Color("#e6c832")},
}
const CLASS_ORDER := ["P", "B", "C", "K", "W", "R"]

## I 49 gettoni ratto: soglia di popolazione e simboli. I primi 12 (cerchio viola) sono i ratti iniziali.
const RATS := [
	[3, "BWM"], [3, "PCM"], [2, "RCW"], [3, "RKM"], [4, "RCBM"], [4, "KCBA"],
	[1, "A"], [4, "KPWM"], [4, "RPWA"], [2, "KBP"], [3, "A"], [4, "MA"],
	[4, "CBPM"], [6, "RBBC"], [1, "KC"], [5, "RBB"], [4, "KBWA"], [3, "RKM"], [2, "KC"], [1, "RP"],
	[4, "RKWA"], [2, "BP"], [6, "MM"], [6, "RKCPBWM"], [3, "CPM"], [5, "PPW"], [6, "RKCPBAW"], [3, "MA"],
	[5, "KCPWA"], [2, "RW"], [5, "KKP"], [5, "MM"], [6, "RRPB"], [4, "RKCBPW"], [6, "RCCW"], [5, "KWW"],
	[5, "RRC"], [6, "KKPW"], [6, "RBPCA"], [4, "RCPM"], [5, "RBWKA"], [1, "MM"], [6, "KWWB"], [5, "CCB"],
	[5, "AA"], [2, "A"], [1, "BW"], [6, "KPPC"], [3, "BWM"],
]
const START_RATS := 12

## Carte di classe: 6 del gioco base e 12 del Pifferaio magico.
const CARDS := {
	"contadino": {"name": "Contadino", "cls": "P", "exp": false,
		"text": "Quando aggiungi cubetti metti un cubetto in più del solito: anche uno in una regione senza ratti."},
	"re": {"name": "Re", "cls": "R", "exp": false,
		"text": "Sposta uno dei tuoi cubetti da una regione senza ratti al palazzo: lì è al sicuro fino alla fine."},
	"cavaliere": {"name": "Cavaliere", "cls": "K", "exp": false,
		"text": "Nella fase C muovi la Peste fino a due passi; prima di scoprire i ratti puoi farle contare come due abitanti neutrali."},
	"mercante": {"name": "Mercante", "cls": "B", "exp": false,
		"text": "Sposta fino a 3 tuoi cubetti da una regione a una confinante."},
	"monaco": {"name": "Monaco", "cls": "C", "exp": false,
		"text": "Sposta un gettone ratto da una regione a una confinante (mai oltre tre ratti in una regione)."},
	"strega": {"name": "Strega", "cls": "W", "exp": false,
		"text": "Guarda di nascosto un gettone ratto, poi un altro; se vuoi scambiali di posto."},
	"corriere": {"name": "Corriere", "cls": "B", "exp": true,
		"text": "Scambia due cubetti di colori diversi in due regioni diverse (i muri non lo fermano)."},
	"vescovo": {"name": "Vescovo", "cls": "C", "exp": true,
		"text": "Metti o sposta uno dei due vescovi: nessun ratto può entrare o essere messo nella sua regione."},
	"suora": {"name": "Suora", "cls": "C", "exp": true,
		"text": "Metti o sposta le tre suore: ognuna toglie un abitante dal conto della popolazione della sua regione."},
	"crociato": {"name": "Crociato", "cls": "K", "exp": true,
		"text": "Nella fase C muovi la Peste fino a due passi; puoi scoprire insieme tutti i ratti e scegliere l'ordine in cui colpiscono."},
	"imperatore": {"name": "Imperatore", "cls": "R", "exp": true,
		"text": "Metti o sposta i tre muri sui confini: niente li attraversa, né ratti, né cubetti, né la Peste."},
	"regina": {"name": "Regina", "cls": "R", "exp": true,
		"text": "Se i tuoi cubetti formano l'area collegata più grande di tutti, quando aggiungi cubetti ne metti due in più."},
	"pifferaio": {"name": "Pifferaio magico", "cls": "W", "exp": true,
		"text": "Sposta un tuo cubetto in una regione confinante e porta con lui più ratti che puoi."},
	"fornaio": {"name": "Fornaio", "cls": "P", "exp": true,
		"text": "Metti un tuo cubetto sulla carta. Chi ti prende la carta mette subito tutti i cubetti della carta in una regione a scelta."},
	"servo": {"name": "Servo della gleba", "cls": "P", "exp": true,
		"text": "Nella fase C, per ogni ratto che uccide almeno un cubetto altrui, metti un tuo cubetto nella regione della Peste."},
	"borgomastro": {"name": "Borgomastro", "cls": "B", "exp": true,
		"text": "Invece di aggiungere cubetti secondo i ratti, metti un cubetto in ogni regione dove hai la maggioranza."},
	"mago": {"name": "Mago", "cls": "W", "exp": true,
		"text": "Metti una pozione su un tuo cubetto: quando la peste dovrebbe ucciderlo, togli la pozione al suo posto."},
	"soldato": {"name": "Soldato", "cls": "K", "exp": true,
		"text": "Nella fase C muovi la Peste fino a due passi; quando metti i ratti nuovi ne aggiungi uno in più."},
}
const CARD_ORDER := ["contadino", "fornaio", "servo", "mercante", "corriere", "borgomastro", "monaco", "vescovo", "suora",
	"cavaliere", "crociato", "soldato", "strega", "pifferaio", "mago", "re", "imperatore", "regina"]
const BASE_SET := ["contadino", "mercante", "monaco", "cavaliere", "strega", "re"]

## Assortimenti consigliati dal regolamento del Pifferaio magico.
const SETS := {
	"base": {"name": "Gioco base", "cards": ["contadino", "mercante", "monaco", "cavaliere", "strega", "re"]},
	"prosperi": {"name": "Tempi prosperi", "cards": ["contadino", "fornaio", "servo", "regina", "borgomastro", "soldato"]},
	"ratti": {"name": "Controllo dei ratti", "cards": ["pifferaio", "mago", "vescovo", "suora", "monaco", "imperatore"]},
	"guerra": {"name": "Europa in guerra", "cards": ["cavaliere", "crociato", "soldato", "corriere", "mercante", "pifferaio"]},
}

## Colori dei giocatori (i cubetti di legno).
const COLORS := [
	{"name": "Rosso", "col": Color("#c0392b"), "dark": Color("#6e1a12"), "text": Color("#fff2e0")},
	{"name": "Blu", "col": Color("#2e6bb5"), "dark": Color("#163a66"), "text": Color("#eef4ff")},
	{"name": "Giallo", "col": Color("#e8b923"), "dark": Color("#7c5c08"), "text": Color("#2a1d05")},
	{"name": "Verde", "col": Color("#3f8f3a"), "dark": Color("#1d4a1a"), "text": Color("#effae8")},
]

const CUBES := 20
const POTIONS := 10


static func neighbors_all(r: int) -> Array:
	var out := []
	for e in EDGES:
		if e[0] == r:
			out.append(e[1])
		elif e[1] == r:
			out.append(e[0])
	return out


static func edge_key(a: int, b: int) -> String:
	return "%d-%d" % [mini(a, b), maxi(a, b)]


static func edge_pos(key: String) -> Vector2:
	for e in EDGES:
		if edge_key(e[0], e[1]) == key:
			return e[2]
	return Vector2.ZERO
