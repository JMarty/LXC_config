#!/usr/bin/env bash
#
# bootstrap-ubuntu.sh
# Friss Ubuntu minimal (pl. Proxmox LXC) elokeszitese a Marveen telepitojehez.
#
#  1. Rendszer frissitese (apt update && upgrade)
#  2. Szukseges csomagok telepitese
#  3. UTF-8 locale telepitese es beallitasa (ekezetek helyes megjelenitese)
#  4. Uj felhasznalo letrehozasa (nev + jelszo bekerese)
#  5. Felhasznalo hozzaadasa a sudo csoporthoz
#  6. Kerdes: kelljen-e jelszo a sudo hasznalatakor (sudoers beallitas)
#
# Futtatas ROOT-kent:
#   chmod +x bootstrap-ubuntu.sh
#   ./bootstrap-ubuntu.sh
#
set -euo pipefail

# --- Szinek ---
BOLD='\033[1m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; DIM='\033[2m'; NC='\033[0m'
ok()   { echo -e "  ${GREEN}✔${NC} $*"; }
info() { echo -e "  ${DIM}$*${NC}"; }
warn() { echo -e "  ${YELLOW}!${NC} $*"; }
err()  { echo -e "  ${RED}✗${NC} $*" >&2; }

# --- Root ellenorzes ---
if [ "$(id -u)" -ne 0 ]; then
  err "Ezt a scriptet root-kent kell futtatni (vagy: sudo ./bootstrap-ubuntu.sh)"
  exit 1
fi

# --- apt-get megléte (Ubuntu/Debian ellenorzes) ---
if ! command -v apt-get >/dev/null 2>&1; then
  err "Nem talalhato apt-get -- ez a script csak Ubuntu/Debian rendszeren fut."
  exit 1
fi

echo
echo -e "${BOLD}=== 1/6  Rendszer frissitese ===${NC}"
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get -y upgrade
ok "Rendszer frissitve"

echo
echo -e "${BOLD}=== 2/6  Csomagok telepitese ===${NC}"
PACKAGES=(
  sudo git curl wget ca-certificates gnupg
  build-essential python3
  zstd xz-utils bzip2 unzip tar
  lsb-release apt-transport-https
  locales
  sqlite3
)
apt-get install -y "${PACKAGES[@]}"
ok "Csomagok telepitve: ${PACKAGES[*]}"

echo
echo -e "${BOLD}=== 3/6  UTF-8 locale beallitasa ===${NC}"
# Friss Ubuntu minimal gyakran C/POSIX locale-ben fut -> ekezetes karakterek
# elromlanak a terminalon. Itt legeneraljuk az UTF-8 locale-okat es beallitjuk
# az alapertelmezett LANG-ot. (en_US.UTF-8 a default a szoftver-kompatibilitas
# miatt; a hu_HU.UTF-8-at is legeneraljuk, ha magyar locale-t szeretnel.)
DEFAULT_LOCALE="en_US.UTF-8"
for loc in en_US.UTF-8 hu_HU.UTF-8; do
  if ! grep -qE "^\s*${loc}\s+UTF-8" /etc/locale.gen 2>/dev/null; then
    echo "${loc} UTF-8" >> /etc/locale.gen
  else
    sed -i -E "s/^#\s*(${loc}\s+UTF-8)/\1/" /etc/locale.gen
  fi
done
locale-gen >/dev/null 2>&1
update-locale LANG="$DEFAULT_LOCALE" LC_ALL="$DEFAULT_LOCALE"
# Az aktualis shellre is ervenyesitjuk (kulonben csak ujabb login utan lat)
export LANG="$DEFAULT_LOCALE" LC_ALL="$DEFAULT_LOCALE"
ok "UTF-8 locale beallitva: $DEFAULT_LOCALE (hu_HU.UTF-8 is elerheto)"
info "Uj SSH-session / re-login utan lesz teljesen ervenyes minden processre."

echo
echo -e "${BOLD}=== 4/6  Uj felhasznalo letrehozasa ===${NC}"

# --- Felhasznalonev bekerese + validalas ---
while true; do
  read -rp "  Uj felhasznalonev: " NEW_USER
  if [[ ! "$NEW_USER" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
    warn "Ervenytelen nev. Csak kisbetuk/szamok/_/- , es betuvel vagy _-rel kezdodjon."
    continue
  fi
  if id "$NEW_USER" >/dev/null 2>&1; then
    warn "A(z) '$NEW_USER' felhasznalo mar letezik. Valassz masikat (vagy Ctrl+C)."
    continue
  fi
  break
done

# --- Jelszo bekerese (rejtett, megerositessel) ---
while true; do
  read -rsp "  Jelszo: " PW1; echo
  if [ -z "$PW1" ]; then
    warn "A jelszo nem lehet ures."
    continue
  fi
  read -rsp "  Jelszo megegyszer: " PW2; echo
  if [ "$PW1" != "$PW2" ]; then
    warn "A ket jelszo nem egyezik. Probald ujra."
    continue
  fi
  break
done

# --- Felhasznalo letrehozasa ---
useradd -m -s /bin/bash "$NEW_USER"
echo "${NEW_USER}:${PW1}" | chpasswd
unset PW1 PW2
ok "Felhasznalo letrehozva: $NEW_USER (home: /home/$NEW_USER)"

echo
echo -e "${BOLD}=== 5/6  Sudo jogosultsag ===${NC}"
usermod -aG sudo "$NEW_USER"
ok "$NEW_USER hozzaadva a 'sudo' csoporthoz"

echo
echo -e "${BOLD}=== 6/6  Sudo jelszo-politika ===${NC}"
echo -e "  Kelljen-e jelszo, amikor ez a felhasznalo ${BOLD}sudo${NC}-t hasznal?"
echo -e "    ${DIM}[i] Igen  - minden sudo parancsnal kell a jelszo (biztonsagosabb, alapertelmezett)${NC}"
echo -e "    ${DIM}[n] Nem   - sudo jelszo nelkul (kenyelmesebb, NOPASSWD a sudoers-ben)${NC}"

while true; do
  read -rp "  Kelljen jelszo a sudo-hoz? [I/n]: " ANS
  ANS="${ANS:-i}"   # ures = alapertelmezett: Igen
  case "$ANS" in
    [Ii]|[Ii]gen)
      info "Marad az alapertelmezett: a sudo jelszot ker."
      # A 'sudo' csoport tagsaga ele mar adja a jelszavas sudo-t,
      # kulon sudoers fajl nem kell.
      SUDOERS_NOTE="jelszo SZUKSEGES"
      break
      ;;
    [Nn]|[Nn]em)
      SUDOERS_FILE="/etc/sudoers.d/90-${NEW_USER}-nopasswd"
      echo "${NEW_USER} ALL=(ALL) NOPASSWD:ALL" > "$SUDOERS_FILE"
      chmod 0440 "$SUDOERS_FILE"
      # Szintaktikai ellenorzes -- ha hibas, toroljuk, hogy ne torjuk el a sudot
      if visudo -cf "$SUDOERS_FILE" >/dev/null 2>&1; then
        ok "Sudo jelszo nelkul beallitva: $SUDOERS_FILE"
        SUDOERS_NOTE="jelszo NEM szukseges (NOPASSWD)"
      else
        rm -f "$SUDOERS_FILE"
        err "A sudoers fajl ervenytelen lett, eltavolitva. Marad a jelszavas sudo."
        SUDOERS_NOTE="jelszo SZUKSEGES (NOPASSWD beallitas sikertelen)"
      fi
      break
      ;;
    *)
      warn "Valaszolj: i (igen) vagy n (nem)."
      ;;
  esac
done

echo
echo -e "${BOLD}=== Elso fazis kesz ===${NC}"
ok "Felhasznalo:     $NEW_USER"
ok "Sudo:            tagja a 'sudo' csoportnak, $SUDOERS_NOTE"

# --- A gep elsodleges IP-cimenek kideritese ---
PRIMARY_IP="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}')"
[ -z "$PRIMARY_IP" ] && PRIMARY_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
[ -z "$PRIMARY_IP" ] && PRIMARY_IP="<a-gep-ip-cime>"

echo
echo -e "${BOLD}Most jelentkezz be a tavoli gepre terminalon keresztul:${NC}"
echo
echo -e "    ${GREEN}ssh ${NEW_USER}@${PRIMARY_IP}${NC}"
echo
info "Masold be a fenti parancsot a sajat geped terminaljaba."

# Ha tobb IP is van (pl. tobb halozati interfesz), listazzuk oket
ALL_IPS="$(hostname -I 2>/dev/null)"
if [ -n "$ALL_IPS" ] && [ "$(echo "$ALL_IPS" | wc -w)" -gt 1 ]; then
  echo
  info "A gepnek tobb IP-cime is van, ha a fenti nem jo, probald valamelyiket:"
  for ip in $ALL_IPS; do
    echo -e "      ${DIM}ssh ${NEW_USER}@${ip}${NC}"
  done
fi

echo
info "Bejelentkezes utan jon a Marveen telepitese (git clone + ./install.sh)."
