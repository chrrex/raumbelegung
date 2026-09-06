#!/bin/bash
# Doppelklick: holt die aktuellen Daten aus Event Temple und erzeugt ein PDF
# im Querformat auf dem Schreibtisch.

cd "$(dirname "$0")" || exit 1

CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
if [ ! -x "$CHROME" ]; then
  echo "Google Chrome wurde nicht gefunden – das PDF kann so nicht erzeugt werden."
  echo "Alternative: Übersicht im Browser öffnen und dort drucken."
  echo; read -r -p "Eingabetaste zum Schließen "; exit 1
fi

echo "Raumbelegung Liebenberg – PDF erzeugen"
echo
echo "  1) Nur belegte Räume   (empfohlen, kürzestes PDF)"
echo "  2) Alle Räume"
echo
read -r -p "Auswahl [1]: " wahl
case "$wahl" in
  2) UMFANG="alle";  NAME="alle-Raeume" ;;
  *) UMFANG="belegt"; NAME="belegte-Raeume" ;;
esac

read -r -p "Wie viele Wochen ab dieser Woche? [10]: " anzahl
case "$anzahl" in
  ''|*[!0-9]*) anzahl=10 ;;
esac

echo
echo "Daten werden geholt …"
if ! ruby build.rb --offen --wochen="$anzahl"; then
  echo; echo "Der Abruf ist fehlgeschlagen – siehe Meldung oben."
  echo; read -r -p "Eingabetaste zum Schließen "; exit 1
fi

ZIEL="$HOME/Desktop/Raumbelegung_${NAME}_$(date +%Y-%m-%d).pdf"
QUELLE="file://$PWD/out/wochenuebersicht.html#druck=$UMFANG,alle"

echo "PDF wird gesetzt …"
"$CHROME" --headless=new --disable-gpu --no-pdf-header-footer \
          --virtual-time-budget=20000 \
          --print-to-pdf="$ZIEL" "$QUELLE" >/dev/null 2>&1

# Danach wieder die geschützte Fassung herstellen, damit ein späterer
# Veröffentlichungslauf nicht versehentlich die offene Datei nimmt.
ruby build.rb --wochen="$anzahl" >/dev/null 2>&1

if [ -f "$ZIEL" ]; then
  echo "Fertig: $ZIEL"
  open "$ZIEL"
else
  echo "Das PDF konnte nicht erzeugt werden."
fi

echo
read -r -p "Eingabetaste zum Schließen "
