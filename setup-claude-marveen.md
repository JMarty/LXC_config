# `setup-claude-marveen.sh` — dokumentáció

> Ez a fájl azt írja le, hogy a `setup-claude-marveen.sh` **pontosan mit csinál és mit tartalmaz**.
> Cél: később AI-val (vagy kézzel) könnyen, biztonságosan lehessen módosítani a scriptet.

---

## 1. Áttekintés

**Mi ez:** A telepítési folyamat **2. fázisa**. Feltelepíti a Claude Code-ot, beállít egy kényelmi aliast + belépési emlékeztetőt, felkínálja a Marveen telepítését, végül beállít egy **Samba megosztást** (hogy a hálózatról fájlokat lehessen rakni az agenteknek).

**Hol fut:** a konténerben, a **létrehozott (NEM root) felhasználóval**, miután SSH-val beléptél.

**Mikor fut:** az 1. fázis (`bootstrap-ubuntu.sh`) **után**.

**Letöltés + futtatás (ekkor már van `curl`):**
```bash
curl -fsSL https://raw.githubusercontent.com/JMarty/LXC_config/main/setup-claude-marveen.sh -o setup-claude-marveen.sh && bash setup-claude-marveen.sh
```

> ⚠️ **Ne** futtasd `... | bash`-sel: interaktívan kérdez (Marveen telepítés `[I/n]`), a pipe elnyelné a stdin-t.

---

## 2. Előfeltételek / feltevések

- **NEM root** felhasználóként fut (a Claude, az alias és a Marveen mind user-szintű) — ezt a script ellenőrzi és kilép, ha root.
- `curl` telepítve van (az 1. fázis felrakja) — ezt a script ellenőrzi.
- A Marveen telepítéséhez **bejelentkezett Claude** kell (lásd lent, OAuth token).

---

## 3. Felépítés / konvenciók (AI-nak fontos)

- **Shell:** `bash`, `set -euo pipefail`.
- **Helper függvények:** `ok` / `info` / `warn` / `err` (mint az 1. fázisban).
- **Lépés-fejlécek:** `=== N/5  Cím ===` — új lépésnél frissítsd az összes `N/5`-öt.
- **`.bashrc` módosítás marker-blokkal és idempotensen** (lásd 4.2).
- **PATH-kezelés:** a frissen telepített eszközök elérési útját (`~/.local/bin`, `~/.bun/bin`) a script az aktuális sessionre is felveszi a PATH-ra.

---

## 4. Lépésről lépésre — mit csinál

### Előellenőrzések
- Ha **root** → hibaüzenet (lépj át sima userre) és kilépés.
- Ha **nincs `curl`** → hibaüzenet (futtasd előbb az 1. fázist) és kilépés.
- `BASHRC="$HOME/.bashrc"` — ha nem létezik, létrehozza (`touch`).

### 1/5 — Claude Code telepítése
- `export PATH="$HOME/.local/bin:$HOME/.bun/bin:$PATH"` (aktuális session).
- Ha a `claude` már elérhető → kihagyja, kiírja a verziót.
- Egyébként: `curl -fsSL https://claude.ai/install.sh | bash` (hivatalos telepítő).
- Telepítés után újra PATH-ra teszi és ellenőrzi; ha nincs a PATH-on, figyelmeztet (új login kell).

### 2/5 — `claudegod` alias + belépési emlékeztető
- **Idempotens:** ha a `.bashrc` már tartalmazza a `# >>> claudegod >>>` markert → kihagyja.
- Egyébként hozzáfűz egy **marker-blokkot** a `.bashrc`-hez:
  ```bash
  # >>> claudegod >>>
  alias claudegod='claude --dangerously-skip-permissions'
  if [[ $- == *i* ]]; then
    echo -e "... 💪 claudegod = a mindenhato Claude ..."
  fi
  # <<< claudegod <<<
  ```
- Az `if [[ $- == *i* ]]` garantálja, hogy a banner **csak interaktív** shellnél fut (nem töri az scp/sftp-t).

### 3/5 — Belépési üzenet próbája
- Most rögtön kiírja egyszer a `claudegod` emlékeztetőt (hogy lásd, hogy néz ki).

### 4/5 — Marveen telepítése
- Info: a Marveenhez bejelentkezett Claude kell; headless gépen `claude setup-token` a böngészős gépen, majd `export CLAUDE_CODE_OAUTH_TOKEN=...` (ANTHROPIC_API_KEY nélkül).
- Kérdés: `Telepitsuk most a Marveent? [I/n]` (alap = Igen).
- **Igen** esetén:
  - `MARVEEN_DIR="$HOME/marveen"`.
  - Ha már létezik (`.git` vagy `install.sh`) → kihagyja az újraklónozást.
  - Egyébként: `git clone https://github.com/Szotasz/marveen.git "$MARVEEN_DIR"`.
  - `cd "$MARVEEN_DIR"` és `./install.sh` futtatása (átadja a vezérlést a Marveen telepítőnek).
