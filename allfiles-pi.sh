#!/usr/bin/env bash
#
# allfiles-pi – Raspberry-Pi-Daten per SSH sammeln und lokal speichern.
#
# Projekt:     allfiles-pi
# Modul:       allfiles-pi.sh
# Version:     1.5.0
# Stand:       2026-08-22
# Abhaengig:   bash ≥ 4, OpenSSH-Client (ssh); optional puttygen, sshpass
# Bezug:       requirements.txt (nicht vorhanden – keine Python-Abhaengigkeiten)
# Lizenz:      MIT
# Upstream:    allfiles.sh / owrtcollect.sh (FFHB / RadioBBS)
# Erstellt mit: Cursor Grok 4.6
# Autor:       (FFHB) / RadioBBS
#
# Beschreibung
# ------------
# Verbindet sich als root per SSH mit einem Raspberry Pi und sammelt
# System-, Hardware-, Netzwerk-, Paket- und Konfigurationsdaten.
# Alle Ausgaben werden ausschliesslich lokal gespeichert. Auf dem Pi
# werden keine Dateien geschrieben.
#
# Der oeffentliche Schluessel sshkey.pub muss auf dem Pi in
# /root/.ssh/authorized_keys liegen. Lokal wird der passende private
# Schluessel verwendet (OpenSSH-Datei "sshkey" oder PuTTY "sshkey.ppk").
# Eine .pub-Datei allein reicht fuer den Login nicht.
#
# Historie
# --------
# Version 1.0.0 – 2026-08-22 – Erste Version: allfiles.sh-Schleife fuer
#                              Raspberry Pi, SSH-Key sshkey.pub/.ppk, CLI
#                              gemaess Styleguide, lokale Protokolle.
# Version 1.1.0 – 2026-08-22 – IPv6-Ziele (Klammerung, -4/-6), -Key fuer
#                              sshkey.ppk im Skriptverzeichnis, -U/-P.
# Version 1.2.0 – 2026-08-22 – Erreichbarkeit vor SSH; -6 vor der Adresse;
#                              eckige Klammern bei IPv6 optional.
# Version 1.3.0 – 2026-08-22 – Tabellarische Ausgaben (iptables, ip6tables,
#                              ss, netstat) mit sed und column -t ausgerichtet;
#                              sudo in den Beispielaufrufen vorangestellt.
# Version 1.4.0 – 2026-08-22 – Eigenes Git-Projekt allfiles-pi unter
#                              GIT-Projects; Projektdateien ergaenzt.
# Version 1.5.0 – 2026-08-22 – Beispielname sshkey statt realem Keynamen;
#                              OpenSSH-Key-Uebergabe (-Key/-i) dokumentiert.
#
# Aufruf / Nutzung
# ----------------
#   sudo ./allfiles-pi.sh 192.168.178.42 -U root -Key sshkey.ppk
#   sudo ./allfiles-pi.sh 192.168.178.42 -Key ./sshkey        # OpenSSH-Key
#   sudo ./allfiles-pi.sh -6 [2a06:8782:ffbb:42:3d5:2865:d9e5:57eb]
#   sudo ./allfiles-pi.sh -6 2a06:8782:ffbb:42:3d5:2865:d9e5:57eb
#   sudo ./allfiles-pi.sh --IPListe ./iplist.txt -o ./ergebnisse
#   ./allfiles-pi.sh --help
#

VERSION="1.5.0"
VERSION_DATUM="2026-08-22"
SKRIPTNAME="${0##*/}"
END_PROMPT="Programmende: Hit any Key or Enter"

# ---------------------------------------------------------------------------
# Defaultwerte (werden von CLI-Parametern ueberschrieben)
# ---------------------------------------------------------------------------
DEFAULT_LOGFILE="allfiles-pi.log"
DEFAULT_USER="root"
DEFAULT_PORT="22"
DEFAULT_HOST="raspberrypi.local"
DEFAULT_IPv4=""
DEFAULT_IPv6=""
DEFAULT_SSHKEY="sshkey.pub"
DEFAULT_PPK="sshkey.ppk"
DEFAULT_SSHPassphrase=""
DEFAULT_PWD=""

# Richtet tabellarische Remote-Ausgaben aus: Mehrfach-Leerzeichen auf eines
# reduzieren, dann Spalten mit column -t buendig auffuellen. Fehlt column
# auf dem Pi, bleibt die Originalausgabe erhalten (cat).
TABELLEN_AUSRICHTUNG='sed "s/  */ /g" | (column -t 2>/dev/null || cat)'

# Laufzeitparameter
ziel_host=""
remote_user="$DEFAULT_USER"
ssh_port="$DEFAULT_PORT"
ssh_identitaet=""
ppk_datei=""
ssh_passphrase="$DEFAULT_SSHPassphrase"
login_password="$DEFAULT_PWD"
openssh_tmp_key=""
basis_ausgabe="."
ausgabe_verzeichnis="."
ip_liste_datei=""
logging_aktiv="false"
warte_am_ende="false"
LOGDATEI="./${DEFAULT_LOGFILE}"
auth_modus=""
liste_fehler=0
flag_ipv4="false"
flag_ipv6="false"
ssh_familie=""
ziel_liste=()
_host_gesetzt="false"

OUTFILE=""
CONFFILE=""
HWFILE=""
NETFILE=""
FWFILE=""
PKGFILE=""
SSH_ZIEL=""

# ---------------------------------------------------------------------------
# Hilfsfunktionen
# ---------------------------------------------------------------------------

zeitstempel() {
	#
	# Beschreibung: Liefert den aktuellen Zeitstempel fuer Logzeilen.
	# Parameter:    keine
	# Rueckgabewert: YYYY-MM-DD HH:MM:SS auf stdout
	# Fehlerfaelle: date nicht verfuegbar
	# Beispiel:     zeitstempel
	#
	date '+%Y-%m-%d %H:%M:%S'
}

log_nachricht() {
	#
	# Beschreibung: Schreibt eine Logzeile, falls Logging aktiv ist.
	# Parameter:    $1 = Meldung
	# Rueckgabewert: keines
	# Fehlerfaelle: Schreibfehler werden ignoriert
	# Beispiel:     log_nachricht "Starte"
	#
	if [ "$logging_aktiv" != "true" ]; then
		return 0
	fi
	printf '%s %s\n' "$(zeitstempel)" "$1" >> "$LOGDATEI"
}

info_meldung() {
	#
	# Beschreibung: Info auf stdout und optional ins Log.
	# Parameter:    $1 = Text
	# Rueckgabewert: keines
	# Fehlerfaelle: keine
	# Beispiel:     info_meldung "verbunden"
	#
	echo "$SKRIPTNAME: $1"
	log_nachricht "INFO  $1"
}

fehler_melden() {
	#
	# Beschreibung: Fehlermeldung mit optionalem Logeintrag.
	# Parameter:    $1 = Text
	# Rueckgabewert: keines
	# Fehlerfaelle: keine
	# Beispiel:     fehler_melden "Host fehlt"
	#
	echo "$SKRIPTNAME: FEHLER: $1" >&2
	log_nachricht "FEHLER $1"
}

beende_mit_fehler() {
	#
	# Beschreibung: Zentrale Fehlerbehandlung mit Exit-Code.
	# Parameter:    $1 = Exit-Code, $2 = Meldung
	# Rueckgabewert: beendet das Skript
	# Fehlerfaelle: finaler Abbruch
	# Beispiel:     beende_mit_fehler 2 "Host fehlt"
	#
	fehler_melden "$2"
	exit "$1"
}

bereinige_tmp_key() {
	#
	# Beschreibung: Loescht temporaeren OpenSSH-Key aus PPK-Konvertierung.
	# Parameter:    keine
	# Rueckgabewert: keines
	# Fehlerfaelle: keine
	# Beispiel:     bereinige_tmp_key
	#
	if [ -n "$openssh_tmp_key" ] && [ -f "$openssh_tmp_key" ]; then
		rm -f "$openssh_tmp_key"
	fi
	openssh_tmp_key=""
}

warte_auf_programmende() {
	#
	# Beschreibung: Wartet auf Taste/Enter bei --Ende / -E.
	# Parameter:    keine
	# Rueckgabewert: keines
	# Fehlerfaelle: nicht-interaktiv -> still beenden
	# Beispiel:     warte_auf_programmende
	#
	if [ "$warte_am_ende" != "true" ]; then
		return 0
	fi
	if [ ! -t 0 ]; then
		return 0
	fi
	echo "$END_PROMPT"
	old_stty=""
	if command -v stty >/dev/null 2>&1; then
		old_stty=$(stty -g 2>/dev/null) || old_stty=""
		stty -icanon -echo min 1 time 0 2>/dev/null || true
		dd bs=1 count=1 2>/dev/null >/dev/null || true
		if [ -n "$old_stty" ]; then
			stty "$old_stty" 2>/dev/null || true
		fi
	else
		read -r _ || true
	fi
	echo
}

