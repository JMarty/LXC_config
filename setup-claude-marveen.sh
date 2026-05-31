#!/usr/bin/env bash
#
# setup-claude-marveen.sh  —  2. fazis (sima felhasznalokent futtatva!)
#
#  1. Claude Code telepitese
#  2. .bashrc: 'claudegod' alias = claude --dangerously-skip-permissions
#  3. .bashrc: minden belepeskor kiir egy emlekeztetot a claudegod parancsrol
#  4. Felkinalja a Marveen telepiteset
#
# Futtatas a sajat (NEM root) felhasznaloddal, miutan SSH-val beleptel:
#   curl -fsSL <RAW_URL> -o setup-claude-marveen.sh && bash setup-claude-marveen.sh
#
set -euo pipefail

BOLD='\033[1m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; DIM='\033[2m'; NC='\033[0m'
ok()   { echo -e "  ${GREEN}✔${NC} $*"; }
info() { echo -e "  ${DIM}$*${NC}"; }
warn() { echo -e "  ${YELLOW}!${NC} $*"; }
err()  { echo -e "  ${RED}✗${NC} $*" >&2; }

# --- NE root-kent fusson (a claude, az alias es a Marveen mind user-szintu) ---
if [ "$(id -u)" -eq 0 ]; then
  err "Ezt a scriptet a sajat (nem root) felhasznaloddal futtasd, ne root-kent."
  err "Lepj at:  su - <felhasznalonev>   majd futtasd ujra."
  exit 1
fi

# --- curl megléte (a telepitokhoz kell) ---
if ! command -v curl >/dev/null 2>&1; then
  err "A curl nincs telepitve. Eloszor futtasd az 1. fazis (bootstrap) scriptet."
  exit 1
fi

BASHRC="$HOME/.bashrc"
[ -f "$BASHRC" ] || touch "$BASHRC"

echo
echo -e "${BOLD}=== 1/5  Claude Code telepitese ===${NC}"
# A ~/.local/bin az aktualis sessionre is keruljon a PATH-ra
export PATH="$HOME/.local/bin:$HOME/.bun/bin:$PATH"
if command -v claude >/dev/null 2>&1; then
  ok "Claude Code mar telepitve: $(claude --version 2>/dev/null | head -1)"
else
  info "Hivatalos telepito futtatasa (https://claude.ai/install.sh)..."
  curl -fsSL https://claude.ai/install.sh | bash
  export PATH="$HOME/.local/bin:$HOME/.bun/bin:$PATH"
  if command -v claude >/dev/null 2>&1; then
    ok "Claude Code telepitve: $(claude --version 2>/dev/null | head -1)"
  else
    warn "A 'claude' nem talalhato a PATH-on. Uj terminal / re-login utan probald: claude --version"
  fi
fi

echo
echo -e "${BOLD}=== 2/5  'claudegod' alias + belepesi emlekezteto ===${NC}"
# Idempotens: marker-blokk a .bashrc-ben; ha mar ott van, nem duplikaljuk.
if grep -q "# >>> claudegod >>>" "$BASHRC"; then
  ok "A claudegod blokk mar benne van a .bashrc-ben (kihagyva)."
else
  cat >> "$BASHRC" <<'BASHRC_BLOCK'

# >>> claudegod >>>
# A mindenhato Claude: minden engedelykeres atugrasaval fut.
alias claudegod='claude --dangerously-skip-permissions'
# Belepesi emlekezteto (csak interaktiv shellnel, hogy ne torjon scp/sftp-t)
if [[ $- == *i* ]]; then
  echo -e "\033[1;33m💪 claudegod\033[0m = a mindenhato Claude (\033[2m--dangerously-skip-permissions\033[0m). Csak ird be: \033[1mclaudegod\033[0m"
fi
# <<< claudegod <<<
BASHRC_BLOCK
  ok "Hozzaadva a .bashrc-hez: 'claudegod' alias + belepesi emlekezteto."
  info "Az uj terminal / re-login utan lesz aktiv (vagy most: source ~/.bashrc)."
fi

echo
echo -e "${BOLD}=== 3/5  Belepesi uzenet probaja ===${NC}"
echo -e "  💪 ${YELLOW}claudegod${NC} = a mindenhato Claude (${DIM}--dangerously-skip-permissions${NC}). Csak ird be: ${BOLD}claudegod${NC}"

echo
echo -e "${BOLD}=== 4/5  Marveen telepitese ===${NC}"
info "A Marveen telepitojehez bejelentkezett Claude kell."
info "Ha headless gepen vagy: a sajat (boengeszos) geped futtasd 'claude setup-token',"
info "majd a kapott tokent itt: export CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-...  (ANTHROPIC_API_KEY NELKUL)"
echo
read -rp "  Telepitsuk most a Marveent? [I/n]: " ANS
ANS="${ANS:-i}"
if [[ "$ANS" =~ ^[Ii] ]]; then
  MARVEEN_DIR="$HOME/marveen"
  if [ -d "$MARVEEN_DIR/.git" ] || [ -f "$MARVEEN_DIR/install.sh" ]; then
    warn "A(z) $MARVEEN_DIR mar letezik -- ujraklonozas kihagyva."
  else
    info "Repo klonozasa: $MARVEEN_DIR"
    git clone https://github.com/Szotasz/marveen.git "$MARVEEN_DIR"
  fi
  cd "$MARVEEN_DIR"
  info "A Marveen telepito inditasa (./install.sh)..."
  echo
  ./install.sh
else
  echo
  info "Rendben, a Marveent kesobb is telepitheted:"
  info "  git clone https://github.com/Szotasz/marveen.git ~/marveen && cd ~/marveen && ./install.sh"
fi

echo
echo -e "${BOLD}=== 5/5  Samba megosztas ===${NC}"
# Cel: Windowsrol/halozatrol fajlokat lehessen rakosgatni az agenteknek
# (a Marveen az agenteket a ~/marveen/agents/ alatt tarolja).
SHARE_NAME="marveen"
SHARE_PATH="$HOME/marveen"
SMB_CONF="/etc/samba/smb.conf"

# A samba csomagot az 1. fazis (bootstrap) telepiti; ha megsem lenne fent, potoljuk.
if ! command -v testparm >/dev/null 2>&1; then
  info "Samba telepitese (potlas)..."
  sudo apt-get update -qq
  sudo apt-get install -y samba samba-common-bin
fi

# A megosztott mappa biztositasa (ha a Marveent nem telepitetted, akkor is letezzen)
mkdir -p "$SHARE_PATH"

# --- Samba felhasznalo (a sajat Linux user) + SMB jelszo ---
echo -e "  SMB (halozati megosztas) jelszo a(z) '${USER}' felhasznalohoz."
info "Ez a Samba-jelszo (errol csatlakozol Windowsrol), NEM a Linux login jelszo."
while true; do
  read -rsp "  SMB jelszo: " SMBPW1; echo
  if [ -z "$SMBPW1" ]; then warn "Nem lehet ures."; continue; fi
  read -rsp "  SMB jelszo megegyszer: " SMBPW2; echo
  if [ "$SMBPW1" != "$SMBPW2" ]; then warn "A ket jelszo nem egyezik."; continue; fi
  break
done
printf '%s\n%s\n' "$SMBPW1" "$SMBPW2" | sudo smbpasswd -s -a "$USER"
sudo smbpasswd -e "$USER" >/dev/null 2>&1 || true
unset SMBPW1 SMBPW2
ok "Samba felhasznalo beallitva: $USER"

# --- Share blokk az smb.conf-ba (idempotens, marker-rel) ---
if sudo grep -q "# >>> ${SHARE_NAME} share >>>" "$SMB_CONF" 2>/dev/null; then
  ok "A(z) '${SHARE_NAME}' megosztas mar szerepel az smb.conf-ban (kihagyva)."
else
  sudo tee -a "$SMB_CONF" >/dev/null <<EOF

# >>> ${SHARE_NAME} share >>>
[${SHARE_NAME}]
   comment = Marveen agents files
   path = ${SHARE_PATH}
   browseable = yes
   read only = no
   writable = yes
   valid users = ${USER}
   force user = ${USER}
   force group = ${USER}
   create mask = 0664
   directory mask = 0775
# <<< ${SHARE_NAME} share <<<
EOF
  ok "Megosztas hozzaadva az smb.conf-hoz: [${SHARE_NAME}] -> ${SHARE_PATH}"
fi

# --- Config ellenorzes + service ujraindítas ---
if sudo testparm -s >/dev/null 2>&1; then
  sudo systemctl enable smbd >/dev/null 2>&1 || true
  sudo systemctl restart smbd
  ok "Samba (smbd) ujraindítva es engedelyezve."
else
  err "Az smb.conf ervenytelen (testparm). Ellenorizd kezzel: sudo testparm"
fi

# --- Eleresi info ---
SMB_IP="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}')"
[ -z "$SMB_IP" ] && SMB_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
[ -z "$SMB_IP" ] && SMB_IP="<gep-ip>"
info "Windowsrol eleres a Fajlkezelo cimsoraban:  \\\\${SMB_IP}\\${SHARE_NAME}"
info "  (felhasznalo: ${USER}, az imenti SMB jelszoval)"

echo
echo -e "${BOLD}=== Kesz ===${NC}"
ok "Claude Code + claudegod alias beallitva."
info "Ha most nem latod a claudegod-ot, nyiss uj terminalt vagy: source ~/.bashrc"
