# Wochenübersicht Raumbelegung – Schloss & Gut Liebenberg

Erzeugt aus den Daten der Event-Temple-API eine Wochenübersicht:
Räume als Zeilen, die sieben Wochentage als Spalten, jede Belegung als Kachel
mit Uhrzeit, Buchungsname und Status. Ergebnis ist eine einzelne HTML-Datei,
die als privater Link im Browser erreichbar ist.

## Einmalig einrichten

1. **API-Zugang hinterlegen**

   In Event Temple: `Settings → Developers → API` einen Key erzeugen,
   unter `Settings → Overview` die Org-ID ablesen.

   Dann in diesem Ordner die Datei `.env` anlegen (Vorlage: `.env.example`):

   ```
   ET_API_KEY=...
   ET_API_ORG=...
   ```

   Die `.env` bleibt auf dem Rechner. Der Key gehört nie in die HTML-Datei –
   deshalb wird die Seite hier gebaut und nicht im Browser aus der API geladen.

2. **Ersten Lauf machen**

   ```bash
   ruby build.rb
   ```

   Am Ende listet das Skript alle gefundenen Räume mit ihrer Gruppenzuordnung.
   Räume, die unter „Weitere Räume“ auftauchen, in `config/raeume.json`
   einsortieren.

## Aktualisieren

Es gibt drei Wege, je nachdem, was aktuell werden soll:

| Weg | Was passiert | Wirkt auf |
|---|---|---|
| Automatisch, jeden Morgen | Die geplante Aufgabe „Raumbelegung Liebenberg“ baut neu und veröffentlicht | den geteilten Link |
| „Jetzt ausführen“ in der Claude-App, Bereich *Scheduled* | dasselbe, sofort | den geteilten Link |
| Doppelklick auf `Raumbelegung aktualisieren.command` | baut neu und öffnet das Ergebnis lokal | nur die Datei auf diesem Rechner |

Die Schaltfläche **„Seite neu laden“** oben rechts in der Übersicht lädt nur die
Seite neu. Sie kann keine Daten aus Event Temple holen: der API-Key darf nicht
in eine Seite, die im Browser läuft, und die Veröffentlichungsplattform lässt
Anfragen an fremde Server ohnehin nicht zu. Sie ist dafür da, nach einer
Aktualisierung den neuen Stand in einem offenen Tab zu sehen.

## Drucken und als PDF sichern

Oben rechts **„Drucken / PDF“**. Es kommt zuerst eine Abfrage:

* **Räume** – die aktuell gefilterte Auswahl, nur belegte Räume, oder alle
* **Zeitraum** – nur die angezeigte Woche, oder alle zehn Wochen mit je einer Seite

Danach öffnet sich der Druckdialog des Browsers; dort „Als PDF sichern“ wählen.
Das Layout ist auf **A4 quer** eingestellt, die Tabellenköpfe wiederholen sich
auf jeder Seite, und keine Zeile wird über einen Seitenumbruch zerrissen.
Damit die Statusfarben mitgedruckt werden, im Druckdialog
„Hintergrundgrafiken“ aktivieren.

Ein direkter PDF-Download war nicht möglich: die Veröffentlichungsplattform
unterbindet Downloads, die eine Seite selbst auslöst. Der Umweg über den
Druckdialog liefert dieselbe Datei.

## Von Hand bauen



```bash
ruby build.rb              # aktuelle Woche + 4 Folgewochen
ruby build.rb --wochen=16  # weiter in die Zukunft (Standard: 10)
ruby build.rb --start=2026-12-21
ruby build.rb --demo       # Beispieldaten, ohne API
```

Das Ergebnis liegt in `out/wochenuebersicht.html`.

## Konfiguration – `config/raeume.json`

| Schlüssel | Bedeutung |
|---|---|
| `gruppen` | Reihenfolge und Gruppierung der Räume. Ein Raum landet in der **ersten** Gruppe, deren Muster (Teilstring, Groß-/Kleinschreibung egal) im Raumnamen vorkommt. |
| `ausblenden` | Räume, deren Name eines dieser Muster enthält, erscheinen nicht. Nützlich, wenn in Event Temple auch Hotelzimmer als Spaces geführt werden. |
| `status_anzeigen` | Welche Event-Status auf die Seite kommen. Standard: `definite`, `tentative`, `lead`. `lost` bleibt außen vor. |

## Was die Seite zeigt

Jede Kachel zeigt Uhrzeit, Buchungsname, Veranstaltungsname sowie Status und
Veranstaltungstyp.

* **Grün, gefüllt** – definitiv gebucht
* **Gold, gefüllt** – optional / vorläufig
* **Grau, gestrichelt** – Anfrage
* Leere Zelle – Raum ist frei
* Mehrtägige Veranstaltungen erscheinen an jedem Tag; Folgetage sind mit
  „läuft weiter“ bzw. „bis …“ gekennzeichnet.
* Über **„Räume filtern“** lassen sich einzelne Räume oder ganze Gruppen aus- und
  wieder einblenden. Die Auswahl bleibt im Browser gespeichert und gilt für alle
  Wochen. „Auswahl zurücksetzen“ stellt den Ausgangszustand her.
* Die Wochenauswahl umfasst die laufende Woche und die neun folgenden.
* Der aktuelle Tag ist farblich markiert, die laufende Woche ist beim Öffnen
  vorausgewählt.

## Aufbau

```
build.rb              Startpunkt: Daten holen, filtern, HTML schreiben
lib/eventtemple.rb    API-Client (JSON:API, Cursor-Pagination)
lib/render.rb         HTML, CSS, Layout
lib/sample_data.rb    Beispieldaten für --demo
config/raeume.json    Gruppierung, Ausblendungen, Status
assets/sgl-logo.svg   Logo
out/                  Ergebnis
Raumbelegung aktualisieren.command   Doppelklick-Aktualisierung
```

## Technische Notizen

* Endpunkte: `GET /v2/spaces` und `GET /v2/events?include=space,booking,event_type`
* Zeitraumfilter fängt auch mehrtägige Veranstaltungen ein:
  `filter[start_date][lteq]=<Ende>` und `filter[end_date][gteq]=<Anfang>`
* Authentifizierung über die Header `X-API-KEY` und `X-API-ORG`
* Läuft mit dem Ruby, das auf macOS vorinstalliert ist – keine Gems nötig.