aufraeumen_beim_exit() {
	#
	# Beschreibung: EXIT-Trap: Temp-Key und optionale Ende-Pause.
	# Parameter:    keine
	# Rueckgabewert: keines
	# Fehlerfaelle: keine
	# Beispiel:     trap aufraeumen_beim_exit EXIT
	#
	bereinige_tmp_key
	warte_auf_programmende
}

zeige_version() {
	#
	# Beschreibung: Versionsnummer, Datum und Programmbeschreibung.
	# Parameter:    keine
	# Rueckgabewert: keines
	# Fehlerfaelle: keine
	# Beispiel:     zeige_version
	#
	echo "allfiles-pi $VERSION ($VERSION_DATUM)"
	echo "Sammelt Raspberry-Pi-Daten per SSH (root, Schluessel sshkey) und speichert lokal."
}

zeige_hilfe() {
	#
	# Beschreibung: Programmbeschreibung, Parameter und Beispiele.
	# Parameter:    keine
	# Rueckgabewert: keines
	# Fehlerfaelle: keine
	# Beispiel:     zeige_hilfe
	#
	cat << EOF
allfiles-pi $VERSION ($VERSION_DATUM)
Sammelt Raspberry-Pi-System-, Hardware- und Konfigurationsdaten per SSH.
Login als root mit einem SSH-Schluesselpaar (Beispielname: sshkey).
Der private Schluessel wird mit -Key uebergeben und darf PuTTY-Format
(sshkey.ppk, wird via puttygen konvertiert) oder OpenSSH-Format
(Datei sshkey, auch ueber -i) haben. Eine .pub-Datei wird erkannt und
der private Partner daneben gesucht.
IPv4- und IPv6-Adressen werden unterstuetzt. Auf dem Pi wird nichts geschrieben.

Verwendung:
  sudo $0 [host] [OPTIONEN]
  sudo $0 -4 -6 -U <user> -P <passwort> -Key sshkey.ppk
  sudo $0 --IPListe <datei> [OPTIONEN]
  $0 --help | -h
  $0 --version

Parameter:
  host                 Zielhost (Hostname, IPv4 oder IPv6)
                       Typ: String, Standard: $DEFAULT_HOST
                       Beispiel: 192.168.178.42
                       IPv6: 2a06:8782:ffbb:42:3d5:2865:d9e5:57eb
                       IPv6 mit Klammern (optional): [2a06:8782:ffbb:42:3d5:2865:d9e5:57eb]
                       In der Shell Klammern in Anfuehrungszeichen setzen
                       Nicht zusammen mit --IPListe verwendbar
  --IPListe <datei>    Textdatei mit einer IP/Hostname pro Zeile (IPv4 und IPv6)
                       Typ: Pfad, Standard: (leer)
                       Beispiel: --IPListe ./iplist.txt
                       Leere Zeilen und #Kommentar werden ignoriert
                       Mit nur -4 bzw. nur -6: Liste nach Adressfamilie filtern
                       IPv6-Zeilen duerfen optional in [] stehen
  -4, --ipv4 [addr]    IPv4 erzwingen (ssh -4, ping -4)
                       Typ: Schalter, optional direkt die IPv4-Adresse
                       Standard: aus; ohne Host: DEFAULT_IPv4 oder $DEFAULT_HOST
                       Zusammen mit -6: IPv4 und IPv6 nacheinander
                       Beispiel: -4 192.168.178.42
  -6, --ipv6 [addr]    IPv6 erzwingen (ssh -6, ping -6); Adresse direkt danach
                       Typ: Schalter, optional IPv6 mit oder ohne []
                       Standard: aus; ohne Host: DEFAULT_IPv6 oder $DEFAULT_HOST
                       Beispiel: -6 [2a06:8782:ffbb:42:3d5:2865:d9e5:57eb]
                       Beispiel: -6 2a06:8782:ffbb:42:3d5:2865:d9e5:57eb
  -U <user>            SSH-Benutzer
                       Typ: String, Standard: $DEFAULT_USER
                       Beispiel: -U root
  -p <port>            SSH-Port
                       Typ: Zahl, Standard: $DEFAULT_PORT
                       Beispiel: -p 22
  -Key <datei>         Privater Schluessel (PuTTY .ppk oder OpenSSH)
                       Typ: Pfad, Standard: $DEFAULT_PPK (neben dem Skript)
                       Beispiel: -Key sshkey.ppk
                       Beispiel: -Key ./sshkey   (OpenSSH-Key)
  -i <datei>           OpenSSH-IdentityFile oder .pub (dann privater Partner)
                       Typ: Pfad, Standard: $DEFAULT_SSHKEY (neben dem Skript)
                       Beispiel: -i ./sshkey
  -ppk, --ppk <datei>  Alias fuer -Key (PuTTY .ppk)
                       Typ: Pfad, Standard: $DEFAULT_PPK
                       Beispiel: -ppk ./sshkey.ppk
  -P <text>            Login-Passwort ODER PPK-Passphrase
                       Typ: String, Standard: (leer)
                       Beispiel: -P geheim
  -o <verzeichnis>     Basis-Ausgabeverzeichnis
                       Typ: Pfad, Standard: .
                       Beispiel: -o ./ergebnisse
                       Ablage je Ziel: -o/<hostname>/...  (IPv6: ':' -> '-')
  --log                Logging in $DEFAULT_LOGFILE aktivieren
                       Typ: Schalter, Standard: aus
                       Beispiel: --log
  -h, --help           Diese Hilfe anzeigen
  --version            Version und Datum anzeigen
  -E, --Ende           Am Ende auf Tastendruck warten
                       Typ: Schalter, Standard: aus

Defaults:
  DEFAULT_LOGFILE       = $DEFAULT_LOGFILE
  DEFAULT_USER          = $DEFAULT_USER
  DEFAULT_PORT          = $DEFAULT_PORT
  DEFAULT_HOST          = $DEFAULT_HOST
  DEFAULT_IPv4          = ${DEFAULT_IPv4:-(leer, Fallback $DEFAULT_HOST)}
  DEFAULT_IPv6          = ${DEFAULT_IPv6:-(leer, Fallback $DEFAULT_HOST)}
  DEFAULT_SSHKEY        = $DEFAULT_SSHKEY
  DEFAULT_PPK           = $DEFAULT_PPK
  DEFAULT_SSHPassphrase = (leer, sofern nicht gesetzt)
  DEFAULT_PWD           = (leer, sofern nicht gesetzt)

Ausgabedateien (lokal, ASCII-safe):
  PiCheck.txt              System, Benutzer, Dienste, Logs
  PiConfig.txt             /etc, /boot, SSH-Keys, Sudoers
  PiHardware.txt           Raspberry-Hardware (vcgencmd, Device-Tree)
  PiNetwork.txt            Adressen, Routen, WLAN, DNS
  Firewall_Netfilter.txt   iptables/nft/ufw
  PiPackages.txt           dpkg/apt und systemd-Units

Beispiele:
  sudo $0 -6 '[2a06:8782:ffbb:42:3d5:2865:d9e5:57eb]' -U root -Key sshkey.ppk
  sudo $0 -6 2a06:8782:ffbb:42:3d5:2865:d9e5:57eb -Key sshkey.ppk
  sudo $0 -4 192.168.178.42 -U root -Key sshkey.ppk --log
  sudo $0 -4 192.168.178.42 -Key ./sshkey
  sudo $0 raspberrypi.local -4 -6 -i ./sshkey -o ./sammel
  sudo $0 --IPListe ./iplist.txt -6 -o ./sammel --log
  sudo $0 -Key sshkey.ppk -E

Hinweise:
  Voraussetzungen: bash, ssh, ping, date, mkdir; bei .ppk: puttygen (putty-tools);
  bei Passwort-Login: sshpass.
  Tabellarische Ausgaben (iptables, ip6tables, ss, netstat) werden auf dem Pi
  mit 'sed "s/  */ /g" | column -t' spaltenweise ausgerichtet; fehlt column
  (Paket bsdmainutils), bleibt die Originalausgabe erhalten.
  Vor SSH wird die Erreichbarkeit per ping (IPv6: ping -6) geprueft.
  IPv6-Klammern sind optional; in der Shell '[...]' quoten, damit [] nicht globt.
  sshkey.pub muss auf dem Pi in /root/.ssh/authorized_keys stehen.
  Lokal: -Key sshkey.ppk oder -Key/-i ./sshkey (OpenSSH); ohne Angabe
  wird $DEFAULT_PPK bzw. $DEFAULT_SSHKEY im Skriptverzeichnis gesucht.
  Falsche Parameter fuehren zu einer Fehlermeldung und Abbruch.
EOF
}

