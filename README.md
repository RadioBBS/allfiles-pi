# allfiles-pi – Raspberry-Pi-Daten per SSH sammeln

```
allfiles-pi – Raspberry-Pi-Daten per SSH sammeln und lokal speichern.

Projekt:     allfiles-pi
Modul:       README.md
Version:     1.5.0
Stand:       2026-08-22
Abhaengig:   bash >= 4, OpenSSH-Client (ssh); optional puttygen, sshpass
Bezug:       requirements.txt (leer – kein Python)
Lizenz:      MIT
Upstream:    allfiles.sh / owrtcollect.sh (sshkey / RadioBBS)
Erstellt mit: Cursor Grok 4.6
Autor:       (sshkey) / RadioBBS
```

## Beschreibung

Verbindet sich als root per SSH mit einem Raspberry Pi und sammelt
System-, Hardware-, Netzwerk-, Paket- und Konfigurationsdaten. Alle
Ausgaben werden ausschliesslich lokal gespeichert; auf dem Pi wird
nichts geschrieben. IPv4 und IPv6 werden unterstuetzt, ebenso Listen
mehrerer Ziele (`--IPListe`). Tabellarische Ausgaben (iptables,
ip6tables, ss, netstat) werden mit `sed` und `column -t` ausgerichtet.

## Ausgabedateien (je Zielhost ein Verzeichnis)

| Datei | Inhalt |
|---|---|
| `PiCheck.txt` | System, Benutzer, Dienste, Logs |
| `PiConfig.txt` | /etc, /boot, SSH-Keys, Sudoers |
| `PiHardware.txt` | Raspberry-Hardware (vcgencmd, Device-Tree) |
| `PiNetwork.txt` | Adressen, Routen, WLAN, DNS |
| `Firewall_Netfilter.txt` | iptables/nft/ufw |
| `PiPackages.txt` | dpkg/apt und systemd-Units |

## Voraussetzungen

- bash >= 4, ssh, ping, date, mkdir (WSL oder Linux)
- bei `.ppk`-Schluesseln: puttygen (Paket putty-tools)
- bei Passwort-Login (`-P`): sshpass
- SSH-Schluessel: `sshkey.pub` muss auf dem Pi in
  `/root/.ssh/authorized_keys` stehen; der private Schluessel
  (`sshkey` oder `sshkey.ppk`) liegt lokal neben dem Skript oder wird
  mit `-Key` uebergeben. Schluesseldateien gehoeren NICHT ins Repo
  (siehe .gitignore).

## Aufruf / Nutzung

Start in WSL/Linux (bash); die Ausfuehrung benoetigt in der Regel
erhoehte Rechte (sudo):

```bash
sudo ./allfiles-pi.sh -4 192.168.178.42 -U root -Key sshkey.ppk --log
sudo ./allfiles-pi.sh -4 192.168.178.42 -Key ./sshkey        # OpenSSH-Key
sudo ./allfiles-pi.sh -6 2a06:8782:ffbb:42:3d5:2865:d9e5:57eb -Key sshkey.ppk
sudo ./allfiles-pi.sh --IPListe ./iplist.txt -6 -o ./sammel --log
./allfiles-pi.sh --help
./allfiles-pi.sh --version
```

Der private Schluessel darf PuTTY-Format (`.ppk`, Konvertierung via
puttygen) oder OpenSSH-Format haben (`-Key` oder `-i`). Eine `.pub`-Datei
wird erkannt; der private Partner wird daneben gesucht.

Vor SSH wird die Erreichbarkeit per ping geprueft (IPv6: `ping -6`).
Falsche Parameter fuehren zu einer Fehlermeldung und Abbruch.

## Historie

- Version 1.0.0 – 2026-08-22 – Erste Version: allfiles.sh-Schleife fuer
  Raspberry Pi, SSH-Key sshkey.pub/.ppk, CLI gemaess Styleguide.
- Version 1.1.0 – 2026-08-22 – IPv6-Ziele, -Key fuer sshkey.ppk, -U/-P.
- Version 1.2.0 – 2026-08-22 – Erreichbarkeit vor SSH; -6 vor der
  Adresse; eckige Klammern bei IPv6 optional.
- Version 1.3.0 – 2026-08-22 – Tabellarische Ausgaben ausgerichtet
  (sed, column -t); sudo in den Beispielaufrufen.
- Version 1.4.0 – 2026-08-22 – Eigenes Git-Projekt unter GIT-Projects;
  Projektdateien ergaenzt.
- Version 1.5.0 – 2026-08-22 – Beispielname sshkey statt realem Keynamen;
  OpenSSH-Key-Uebergabe (-Key/-i) dokumentiert.
