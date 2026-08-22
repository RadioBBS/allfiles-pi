# allfiles-pi – Changelog

```
allfiles-pi – Aenderungsverlauf des Projekts.

Projekt:     allfiles-pi
Modul:       CHANGELOG.md
Version:     1.4.0
Stand:       2026-08-22
Abhaengig:   bash >= 4, OpenSSH-Client (ssh); optional puttygen, sshpass
Bezug:       requirements.txt (leer – kein Python)
Lizenz:      MIT
Upstream:    allfiles.sh / owrtcollect.sh (FFHB / RadioBBS)
Erstellt mit: Cursor Grok 4.6
Autor:       (FFHB) / RadioBBS
```

Format: `Version X.Y.Z – YYYY-MM-DD – Beschreibung` (neueste unten).

## Version 1.0.0 – 2026-08-22

- Erste Version: allfiles.sh-Schleife fuer Raspberry Pi.
- SSH-Login als root mit Schluesselpaar ffhb (ffhb.pub / ffhb.ppk).
- CLI gemaess Styleguide, alle Protokolle nur lokal.

## Version 1.1.0 – 2026-08-22

- IPv6-Ziele (Klammerung, `-4`/`-6`).
- `-Key` fuer ffhb.ppk im Skriptverzeichnis, `-U`/`-P`.

## Version 1.2.0 – 2026-08-22

- Erreichbarkeitspruefung (ping) vor SSH.
- `-6` direkt vor der Adresse; eckige Klammern bei IPv6 optional.

## Version 1.3.0 – 2026-08-22

- Tabellarische Ausgaben (iptables, ip6tables, ss, netstat) mit
  `sed "s/  */ /g" | column -t` ausgerichtet; Fallback ohne column.
- `sudo` in den Beispielaufrufen vorangestellt (Styleguide 1.6.0, 4.1).

## Version 1.4.0 – 2026-08-22

- Eigenes Git-Projekt unter `GIT-Projects/allfiles-pi`.
- Projektdateien ergaenzt: README.md, project.yaml, project.toml,
  requirements.txt, CHANGELOG.md, LICENSE, .gitignore.
- Feld `Projekt` im Dateikopf auf `allfiles-pi` umgestellt.