pruefe_voraussetzungen() {
	#
	# Beschreibung: Prueft benoetigte lokale Befehle.
	# Parameter:    keine
	# Rueckgabewert: 0 bei Erfolg, sonst Abbruch
	# Fehlerfaelle: fehlende Tools
	# Beispiel:     pruefe_voraussetzungen
	#
	command -v ssh >/dev/null 2>&1 || beende_mit_fehler 127 "ssh nicht gefunden"
	command -v date >/dev/null 2>&1 || beende_mit_fehler 127 "date nicht gefunden"
	command -v mkdir >/dev/null 2>&1 || beende_mit_fehler 127 "mkdir nicht gefunden"
	command -v head >/dev/null 2>&1 || beende_mit_fehler 127 "head nicht gefunden"
	command -v ping >/dev/null 2>&1 || command -v ping6 >/dev/null 2>&1 \
		|| beende_mit_fehler 127 "ping/ping6 nicht gefunden"
}

setze_ausgabepfade() {
	#
	# Beschreibung: Setzt relative Pfade der Protokolldateien.
	# Parameter:    keine (nutzt ausgabe_verzeichnis)
	# Rueckgabewert: keines
	# Fehlerfaelle: Verzeichnis nicht anlegbar
	# Beispiel:     setze_ausgabepfade
	#
	mkdir -p "$ausgabe_verzeichnis" \
		|| beende_mit_fehler 1 "Ausgabeverzeichnis nicht anlegbar: $ausgabe_verzeichnis"
	OUTFILE="${ausgabe_verzeichnis}/PiCheck.txt"
	CONFFILE="${ausgabe_verzeichnis}/PiConfig.txt"
	HWFILE="${ausgabe_verzeichnis}/PiHardware.txt"
	NETFILE="${ausgabe_verzeichnis}/PiNetwork.txt"
	FWFILE="${ausgabe_verzeichnis}/Firewall_Netfilter.txt"
	PKGFILE="${ausgabe_verzeichnis}/PiPackages.txt"
}

ip_als_verzeichnisname() {
	#
	# Beschreibung: Wandelt eine IP/Hostangabe in einen Verzeichnisnamen um.
	# Parameter:    $1 = IP oder Hostname
	# Rueckgabewert: Name auf stdout (':' wird zu '-')
	# Fehlerfaelle: keine
	# Beispiel:     ip_als_verzeichnisname "fd00::1"
	#
	printf '%s' "$1" | tr ':' '-' | tr '/\\' '__'
}

bereinige_verzeichnisname() {
	#
	# Beschreibung: Bereinigt einen Hostnamen fuer Dateisystem-Pfade.
	# Parameter:    $1 = Roh-Hostname
	# Rueckgabewert: bereinigter Name auf stdout (leer wenn unbrauchbar)
	# Fehlerfaelle: keine
	# Beispiel:     bereinige_verzeichnisname "raspi-wohnzimmer"
	#
	_name=$(printf '%s' "$1" | tr -d '\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
	_name=$(printf '%s' "$_name" | sed "s/^['\"]//;s/['\"]$//")
	_name=$(printf '%s' "$_name" | tr '/\\:*?"<>|' '_________')
	case "$_name" in
		""|"."|"..") printf '' ;;
		*) printf '%s' "$_name" ;;
	esac
}

ermittle_hostname_verzeichnis() {
	#
	# Beschreibung: Liest den Hostnamen per SSH; Fallback IP mit '-'.
	# Parameter:    keine (nutzt ziel_host / SSH)
	# Rueckgabewert: Verzeichnisname auf stdout
	# Fehlerfaelle: bei Fehlern Fallback auf IP-Name
	# Beispiel:     ermittle_hostname_verzeichnis
	#
	_hn=""
	_hn=$(ssh_remote "hostname -s 2>/dev/null" 2>/dev/null) || _hn=""
	_hn=$(bereinige_verzeichnisname "$_hn")
	if [ -z "$_hn" ]; then
		_hn=$(ssh_remote "hostname 2>/dev/null" 2>/dev/null) || _hn=""
		_hn=$(bereinige_verzeichnisname "$_hn")
	fi
	if [ -n "$_hn" ]; then
		printf '%s' "$_hn"
		return 0
	fi
	ip_als_verzeichnisname "$ziel_host"
}

shell_single_quote() {
	#
	# Beschreibung: Escaped eine Zeichenkette fuer sichere Single-Quotes.
	# Parameter:    $1 = Rohtext
	# Rueckgabewert: gequoteter Text auf stdout
	# Fehlerfaelle: keine
	# Beispiel:     shell_single_quote "a'b"
	#
	printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

skript_verzeichnis() {
	#
	# Beschreibung: Ermittelt das Verzeichnis dieser Skriptdatei.
	# Parameter:    keine
	# Rueckgabewert: absoluter Pfad auf stdout
	# Fehlerfaelle: Fallback .
	# Beispiel:     skript_verzeichnis
	#
	CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd || printf '%s\n' "."
}

loese_dateipfad() {
	#
	# Beschreibung: Findet eine Datei inkl. Windows-/WSL-Pfadvarianten.
	# Parameter:    $1 = konfigurierter Pfad
	# Rueckgabewert: aufgeloester Pfad auf stdout (auch wenn Datei fehlt)
	# Fehlerfaelle: keine (Aufrufer prueft Existenz)
	# Beispiel:     loese_dateipfad "$DEFAULT_SSHKEY"
	#
	_pfad="$1"
	if [ -f "$_pfad" ]; then
		printf '%s\n' "$_pfad"
		return 0
	fi

	case "$_pfad" in
		[A-Za-z]:[\\/]*)
			_drive=$(printf '%s' "$_pfad" | cut -c1 | tr 'A-Z' 'a-z')
			_rest=$(printf '%s' "$_pfad" | cut -c3- | tr '\\' '/')
			_wsl="/mnt/${_drive}${_rest}"
			if [ -f "$_wsl" ]; then
				printf '%s\n' "$_wsl"
				return 0
			fi
			;;
	esac

	_base=$(printf '%s' "$_pfad" | tr '\\' '/' | sed 's|.*/||')
	_lokal="$(skript_verzeichnis)/${_base}"
	if [ -f "$_lokal" ]; then
		printf '%s\n' "$_lokal"
		return 0
	fi

	printf '%s\n' "$_pfad"
}

ist_oeffentlicher_schluessel() {
	#
	# Beschreibung: Erkennt OpenSSH-Public-Key-Dateien (.pub).
	# Parameter:    $1 = Dateipfad
	# Rueckgabewert: 0 wenn Public Key, sonst 1
	# Fehlerfaelle: Datei unlesbar -> 1
	# Beispiel:     ist_oeffentlicher_schluessel ./sshkey.pub
	#
	[ -f "$1" ] || return 1
	_kopf=$(head -n 1 "$1" 2>/dev/null) || return 1
	case "$_kopf" in
		ssh-rsa\ *|ssh-ed25519\ *|ecdsa-sha2-nistp*\ *|ssh-dss\ *)
			return 0
			;;
		sk-ssh-ed25519@openssh.com\ *|sk-ecdsa-sha2-nistp256@openssh.com\ *)
			return 0
			;;
	esac
	return 1
}

ist_ppk_datei() {
	#
	# Beschreibung: Erkennt PuTTY-Private-Key-Dateien.
	# Parameter:    $1 = Dateipfad
	# Rueckgabewert: 0 wenn PPK, sonst 1
	# Fehlerfaelle: Datei unlesbar -> 1
	# Beispiel:     ist_ppk_datei ./sshkey.ppk
	#
	[ -f "$1" ] || return 1
	case "$1" in
		*.ppk|*.PPK) return 0 ;;
	esac
	head -n 1 "$1" 2>/dev/null | grep -q '^PuTTY-User-Key-File' || return 1
}

finde_privaten_partner() {
	#
	# Beschreibung: Sucht den privaten Schluessel zu einer .pub-Datei.
	# Parameter:    $1 = Pfad zur Public-Key-Datei
	# Rueckgabewert: privater Pfad auf stdout, Exit 0; sonst 1
	# Fehlerfaelle: kein privater Partner gefunden
	# Beispiel:     finde_privaten_partner ./sshkey.pub
	#
	_pub="$1"
	_dir=$(dirname -- "$_pub")
	_name=$(basename -- "$_pub" .pub)
	_skript=$(skript_verzeichnis)
	for _kandidat in \
		"${_dir}/${_name}" \
		"${_dir}/${_name}.ppk" \
		"${_dir}/${_name}.key" \
		"${_skript}/${_name}" \
		"${_skript}/${_name}.ppk" \
		"${_skript}/${DEFAULT_PPK}"
	do
		if [ -f "$_kandidat" ] && ! ist_oeffentlicher_schluessel "$_kandidat"; then
			printf '%s\n' "$_kandidat"
			return 0
		fi
	done
	return 1
}

