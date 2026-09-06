# frozen_string_literal: true

require "cgi"
require "date"
require "openssl"
require "base64"
require "json"

# Rendert die Wochenübersicht als eigenständige HTML-Datei.
module Render
  TAGE   = %w[Mo Di Mi Do Fr Sa So].freeze
  MONATE = %w[Januar Februar März April Mai Juni Juli August September Oktober November Dezember].freeze

  STATUS = {
    "definite"  => { label: "definitiv", css: "is-definite" },
    "tentative" => { label: "optional",  css: "is-tentative" },
    "lead"      => { label: "Anfrage",   css: "is-lead" },
    "lost"      => { label: "verloren",  css: "is-lost" }
  }.freeze

  module_function

  def h(s)
    CGI.escapeHTML(s.to_s)
  end

  def zeit(seconds)
    return nil if seconds.nil?
    m = (seconds.to_i / 60) % (24 * 60)
    format("%02d:%02d", m / 60, m % 60)
  end

  def zeitraum(von, bis)
    if von.month == bis.month
      "#{von.day}.–#{bis.day}. #{MONATE[von.month - 1]} #{von.year}"
    else
      "#{von.day}. #{MONATE[von.month - 1]} – #{bis.day}. #{MONATE[bis.month - 1]} #{bis.year}"
    end
  end

  def zeitraum_kurz(von, bis)
    format("%02d.%02d.–%02d.%02d.", von.day, von.month, bis.day, bis.month)
  end

  # --- Datenaufbereitung ---------------------------------------------------

  def gruppiere(spaces, gruppen_config)
    rest = spaces.dup
    gruppen = gruppen_config.map do |g|
      muster = Array(g["muster"]).map(&:downcase)
      treffer = rest.select { |s| muster.any? { |m| s[:name].to_s.downcase.include?(m) } }
      rest -= treffer
      { name: g["name"], rooms: treffer.sort_by { |s| s[:name].to_s } }
    end
    gruppen << { name: "Weitere Räume", rooms: rest.sort_by { |s| s[:name].to_s } } unless rest.empty?
    gruppen.reject { |g| g[:rooms].empty? }
  end

  def woche(start_montag, events, gruppen)
    tage = (0..6).map { |i| start_montag + i }

    zeilen = gruppen.each_with_index.map do |g, gi|
      rooms = g[:rooms].map do |space|
        zellen = tage.map do |tag|
          events.select do |e|
            e[:space_id].to_s == space[:id].to_s &&
              Date.parse(e[:start_date]) <= tag &&
              Date.parse(e[:end_date]) >= tag
          end.sort_by { |e| [e[:start_time] || -1, e[:name].to_s] }
        end
        { space: space, zellen: zellen, belegt: zellen.flatten.size }
      end
      { name: g[:name], index: gi, rooms: rooms }
    end

    {
      start:         start_montag,
      ende:          start_montag + 6,
      kw:            start_montag.cweek,
      tage:          tage,
      zeilen:        zeilen,
      anzahl:        zeilen.sum { |z| z[:rooms].sum { |r| r[:belegt] } },
      raeume:        zeilen.sum { |z| z[:rooms].size },
      raeume_belegt: zeilen.sum { |z| z[:rooms].count { |r| r[:belegt] > 0 } }
    }
  end

  # --- Bausteine -----------------------------------------------------------

  def logo_svg(pfad, klasse)
    return "" unless File.exist?(pfad)
    svg = File.read(pfad).sub(/<\?xml.*?\?>/m, "").strip
    svg = svg.gsub("#6b7525", "currentColor")
    svg.sub("<svg", %(<svg class="#{klasse}" role="img" aria-label="Schloss & Gut Liebenberg" focusable="false"))
  end

  def event_chip(ev, tag)
    st = STATUS[ev[:status]] || STATUS["lead"]
    beginnt = Date.parse(ev[:start_date]) == tag
    endet   = Date.parse(ev[:end_date]) == tag

    zeile_zeit =
      if !beginnt && !endet then "läuft weiter"
      elsif !beginnt then "bis #{zeit(ev[:end_time]) || 'Ende'}"
      elsif ev[:all_day] || ev[:start_time].nil? then "ganztägig"
      elsif !endet then "ab #{zeit(ev[:start_time])}"
      else "#{zeit(ev[:start_time])}–#{zeit(ev[:end_time])}"
      end

    titel = [ev[:booking_name], ev[:name]].compact.map(&:to_s).map(&:strip).reject(&:empty?)
    haupt = titel.first || "Ohne Namen"
    neben = titel[1]

    out = +%(<article lang="de" class="ev #{st[:css]}#{beginnt ? '' : ' ev--fortsetzung'}">)
    out << %(<span class="ev-time">#{h(zeile_zeit)}</span>)
    out << %(<span class="ev-name">#{h(haupt)}</span>)
    out << %(<span class="ev-sub">#{h(neben)}</span>) if neben
    out << %(<span class="ev-meta"><span class="ev-status">#{h(st[:label])}</span>)
    out << %(<span class="ev-typ">#{h(ev[:event_type])}</span>) if ev[:event_type].to_s.strip != ""
    out << "</span>"
    out << "</article>"
    out
  end

  def woche_tabelle(w, heute)
    out = +%(<div class="grid-scroll"><table class="grid">)
    out << %(<caption class="sr-only">Raumbelegung KW #{w[:kw]}, #{h(zeitraum(w[:start], w[:ende]))}</caption>)
    out << %(<thead><tr><th scope="col" class="col-room">Raum</th>)

    w[:tage].each_with_index do |t, i|
      klassen = ["col-day"]
      klassen << "is-weekend" if i >= 5
      klassen << "is-today" if t == heute
      out << %(<th scope="col" class="#{klassen.join(' ')}">)
      out << %(<span class="day-name">#{TAGE[i]}</span>)
      out << %(<span class="day-date">#{format('%02d.%02d.', t.day, t.month)}</span>)
      out << %(<span class="day-today">heute</span>) if t == heute
      out << "</th>"
    end
    out << "</tr></thead>"

    w[:zeilen].each do |gruppe|
      belegte = gruppe[:rooms].count { |r| r[:belegt] > 0 }
      out << %(<tbody class="group" data-group="#{gruppe[:index]}">)
      out << %(<tr class="group-row" data-group="#{gruppe[:index]}"><th scope="colgroup" colspan="8">)
      out << %(#{h(gruppe[:name])}<span class="group-count">#{belegte}/#{gruppe[:rooms].size} belegt</span>)
      out << "</th></tr>"

      gruppe[:rooms].each do |r|
        klassen = ["room-row"]
        klassen << "row-frei" if r[:belegt].zero?
        out << %(<tr class="#{klassen.join(' ')}" data-room="#{h(r[:space][:id])}" data-group="#{gruppe[:index]}" data-belegt="#{r[:belegt]}">)
        out << %(<th scope="row" class="col-room"><span class="room-name">#{h(r[:space][:name])}</span>)
        kap = r[:space][:capacity].to_i
        out << %(<span class="room-meta">bis #{kap} Pers.</span>) if kap > 0 && kap < 500
        out << "</th>"

        r[:zellen].each_with_index do |evs, i|
          zk = ["cell"]
          zk << "is-weekend" if i >= 5
          zk << "is-today" if w[:tage][i] == heute
          zk << "is-free" if evs.empty?
          out << %(<td class="#{zk.join(' ')}">)
          evs.each { |ev| out << event_chip(ev, w[:tage][i]) }
          out << "</td>"
        end
        out << "</tr>"
      end
      out << "</tbody>"
    end

    out << "</table></div>"
    out
  end

  def filterleiste(gruppen, raeume_gesamt)
    out = +%(<div class="filterbar"><details class="filter" id="raumfilter">)
    out << %(<summary><span class="filter-title">Räume filtern</span>)
    out << %(<span class="filter-count" id="filter-count">alle #{raeume_gesamt} Räume sichtbar</span></summary>)
    out << %(<div class="filter-body">)
    out << %(<div class="filter-actions">)
    out << %(<button type="button" class="btn" data-aktion="alle">Alle Räume</button>)
    out << %(<button type="button" class="btn" data-aktion="keine">Keinen Raum</button>)
    out << %(<button type="button" class="btn" data-aktion="belegt">Nur in dieser Woche belegte</button>)
    out << %(<button type="button" class="btn" data-aktion="zuruecksetzen">Auswahl zurücksetzen</button>)
    out << "</div>"

    out << %(<div class="filter-groups">)
    gruppen.each_with_index do |g, gi|
      out << %(<fieldset class="filter-group"><legend>)
      out << %(<label class="check check--gruppe"><input type="checkbox" class="gruppe-check" data-group="#{gi}" checked>)
      out << %(<span>#{h(g[:name])}</span></label></legend>)
      g[:rooms].each do |s|
        out << %(<label class="check"><input type="checkbox" class="raum-check" data-group="#{gi}" data-room="#{h(s[:id])}" checked>)
        out << %(<span>#{h(s[:name])}</span></label>)
      end
      out << "</fieldset>"
    end
    out << "</div></div></details></div>"
    out
  end

  # --- Seite ---------------------------------------------------------------

  def page(wochen:, gruppen:, generated_at:, logo_pfad:, quelle:, passwort: nil, heute: Date.today)
    logo  = logo_svg(logo_pfad, "logo")
    stand = generated_at.strftime("%d.%m.%Y, %H:%M Uhr")
    aktiv = wochen.index { |w| heute.between?(w[:start], w[:ende]) } || 0
    raeume_gesamt = gruppen.sum { |g| g[:rooms].size }

    tabs = wochen.each_with_index.map do |w, i|
      sel = i == aktiv
      %(<button type="button" role="tab" id="tab-#{i}" aria-controls="woche-#{i}" ) +
        %(aria-selected="#{sel}" tabindex="#{sel ? 0 : -1}" class="tab#{sel ? ' is-active' : ''}">) +
        %(<span class="tab-kw">KW #{w[:kw]}</span>) +
        %(<span class="tab-range">#{h(zeitraum_kurz(w[:start], w[:ende]))}</span></button>)
    end.join

    panels = wochen.each_with_index.map do |w, i|
      %(<section class="woche" id="woche-#{i}" role="tabpanel" aria-labelledby="tab-#{i}"#{i == aktiv ? '' : ' hidden'}>) +
        %(<div class="woche-head"><h2>KW #{w[:kw]}</h2>) +
        %(<p>#{h(zeitraum(w[:start], w[:ende]))} · <strong>#{w[:raeume_belegt]} von #{w[:raeume]} Räumen belegt</strong> · #{w[:anzahl]} Belegungen</p></div>) +
        woche_tabelle(w, heute) + "</section>"
    end.join

    kopf = <<~HTML
      <meta charset="utf-8">
      <meta name="sgl-stand" content="#{generated_at.strftime(%q(%Y-%m-%dT%H:%M:%S%z))}">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>Raumbelegung Liebenberg</title>
      <link rel="preconnect" href="https://fonts.googleapis.com">
      <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
      <link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Source+Sans+3:ital,wght@0,300;0,400;0,600;0,700;1,400&display=swap">
      <style>#{css}</style>
    HTML

    inhalt = <<~HTML
      <a class="skip" href="#inhalt">Zur Übersicht springen</a>

      <header class="masthead">
        <div class="masthead-inner">
          <div class="brand">#{logo}</div>
          <div class="masthead-text">
            <p class="eyebrow">Schloss &amp; Gut Liebenberg</p>
            <h1>Raumbelegung der Woche</h1>
          </div>
          <dl class="stand">
            <dt>Stand</dt><dd>#{h(stand)}</dd>
            <dt>Quelle</dt><dd>#{h(quelle)}</dd>
<div class="mast-actions">
  <button type="button" class="btn-reload" id="drucken">Drucken / PDF</button>
  <button type="button" class="btn-reload" id="reload">Daten aktualisieren</button>
</div>
          </dl>
        </div>
      </header>

      <nav class="tabs" role="tablist" aria-label="Woche wählen">#{tabs}</nav>

      #{filterleiste(gruppen, raeume_gesamt)}

<div class="print-head" aria-hidden="true">
  <div class="print-brand">
    <span class="print-title">Raumbelegung · Schloss &amp; Gut Liebenberg</span>
    <span class="print-meta">Stand #{h(stand)} · <span id="print-umfang"></span></span>
  </div>
  <div class="print-legend">
    <span class="key"><i class="swatch is-definite"></i>definitiv</span>
    <span class="key"><i class="swatch is-tentative"></i>optional</span>
    <span class="key"><i class="swatch is-lead"></i>Anfrage</span>
  </div>
</div>

<main id="inhalt">#{panels}</main>

<dialog id="druck-dialog" class="druck" aria-labelledby="druck-titel">
  <form method="dialog" id="druck-form">
    <h2 id="druck-titel">Drucken oder als PDF sichern</h2>

    <fieldset>
      <legend>Welche Räume?</legend>
      <label class="check"><input type="radio" name="umfang" value="gefiltert" checked><span>Nur die aktuell gefilterten Räume <b id="druck-n-gefiltert"></b></span></label>
      <label class="check"><input type="radio" name="umfang" value="belegt"><span>Nur belegte Räume <b>(je Woche verschieden)</b></span></label>
      <label class="check"><input type="radio" name="umfang" value="alle"><span>Alle Räume <b id="druck-n-alle"></b></span></label>
    </fieldset>

    <fieldset>
      <legend>Welcher Zeitraum?</legend>
      <label class="check"><input type="radio" name="zeit" value="woche" checked><span>Nur die angezeigte Woche <b id="druck-kw"></b></span></label>
      <label class="check"><input type="radio" name="zeit" value="alle"><span>Alle <b id="druck-n-wochen"></b> Wochen, je eine Seite</span></label>
    </fieldset>

    <p class="druck-hinweis">Es öffnet sich der Druckdialog des Browsers. Dort „Als PDF sichern“ wählen – das Layout ist auf A4 quer eingestellt. Damit die Farben mitkommen, im Druckdialog „Hintergrundgrafiken“ aktivieren.</p>

    <menu>
      <button type="submit" value="abbruch" class="btn">Abbrechen</button>
      <button type="submit" value="drucken" class="btn btn--primary">Drucken …</button>
    </menu>
  </form>
  <div class="druck-notausgang" id="druck-notausgang" hidden>
    <h2>Drucken wird hier unterbunden</h2>
    <p>Diese Übersicht läuft in einem abgeschirmten Rahmen, der den Druckbefehl einer Seite nicht zulässt. Das lässt sich von hier aus nicht umgehen. Zwei Wege führen trotzdem zum PDF:</p>
    <ol>
      <li><b>⌘P direkt im Browser drücken.</b> Die eben getroffene Auswahl ist bereits angewendet. Ob das gelingt, hängt von der Ansicht ab – einen Versuch ist es wert.</li>
      <li><b>Auf dem Rechner erzeugen.</b> Im Ordner <code>wochenuebersicht</code> auf <code>Raumbelegung als PDF.command</code> doppelklicken. Das liefert immer ein sauberes PDF im Querformat.</li>
    </ol>
    <menu><button type="button" class="btn btn--primary" id="notausgang-ok">Verstanden</button></menu>
  </div>
</dialog>

      <footer class="footer">
        <div class="legend">
          <span class="legend-title">Legende</span>
          <span class="key"><i class="swatch is-definite"></i>definitiv</span>
          <span class="key"><i class="swatch is-tentative"></i>optional</span>
          <span class="key"><i class="swatch is-lead"></i>Anfrage</span>
          <span class="key"><i class="swatch is-free"></i>frei</span>
        </div>
        <p class="footnote">Daten aus Event Temple. Änderungen bitte dort pflegen – diese Seite spiegelt nur.<br>Ein Wirkungsort der DKB STIFTUNG.</p>
      </footer>

    HTML

    tor(kopf, inhalt, passwort)
  end


# Setzt Kopf und Inhalt zusammen. Ohne Passwort steht der Inhalt direkt in
# der Datei; mit Passwort liegt er nur verschlüsselt vor (AES-256-CBC mit
# HMAC-SHA256, Schlüssel aus PBKDF2) und wird erst im Browser entschlüsselt.
def tor(kopf, inhalt, passwort)
  if passwort.to_s.empty?
    kopf + %(<div id="app">\n) + inhalt + %(</div>\n<script>#{js}\nwindow.starteApp();</script>\n)
  else
    # AES-256-CBC mit anschließender HMAC-Prüfung (encrypt-then-MAC).
    # Bewusst nicht GCM: das LibreSSL des System-Rubys kann es nicht.
    salt = OpenSSL::Random.random_bytes(16)
    iv   = OpenSSL::Random.random_bytes(16)
    iter = 250_000
    roh  = OpenSSL::PKCS5.pbkdf2_hmac(passwort, salt, iter, 64, "sha256")
    schluessel_chiffre = roh[0, 32]
    schluessel_mac     = roh[32, 32]

    c = OpenSSL::Cipher.new("aes-256-cbc").encrypt
    c.key = schluessel_chiffre
    c.iv  = iv
    geheim = c.update(inhalt) + c.final
    mac = OpenSSL::HMAC.digest("SHA256", schluessel_mac, iv + geheim)

    tresor = {
      "salt" => Base64.strict_encode64(salt),
      "iv"   => Base64.strict_encode64(iv),
      "iter" => iter,
      "data" => Base64.strict_encode64(geheim),
      "mac"  => Base64.strict_encode64(mac)
    }

    kopf + schloss_html +
      %(<div id="app" hidden></div>\n) +
      %(<script type="application/json" id="tresor">#{tresor.to_json}</script>\n) +
      %(<script>#{js}\n#{schloss_js}</script>\n)
  end
end

def schloss_html
  <<~HTML
    <div class="tor" id="tor">
      <form class="tor-box" id="tor-form" autocomplete="on">
        <p class="tor-eyebrow">Schloss &amp; Gut Liebenberg</p>
        <h1 class="tor-titel">Raumbelegung</h1>
        <p class="tor-text">Diese Übersicht ist geschützt. Bitte das Passwort eingeben.</p>
        <label class="tor-feld" for="tor-pw">Passwort</label>
        <input class="tor-input" type="password" id="tor-pw" name="password" autocomplete="current-password" required>
        <p class="tor-fehler" id="tor-fehler" hidden>Das Passwort stimmt nicht.</p>
        <button type="submit" class="tor-knopf" id="tor-knopf">Öffnen</button>
      </form>
    </div>
  HTML
end

def schloss_js
  <<~JS
    (function () {
      var tor    = document.getElementById('tor');
      var form   = document.getElementById('tor-form');
      var feld   = document.getElementById('tor-pw');
      var fehler = document.getElementById('tor-fehler');
      var knopf  = document.getElementById('tor-knopf');
      var tresor = JSON.parse(document.getElementById('tresor').textContent);
      var app    = document.getElementById('app');

      function bytes(b64) {
        var roh = window.atob(b64);
        var feldchen = new Uint8Array(roh.length);
        for (var i = 0; i < roh.length; i++) feldchen[i] = roh.charCodeAt(i);
        return feldchen;
      }

      if (!window.crypto || !window.crypto.subtle) {
        fehler.textContent = 'Dieser Browser kann die Seite hier nicht entschlüsseln. Das geht nur über eine https-Adresse.';
        fehler.hidden = false;
        knopf.disabled = true;
        return;
      }

      function oeffnen(passwort) {
        var enc = new TextEncoder();
        var iv = bytes(tresor.iv);
        var daten = bytes(tresor.data);
        var signiert = new Uint8Array(iv.length + daten.length);
        signiert.set(iv, 0);
        signiert.set(daten, iv.length);

        return window.crypto.subtle
          .importKey('raw', enc.encode(passwort), 'PBKDF2', false, ['deriveBits'])
          .then(function (basis) {
            return window.crypto.subtle.deriveBits(
              { name: 'PBKDF2', salt: bytes(tresor.salt), iterations: tresor.iter, hash: 'SHA-256' },
              basis, 512
            );
          })
          .then(function (roh) {
            var alle = new Uint8Array(roh);
            var chiffre = alle.slice(0, 32);
            var macRoh = alle.slice(32, 64);
            return window.crypto.subtle
              .importKey('raw', macRoh, { name: 'HMAC', hash: 'SHA-256' }, false, ['verify'])
              .then(function (macKey) {
                return window.crypto.subtle.verify('HMAC', macKey, bytes(tresor.mac), signiert);
              })
              .then(function (stimmt) {
                if (!stimmt) throw new Error('Passwort stimmt nicht');
                return window.crypto.subtle.importKey('raw', chiffre, { name: 'AES-CBC' }, false, ['decrypt']);
              });
          })
          .then(function (schluessel) {
            return window.crypto.subtle.decrypt({ name: 'AES-CBC', iv: iv }, schluessel, daten);
          })
          .then(function (klar) {
            app.innerHTML = new TextDecoder().decode(klar);
            app.hidden = false;
            if (tor && tor.parentNode) tor.parentNode.removeChild(tor);
            window.starteApp();
          });
      }

      form.addEventListener('submit', function (e) {
        e.preventDefault();
        fehler.hidden = true;
        knopf.disabled = true;
        knopf.textContent = 'Wird geöffnet …';
        var eingabe = feld.value;
        oeffnen(eingabe)
          .then(function () {
            try { window.sessionStorage.setItem('sgl-tor', eingabe); } catch (x) { /* egal */ }
          })
          .catch(function () {
            fehler.hidden = false;
            knopf.disabled = false;
            knopf.textContent = 'Öffnen';
            feld.select();
          });
      });

      var gemerkt = null;
      try { gemerkt = window.sessionStorage.getItem('sgl-tor'); } catch (x) { /* egal */ }
      if (gemerkt) {
        oeffnen(gemerkt).catch(function () {
          try { window.sessionStorage.removeItem('sgl-tor'); } catch (y) { /* egal */ }
          feld.focus();
        });
      } else {
        feld.focus();
      }
    })();
  JS
end

  # --- CSS -----------------------------------------------------------------

  def css
    <<~CSS
      :root {
        --ground:      #FBFAF5;
        --surface:     #FFFFFF;
        --surface-alt: #F5F4EB;
        --ink:         #23281C;
        --ink-soft:    #4E5544;
        --ink-muted:   #7A806D;
        --line:        #E0DED0;
        --line-soft:   #EDEBE0;
        --gruen:       #6B7A3E;
        --gruen-tief:  #4E5A2B;
        --gruen-tint:  #EBEFDE;
        --gold:        #A87F2E;
        --gold-tint:   #F7EFDD;
        --grau:        #7E8471;
        --grau-tint:   #F0EFE6;
        --heute:       #A04050;
        --radius: 3px;
        color-scheme: light;
      }
      @media (prefers-color-scheme: dark) {
        :root:not([data-theme="light"]) {
          --ground:      #15180F;
          --surface:     #1D2116;
          --surface-alt: #23271A;
          --ink:         #EAEADD;
          --ink-soft:    #C3C6B2;
          --ink-muted:   #949A83;
          --line:        #343925;
          --line-soft:   #2A2E1E;
          --gruen:       #A3B562;
          --gruen-tief:  #C2D086;
          --gruen-tint:  #2B3319;
          --gold:        #D4AC63;
          --gold-tint:   #2E2716;
          --grau:        #9AA087;
          --grau-tint:   #24281B;
          --heute:       #D98A96;
          color-scheme: dark;
        }
      }
      :root[data-theme="dark"] {
        --ground:      #15180F;
        --surface:     #1D2116;
        --surface-alt: #23271A;
        --ink:         #EAEADD;
        --ink-soft:    #C3C6B2;
        --ink-muted:   #949A83;
        --line:        #343925;
        --line-soft:   #2A2E1E;
        --gruen:       #A3B562;
        --gruen-tief:  #C2D086;
        --gruen-tint:  #2B3319;
        --gold:        #D4AC63;
        --gold-tint:   #2E2716;
        --grau:        #9AA087;
        --grau-tint:   #24281B;
        --heute:       #D98A96;
        color-scheme: dark;
      }

      * { box-sizing: border-box; }
      body {
        margin: 0;
        background: var(--ground);
        color: var(--ink);
        font-family: "Source Sans 3", "Source Sans Pro", -apple-system, BlinkMacSystemFont, "Segoe UI", Arial, sans-serif;
        font-size: 15px; line-height: 1.45;
        -webkit-font-smoothing: antialiased;
      }
      .sr-only {
        position: absolute; width: 1px; height: 1px; padding: 0; margin: -1px;
        overflow: hidden; clip: rect(0 0 0 0); white-space: nowrap; border: 0;
      }
      .skip { position: absolute; left: -9999px; top: 0; z-index: 30; background: var(--gruen); color: #fff; padding: 10px 16px; }
      .skip:focus { left: 8px; top: 8px; }
      :focus-visible { outline: 2px solid var(--gruen); outline-offset: 2px; }

      /* --- Passwortabfrage --- */
      .tor {
        min-height: 100vh; display: flex; align-items: center; justify-content: center;
        padding: 32px 20px; background: var(--gruen-tief);
      }
      .tor-box {
        width: 100%; max-width: 340px;
        display: flex; flex-direction: column; gap: 4px;
        background: var(--surface); color: var(--ink);
        border-radius: var(--radius); padding: 30px 28px 26px;
        box-shadow: 0 20px 50px rgba(20, 24, 15, .3);
      }
      .tor-eyebrow {
        margin: 0; font-size: 10.5px; font-weight: 600;
        letter-spacing: .16em; text-transform: uppercase; color: var(--ink-muted);
      }
      .tor-titel { margin: 2px 0 0; font-size: 24px; font-weight: 300; color: var(--gruen); }
      .tor-text { margin: 10px 0 18px; font-size: 13.5px; line-height: 1.45; color: var(--ink-soft); }
      .tor-feld {
        font-size: 10.5px; font-weight: 700; letter-spacing: .12em;
        text-transform: uppercase; color: var(--ink-muted); margin-bottom: 5px;
      }
      .tor-input {
        font: inherit; font-size: 15px; color: var(--ink);
        background: var(--ground); border: 1px solid var(--line);
        border-radius: var(--radius); padding: 9px 11px; width: 100%;
      }
      .tor-input:focus-visible { border-color: var(--gruen); }
      .tor-fehler {
        margin: 9px 0 0; font-size: 12.5px; line-height: 1.4; color: #A04050;
      }
      .tor-knopf {
        appearance: none; cursor: pointer; font: inherit; font-size: 14px; font-weight: 600;
        margin-top: 18px; padding: 9px 14px;
        background: var(--gruen); color: #fff;
        border: 1px solid var(--gruen); border-radius: var(--radius);
      }
      .tor-knopf:hover { background: var(--gruen-tief); border-color: var(--gruen-tief); }
      .tor-knopf[disabled] { opacity: .6; cursor: default; }

      /* --- Kopf --- */
      .masthead { background: var(--gruen-tief); color: #F3F2E8; }
      .masthead-inner {
        max-width: 1440px; margin: 0 auto;
        display: flex; align-items: center; gap: 28px;
        padding: 22px 28px; flex-wrap: wrap;
      }
      .brand { padding: 18px; color: #FFFFFF; flex: none; }   /* Schutzraum: 72px x 0.25 */
      .logo { width: 72px; height: auto; display: block; }
      .masthead-text { flex: 1 1 240px; }
      .eyebrow {
        margin: 0 0 2px; font-size: 11px; font-weight: 600;
        letter-spacing: .16em; text-transform: uppercase; color: #C6CDA5;
      }
      .masthead h1 { margin: 0; font-size: 26px; font-weight: 300; text-wrap: balance; }
      .stand {
        margin: 0; flex: none; display: grid; grid-template-columns: auto auto;
        gap: 2px 12px; font-size: 12.5px; align-content: center;
      }
      .stand dt { color: #B8C199; text-transform: uppercase; letter-spacing: .1em; font-size: 10.5px; padding-top: 2px; }
      .stand dd { margin: 0; font-variant-numeric: tabular-nums; }
      .mast-actions { grid-column: 1 / -1; display: flex; gap: 8px; margin-top: 9px; flex-wrap: wrap; }
      .btn-reload {
        appearance: none; cursor: pointer; font: inherit; font-size: 12px;
        color: #F3F2E8; background: transparent;
        border: 1px solid rgba(243,242,232,.45); border-radius: var(--radius);
        padding: 4px 11px; white-space: nowrap;
      }
      .btn-reload:hover { background: rgba(243,242,232,.12); border-color: #F3F2E8; }

      /* --- Wochenreiter --- */
      .tabs {
        position: sticky; top: 0; z-index: 12;
        display: flex; overflow-x: auto;
        background: var(--surface); border-bottom: 1px solid var(--line);
        padding: 0 28px; max-width: 1440px; margin: 0 auto; scrollbar-width: thin;
      }
      .tab {
        appearance: none; border: 0; background: none; cursor: pointer; font: inherit;
        color: var(--ink-muted); padding: 10px 14px 8px; flex: none;
        display: flex; flex-direction: column; align-items: flex-start; gap: 1px;
        border-bottom: 2px solid transparent; white-space: nowrap;
      }
      .tab-kw { font-weight: 600; font-size: 13px; letter-spacing: .08em; text-transform: uppercase; }
      .tab-range { font-size: 11.5px; font-variant-numeric: tabular-nums; }
      .tab:hover { color: var(--ink); background: var(--surface-alt); }
      .tab.is-active { color: var(--gruen); border-bottom-color: var(--gruen); }
      .tab.is-active .tab-range { color: var(--ink-soft); }

      /* --- Filter --- */
      .filterbar { max-width: 1440px; margin: 0 auto; padding: 0 28px; }
      .filter {
        border: 1px solid var(--line); border-radius: var(--radius);
        background: var(--surface); margin-top: 16px;
      }
      .filter > summary {
        cursor: pointer; list-style: none; padding: 10px 14px;
        display: flex; align-items: baseline; gap: 12px; flex-wrap: wrap;
      }
      .filter > summary::-webkit-details-marker { display: none; }
      .filter > summary::before {
        content: "›"; display: inline-block; font-size: 17px; line-height: 1;
        color: var(--gruen); transform: rotate(0deg); transition: transform .15s;
      }
      .filter[open] > summary::before { transform: rotate(90deg); }
      .filter-title { font-size: 12px; font-weight: 700; letter-spacing: .14em; text-transform: uppercase; color: var(--gruen); }
      .filter-count { font-size: 12.5px; color: var(--ink-muted); font-variant-numeric: tabular-nums; }
      .filter-body { padding: 4px 14px 16px; border-top: 1px solid var(--line-soft); }
      .filter-actions { display: flex; gap: 8px; flex-wrap: wrap; padding: 12px 0 14px; }
      .filter-groups {
        display: grid; gap: 18px 26px;
        grid-template-columns: repeat(auto-fill, minmax(215px, 1fr));
      }
      .filter-group { border: 0; margin: 0; padding: 0; min-width: 0; }
      .filter-group legend { padding: 0 0 5px; }
      .check { display: flex; align-items: flex-start; gap: 7px; font-size: 13px; padding: 2px 0; cursor: pointer; line-height: 1.3; }
      .check input { margin: 2px 0 0; accent-color: var(--gruen); flex: none; }
      .check--gruppe { font-size: 11px; font-weight: 700; letter-spacing: .12em; text-transform: uppercase; color: var(--gruen); }
      .check span { overflow-wrap: anywhere; }

      .btn {
        appearance: none; cursor: pointer; font: inherit; font-size: 12.5px;
        color: var(--ink-soft); background: var(--surface);
        border: 1px solid var(--line); border-radius: var(--radius);
        padding: 5px 12px; white-space: nowrap;
      }
      .btn:hover { border-color: var(--gruen); color: var(--gruen); }

      /* --- Druckdialog --- */
      dialog.druck {
        border: 1px solid var(--line); border-radius: var(--radius);
        background: var(--surface); color: var(--ink);
        padding: 0; max-width: 460px; width: calc(100% - 32px);
        box-shadow: 0 18px 48px rgba(20, 24, 15, .28);
      }
      dialog.druck::backdrop { background: rgba(20, 24, 15, .45); }
      dialog.druck form { padding: 20px 22px 16px; display: flex; flex-direction: column; gap: 16px; }
      dialog.druck h2 {
        margin: 0; font-size: 13px; font-weight: 700;
        letter-spacing: .14em; text-transform: uppercase; color: var(--gruen);
      }
      dialog.druck fieldset { border: 0; margin: 0; padding: 0; display: flex; flex-direction: column; gap: 4px; }
      dialog.druck legend {
        padding: 0 0 6px; font-size: 11px; font-weight: 700;
        letter-spacing: .1em; text-transform: uppercase; color: var(--ink-muted);
      }
      dialog.druck .check { font-size: 13.5px; align-items: baseline; }
      dialog.druck .check b { font-weight: 400; color: var(--ink-muted); font-variant-numeric: tabular-nums; }
      .druck-hinweis {
        margin: 0; font-size: 12px; line-height: 1.4; color: var(--ink-muted);
        border-left: 2px solid var(--line); padding-left: 10px;
      }
      dialog.druck menu {
        margin: 0; padding: 12px 0 0; list-style: none;
        display: flex; gap: 8px; justify-content: flex-end;
        border-top: 1px solid var(--line-soft);
      }
      .btn--primary { background: var(--gruen); border-color: var(--gruen); color: #fff; font-weight: 600; }
      .btn--primary:hover { background: var(--gruen-tief); border-color: var(--gruen-tief); color: #fff; }

      .druck-notausgang { padding: 20px 22px 16px; display: flex; flex-direction: column; gap: 14px; }
      .druck-notausgang h2 {
        margin: 0; font-size: 13px; font-weight: 700;
        letter-spacing: .14em; text-transform: uppercase; color: var(--gold);
      }
      .druck-notausgang p { margin: 0; font-size: 13.5px; line-height: 1.45; }
      .druck-notausgang ol { margin: 0; padding-left: 20px; display: flex; flex-direction: column; gap: 8px; }
      .druck-notausgang li { font-size: 13px; line-height: 1.45; }
      .druck-notausgang code {
        font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 12px;
        background: var(--surface-alt); border: 1px solid var(--line-soft);
        border-radius: 2px; padding: 1px 4px;
      }
      .druck-notausgang menu {
        margin: 0; padding: 10px 0 0; list-style: none;
        display: flex; justify-content: flex-end; border-top: 1px solid var(--line-soft);
      }

      /* --- Kopfzeile, die nur auf Papier erscheint --- */
      .print-head { display: none; }

      /* --- Woche --- */
      main { max-width: 1440px; margin: 0 auto; padding: 0 28px 8px; }
      .woche-head { display: flex; align-items: baseline; gap: 14px; flex-wrap: wrap; padding: 22px 0 14px; }
      .woche-head h2 { margin: 0; font-size: 13px; font-weight: 700; letter-spacing: .14em; text-transform: uppercase; color: var(--gruen); }
      .woche-head p { margin: 0; color: var(--ink-muted); font-size: 13.5px; }
      .woche-head strong { color: var(--ink-soft); font-weight: 600; }

      .grid-scroll { overflow-x: auto; border: 1px solid var(--line); background: var(--surface); border-radius: var(--radius); }
      table.grid { border-collapse: collapse; width: 100%; min-width: 1000px; }

      thead th {
        position: sticky; top: 0; z-index: 3;
        background: var(--surface-alt); border-bottom: 1px solid var(--line);
        padding: 9px 10px; text-align: left; vertical-align: bottom; font-weight: 400;
      }
      thead th.col-day { width: 12.7%; }
      .day-name { display: block; font-size: 11px; font-weight: 700; letter-spacing: .14em; text-transform: uppercase; color: var(--ink-soft); }
      .day-date { display: block; font-size: 13px; color: var(--ink-muted); font-variant-numeric: tabular-nums; }
      .day-today { display: inline-block; margin-top: 3px; font-size: 10px; font-weight: 700; letter-spacing: .1em; text-transform: uppercase; color: var(--heute); }
      thead th.is-weekend { background: var(--grau-tint); }
      thead th.is-today { box-shadow: inset 0 -2px 0 var(--heute); }

      th.col-room {
        position: sticky; left: 0; z-index: 4;
        background: var(--surface-alt); width: 190px; min-width: 190px;
        text-align: left; border-right: 1px solid var(--line);
      }
      tbody th.col-room { background: var(--surface); vertical-align: top; padding: 10px; }
      .room-name { display: block; font-weight: 600; font-size: 14px; line-height: 1.25; }
      .room-meta { display: block; font-size: 11.5px; color: var(--ink-muted); font-variant-numeric: tabular-nums; }

      .group-row th {
        position: sticky; left: 0;
        background: var(--gruen-tint); color: var(--gruen-tief);
        font-size: 11px; font-weight: 700; letter-spacing: .16em; text-transform: uppercase;
        padding: 6px 10px; text-align: left;
        border-top: 1px solid var(--line); border-bottom: 1px solid var(--line);
      }
      .group-count { margin-left: 12px; font-weight: 400; font-size: 11px; letter-spacing: .04em; text-transform: none; color: var(--ink-muted); font-variant-numeric: tabular-nums; }

      td.cell { border-left: 1px solid var(--line-soft); border-top: 1px solid var(--line-soft); padding: 5px; vertical-align: top; }
      td.cell.is-weekend { background: var(--grau-tint); }
      td.cell.is-today { background: color-mix(in srgb, var(--heute) 5%, transparent); }
      tbody tr:hover td.cell { background: var(--surface-alt); }
      tr.row-frei th.col-room .room-name { font-weight: 400; color: var(--ink-muted); }

      /* --- Belegung --- */
      .ev {
        display: flex; flex-direction: column;
        padding: 5px 7px; margin-bottom: 4px;
        border-radius: var(--radius); border-left: 3px solid var(--gruen);
        background: var(--gruen-tint); font-size: 12.5px;
      }
      .ev:last-child { margin-bottom: 0; }
      .ev-time { font-size: 11px; font-weight: 600; letter-spacing: .04em; font-variant-numeric: tabular-nums; color: var(--ink-soft); }
      .ev-name { font-weight: 600; line-height: 1.25; overflow-wrap: break-word; hyphens: auto; }
      .ev-sub { color: var(--ink-muted); line-height: 1.25; overflow-wrap: break-word; hyphens: auto; }
      .ev-meta { display: flex; align-items: baseline; gap: 6px; flex-wrap: wrap; margin-top: 3px; }
      .ev-typ { font-size: 10.5px; color: var(--ink-muted); overflow-wrap: anywhere; }
      .ev-typ::before { content: "·"; margin-right: 5px; }
      .ev-status { font-size: 10px; font-weight: 700; letter-spacing: .1em; text-transform: uppercase; }
      .ev.is-definite { border-left-color: var(--gruen); background: var(--gruen-tint); }
      .ev.is-definite .ev-status { color: var(--gruen-tief); }
      .ev.is-tentative { border-left-color: var(--gold); background: var(--gold-tint); }
      .ev.is-tentative .ev-status { color: var(--gold); }
      .ev.is-lead { border-left-style: dashed; border-left-color: var(--grau); background: transparent; box-shadow: inset 0 0 0 1px var(--line); }
      .ev.is-lead .ev-status { color: var(--grau); }
      .ev--fortsetzung .ev-time { font-style: italic; font-weight: 400; color: var(--ink-muted); }

      /* --- Fuß --- */
      .footer {
        max-width: 1440px; margin: 18px auto 0; padding: 20px 28px 40px;
        display: flex; gap: 20px 40px; flex-wrap: wrap;
        align-items: flex-start; justify-content: space-between;
        border-top: 1px solid var(--line);
      }
      .legend { display: flex; gap: 16px; align-items: center; flex-wrap: wrap; }
      .legend-title { font-size: 10.5px; font-weight: 700; letter-spacing: .16em; text-transform: uppercase; color: var(--ink-muted); }
      .key { display: inline-flex; align-items: center; gap: 6px; font-size: 12.5px; color: var(--ink-soft); }
      .swatch { width: 14px; height: 14px; border-radius: 2px; display: inline-block; }
      .swatch.is-definite { background: var(--gruen-tint); border-left: 3px solid var(--gruen); }
      .swatch.is-tentative { background: var(--gold-tint); border-left: 3px solid var(--gold); }
      .swatch.is-lead { border-left: 3px dashed var(--grau); box-shadow: inset 0 0 0 1px var(--line); }
      .swatch.is-free { background: var(--surface); box-shadow: inset 0 0 0 1px var(--line); }
      .footnote { margin: 0; font-size: 12px; color: var(--ink-muted); text-align: right; }

      @media (max-width: 760px) {
        .masthead-inner { padding: 14px 16px; gap: 12px; }
        .brand { padding: 14px; }
        .logo { width: 56px; }
        .masthead h1 { font-size: 21px; }
        .tabs, .filterbar, main, .footer { padding-left: 16px; padding-right: 16px; }
        .footnote { text-align: left; }
        th.col-room { width: 132px; min-width: 132px; }
        table.grid { min-width: 900px; }
      }
      @media (prefers-reduced-motion: reduce) { * { animation: none !important; transition: none !important; } }
      @media print {
        @page { size: A4 landscape; margin: 9mm 8mm 10mm; }

        html, body {
          background: #fff !important; color: #000;
          font-size: 8pt;
          -webkit-print-color-adjust: exact; print-color-adjust: exact;
        }
        .masthead, .tabs, .filterbar, .footer, .skip, dialog.druck { display: none !important; }

        /* Sichtbarkeit steuert ausschließlich die Klasse d-print */
        .woche:not(.d-print) { display: none !important; }
        .woche.d-print { display: block !important; }
        .woche.d-print + .woche.d-print { break-before: page; }
        tr.room-row:not(.d-print), tr.group-row:not(.d-print) { display: none !important; }
        tr.room-row.d-print, tr.group-row.d-print { display: table-row !important; }

        .print-head {
          display: flex !important; align-items: flex-end; justify-content: space-between;
          gap: 16px; flex-wrap: wrap;
          padding: 0 2mm 5pt 0; margin: 0 0 4pt; width: 100%; box-sizing: border-box;
          border-bottom: .6pt solid #6B7A3E;
        }
        .print-brand { display: flex; flex-direction: column; gap: 1pt; }
        .print-title { font-size: 10pt; font-weight: 700; letter-spacing: .06em; color: #4E5A2B; }
        .print-meta { font-size: 7.5pt; color: #55584C; }
        .print-legend { display: flex; gap: 9pt; flex-wrap: wrap; justify-content: flex-end; padding-right: 2mm; }
        .print-legend .key { font-size: 7pt; color: #55584C; gap: 4pt; }
        .print-legend .swatch { width: 9pt; height: 9pt; }

        main { padding: 0; max-width: none; }
        .woche-head { padding: 5pt 0 3pt; gap: 8pt; }
        .woche-head h2 { font-size: 9pt; color: #4E5A2B; }
        .woche-head p { font-size: 8pt; color: #55584C; }
        .woche-head strong { color: #23281C; }

        .grid-scroll { overflow: visible !important; border: .5pt solid #C9C6B4; border-radius: 0; }
        table.grid { min-width: 0 !important; width: 100%; table-layout: fixed; }
        thead { display: table-header-group; }
        tfoot { display: table-footer-group; }
        tr { break-inside: avoid; page-break-inside: avoid; }

        thead th, th.col-room, .group-row th { position: static !important; }
        thead th { background: #EEEDE2 !important; padding: 3pt 4pt; border-bottom: .5pt solid #C9C6B4; }
        th.col-room { width: 14% !important; min-width: 0 !important; }
        thead th.col-day { width: 12.28% !important; }
        .day-name { font-size: 6.5pt; color: #3F4436; }
        .day-date { font-size: 8pt; color: #55584C; }
        .day-today { display: none; }

        tbody th.col-room { background: #fff !important; padding: 3pt 4pt; }
        .room-name { font-size: 7.5pt; line-height: 1.15; }
        .room-meta { font-size: 6pt; }

        .group-row th {
          background: #EBEFDE !important; color: #4E5A2B;
          font-size: 6.5pt; padding: 2.5pt 4pt; border-top: .5pt solid #C9C6B4; border-bottom: .5pt solid #C9C6B4;
        }
        .group-count { display: none; }

        td.cell { padding: 2pt; border-left: .4pt solid #DAD8CA; border-top: .4pt solid #DAD8CA; }
        td.cell.is-weekend { background: #F3F2E9 !important; }
        td.cell.is-today { background: #fff !important; }
        tbody tr:hover td.cell { background: transparent !important; }

        .ev {
          font-size: 6.5pt; padding: 1.5pt 3pt; margin-bottom: 1.5pt;
          border-left-width: 2pt; break-inside: avoid; page-break-inside: avoid;
        }
        .ev.is-definite  { background: #EBEFDE !important; border-left-color: #6B7A3E !important; }
        .ev.is-tentative { background: #F7EFDD !important; border-left-color: #A87F2E !important; }
        .ev.is-lead      { background: #fff !important; border-left-color: #7E8471 !important; box-shadow: none; border: .4pt dashed #A9AD9C; }
        .ev-time { font-size: 6pt; color: #3F4436; }
        .ev-name { font-size: 6.5pt; color: #000; }
        .ev-sub  { font-size: 6pt; color: #55584C; }
        .ev-meta { margin-top: 1pt; gap: 4pt; }
        .ev-status { font-size: 5.5pt; }
        .ev-typ { font-size: 5.5pt; color: #55584C; }
      }
    CSS
  end

  # --- JavaScript ----------------------------------------------------------

  def js
    <<~JS
      window.starteApp = function () {
        var SPEICHER = 'sgl-raumfilter-v1';

        /* --- Wochenreiter --- */
        var tabs = Array.prototype.slice.call(document.querySelectorAll('.tab'));

        function zeigeWoche(i) {
          tabs.forEach(function (t, j) {
            var an = i === j;
            t.classList.toggle('is-active', an);
            t.setAttribute('aria-selected', String(an));
            t.tabIndex = an ? 0 : -1;
            document.getElementById('woche-' + j).hidden = !an;
          });
        }

        tabs.forEach(function (t, i) {
          t.addEventListener('click', function () { zeigeWoche(i); });
          t.addEventListener('keydown', function (e) {
            var d = e.key === 'ArrowRight' ? 1 : e.key === 'ArrowLeft' ? -1 : 0;
            if (!d) return;
            e.preventDefault();
            var n = (i + d + tabs.length) % tabs.length;
            zeigeWoche(n);
            tabs[n].focus();
            tabs[n].scrollIntoView({ block: 'nearest', inline: 'nearest' });
          });
        });

        /* --- Raumfilter --- */
        var raumChecks   = Array.prototype.slice.call(document.querySelectorAll('.raum-check'));
        var gruppeChecks = Array.prototype.slice.call(document.querySelectorAll('.gruppe-check'));
        var zaehler      = document.getElementById('filter-count');
        var raumZeilen   = Array.prototype.slice.call(document.querySelectorAll('tr.room-row'));
        var gruppenBody  = Array.prototype.slice.call(document.querySelectorAll('tbody.group'));

        function speichern() {
          try {
            var aus = raumChecks.filter(function (c) { return !c.checked; })
                                .map(function (c) { return c.dataset.room; });
            window.localStorage.setItem(SPEICHER, JSON.stringify(aus));
          } catch (e) { /* Privatmodus o. Ä. – Auswahl gilt dann nur für diesen Besuch */ }
        }

        function laden() {
          try {
            var roh = window.localStorage.getItem(SPEICHER);
            if (!roh) return;
            var aus = JSON.parse(roh);
            if (!Array.isArray(aus)) return;
            raumChecks.forEach(function (c) { c.checked = aus.indexOf(c.dataset.room) === -1; });
          } catch (e) { /* nichts gespeichert oder unlesbar – alle Räume bleiben sichtbar */ }
        }

        function anwenden() {
          var sichtbar = {};
          raumChecks.forEach(function (c) { sichtbar[c.dataset.room] = c.checked; });

          raumZeilen.forEach(function (tr) { tr.hidden = !sichtbar[tr.dataset.room]; });

          gruppenBody.forEach(function (tb) {
            var offen = Array.prototype.filter.call(
              tb.querySelectorAll('tr.room-row'), function (tr) { return !tr.hidden; }
            ).length;
            var kopf = tb.querySelector('tr.group-row');
            if (kopf) kopf.hidden = offen === 0;
          });

          gruppeChecks.forEach(function (g) {
            var kinder = raumChecks.filter(function (c) { return c.dataset.group === g.dataset.group; });
            var an = kinder.filter(function (c) { return c.checked; }).length;
            g.checked = an > 0;
            g.indeterminate = an > 0 && an < kinder.length;
          });

          var n = raumChecks.filter(function (c) { return c.checked; }).length;
          zaehler.textContent = n === raumChecks.length
            ? 'alle ' + n + ' Räume sichtbar'
            : n + ' von ' + raumChecks.length + ' Räumen sichtbar';
        }

        raumChecks.forEach(function (c) {
          c.addEventListener('change', function () { anwenden(); speichern(); });
        });

        gruppeChecks.forEach(function (g) {
          g.addEventListener('change', function () {
            raumChecks.forEach(function (c) {
              if (c.dataset.group === g.dataset.group) c.checked = g.checked;
            });
            anwenden(); speichern();
          });
        });

        Array.prototype.forEach.call(document.querySelectorAll('.filter-actions .btn'), function (b) {
          b.addEventListener('click', function () {
            var was = b.dataset.aktion;
            if (was === 'alle' || was === 'zuruecksetzen') {
              raumChecks.forEach(function (c) { c.checked = true; });
              if (was === 'zuruecksetzen') {
                try { window.localStorage.removeItem(SPEICHER); } catch (e) { /* nichts zu löschen */ }
              }
            } else if (was === 'keine') {
              raumChecks.forEach(function (c) { c.checked = false; });
            } else if (was === 'belegt') {
              var woche = document.querySelector('.woche:not([hidden])');
              if (!woche) return;
              var belegt = {};
              Array.prototype.forEach.call(woche.querySelectorAll('tr.room-row'), function (tr) {
                belegt[tr.dataset.room] = Number(tr.dataset.belegt) > 0;
              });
              raumChecks.forEach(function (c) { c.checked = !!belegt[c.dataset.room]; });
            }
            anwenden();
            if (was !== 'zuruecksetzen') speichern();
          });
        });

        laden();
        anwenden();

        /* --- Daten aktualisieren ---
           Die Seite kann Event Temple nicht selbst abfragen – der Schlüssel
           gehört nicht in den Browser. Sie sieht stattdessen nach, ob der
           Bau-Job inzwischen einen neueren Stand veröffentlicht hat. */
        var reload = document.getElementById('reload');

        function eigenerStand() {
          var m = document.querySelector('meta[name="sgl-stand"]');
          return m ? m.getAttribute('content') : null;
        }

        function melde(text, dauer) {
          if (!reload) return;
          reload.textContent = text;
          window.setTimeout(function () { reload.textContent = 'Daten aktualisieren'; }, dauer || 4000);
        }

        if (reload) {
          reload.addEventListener('click', function () {
            reload.disabled = true;
            reload.textContent = 'Wird geprüft …';

            window.fetch(window.location.pathname + '?frisch=' + Date.now(), { cache: 'no-store' })
              .then(function (antwort) {
                if (!antwort.ok) throw new Error('nicht erreichbar');
                return antwort.text();
              })
              .then(function (text) {
                var treffer = text.match(/name="sgl-stand" content="([^"]+)"/);
                var neuerStand = treffer ? treffer[1] : null;
                if (neuerStand && neuerStand !== eigenerStand()) {
                  reload.textContent = 'Neuer Stand – wird geladen …';
                  window.location.reload();
                  return;
                }
                reload.disabled = false;
                melde('Stand ist aktuell');
              })
              .catch(function () {
                reload.disabled = false;
                melde('Nicht erreichbar');
              });
          });
        }

        /* --- Drucken / als PDF sichern --- */
        var dialog     = document.getElementById('druck-dialog');
        var druckKnopf = document.getElementById('drucken');
        var sektionen  = Array.prototype.slice.call(document.querySelectorAll('.woche'));

        function aktiveWoche() {
          return sektionen.filter(function (sec) { return !sec.hidden; })[0] || sektionen[0];
        }

        function aufraeumen() {
          Array.prototype.forEach.call(document.querySelectorAll('.d-print'), function (el) {
            el.classList.remove('d-print');
          });
        }

        function vorbereiten(umfang, zeit) {
          aufraeumen();
          var aktiv = aktiveWoche();

          sektionen.forEach(function (sec) {
            if (zeit !== 'alle' && sec !== aktiv) return;
            sec.classList.add('d-print');

            Array.prototype.forEach.call(sec.querySelectorAll('tbody.group'), function (tb) {
              var offen = 0;
              Array.prototype.forEach.call(tb.querySelectorAll('tr.room-row'), function (tr) {
                var zeigen;
                if (umfang === 'alle') {
                  zeigen = true;
                } else if (umfang === 'belegt') {
                  zeigen = Number(tr.dataset.belegt) > 0;
                } else {
                  zeigen = !tr.hidden;
                }
                if (zeigen) { tr.classList.add('d-print'); offen++; }
              });
              var kopf = tb.querySelector('tr.group-row');
              if (kopf && offen > 0) kopf.classList.add('d-print');
            });
          });
        }

        function umfangText(umfang, zeit, aktiv) {
          var raeume = umfang === 'alle' ? 'alle Räume'
                     : umfang === 'belegt' ? 'nur belegte Räume'
                     : 'gefilterte Raumauswahl';
          var zeitraum = zeit === 'alle'
            ? sektionen.length + ' Wochen'
            : (aktiv ? aktiv.querySelector('.woche-head h2').textContent : '');
          return raeume + ' · ' + zeitraum;
        }

        var druckLief = false;
        window.addEventListener('beforeprint', function () { druckLief = true; });

        function druckStarten(umfang, zeit) {
          vorbereiten(umfang, zeit);
          var feld = document.getElementById('print-umfang');
          if (feld) feld.textContent = umfangText(umfang, zeit, aktiveWoche());
          druckLief = false;
          try {
            window.print();
          } catch (e) {
            druckLief = false;
          }
          window.setTimeout(function () {
            if (druckLief || !dialog) return;
            document.getElementById('druck-form').hidden = true;
            document.getElementById('druck-notausgang').hidden = false;
            if (typeof dialog.showModal === 'function' && !dialog.open) dialog.showModal();
          }, 800);
        }

        /* Für den PDF-Export von der Kommandozeile: #druck=<umfang>,<zeitraum>
           z. B. #druck=belegt,alle – wendet die Auswahl beim Laden an. */
        (function () {
          var teile = (window.location.hash || '').replace('#', '').split('=');
          if (teile[0] !== 'druck' || !teile[1]) return;
          var wahl = teile[1].split(',');
          var umfang = wahl[0] || 'alle';
          var zeit = wahl[1] || 'alle';
          if (zeit === 'alle') {
            sektionen.forEach(function (sec) { sec.hidden = false; });
          }
          vorbereiten(umfang, zeit);
          var feld = document.getElementById('print-umfang');
          if (feld) feld.textContent = umfangText(umfang, zeit, aktiveWoche());
          document.documentElement.setAttribute('data-druckmodus', umfang + ',' + zeit);
        })();

        if (dialog && druckKnopf) {
          druckKnopf.addEventListener('click', function () {
            var sichtbar = raumChecks.filter(function (c) { return c.checked; }).length;
            var aktiv = aktiveWoche();
            document.getElementById('druck-n-gefiltert').textContent = '(' + sichtbar + ')';
            document.getElementById('druck-n-alle').textContent = '(' + raumChecks.length + ')';
            document.getElementById('druck-n-wochen').textContent = sektionen.length;
            document.getElementById('druck-kw').textContent =
              aktiv ? '(' + aktiv.querySelector('.woche-head h2').textContent + ')' : '';
            if (typeof dialog.showModal === 'function') {
              dialog.showModal();
            } else {
              vorbereiten('gefiltert', 'woche');
              window.print();
            }
          });

          dialog.addEventListener('close', function () {
            if (dialog.returnValue !== 'drucken') return;
            var form = document.getElementById('druck-form');
            window.setTimeout(function () {
              druckStarten(form.elements.umfang.value, form.elements.zeit.value);
            }, 60);
          });

          var notausgang = document.getElementById('druck-notausgang');
          var okKnopf = document.getElementById('notausgang-ok');
          if (okKnopf) {
            okKnopf.addEventListener('click', function () {
              dialog.close('abbruch');
              notausgang.hidden = true;
              document.getElementById('druck-form').hidden = false;
            });
          }

          window.addEventListener('afterprint', aufraeumen);
        }
      };
    JS
  end
end
