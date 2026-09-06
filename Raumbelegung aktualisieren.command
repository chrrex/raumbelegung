#!/bin/bash
# Doppelklick: holt die aktuellen Daten aus Event Temple, baut die Übersicht
# neu und öffnet sie im Browser. Aktualisiert die lokale Datei –
# der geteilte Link wird davon nicht berührt.

cd "$(dirname "$0")" || exit 1

echo "Raumbelegung Liebenberg – Daten werden geholt …"
echo

if ruby build.rb; then
  echo
  echo "Fertig. Die Übersicht wird jetzt geöffnet."
  open "out/wochenuebersicht.html"
else
  echo
  echo "Der Abruf ist fehlgeschlagen – siehe Meldung oben."
  echo "Häufigste Ursache: der API-Key in .env ist abgelaufen."
fi

echo
echo "Dieses Fenster kann geschlossen werden."