- **Nem** esetén: kiírja a kézi telepítés parancsát.

### 5/5 — Samba megosztás
Cél: a hálózatról (pl. Windows Fájlkezelő) fájlokat lehessen tenni az agenteknek (a Marveen az agenteket a `~/marveen/agents/` alatt tárolja).

- Változók: `SHARE_NAME="marveen"`, `SHARE_PATH="$HOME/marveen"`, `SMB_CONF="/etc/samba/smb.conf"`.
- Ha a `testparm` nincs meg (azaz a samba valamiért nem települt az 1. fázisban) → `sudo apt-get install -y samba samba-common-bin` (pótlás).
- `mkdir -p "$SHARE_PATH"` — a megosztott mappa létezzen akkor is, ha a Marveent nem telepítetted.
- **SMB jelszó bekérése** (rejtve, kétszer) a `$USER`-hez — ez külön a samba-jelszó, nem a Linux login.
  - `printf '%s\n%s\n' ... | sudo smbpasswd -s -a "$USER"` (létrehoz), majd `sudo smbpasswd -e "$USER"` (engedélyez).
- **Share blokk** az `smb.conf`-ba (idempotens, `# >>> marveen share >>>` markerrel):
  ```ini
  [marveen]
     comment = Marveen agents files
     path = /home/<user>/marveen
     browseable = yes
     read only = no
     writable = yes
     valid users = <user>
     force user = <user>
     force group = <user>
     create mask = 0664
     directory mask = 0775
  ```
  - `force user`/`force group` = a megosztáson át létrehozott fájlok a `$USER` tulajdonába kerülnek, így a Marveen (ami userként fut) olvas/ír rajtuk.
  - `valid users` = csak a `$USER` férhet hozzá.
- **Validálás + indítás:** `sudo testparm -s` (config-ellenőrzés); ha jó → `sudo systemctl enable smbd` + `sudo systemctl restart smbd`.
- **Elérési info:** kiírja a `\\<ip>\marveen` címet (a `$USER`-rel és az SMB jelszóval).

### Záró rész
- Összefoglaló + emlékeztető: `source ~/.bashrc` vagy új terminál a `claudegod`-hoz.

---

## 5. Fontos változók

| Változó | Jelentés |
|---|---|
| `BASHRC` | a `.bashrc` útvonala (`$HOME/.bashrc`) |
| `ANS` | a Marveen-telepítés `[I/n]` válasza |
| `MARVEEN_DIR` | a Marveen klón célmappája (`$HOME/marveen`) |
| `SHARE_NAME` | a Samba megosztás neve (`marveen`) |
| `SHARE_PATH` | a megosztott mappa (`$HOME/marveen`) |
| `SMB_CONF` | a samba konfig útvonala (`/etc/samba/smb.conf`) |
| `SMBPW1` / `SMBPW2` | az SMB jelszó bekéréséhez (utána `unset`) |
| `SMB_IP` | a kiírt `\\<ip>\marveen` címhez |

---

## 6. Külső hivatkozások (módosításkor figyelni)

| Hivatkozás | Hol | Megjegyzés |
|---|---|---|
| `https://claude.ai/install.sh` | 1/5 | hivatalos Claude Code telepítő |
| `alias claudegod='claude --dangerously-skip-permissions'` | 2/5 | a flag neve fontos: `--dangerously-skip-permissions` |
| `https://github.com/Szotasz/marveen.git` | 4/5 | a Marveen repó |
| `smbpasswd` / `testparm` / `smbd` | 5/5 | samba eszközök (a `samba-common-bin`-ből); a service neve `smbd` |

---

## 7. Amit a script **NEM** csinál

- Nem állít be `.env`-et a Marveenhez (azt a Marveen `install.sh` interaktívan kéri).
- Nem kezeli közvetlenül az OAuth tokent (csak emlékeztet rá); azt a Marveen telepítő rögzíti.
- Nem konfigurál dashboard LAN-elérést / Tailscale-t (külön bővíthető).

---

## 8. Bővítési útmutató (AI-nak)

- **Új `.bashrc` bejegyzés:** ugyanazzal a marker-blokk mintával (`# >>> név >>>` … `# <<< név <<<`) és `grep`-es idempotencia-ellenőrzéssel.
- **Banner módosítás:** a 2/5 marker-blokkon belül; tartsd meg az `if [[ $- == *i* ]]` interaktív-védelmet.
- **Új lépés:** frissítsd az összes `=== N/5 ===` fejlécet.
- **Alias flag változás:** ha a Claude CLI flagje változik, a 2/5 blokkban és a 6. szakasz táblájában is frissítsd.
- **Samba megosztott mappa/jogok:** az 5/5 lépésben a `SHARE_PATH`-t és az `smb.conf` blokkot módosítsd; a share blokk idempotens marker mintáját (`# >>> marveen share >>>`) tartsd meg, és változtatás után `sudo testparm` + `sudo systemctl restart smbd`.
- Tartsd meg a `set -euo pipefail`-t és a `root`/`curl` előellenőrzéseket.
