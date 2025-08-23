# Projektübersicht

Dieses Verteilte-Systeme-Projekt soll über Godot ein Spiel hervorbringen welches über Websockets direkt im Browser zusammen gespielt werden kann.

## Schritte zur Nutzung

1. **Godot-Spiel exportieren**

   - Bearbeite/Erstelle das Spiel in Godot (`client/papertim`).
   - Exportiere es als HTML5-Projekt.
   - Im Start-Node (z.B. `game_paper.gd`) wird das Spiel mit dem Webserver verbunden.

2. **Client-Template**

   - Lade die nötigen HTML/JS-Dateien (Godot Export Template) von der offiziellen Godot-Webseite herunter:  
     https://godotengine.org/download/web
   - Kopiere das komplette HTML5-Export-Template in den Ordner `client/Game`.
   - Ersetze oder ergänze die Dateien mit deinem exportierten Spiel.

3. **HTTPS-Zertifikate mit mkcert erstellen**

   - Lade mkcert für Windows herunter, z.B. von:  
     https://github.com/FiloSottile/mkcert/releases  
     (Version `mkcert-v1.4.4-windows-amd64.exe`)
   
   - Öffne die Eingabeaufforderung (CMD) und navigiere zum Ordner, in dem die mkcert-Exe liegt (z.B. `Downloads`):
     ```
     cd C:\Users\<Name>\Downloads
     ```
   - Installiere die lokale Zertifizierungsstelle (CA), falls noch nicht geschehen:
     ```
     .\mkcert-v1.4.4-windows-amd64.exe -install
     ```
   - Erstelle die Zertifikate für `localhost`:
     ```
     .\mkcert-v1.4.4-windows-amd64.exe localhost
     ```
     Dadurch werden zwei Dateien erstellt:
     - `localhost.pem`
     - `localhost-key.pem`

   - Kopiere diese beiden Dateien in den `server`-Ordner des Projekts.

4. **Server starten**

   - Im Projekt-Root oder im `server`-Ordner:  
     ```
     node server.js
     ```
   - Der Server läuft dann unter:  
     ```
     https://localhost:8443/game.html
     ```
     (Alternativ einfach `https://localhost:8443/` wenn der Server so konfiguriert ist, dass er auf `/` auf `game.html` weiterleitet)

---

## Hinweise

- `localhost.pem` und `localhost-key.pem` sind private Zertifikate für die lokale Entwicklung und sollten **nicht** ins Git-Repository gepusht werden. Daher in `.gitignore` eintragen.
- Für mehr als 10 WebSocket-Clients ist der Server nicht ausgelegt.
- Das HTTPS ist nötig, damit der Browser WebGL und WebSocket-Verbindungen im sicheren Kontext erlaubt.

## Ablauf des Projekts:
- Masterserver
    - wählt einen freien Host-Port (z. B. 43943).
    - startet den Container gameserver:latest mit Port-Mapping Host:43943 → Container:8443 und gibt PUBLIC_PORT=43943 per ENV mit.

- Gameserver (im Container)
  - lauscht immer auf 8443 (interner Container-Port).
  - liefert die Godot-Buildfiles und /config.
  - /config baut die WebSocket-URL aus dem Host-Header (z. B. ws://localhost:43943) – damit ist der dyn. Port automatisch richtig.
  - registriert sich in Redis unter server:43943 und hält die players-Zahl aktuell.

- Godot (Web)
  - lädt per HTTPRequest absolute URL window.location.origin + "/config".
  - bekommt ws_url zurück (z. B. ws://localhost:43943) und verbindet sich darüber mit dem WS-Server.