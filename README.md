# PaperTim

Ein Projekt für das Modul *Verteilte Systeme*: Ein browserbasiertes Mehrspieler-Spiel (inspiriert von „Achtung, Kurve!“), umgesetzt mit Godot, Node.js und WebSockets.

---

## Inhaltsverzeichnis

- [Projektbeschreibung](#projektbeschreibung)  
- [Features](#features)  
- [Architektur](#architektur)  
- [Technologien](#technologien)  
- [Installation & Setup](#installation--setup)  
- [Benutzung](#benutzung)  
- [Entwicklungsrichtlinien](#entwicklungsrichtlinien)   

---

## Projektbeschreibung

PaperTim ermöglicht es, das klassische Spielprinzip von „Achtung, Kurve!“ direkt im Browser mit mehreren Spielern zu erleben.  
Spieler verbinden sich über WebSockets mit einem Game-Server, steuern ihre „Kurve“ in Echtzeit und kämpfen um den letzten Überlebenden. Das Spiel basiert auf einer verteilten Systemarchitektur mit Master- und Game-Servern, persistenten Benutzerdaten und best möglich synchronisiertem Spielablauf.

---

## Features

- Mehrspieler-Gameplay über WebSockets  
- Lobby-System mit Player Tracking und Host-Regel (Master-Client)  
- Ready-Mechanismus vor dem Spielstart  
- Nutzerauthentifizierung und Sicherung der Datenintegrität  
- Dynamisches Ausliefern der Godot-HTML5 Export-Builds  
- HTTP(s) Zugriff + Konfigurations-Endpoint `/config` für dynamische WebSocket-URLs  

---

## Architektur
![Architekturübersicht](https://raw.githubusercontent.com/StmMtn/PaperTim/main/Documentation/ProjektSe/images/content.png)


- **Master-Server**: Verwaltung der aktiven Game-Server‐Instanzen, Lobby-Metadaten, Spielerzahlen  
- **Game-Server**: Hostet die Godot HTML5 Builds, liefert Konfigurationsantworten, stellt WebSocket Verbindungen her  
- **Redis**: Speichert aktuelle Spielerzahlen und Lobbystatus für schnelle Zugriffe  
- **Client (Godot HTML5)**: Lädt die Spielvarianten, verbindet via WebSocket, sendet Eingaben (links/rechts), empfängt Update-Events  

---

## Technologien

| Komponente         | Technologie                         |
|--------------------|-------------------------------------|
| Spiel              | Godot (HTML5 Export)                |
| Backend / APIs     | Node.js, Express.js                 |
| Datenbank / Cache  | Redis, ggf. PostgreSQL / andere     |
| Frontend           | Angular & WebSocket Client          |
| Authentifizierung  | Token / JWT, Passwort Hashing       |

---

## Installation & Setup

1. Repository clonen  
   ```bash
   git clone https://github.com/StmMtn/PaperTim.git
   cd PaperTim
   ```

2. Server starten 
   ```bash
   docker compose up --build -d
   ```
   -> für hochverfügbaren Masterserver Flag: --scale masterserver=3 (oder mehr)
   
   Danach sollte die Lobby erreichbar sein unter: `https://localhost:8081/`
---

## Benutzung

- Benutzer öffnen ihre Browser (idealerweise moderner Browser mit HTTPS Unterstützung)  
- Nutzer verbinden sich nach Anmeldung / Lobbybeitritt via WebSocket  
- Sobald alle Spieler „ready“ sind, beginnt das Spiel  
- Steuerung erfolgt per Tastatur: Links / Rechts  
- Nach jedem Durchgang werden Ergebnisse / Trophäen zurückgemeldet  

---

## Entwicklungsrichtlinien

- **Codeorganisation**: Backend (Master + Game-Server) getrennt halten, Client (Godot) klar separiert  
- **Validierung**: Authentifizierung und Datenintegrität prüfen, insbesondere beim Lobbybeitritt und Ergebnisermittlung  
- **Synchronisation**: Host / Master-Client Ansatz nutzen, um divergierende Simulationen zu vermeiden  

---

## DB-Backup
- Backup erstellen: ```bash 
docker exec -t papertim-postgres-1 pg_dump -U postgres -d papertim > masterserver/init.sql  
```