konvertiere_ppk_nach_openssh() {
	#
	# Beschreibung: Wandelt .ppk via puttygen in einen Temp-OpenSSH-Key um.
	# Parameter:    keine (nutzt ppk_datei / ssh_passphrase)
	# Rueckgabewert: setzt openssh_tmp_key und ssh_identitaet
	# Fehlerfaelle: puttygen fehlt, PPK fehlt, Konvertierung scheitert
	# Beispiel:     konvertiere_ppk_nach_openssh
	#
	_pass_file=""
	command -v puttygen >/dev/null 2>&1 \
		|| beende_mit_fehler 4 "puttygen fehlt (Paket putty-tools fuer .ppk)."
	[ -f "$ppk_datei" ] || beende_mit_fehler 3 "PPK-Datei nicht gefunden: $ppk_datei"

	openssh_tmp_key=$(mktemp) || beende_mit_fehler 1 "mktemp fehlgeschlagen"
	chmod 600 "$openssh_tmp_key"

	if [ -n "$ssh_passphrase" ]; then
		_pass_file=$(mktemp) || beende_mit_fehler 1 "mktemp fehlgeschlagen"
		chmod 600 "$_pass_file"
		printf '%s' "$ssh_passphrase" > "$_pass_file"
		if ! puttygen "$ppk_datei" -O private-openssh -o "$openssh_tmp_key" \
			--old-passphrase "$_pass_file" >/dev/null 2>&1; then
			rm -f "$_pass_file"
			bereinige_tmp_key
			beende_mit_fehler 8 "PPK-Konvertierung fehlgeschlagen (Passphrase/Datei?)."
		fi
		rm -f "$_pass_file"
	else
		if ! puttygen "$ppk_datei" -O private-openssh -o "$openssh_tmp_key" \
			>/dev/null 2>&1; then
			bereinige_tmp_key
			beende_mit_fehler 8 "PPK-Konvertierung fehlgeschlagen (Passphrase noetig? -P)."
		fi
	fi
	ssh_identitaet="$openssh_tmp_key"
	info_meldung "PPK konvertiert: $ppk_datei"
}

setze_identitaet_aus_datei() {
	#
	# Beschreibung: Setzt Auth aus Keydatei (.pub-Partner, PPK oder OpenSSH).
	# Parameter:    $1 = aufgeloester Dateipfad
	# Rueckgabewert: 0 bei gesetzter Identitaet
	# Fehlerfaelle: .pub ohne privaten Partner
	# Beispiel:     setze_identitaet_aus_datei ./sshkey.pub
	#
	_datei="$1"
	if ist_oeffentlicher_schluessel "$_datei"; then
		_privat=$(finde_privaten_partner "$_datei") || \
			beende_mit_fehler 3 "$_datei ist oeffentlich. Privater Partner fehlt (z. B. sshkey oder sshkey.ppk daneben)."
		info_meldung "Public Key $_datei -> privater Schluessel $_privat"
		_datei="$_privat"
	fi
	if ist_ppk_datei "$_datei"; then
		ppk_datei="$_datei"
		if [ -n "$login_password" ] && [ -z "$ssh_passphrase" ]; then
			ssh_passphrase="$login_password"
		fi
		konvertiere_ppk_nach_openssh
		auth_modus="ppk"
		return 0
	fi
	ssh_identitaet="$_datei"
	auth_modus="openssh"
	info_meldung "Auth: OpenSSH-Key ($ssh_identitaet)"
}

bereite_authentifizierung() {
	#
	# Beschreibung: Waehlt Auth: OpenSSH-Key, PPK (sshkey) oder Passwort.
	# Parameter:    keine
	# Rueckgabewert: setzt auth_modus und ggf. ssh_identitaet
	# Fehlerfaelle: fehlende Datei/Tools
	# Beispiel:     bereite_authentifizierung
	#
	# Prioritaet: -Key/-ppk > -i > DEFAULT_PPK (Skriptverzeichnis) > sshkey.pub-Partner
	if [ -n "$ppk_datei" ]; then
		ppk_datei=$(loese_dateipfad "$ppk_datei")
		[ -f "$ppk_datei" ] || beende_mit_fehler 3 "Key-Datei nicht gefunden: $ppk_datei"
		setze_identitaet_aus_datei "$ppk_datei"
		return 0
	fi

	if [ -n "$ssh_identitaet" ]; then
		ssh_identitaet=$(loese_dateipfad "$ssh_identitaet")
		[ -f "$ssh_identitaet" ] || beende_mit_fehler 3 "Schluesseldatei nicht gefunden: $ssh_identitaet"
		setze_identitaet_aus_datei "$ssh_identitaet"
		return 0
	fi

	_default_ppk=$(loese_dateipfad "$DEFAULT_PPK")
	if [ -f "$_default_ppk" ]; then
		setze_identitaet_aus_datei "$_default_ppk"
		return 0
	fi

	_default_key=$(loese_dateipfad "$DEFAULT_SSHKEY")
	if [ -f "$_default_key" ]; then
		setze_identitaet_aus_datei "$_default_key"
		return 0
	fi

	if [ -n "$login_password" ]; then
		command -v sshpass >/dev/null 2>&1 \
			|| beende_mit_fehler 4 "sshpass fehlt (fuer Passwort-Login -P)."
		auth_modus="password"
		info_meldung "Auth: Passwort-Login"
		return 0
	fi

	beende_mit_fehler 1 "Keine Auth: $DEFAULT_SSHKEY / $DEFAULT_PPK fehlen und kein Passwort (-P)."
}

normalisiere_host() {
	#
	# Beschreibung: Entfernt Klammern und Leerzeichen von Host/IP-Angaben.
	# Parameter:    $1 = Host, IPv4 oder IPv6 (optional in [])
	# Rueckgabewert: bereinigter Host auf stdout
	# Fehlerfaelle: keine
	# Beispiel:     normalisiere_host "[2001:db8::1]"
	#
	_h=$(printf '%s' "$1" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
	_h="${_h#[}"
	_h="${_h%]}"
	printf '%s' "$_h"
}

ist_ipv4_adresse() {
	#
	# Beschreibung: Prueft, ob die Angabe eine IPv4-Adresse ist.
	# Parameter:    $1 = Hostangabe
	# Rueckgabewert: 0 wenn IPv4, sonst 1
	# Fehlerfaelle: keine
	# Beispiel:     ist_ipv4_adresse "192.168.178.42"
	#
	case "$1" in
		""|*[!0-9.]*) return 1 ;;
	esac
	_punkte=${1//[!.]/}
	[ "${#_punkte}" -eq 3 ]
}

ist_ipv6_adresse() {
	#
	# Beschreibung: Prueft, ob die Angabe eine IPv6-Adresse ist ([] optional).
	# Parameter:    $1 = Hostangabe (ohne oder mit [])
	# Rueckgabewert: 0 wenn IPv6, sonst 1
	# Fehlerfaelle: keine
	# Beispiel:     ist_ipv6_adresse "[2a06:8782:ffbb:42:3d5:2865:d9e5:57eb]"
	#
	_h=$(normalisiere_host "$1")
	_h="${_h%%\%*}"
	case "$_h" in
		""|*[!0-9a-fA-F:]*) return 1 ;;
	esac
	_doppel=${_h//[^:]/}
	[ "${#_doppel}" -ge 2 ]
}

ist_cli_option() {
	#
	# Beschreibung: Erkennt CLI-Optionen (beginnen mit -), nicht IPv6 in [].
	# Parameter:    $1 = Argument
	# Rueckgabewert: 0 wenn Option, sonst 1
	# Fehlerfaelle: keine
	# Beispiel:     ist_cli_option "-U"
	#
	case "$1" in
		\[*) return 1 ;;
		-*) return 0 ;;
	esac
	return 1
}

setze_cli_ziel() {
	#
	# Beschreibung: Uebernimmt ein Hostargument (Klammern werden entfernt).
	# Parameter:    $1 = Rohangabe, $2 = erwartete Familie (4|6|leer)
	# Rueckgabewert: keines (setzt ziel_host, _host_gesetzt)
	# Fehlerfaelle: doppelter Host, Familie passt nicht zur Adresse
	# Beispiel:     setze_cli_ziel "[2a06:8782::1]" 6
	#
	_neu=$(normalisiere_host "$1")
	[ -n "$_neu" ] || beende_mit_fehler 2 "Leere Hostangabe"
	if [ "${_host_gesetzt:-false}" = "true" ]; then
		beende_mit_fehler 2 "Host bereits gesetzt ($ziel_host), zusaetzlich: $_neu"
	fi
	if [ "${2:-}" = "6" ] && ist_ipv4_adresse "$_neu"; then
		beende_mit_fehler 2 "Nach -6 keine IPv4-Adresse: $_neu"
	fi
	if [ "${2:-}" = "4" ] && ist_ipv6_adresse "$_neu"; then
		beende_mit_fehler 2 "Nach -4 keine IPv6-Adresse: $_neu"
	fi
	ziel_host="$_neu"
	_host_gesetzt="true"
}

