# frozen_string_literal: true

# Beispieldaten für den Demo-Modus (build.rb --demo).
# Echte Liebenberger Raumnamen, erfundene Buchungen – damit die Seite
# ohne API-Zugriff realistisch aussieht.
module SampleData
  SPACES = [
    { id: "1",  name: "Schlosssaal",                     capacity: 70 },
    { id: "2",  name: "Nordische Halle 1",               capacity: 20 },
    { id: "3",  name: "Nordische Halle 2",               capacity: 45 },
    { id: "4",  name: "Seehaus Kaminzimmer",             capacity: 60 },
    { id: "5",  name: "Seehaus Saal",                    capacity: 40 },
    { id: "6",  name: "Seehaus Parkzimmer",              capacity: 20 },
    { id: "7",  name: "Seehaus Seezimmer",               capacity: 22 },
    { id: "8",  name: "Gutshof Historischer Rinderstall",capacity: 260 },
    { id: "9",  name: "Jagdtrainingszentrum",            capacity: 100 },
    { id: "10", name: "Teehaus im Park",                 capacity: 30 }
  ].freeze

  BOOKINGS = [
    ["Helmholtz-Gemeinschaft",        "Strategieklausur",        "definite"],
    ["Stadtwerke Oranienburg",        "Führungskräfte-Workshop", "definite"],
    ["Hochzeit Sander / Bracht",      "Trauung & Empfang",       "definite"],
    ["DKB Stiftung",                  "Kuratoriumssitzung",      "definite"],
    ["Barmer Ersatzkasse",            "Regionaltagung",          "tentative"],
    ["Landesverband Brandenburg",     "Mitgliederversammlung",   "tentative"],
    ["Agentur Nordlicht",             "Jahresauftakt",           "lead"],
    ["Team Bundesliga Nachwuchs",     "Trainingslager",          "definite"],
    ["Kreisverwaltung OHV",           "Klausurtagung",           "tentative"],
    ["Familie Wernicke",              "Goldene Hochzeit",        "definite"],
    ["Deutsche Bahn Regio",           "Führungskreis",           "lead"],
    ["Naturschutzbund Brandenburg",   "Fachtag Moorschutz",      "definite"]
  ].freeze

  # Deterministische Pseudo-Belegung über den gewünschten Zeitraum.
  def self.events(from:, to:)
    rng = Random.new(20260906)
    out = []
    eid = 0

    (from..to).each do |day|
      # Wochenende: Feiern; Werktags: Tagungen
      weekend = [0, 6].include?(day.wday)
      slots = weekend ? 2 : 4

      SPACES.sample(slots, random: rng).each do |space|
        next if rng.rand > (weekend ? 0.55 : 0.75)

        kunde, titel, status = BOOKINGS[rng.rand(BOOKINGS.size)]
        mehrtaegig = !weekend && rng.rand < 0.25
        ende = mehrtaegig ? [day + 1, to].min : day

        start_h = weekend ? 14 : [8, 9, 9, 10, 13].sample(random: rng)
        dauer   = weekend ? 9 : [3, 4, 6, 8].sample(random: rng)

        eid += 1
        out << {
          id:           eid.to_s,
          name:         titel,
          status:       status,
          start_date:   day.to_s,
          end_date:     ende.to_s,
          start_time:   start_h * 3600,
          end_time:     [(start_h + dauer), 23].min * 3600,
          all_day:      false,
          expected:     [12, 18, 24, 40, 60, 90, 120].sample(random: rng),
          space_id:     space[:id],
          space_name:   space[:name],
          booking_id:   eid.to_s,
          booking_name: kunde
        }
      end
    end

    out
  end

  def self.spaces
    SPACES.map { |s| s.merge(area: nil, archived: false) }
  end
end
