# Rattus — versione digitale

Versione digitale in italiano di **Rattus** (Åse e Henrik Berg, White Goblin Games 2010) con l'espansione
**Pied Piper** (il Pifferaio magico), fatta con Godot 4.7 per la ludoteca digitale.

Europa, 1347: la peste nera dilaga. Ogni giocatore fa crescere il suo popolo nelle regioni d'Europa,
prende le carte di classe (Contadino, Mercante, Monaco, Cavaliere, Strega, Re e le 12 carte del Pifferaio)
e manda la Peste dagli avversari. Quando la peste si ritira vince chi ha più abitanti sopravvissuti.

- Da 2 a 4 giocatori: persone sullo stesso dispositivo, avversari IA (facile, normale, difficile) e
  **gioco online** con gli amici (stanze con codice di 4 lettere su Firebase, radice `rattus/rooms`).
- Le sei carte della partita: gioco base, i tre assortimenti consigliati, una a caso per classe, sei a caso
  o scelta libera.
- **Mappa 3D** con il tabellone originale: cubetti di legno, gettoni ratto, la Peste, suore, vescovi, muri e
  pozioni modellati in Godot. Si usa anche su iPad: un dito trascina, due dita fanno zoom e ruotano.
- **Partite salvate** su Firebase (`rattus/partite/<codice di 6 lettere>`), riprendibili da ogni dispositivo.
- Regolamento completo, carte e gettoni consultabili dal menu e durante la partita.

## Struttura

| Cartella | Contenuto |
|---|---|
| `scripts/core` | regole (`engine.gd`, `state.gd`) e IA (`ai.gd`) |
| `scripts/data` | regioni, confini, gettoni ratto e carte (`rt_data.gd`) |
| `scripts/net` | Firebase: stanze online e salvataggi |
| `scripts/ui` | menu, partita, tabellone 3D, regolamento |
| `assets` | tabellone, carte, gettoni (dal modulo di Tabletop Simulator), font liberi (OFL) |
| `tests` | partite automatiche, prova online su finto Firebase, salvataggi, fotografie dell'interfaccia |
| `ludoteca` | scheda e copertina per la pagina della ludoteca |

## Prove

```
godot --headless --path . --script res://tests/sim.gd -- 30 1       # 30 partite fra IA
python3 tools/controlla_glifi.py                                     # niente quadratini nei testi
xvfb-run -s "-screen 0 1920x1080x24" godot --path . -s tests/shot.gd -- /tmp/foto 4
```

Prova online: `python3 tests/firebase_mock.py 8765` e due istanze di `tests/online_play.gd` con
`RT_DB_URL`, `RT_AUTH_URL`, `RT_REFRESH_URL`, `RT_ROLE=host|guest`, `RT_CODEFILE`.

## Pubblicazione

Il workflow **Pubblica** non parte da solo: si avvia da Actions → Pubblica → Run workflow, oppure con un
commit che contiene `[pubblica]` nel messaggio. Costruisce la versione web e la mette su GitHub Pages
(https://tannoiser2.github.io/Rattus/); la ludoteca privata su Cloudflare la pubblica il repository della ludoteca.