ping_ziel() {
	#
	# Beschreibung: Ein ICMP-Echo an das Ziel (Familie 4, 6 oder auto).
	# Parameter:    $1 = Host ohne Klammern, $2 = 4|6|leer
	# Rueckgabewert: 0 wenn erreichbar, sonst 1
	# Fehlerfaelle: ping fehlt oder Timeout
	# Beispiel:     ping_ziel "2a06:8782::1" 6
	#
	_z="$1"
	_f="${2:-}"
	case "$_f" in
		6)
			ping -6 -c 1 -W 2 "$_z" >/dev/null 2>&1 && return 0
			command -v ping6 >/dev/null 2>&1 && ping6 -c 1 -W 2 "$_z" >/dev/null 2>&1
			return $?
			;;
		4)
			ping -4 -c 1 -W 2 "$_z" >/dev/null 2>&1 && return 0
			ping -c 1 -W 2 "$_z" >/dev/null 2>&1
			return $?
			;;
		*)
			ping -c 1 -W 2 "$_z" >/dev/null 2>&1
			return $?
			;;
	esac
}

pruefe_erreichbarkeit() {
	#
	# Beschreibung: Ping vor SSH; IPv6 mit ping -6, ohne eckige Klammern.
	# Parameter:    $1 = optional "soft" -> Rueckgabe 1 statt Abbruch
	# Rueckgabewert: 0 erreichbar; soft: 1 bei Fehler, sonst Abbruch
	# Fehlerfaelle: Host antwortet nicht auf ICMP
	# Beispiel:     pruefe_erreichbarkeit
	#
	_host=$(normalisiere_host "$ziel_host")
	_fam="$ssh_familie"
	if [ -z "$_fam" ]; then
		ist_ipv6_adresse "$_host" && _fam="6"
		ist_ipv4_adresse "$_host" && _fam="4"
	fi
	info_meldung "Pruefe Erreichbarkeit von $_host (IPv${_fam:-auto}) ..."
	if ping_ziel "$_host" "$_fam"; then
		info_meldung "Host $_host ist erreichbar"
		return 0
	fi
	if [ "${1:-}" = "soft" ]; then
		fehler_melden "Host $_host nicht erreichbar (ping) - SSH wird nicht versucht"
		return 1
	fi
	beende_mit_fehler 1 "Host $_host nicht erreichbar (ping) - SSH wird nicht versucht"
}

passe_ssh_familie_an() {
	#
	# Beschreibung: Setzt ssh_familie passend zu Host und -4/-6.
	# Parameter:    $1 = Host, $2 = gewuenschte Familie (4|6|auto|leer)
	# Rueckgabewert: setzt ssh_familie (4, 6 oder leer)
	# Fehlerfaelle: IPv6 mit -4 bzw. IPv4 mit -6
	# Beispiel:     passe_ssh_familie_an "2001:db8::1" 6
	#
	_host="$1"
	_wunsch="${2:-}"
	ssh_familie=""
	if [ "$_wunsch" = "4" ] || [ "$_wunsch" = "6" ]; then
		ssh_familie="$_wunsch"
	elif ist_ipv6_adresse "$_host"; then
		ssh_familie="6"
	elif ist_ipv4_adresse "$_host"; then
		ssh_familie="4"
	fi
	if [ "$ssh_familie" = "4" ] && ist_ipv6_adresse "$_host"; then
		beende_mit_fehler 2 "IPv6-Adresse nicht mit -4 kombinierbar: $_host"
	fi
	if [ "$ssh_familie" = "6" ] && ist_ipv4_adresse "$_host"; then
		beende_mit_fehler 2 "IPv4-Adresse nicht mit -6 kombinierbar: $_host"
	fi
}

liste_eintrag_erlaubt() {
	#
	# Beschreibung: Filtert IP-Listen-Zeilen nach -4/-6.
	# Parameter:    $1 = Host/IP
	# Rueckgabewert: 0 wenn verarbeiten, sonst 1
	# Fehlerfaelle: keine
	# Beispiel:     liste_eintrag_erlaubt "2001:db8::1"
	#
	if [ "$flag_ipv4" = "true" ] && [ "$flag_ipv6" != "true" ]; then
		ist_ipv6_adresse "$1" && return 1
		return 0
	fi
	if [ "$flag_ipv6" = "true" ] && [ "$flag_ipv4" != "true" ]; then
		ist_ipv4_adresse "$1" && return 1
		return 0
	fi
	return 0
}

fuege_ziel_hinzu() {
	#
	# Beschreibung: Haengt ein Sammelziel (Host plus Adressfamilie) an.
	# Parameter:    $1 = Host, $2 = Familie (4|6|auto)
	# Rueckgabewert: keines (erweitert ziel_liste)
	# Fehlerfaelle: leerer Host
	# Beispiel:     fuege_ziel_hinzu "2001:db8::1" 6
	#
	_ziel=$(normalisiere_host "$1")
	[ -n "$_ziel" ] || beende_mit_fehler 2 "Leeres SSH-Ziel (DEFAULT_IPv4/IPv6 setzen oder Host angeben)"
	ziel_liste+=("${_ziel}|${2:-auto}")
}

baue_ssh_basis() {
	#
	# Beschreibung: Setzt SSH-Ziel; IPv6 wird fuer ssh geklammert.
	# Parameter:    keine
	# Rueckgabewert: setzt SSH_ZIEL
	# Fehlerfaelle: keine
	# Beispiel:     baue_ssh_basis
	#
	ziel_host=$(normalisiere_host "$ziel_host")
	if ist_ipv6_adresse "$ziel_host"; then
		SSH_ZIEL="${remote_user}@[${ziel_host}]"
	else
		SSH_ZIEL="${remote_user}@${ziel_host}"
	fi
}

ssh_remote() {
	#
	# Beschreibung: Fuehrt einen Befehl remote aus; Ausgabe lokal (stdout).
	# Parameter:    $1 = Remote-Kommando (eine Zeichenkette)
	# Rueckgabewert: Exit-Code von ssh
	# Fehlerfaelle: Verbindungs- oder Remote-Fehler
	# Beispiel:     ssh_remote "uname -a"
	#
	_remote_cmd="bash -c $(shell_single_quote "$1")"
	_rc=0
	_ssh=(ssh)
	if [ "$ssh_familie" = "4" ]; then
		_ssh+=(-4)
	elif [ "$ssh_familie" = "6" ]; then
		_ssh+=(-6)
	fi

	if [ "$auth_modus" = "password" ]; then
		SSHPASS="$login_password"
		export SSHPASS
		_ssh=(sshpass -e "${_ssh[@]}"
			-o StrictHostKeyChecking=accept-new
			-o PreferredAuthentications=keyboard-interactive,password
			-o PubkeyAuthentication=no
			-o PasswordAuthentication=yes
			-o KbdInteractiveAuthentication=yes
			-p "$ssh_port"
			"$SSH_ZIEL" "$_remote_cmd")
		"${_ssh[@]}"
		_rc=$?
		unset SSHPASS
		return "$_rc"
	fi

	_ssh+=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new
		-o IdentitiesOnly=yes
		-o PreferredAuthentications=publickey
		-p "$ssh_port" -i "$ssh_identitaet"
		"$SSH_ZIEL" "$_remote_cmd")
	"${_ssh[@]}"
}

schreibe_abschnitt() {
	#
	# Beschreibung: Schreibt Trennzeile und Befehlskopf in eine lokale Datei.
	# Parameter:    $1 = Zieldatei, $2 = Abschnittsueberschrift
	# Rueckgabewert: keines
	# Fehlerfaelle: Schreibfehler lokal
	# Beispiel:     schreibe_abschnitt "$OUTFILE" "uptime"
	#
	{
		echo ""
		echo "#------------------------------------------------------------------------------------------#"
		echo "##-> $2"
	} >> "$1"
}

sammle_befehl() {
	#
	# Beschreibung: Fuehrt einen Remote-Befehl aus und haengt lokal an.
	# Parameter:    $1 = Zieldatei, $2 = Remote-Kommando
	# Rueckgabewert: keines (Fehler werden in die Datei geschrieben)
	# Fehlerfaelle: SSH-/Remote-Fehler landen in der Ausgabedatei
	# Beispiel:     sammle_befehl "$OUTFILE" "uptime"
	#
	schreibe_abschnitt "$1" "$2"
	ssh_remote "$2" >> "$1" 2>&1 || true
	printf '%s' "."
}

sammle_befehlsliste() {
	#
	# Beschreibung: Fuehrt eine Liste Remote-Befehle nacheinander aus.
	# Parameter:    $1 = Zieldatei, restliche Argumente = Befehle
	# Rueckgabewert: keines
	# Fehlerfaelle: Einzelbefehl-Fehler werden lokal protokolliert
	# Beispiel:     sammle_befehlsliste "$OUTFILE" date uptime
	#
	_datei="$1"
	shift
	for _cmd in "$@"; do
		sammle_befehl "$_datei" "$_cmd"
	done
}

