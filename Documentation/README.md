# 📄 Projektdokumentation – SE-Projekt DHBW

## 📁 Verzeichnisstruktur

- `ProjektSe/`: Enthält das LaTeX-Template der DHBW, auf dem die gesamte Dokumentation basiert
- `dokumentation.tex`: Main Datei zur PDF-Erzeugung

## ⚙️ Voraussetzungen (für LaTeX)

Zum Bearbeiten und Kompilieren der Dokumentation wird folgendes empfohlen:

- **Visual Studio Code**
- Plugin: `LaTeX Workshop`
- **Perl** (für das DHBW-Template, z. B. zur Seitenanzahlzählung)
- **MiKTeX** oder **TeX Live** (je nach Betriebssystem)

## 🔀 Git-Workflow & Teamregeln

Damit alle effizient zusammenarbeiten können, gelten folgende Regeln für dieses Doku-Repository:

### Allgemeine Regeln

-  Im Normalfall arbeiten alle direkt auf dem `main`-Branch.
-  Bevor Änderungen gepusht werden: Kompiliere lokal, prüfe auf Fehler und achte auf sauberes Layout.
-  Sinnvolle Commit-Nachrichten, z. B. `Kapitel Methodik ergänzt` oder `Tippfehler in Einleitung korrigiert`.
-  **Kein** Commit von generierten Hilfsdateien (z. B. `.lot`, `.aux`, `.log`, etc.). Diese gehören nicht ins Repository (siehe `.gitignore` unten).

### Arbeiten im Team (optional bei paralleler Arbeit)

Falls mehrere Personen gleichzeitig an verschiedenen Teilen schreiben, jeweiligen Branch erstellen. 