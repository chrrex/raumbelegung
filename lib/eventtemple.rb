# frozen_string_literal: true

require "net/http"
require "json"
require "uri"
require "cgi"

# Schlanker Client für die Event Temple API v2 (JSON:API).
# Doku: https://developers.eventtemple.com/
module EventTemple
  BASE = "https://api.eventtemple.com/v2"

  class Error < StandardError; end

  class Client
    def initialize(api_key:, api_org:)
      @api_key = api_key
      @api_org = api_org
    end

    # Holt alle Seiten einer Collection und liefert [records, included_index].
    # included_index: { ["spaces", "42"] => {...}, ["bookings", "7"] => {...} }
    def get_all(path, params = {})
      records = []
      included = {}
      cursor = nil
      pages = 0

      loop do
        query = params.merge("page[size]" => 100)
        query["page[after]"] = cursor if cursor
        body = get(path, query)

        records.concat(Array(body["data"]))
        Array(body["included"]).each { |o| included[[o["type"], o["id"].to_s]] = o }

        meta = body["meta"] || {}
        cursor = meta["after_cursor"]
        pages += 1
        break unless meta["has_more"] && cursor
        raise Error, "Zu viele Seiten bei #{path} – Abbruch zur Sicherheit." if pages > 200
      end

      [records, included]
    end

    def get(path, params = {})
      uri = URI("#{BASE}#{path}")
      uri.query = encode(params) unless params.empty?

      req = Net::HTTP::Get.new(uri)
      req["X-API-KEY"] = @api_key
      req["X-API-ORG"] = @api_org
      req["Accept"]    = "application/vnd.api+json"

      res = Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                            open_timeout: 15, read_timeout: 60) { |http| http.request(req) }

      unless res.is_a?(Net::HTTPSuccess)
        raise Error, "GET #{uri} → HTTP #{res.code}\n#{res.body.to_s[0, 800]}"
      end

      JSON.parse(res.body)
    rescue JSON::ParserError => e
      raise Error, "Antwort von #{uri} ist kein JSON: #{e.message}"
    end

    private

    def encode(params)
      params.map { |k, v| "#{CGI.escape(k.to_s)}=#{CGI.escape(v.to_s)}" }.join("&")
    end
  end

  # --- Fachliche Abfragen -------------------------------------------------

  # Alle nicht archivierten Räume.
  def self.spaces(client)
    records, = client.get_all("/spaces")
    records.map { |r| normalize_space(r) }.reject { |s| s[:archived] }
  end

  # Alle Events, die den Zeitraum [from, to] berühren (inkl. mehrtägiger).
  # Filterlogik: start_date <= to UND end_date >= from
  def self.events(client, from:, to:)
    records, included = client.get_all(
      "/events",
      "include"                 => "space,booking,event_type",
      "filter[start_date][lteq]" => to.to_s,
      "filter[end_date][gteq]"   => from.to_s
    )
    records.map { |r| normalize_event(r, included) }
  end

  def self.normalize_space(record)
    a = record["attributes"] || {}
    {
      id:       record["id"].to_s,
      name:     a["name"].to_s,
      capacity: a["capacity"],
      area:     a["area"],
      archived: !a["archived_at"].nil?
    }
  end

  def self.normalize_event(record, included)
    a = record["attributes"] || {}
    rel = record["relationships"] || {}

    space_ref   = rel.dig("space", "data")
    booking_ref = rel.dig("booking", "data")
    typ_ref     = rel.dig("event_type", "data")
    booking     = booking_ref && included[["bookings", booking_ref["id"].to_s]]
    space       = space_ref && included[["spaces", space_ref["id"].to_s]]
    typ         = typ_ref && included[["event_types", typ_ref["id"].to_s]]

    {
      id:           record["id"].to_s,
      name:         a["name"].to_s,
      status:       a["status"].to_s,
      start_date:   a["start_date"],
      end_date:     a["end_date"] || a["start_date"],
      start_time:   a["start_time"],
      end_time:     a["end_time"],
      all_day:      a["all_day"],
      expected:     a["expected"],
      event_type:   typ && typ.dig("attributes", "value"),
      space_id:     space_ref && space_ref["id"].to_s,
      space_name:   space && space.dig("attributes", "name"),
      booking_id:   booking_ref && booking_ref["id"].to_s,
      booking_name: booking && booking.dig("attributes", "name")
    }
  end
end