starte_sammeldatei() {
	#
	# Beschreibung: Legt eine Sammeldatei mit Titel und Zeitstempel an.
	# Parameter:    $1 = Datei, $2 = Titelzeile
	# Rueckgabewert: keines
	# Fehlerfaelle: lokale Schreibfehler
	# Beispiel:     starte_sammeldatei "$OUTFILE" "Linux-Check"
	#
	{
		echo "$2"
		echo "# Gestartet: $(zeitstempel)"
		echo "# Host: $ziel_host  User: $remote_user  Auth: $auth_modus"
		echo "#------------------------------------------------------------------------------------------#"
	} > "$1"
}

beende_sammeldatei() {
	#
	# Beschreibung: Schreibt die Abschlusszeile einer Sammeldatei.
	# Parameter:    $1 = Datei, $2 = Endetext
	# Rueckgabewert: keines
	# Fehlerfaelle: lokale Schreibfehler
	# Beispiel:     beende_sammeldatei "$OUTFILE" "Linux-Check Ende"
	#
	{
		echo ""
		echo "#------------------------------------------------------------------------------------------#"
		echo "$2 ($(zeitstempel))"
	} >> "$1"
	echo ""
}

# ---------------------------------------------------------------------------
# Sammelroutinen (kein Schreibzugriff auf dem Pi)
# ---------------------------------------------------------------------------

sammle_pi_check() {
	#
	# Beschreibung: System, Benutzer, Dienste und Logs (allfiles-Schleife).
	# Parameter:    keine
	# Rueckgabewert: keines
	# Fehlerfaelle: Einzelbefehl-Fehler werden lokal protokolliert
	# Beispiel:     sammle_pi_check
	#
	info_meldung "Linux-Check - Allgemein: Bitte etwas Geduld!"
	starte_sammeldatei "$OUTFILE" "Linux-Check - Raspberry Pi - Allgemein:"
	sammle_befehlsliste "$OUTFILE" \
		date \
		uptime \
		hostname \
		'hostname -f' \
		hostnamectl \
		timedatectl \
		localectl \
		'uname -a' \
		'uname -r' \
		'cat /etc/os-release' \
		'cat /etc/rpi-issue' \
		'cat /etc/debian_version' \
		'cat /etc/issue' \
		'cat /proc/cpuinfo' \
		'cat /proc/meminfo' \
		'free -h' \
		lscpu \
		nproc \
		'cat /proc/loadavg' \
		who \
		w \
		'last -n 30' \
		id \
		'cat /etc/passwd' \
		'cat /etc/group' \
		'cat /etc/shadow' \
		'ps aux' \
		'df -h' \
		'df -i' \
		'lsblk -a' \
		'lsblk -f' \
		mount \
		findmnt \
		'cat /etc/fstab' \
		'cat /proc/partitions' \
		'swapon --show' \
		'crontab -l' \
		'cat /etc/crontab' \
		'ls -la /etc/cron.d /etc/cron.daily /etc/cron.hourly /etc/cron.weekly /etc/cron.monthly' \
		'ls -la /var/log/' \
		'journalctl -b -n 200 --no-pager' \
		'dmesg -T | tail -n 300' \
		'systemctl --failed --no-pager' \
		'systemctl list-units --type=service --state=running --no-pager' \
		'cat /etc/sysctl.conf' \
		'lsmod' \
		'cat /etc/modules' \
		'cat /etc/rc.local' \
		'cat /etc/timezone' \
		'cat /etc/default/keyboard'
	beende_sammeldatei "$OUTFILE" "Linux-Check - Allgemein: Ende"
	info_meldung "Linux-Check - Allgemein: Ende"
}

sammle_pi_hardware() {
	#
	# Beschreibung: Raspberry-spezifische Hardware- und Firmware-Daten.
	# Parameter:    keine
	# Rueckgabewert: keines
	# Fehlerfaelle: fehlende Tools auf dem Pi sind unkritisch
	# Beispiel:     sammle_pi_hardware
	#
	info_meldung "Sammle Raspberry-Hardware ..."
	starte_sammeldatei "$HWFILE" "Raspberry-Pi-Hardware:"
	sammle_befehlsliste "$HWFILE" \
		'tr -d "\0" < /proc/device-tree/model' \
		'tr -d "\0" < /proc/device-tree/serial-number' \
		'tr -d "\0" < /proc/device-tree/compatible' \
		'ls -la /proc/device-tree' \
		'vcgencmd version' \
		'vcgencmd measure_temp' \
		'vcgencmd measure_volts' \
		'vcgencmd measure_volts core' \
		'vcgencmd measure_volts sdram_c' \
		'vcgencmd measure_volts sdram_i' \
		'vcgencmd measure_volts sdram_p' \
		'vcgencmd get_throttled' \
		'vcgencmd get_config int' \
		'vcgencmd get_config str' \
		'vcgencmd get_mem arm' \
		'vcgencmd get_mem gpu' \
		'vcgencmd bootloader_version' \
		'vcgencmd bootloader_config' \
		'vcgencmd otp_dump' \
		'vcgencmd get_camera' \
		'vcgencmd display_power' \
		'vcgencmd get_lcd_info' \
		'cat /sys/class/thermal/thermal_zone0/temp' \
		'cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq' \
		'cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor' \
		lsusb \
		'lsusb -t' \
		'ls -la /dev/i2c* /dev/spidev* /dev/gpiomem /dev/ttyAMA* /dev/serial* /dev/video*' \
		'i2cdetect -l' \
		pinout \
		'raspi-gpio readall' \
		pinctrl \
		'tvservice -s' \
		'ls -la /boot /boot/firmware' \
		'cat /boot/config.txt' \
		'cat /boot/cmdline.txt' \
		'cat /boot/firmware/config.txt' \
		'cat /boot/firmware/cmdline.txt' \
		'cat /boot/issue.txt' \
		'ls /boot/overlays' \
		'rpi-eeprom-update' \
		'rpi-eeprom-config' \
		'cat /proc/asound/cards' \
		'libcamera-hello --list-cameras --timeout 1'
	beende_sammeldatei "$HWFILE" "Raspberry-Pi-Hardware: Ende"
	info_meldung "Raspberry-Hardware: Ende"
}

sammle_pi_config() {
	#
	# Beschreibung: Holt Konfigurationsdateien, SSH-Keys und Sudoers lokal.
	# Parameter:    keine
	# Rueckgabewert: keines
	# Fehlerfaelle: SSH-Fehler werden in CONFFILE festgehalten
	# Beispiel:     sammle_pi_config
	#
	info_meldung "Sammle Konfigurationen ..."
	starte_sammeldatei "$CONFFILE" "Raspberry-Pi-Konfiguration:"
	sammle_befehlsliste "$CONFFILE" \
		'cat /etc/hostname' \
		'cat /etc/hosts' \
		'cat /etc/resolv.conf' \
		'cat /etc/nsswitch.conf' \
		'cat /etc/ssh/sshd_config' \
		'ls -la /etc/ssh/sshd_config.d' \
		'for f in /etc/ssh/sshd_config.d/*; do [ -f "$f" ] && echo "## FILE: $f" && cat "$f"; done' \
		'cat /root/.ssh/authorized_keys' \
		'ls -la /root/.ssh' \
		'for h in /home/*; do echo "## HOME: $h"; ls -la "$h/.ssh" 2>/dev/null; echo "## authorized_keys"; cat "$h/.ssh/authorized_keys" 2>/dev/null; done' \
		'cat /etc/sudoers' \
		'ls -la /etc/sudoers.d' \
		'for f in /etc/sudoers.d/*; do [ -f "$f" ] && echo "## FILE: $f" && cat "$f"; done' \
		'cat /etc/login.defs' \
		'cat /etc/security/limits.conf' \
		'ls -la /etc/systemd/system' \
		'cat /etc/default/raspi-firmware' \
		'ls -la /etc/modprobe.d' \
		'for f in /etc/modprobe.d/*; do [ -f "$f" ] && echo "## FILE: $f" && cat "$f"; done' \
		'ls -la /etc/udev/rules.d' \
		'for f in /etc/udev/rules.d/*; do [ -f "$f" ] && echo "## FILE: $f" && cat "$f"; done' \
		'ls -la /etc/sysctl.d' \
		'for f in /etc/sysctl.d/*; do [ -f "$f" ] && echo "## FILE: $f" && cat "$f"; done' \
		'ls -la /etc/modules-load.d' \
		'cat /etc/locale.gen' \
		'ls -la /etc'
	beende_sammeldatei "$CONFFILE" "Raspberry-Pi-Konfiguration: Ende"
	info_meldung "Konfigurationen: Ende"
}

