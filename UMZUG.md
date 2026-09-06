# Umzug ins Web – Schritt für Schritt

Ziel: Die Übersicht liegt auf einer normalen Webadresse. Damit funktioniert der
Druck-Knopf auf **jedem** Rechner, und die tägliche Aktualisierung läuft in der
Cloud – unabhängig davon, ob ein Rechner im Haus an ist.

Gewählter Weg: **GitHub + GitHub Pages**. Ein Konto genügt, alles kostenfrei,
https ist inklusive. Netlify oder Cloudflare Pages gingen genauso, brauchen aber
ein zweites Konto.

---

## 1. GitHub-Konto anlegen

<https://github.com/signup> – am besten mit einer Adresse, an die auch
Kolleg:innen herankommen (z. B. it@schloss-liebenberg.de), damit der Zugang
nicht an einer Person hängt.

## 2. Neues Repository anlegen

Name z. B. `raumbelegung`. **Wichtig: auf „Public" stellen** – GitHub Pages
funktioniert bei kostenlosen Konten nur mit öffentlichen Repositories.

Öffentlich ist hier nur der *Programmcode*, nicht die Belegungsdaten:
API-Key und Passwort liegen getrennt davon (siehe Schritt 4), und der
Seiteninhalt ist verschlüsselt.

## 3. Diesen Ordner hochladen

Auf der Startseite des neuen Repositories „uploading an existing file" wählen
und den kompletten Inhalt des Ordners `wochenuebersicht` hineinziehen –
**außer der Datei `.env`**. Die enthält die Zugangsdaten und gehört nicht ins
Netz. (Sie ist in `.gitignore` eingetragen, wird also ohnehin ignoriert.)

## 4. Zugangsdaten als Secrets hinterlegen

Im Repository: `Settings → Secrets and variables → Actions → New repository secret`.
Drei Stück anlegen, exakt so benannt:

| Name | Wert |
|---|---|
| `ET_API_KEY` | der Event-Temple-API-Key |
| `ET_API_ORG` | die Org-ID |
| `SEITEN_PASSWORT` | das Passwort für die Seite |

Diese Werte sind danach auch für dich nicht mehr lesbar – GitHub zeigt sie nie
wieder an. Sie stehen weiterhin in deiner lokalen `.env`.

## 5. GitHub Pages einschalten

`Settings → Pages → Build and deployment → Source:` **GitHub Actions** wählen.

## 6. Ersten Lauf starten

`Actions → Raumbelegung aktualisieren → Run workflow`. Nach ein bis zwei
Minuten steht die Adresse unter `Settings → Pages`, meist
`https://<kontoname>.github.io/raumbelegung/`.

Ab dann baut sich die Seite jeden Morgen um 6:30 Uhr von selbst neu.

## 7. Aufräumen

Wenn die neue Adresse läuft: in der Claude-App unter *Scheduled* die Aufgabe
„Raumbelegung Liebenberg" abschalten. Sie wird nicht mehr gebraucht.

---

## Zum Passwort

Die Adresse ist öffentlich erreichbar, der Inhalt aber verschlüsselt
(AES-256, Schlüssel aus dem Passwort über PBKDF2 mit 250.000 Runden).
Wer das Passwort nicht hat, sieht im Quelltext nur Zufallszeichen.

Trotzdem: Bei einer öffentlichen Adresse kann jemand die Datei herunterladen
und in Ruhe Passwörter durchprobieren. `Fontane2019!` folgt einem Muster, auf
das man bei Liebenberg kommen kann. **Empfehlung:** für die öffentliche
Fassung ein längeres Passwort wählen – drei zufällige Wörter mit Zahl reichen
und lassen sich gut weitergeben. Ändern in `SEITEN_PASSWORT` (Secret und
lokale `.env`), danach einmal `Run workflow`.

Wer echte Zugangskontrolle möchte statt eines Passworts in der Seite: Bei
Cloudflare Pages lässt sich „Cloudflare Access" davorschalten – Anmeldung per
E-Mail-Code, bis 50 Personen kostenfrei. Das wäre der nächste Ausbauschritt.
