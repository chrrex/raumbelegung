#!/usr/bin/env ruby
# frozen_string_literal: true

# Wochenübersicht Raumbelegung – Schloss & Gut Liebenberg
#
#   ruby build.rb              # echte Daten aus Event Temple
#   ruby build.rb --demo       # Beispieldaten, ohne API-Zugriff
#   ruby build.rb --wochen=16  # mehr Wochen im Voraus
#   ruby build.rb --start=2026-12-21
#
# Ergebnis: out/wochenuebersicht.html

require "date"
require "json"
require "time"

ROOT = File.expand_path(__dir__)
$LOAD_PATH.unshift(File.join(ROOT, "lib"))

require "eventtemple"
require "render"
require "sample_data"

# --- Argumente -----------------------------------------------------------

demo   = ARGV.include?("--demo")
offen  = ARGV.include?("--offen")   # ohne Passwortschutz bauen
wochen = (ARGV.find { |a| a.start_with?("--wochen=") } || "--wochen=10").split("=", 2).last.to_i
start_arg = ARGV.find { |a| a.start_with?("--start=") }

heute = Date.today
start_montag = start_arg ? Date.parse(start_arg.split("=", 2).last) : heute
start_montag -= (start_montag.cwday - 1) # auf Montag zurück
wochen = 1 if wochen < 1
wochen = 26 if wochen > 26

von = start_montag
bis = start_montag + (wochen * 7) - 1

# --- Konfiguration -------------------------------------------------------

config_pfad = File.join(ROOT, "config", "raeume.json")
config = File.exist?(config_pfad) ? JSON.parse(File.read(config_pfad)) : {}
gruppen_config  = config["gruppen"] || []
ausblenden      = Array(config["ausblenden"]).map(&:downcase)
status_anzeigen = Array(config["status_anzeigen"])
status_anzeigen = %w[definite tentative lead] if status_anzeigen.empty?

# --- Daten holen ---------------------------------------------------------

def lade_env(pfad)
  return {} unless File.exist?(pfad)
  File.readlines(pfad).each_with_object({}) do |zeile, acc|
    zeile = zeile.strip
    next if zeile.empty? || zeile.start_with?("#")
    k, v = zeile.split("=", 2)
    next unless k && v
    acc[k.strip] = v.strip.gsub(/\A["']|["']\z/, "")
  end
end

if demo
  spaces = SampleData.spaces
  events = SampleData.events(from: von, to: bis)
  quelle = "Beispieldaten (Demo)"
else
  env     = lade_env(File.join(ROOT, ".env"))
  api_key = ENV["ET_API_KEY"] || env["ET_API_KEY"]
  api_org = ENV["ET_API_ORG"] || env["ET_API_ORG"]

  if api_key.to_s.empty? || api_org.to_s.empty?
    abort <<~MSG
      Es fehlen die Zugangsdaten.

      Lege im Ordner #{ROOT} eine Datei .env an mit:

        ET_API_KEY=dein_api_key
        ET_API_ORG=deine_org_id

      API-Key:  Event Temple → Settings → Developers → API
      Org-ID:   Event Temple → Settings → Overview

      Oder starte zum Ausprobieren ohne API:  ruby build.rb --demo
    MSG
  end

  client = EventTemple::Client.new(api_key: api_key, api_org: api_org)
  warn "Räume werden geladen …"
  spaces = EventTemple.spaces(client)
  warn "Events #{von} bis #{bis} werden geladen …"
  events = EventTemple.events(client, from: von, to: bis)
  quelle = "Event Temple API"
end

seiten_passwort = nil
unless offen
  env2 = lade_env(File.join(ROOT, ".env"))
  seiten_passwort = ENV["SEITEN_PASSWORT"] || env2["SEITEN_PASSWORT"]
  seiten_passwort = nil if seiten_passwort.to_s.empty?
end

# --- Filtern -------------------------------------------------------------

spaces = spaces.reject { |s| ausblenden.any? { |m| s[:name].to_s.downcase.include?(m) } }
events = events.select { |e| status_anzeigen.include?(e[:status]) }
events = events.select { |e| e[:space_id] && spaces.any? { |s| s[:id].to_s == e[:space_id].to_s } }

# --- Rendern -------------------------------------------------------------

gruppen = Render.gruppiere(spaces, gruppen_config)
wochen_daten = (0...wochen).map do |i|
  Render.woche(start_montag + (i * 7), events, gruppen)
end

html = Render.page(
  wochen: wochen_daten,
  gruppen: gruppen,
  generated_at: Time.now,
  logo_pfad: File.join(ROOT, "assets", "sgl-logo.svg"),
  quelle: quelle,
  passwort: seiten_passwort,
  heute: heute
)

ziel = File.join(ROOT, "out", "wochenuebersicht.html")
Dir.mkdir(File.join(ROOT, "out")) unless Dir.exist?(File.join(ROOT, "out"))
File.write(ziel, html)
# Für statisches Hosting: dieselbe Seite zusätzlich als Startseite ablegen.
File.write(File.join(ROOT, "out", "index.html"), html)

# --- Rückmeldung ---------------------------------------------------------

warn ""
warn "#{spaces.size} Räume, #{events.size} Belegungen, #{wochen} Wochen ab #{start_montag}."
warn(seiten_passwort ? "Passwortschutz: aktiv (Inhalt ist verschlüsselt)." : "Passwortschutz: aus.")
warn "Geschrieben: #{ziel} (#{(File.size(ziel) / 1024.0).round(1)} KB)"
warn ""
warn "Gefundene Räume – zum Einsortieren in config/raeume.json:"
gruppen.each do |g|
  warn "  #{g[:name]}:"
  g[:rooms].each { |r| warn "    · #{r[:name]}" }
end
ohne = gruppen.find { |g| g[:name] == "Weitere Räume" }
warn "\nHinweis: #{ohne[:rooms].size} Räume ohne Gruppenzuordnung – Muster in config/raeume.json ergänzen." if ohne