sammle_pi_netzwerk() {
	#
	# Beschreibung: Sammelt Adressen, Routen, Sockets und WLAN-Konfiguration.
	# Parameter:    keine
	# Rueckgabewert: keines
	# Fehlerfaelle: fehlende Tools auf dem Pi sind unkritisch
	# Beispiel:     sammle_pi_netzwerk
	#
	info_meldung "Sammle Netzwerk ..."
	starte_sammeldatei "$NETFILE" "Raspberry-Pi-Netzwerk:"
	sammle_befehlsliste "$NETFILE" \
		'ip addr' \
		'ip -s link' \
		'ip route' \
		'ip -6 route' \
		'ip rule' \
		'ip neigh' \
		"ss -tulpen | $TABELLEN_AUSRICHTUNG" \
		'ss -s' \
		'hostname -I' \
		'cat /etc/network/interfaces' \
		'ls -la /etc/network/interfaces.d' \
		'cat /etc/dhcpcd.conf' \
		'ls -la /etc/netplan' \
		'for f in /etc/netplan/*; do [ -f "$f" ] && echo "## FILE: $f" && cat "$f"; done' \
		'nmcli general status' \
		'nmcli device' \
		'nmcli connection show' \
		iwconfig \
		'iw dev' \
		'iw list' \
		'rfkill list' \
		'cat /etc/wpa_supplicant/wpa_supplicant.conf' \
		'resolvectl status' \
		'cat /etc/avahi/avahi-daemon.conf' \
		"netstat -tulpe | $TABELLEN_AUSRICHTUNG" \
		"netstat -rn | $TABELLEN_AUSRICHTUNG"
	beende_sammeldatei "$NETFILE" "Raspberry-Pi-Netzwerk: Ende"
	info_meldung "Netzwerk: Ende"
}

sammle_firewall_netfilter() {
	#
	# Beschreibung: Sammelt Firewall- und Netfilter-Konfiguration lokal.
	# Parameter:    keine
	# Rueckgabewert: keines
	# Fehlerfaelle: fehlende Tools auf dem Pi sind unkritisch
	# Beispiel:     sammle_firewall_netfilter
	#
	info_meldung "Sammle Firewall und Netfilter ..."
	starte_sammeldatei "$FWFILE" "Firewall- und Netfilter-Check:"
	sammle_befehlsliste "$FWFILE" \
		"iptables -L -v -n | $TABELLEN_AUSRICHTUNG" \
		"iptables -t nat -L -v -n | $TABELLEN_AUSRICHTUNG" \
		"iptables -t mangle -L -v -n | $TABELLEN_AUSRICHTUNG" \
		'iptables-save' \
		"ip6tables -L -v -n | $TABELLEN_AUSRICHTUNG" \
		'ip6tables-save' \
		'nft list ruleset' \
		'nft list tables' \
		'ufw status verbose' \
		'ufw status numbered' \
		'cat /etc/ufw/ufw.conf' \
		'firewall-cmd --list-all' \
		'cat /etc/nftables.conf'
	beende_sammeldatei "$FWFILE" "Firewall-/Netfilter-Check: Ende"
	info_meldung "Firewall-/Netfilter-Check: Ende"
}

sammle_pi_pakete() {
	#
	# Beschreibung: Sammelt Paketlisten, APT-Quellen und systemd-Units.
	# Parameter:    keine
	# Rueckgabewert: keines
	# Fehlerfaelle: fehlende Tools auf dem Pi sind unkritisch
	# Beispiel:     sammle_pi_pakete
	#
	info_meldung "Sammle Pakete und Dienste ..."
	starte_sammeldatei "$PKGFILE" "Raspberry-Pi-Pakete und Dienste:"
	sammle_befehlsliste "$PKGFILE" \
		'dpkg -l' \
		'apt-mark showhold' \
		'cat /etc/apt/sources.list' \
		'ls -la /etc/apt/sources.list.d' \
		'for f in /etc/apt/sources.list.d/*; do [ -f "$f" ] && echo "## FILE: $f" && cat "$f"; done' \
		'systemctl list-unit-files --type=service --no-pager' \
		'docker version' \
		'docker ps -a' \
		'docker images' \
		'podman ps -a'
	beende_sammeldatei "$PKGFILE" "Raspberry-Pi-Pakete: Ende"
	info_meldung "Pakete und Dienste: Ende"
}

pruefe_ssh_verbindung() {
	#
	# Beschreibung: Testet die SSH-Erreichbarkeit des Raspberry Pi.
	# Parameter:    $1 = optional "soft" -> Rueckgabe 1 statt Abbruch
	# Rueckgabewert: 0 bei Erfolg; soft: 1 bei Fehler, sonst Abbruch
	# Fehlerfaelle: Host unerreichbar / Auth fehlgeschlagen
	# Beispiel:     pruefe_ssh_verbindung
	#
	info_meldung "Pruefe SSH-Verbindung zu $SSH_ZIEL ..."
	if ssh_remote "echo ok" >/dev/null 2>&1; then
		info_meldung "SSH-Verbindung erfolgreich"
		return 0
	fi
	if [ "${1:-}" = "soft" ]; then
		fehler_melden "SSH-Verbindung zu $SSH_ZIEL fehlgeschlagen"
		return 1
	fi
	beende_mit_fehler 1 "SSH-Verbindung zu $SSH_ZIEL fehlgeschlagen"
}

sammle_einen_host() {
	#
	# Beschreibung: Sammelt Daten eines Zielhosts in ein Hostname-Verzeichnis.
	# Parameter:    $1 = Zielhost (IP/Name), $2 = "liste" fuer Soft-Fehler,
	#               $3 = Adressfamilie (4|6|auto|leer)
	# Rueckgabewert: 0 bei Erfolg, 1 bei Soft-Fehler
	# Fehlerfaelle: SSH/Hostname; bei Liste weiter, sonst Abbruch
	# Beispiel:     sammle_einen_host "2001:db8::42" "" 6
	#
	ziel_host=$(normalisiere_host "$1")
	_modus="${2:-}"
	passe_ssh_familie_an "$ziel_host" "${3:-}"
	baue_ssh_basis
	if [ "$_modus" = "liste" ]; then
		pruefe_erreichbarkeit soft || return 1
		pruefe_ssh_verbindung soft || return 1
	else
		pruefe_erreichbarkeit
		pruefe_ssh_verbindung
	fi

	_hostdir=$(ermittle_hostname_verzeichnis)
	if [ "$ssh_familie" = "4" ] || [ "$ssh_familie" = "6" ]; then
		_hostdir="${_hostdir}-ipv${ssh_familie}"
	fi
	ausgabe_verzeichnis="${basis_ausgabe}/${_hostdir}"
	info_meldung "Ausgabeverzeichnis: $ausgabe_verzeichnis (Host $ziel_host Familie ${ssh_familie:-auto})"
	setze_ausgabepfade

	log_nachricht "START host=$ziel_host familie=$ssh_familie user=$remote_user auth=$auth_modus out=$ausgabe_verzeichnis"
	sammle_pi_check
	sammle_pi_hardware
	sammle_pi_config
	sammle_pi_netzwerk
	sammle_firewall_netfilter
	sammle_pi_pakete
	info_meldung "Ergebnisse: $OUTFILE, $CONFFILE, $HWFILE, $NETFILE, $FWFILE, $PKGFILE"
	log_nachricht "ENDE host=$ziel_host erfolgreich"
	return 0
}

verarbeite_ip_liste() {
	#
	# Beschreibung: Liest --IPListe und sammelt jeden Eintrag.
	# Parameter:    keine (nutzt ip_liste_datei)
	# Rueckgabewert: keines; setzt liste_fehler
	# Fehlerfaelle: Datei fehlt/leer; Einzelhosts werden uebersprungen
	# Beispiel:     verarbeite_ip_liste
	#
	[ -f "$ip_liste_datei" ] || beende_mit_fehler 2 "IP-Liste nicht gefunden: $ip_liste_datei"
	_anzahl=0
	liste_fehler=0
	while IFS= read -r _zeile || [ -n "$_zeile" ]; do
		_zeile=$(normalisiere_host "$_zeile")
		case "$_zeile" in
			""|\#*) continue ;;
		esac
		if ! liste_eintrag_erlaubt "$_zeile"; then
			log_nachricht "FILTER host=$_zeile"
			continue
		fi
		_anzahl=$((_anzahl + 1))
		_fam="auto"
		if ist_ipv6_adresse "$_zeile"; then
			_fam="6"
		elif ist_ipv4_adresse "$_zeile"; then
			_fam="4"
		elif [ "$flag_ipv6" = "true" ] && [ "$flag_ipv4" != "true" ]; then
			_fam="6"
		elif [ "$flag_ipv4" = "true" ] && [ "$flag_ipv6" != "true" ]; then
			_fam="4"
		fi
		if [ "$_fam" = "auto" ]; then
			info_meldung "=== Liste $_anzahl: $_zeile (auto) ==="
		else
			info_meldung "=== Liste $_anzahl: $_zeile (IPv$_fam) ==="
		fi
		if ! sammle_einen_host "$_zeile" liste "$_fam"; then
			liste_fehler=$((liste_fehler + 1))
			log_nachricht "SKIP host=$_zeile"
		fi
	done < "$ip_liste_datei"
	[ "$_anzahl" -gt 0 ] || beende_mit_fehler 2 "IP-Liste enthaelt keine gueltigen Eintraege: $ip_liste_datei"
	info_meldung "IP-Liste fertig: $_anzahl Ziel(e), Fehler: $liste_fehler"
}

lege_ziel_liste_fest() {
	#
	# Beschreibung: Baut die Zielliste aus Host und -4/-6.
	# Parameter:    $1 = "true" wenn ein Host-Argument gesetzt wurde
	# Rueckgabewert: keines (setzt ziel_liste)
	# Fehlerfaelle: leere Defaults ohne Host
	# Beispiel:     lege_ziel_liste_fest true
	#
	_gesetzt="$1"
	ziel_liste=()
	if [ "$_gesetzt" = "true" ] && [ -n "$ziel_host" ]; then
		_ziel=$(normalisiere_host "$ziel_host")
		if ist_ipv6_adresse "$_ziel"; then
			if [ "$flag_ipv4" = "true" ] && [ "$flag_ipv6" != "true" ]; then
				beende_mit_fehler 2 "IPv6-Adresse nicht mit nur -4 kombinierbar: $_ziel"
			fi
			fuege_ziel_hinzu "$_ziel" 6
			return 0
		fi
		if ist_ipv4_adresse "$_ziel"; then
			if [ "$flag_ipv6" = "true" ] && [ "$flag_ipv4" != "true" ]; then
				beende_mit_fehler 2 "IPv4-Adresse nicht mit nur -6 kombinierbar: $_ziel"
			fi
			fuege_ziel_hinzu "$_ziel" 4
			return 0
		fi
		if [ "$flag_ipv4" = "true" ] && [ "$flag_ipv6" = "true" ]; then
			fuege_ziel_hinzu "$_ziel" 4
			fuege_ziel_hinzu "$_ziel" 6
		elif [ "$flag_ipv4" = "true" ]; then
			fuege_ziel_hinzu "$_ziel" 4
		elif [ "$flag_ipv6" = "true" ]; then
			fuege_ziel_hinzu "$_ziel" 6
		else
			fuege_ziel_hinzu "$_ziel" auto
		fi
		return 0
	fi

	_v4="${DEFAULT_IPv4:-$DEFAULT_HOST}"
	_v6="${DEFAULT_IPv6:-$DEFAULT_HOST}"
	if [ "$flag_ipv4" = "true" ] && [ "$flag_ipv6" = "true" ]; then
		info_meldung "Kein Host - sammle DEFAULT IPv4 ($_v4) und IPv6 ($_v6)"
		fuege_ziel_hinzu "$_v4" 4
		fuege_ziel_hinzu "$_v6" 6
	elif [ "$flag_ipv4" = "true" ]; then
		info_meldung "Kein Host - verwende IPv4 ($_v4)"
		fuege_ziel_hinzu "$_v4" 4
	elif [ "$flag_ipv6" = "true" ]; then
		info_meldung "Kein Host - verwende IPv6 ($_v6)"
		fuege_ziel_hinzu "$_v6" 6
	else
		info_meldung "Kein Host angegeben - verwende DEFAULT_HOST ($DEFAULT_HOST)"
		fuege_ziel_hinzu "$DEFAULT_HOST" auto
	fi
}

parse_argumente() {
	#
	# Beschreibung: Parst Aufrufparameter und setzt globale Variablen.
	# Parameter:    alle Skriptargumente
	# Rueckgabewert: keines
	# Fehlerfaelle: unbekannte/fehlerhafte Parameter -> Abbruch
	# Beispiel:     parse_argumente "$@"
	#
	_host_gesetzt="false"
	_ppk_cli=""
	_ident_cli=""
	_pass_cli=""
	_pass_cli_gesetzt="false"
	_ipliste_gesetzt="false"
	_key_cli=""

	while [ $# -gt 0 ]; do
		case "$1" in
			-h|--help)
				zeige_hilfe
				exit 0
				;;
			--version)
				zeige_version
				exit 0
				;;
			--log)
				logging_aktiv="true"
				shift
				;;
			-E|--Ende)
				warte_am_ende="true"
				shift
				;;
			--IPListe)
				[ -n "${2:-}" ] || beende_mit_fehler 2 "Parameter --IPListe erfordert eine Datei"
				ip_liste_datei="$2"
				_ipliste_gesetzt="true"
				shift 2
				;;
			-4|--ipv4)
				flag_ipv4="true"
				shift
				if [ $# -gt 0 ] && ! ist_cli_option "$1"; then
					setze_cli_ziel "$1" 4
					shift
				fi
				;;
			-6|--ipv6)
				flag_ipv6="true"
				shift
				if [ $# -gt 0 ] && ! ist_cli_option "$1"; then
					setze_cli_ziel "$1" 6
					shift
				fi
				;;
			-U)
				[ -n "${2:-}" ] || beende_mit_fehler 2 "Parameter -U erfordert einen Benutzernamen"
				remote_user="$2"
				shift 2
				;;
			-p)
				[ -n "${2:-}" ] || beende_mit_fehler 2 "Parameter -p erfordert einen Port"
				case "$2" in
					*[!0-9]*) beende_mit_fehler 2 "Ungueltiger Port: $2" ;;
				esac
				ssh_port="$2"
				shift 2
				;;
			-Key|--Key|-key)
				[ -n "${2:-}" ] || beende_mit_fehler 2 "Parameter -Key erfordert eine Schluesseldatei (Beispiel: -Key sshkey.ppk)"
				_key_cli="$2"
				shift 2
				;;
			-i)
				[ -n "${2:-}" ] || beende_mit_fehler 2 "Parameter -i erfordert eine Schluesseldatei"
				_ident_cli="$2"
				shift 2
				;;
			-ppk|--ppk)
				[ -n "${2:-}" ] || beende_mit_fehler 2 "Parameter -ppk erfordert eine Datei.ppk"
				_ppk_cli="$2"
				shift 2
				;;
			-P)
				[ -n "${2:-}" ] || beende_mit_fehler 2 "Parameter -P erfordert Passwort oder Passphrase"
				_pass_cli="$2"
				_pass_cli_gesetzt="true"
				shift 2
				;;
			-o)
				[ -n "${2:-}" ] || beende_mit_fehler 2 "Parameter -o erfordert ein Verzeichnis"
				basis_ausgabe="$2"
				ausgabe_verzeichnis="$2"
				shift 2
				;;
			--)
				shift
				break
				;;
			-*)
				beende_mit_fehler 2 "Unbekannter Parameter: $1 (siehe --help)"
				;;
			*)
				setze_cli_ziel "$1" ""
				shift
				;;
		esac
	done

	while [ $# -gt 0 ]; do
		setze_cli_ziel "$1" ""
		shift
	done

	if [ "$_ipliste_gesetzt" = "true" ] && [ "$_host_gesetzt" = "true" ]; then
		beende_mit_fehler 2 "--IPListe und einzelner Host schliessen sich aus (siehe --help)"
	fi

	if [ "$_ipliste_gesetzt" = "true" ]; then
		[ -f "$ip_liste_datei" ] || beende_mit_fehler 2 "IP-Liste nicht gefunden: $ip_liste_datei"
	else
		lege_ziel_liste_fest "$_host_gesetzt"
	fi

	if [ -n "$_key_cli" ]; then
		ppk_datei="$_key_cli"
	fi
	if [ -n "$_ident_cli" ]; then
		ssh_identitaet="$_ident_cli"
	fi
	if [ -n "$_ppk_cli" ] && [ -z "$ppk_datei" ]; then
		ppk_datei="$_ppk_cli"
	fi
	if [ "$_pass_cli_gesetzt" = "true" ]; then
		login_password="$_pass_cli"
		ssh_passphrase="$_pass_cli"
	fi
}

hauptschleife() {
	#
	# Beschreibung: Orchestriert die lokalen Sammelvorgaenge.
	# Parameter:    keine
	# Rueckgabewert: keines
	# Fehlerfaelle: siehe Unterfunktionen
	# Beispiel:     hauptschleife
	#
	pruefe_voraussetzungen
	mkdir -p "$basis_ausgabe" \
		|| beende_mit_fehler 1 "Basisverzeichnis nicht anlegbar: $basis_ausgabe"
	LOGDATEI="${basis_ausgabe}/${DEFAULT_LOGFILE}"
	bereite_authentifizierung

	if [ -n "$ip_liste_datei" ]; then
		verarbeite_ip_liste
		if [ "$liste_fehler" -gt 0 ]; then
			info_meldung "Programm beendet mit $liste_fehler Fehler(n)."
			exit 1
		fi
	else
		for _eintrag in "${ziel_liste[@]}"; do
			_ziel="${_eintrag%|*}"
			_fam="${_eintrag##*|}"
			sammle_einen_host "$_ziel" "" "$_fam"
		done
	fi

	info_meldung "Programm beendet."
}

# ---------------------------------------------------------------------------
# Hauptprogramm
# ---------------------------------------------------------------------------

trap aufraeumen_beim_exit EXIT

parse_argumente "$@"
hauptschleife

exit 0
