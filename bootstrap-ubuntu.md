# `bootstrap-ubuntu.sh` — dokumentáció

> Ez a fájl azt írja le, hogy a `bootstrap-ubuntu.sh` **pontosan mit csinál és mit tartalmaz**.
> Cél: később AI-val (vagy kézzel) könnyen, biztonságosan lehessen módosítani a scriptet.

---

## 1. Áttekintés

**Mi ez:** A telepítési folyamat **1. fázisa**. Egy friss **Ubuntu minimal** (jellemzően Proxmox LXC) konténert készít elő a Marveen telepítéséhez.

**Hol fut:** a konténerben, **`root`-ként**.

**Mikor fut:** legelőször, a teljesen csupasz rendszeren.

**Letöltés + futtatás (friss CT-n nincs `curl`, ezért `wget`):**
```bash
wget -qO bootstrap-ubuntu.sh https://raw.githubusercontent.com/JMarty/LXC_config/main/bootstrap-ubuntu.sh && bash bootstrap-ubuntu.sh
```

> ⚠️ **Ne** futtasd `... | bash`-sel: a script interaktívan kérdez (felhasználónév/jelszó), a pipe elnyelné a stdin-t.

---

## 2. Előfeltételek / feltevések

- Ubuntu/Debian rendszer (`apt-get` létezik) — ezt a script ellenőrzi.
- `root` jogosultság — ezt a script ellenőrzi.
- Hálózati elérés az apt tükrökhöz.
- A `wget` (a letöltéshez) jellemzően alap a minimal image-ben; ha nincs, a felhasználónak előbb azt kell felraknia.

---

## 3. Felépítés / konvenciók (AI-nak fontos)

- **Shell:** `bash`, `set -euo pipefail` (hibára/üres változóra leáll).
- **Színes kimenet + helper függvények** a konzisztens üzenetekhez:
  - `ok "..."`   → zöld pipa
  - `info "..."` → halvány info
  - `warn "..."` → sárga figyelmeztetés
  - `err "..."`  → piros hiba (stderr-re)
- **Lépés-fejlécek** formátuma: `=== N/6  Cím ===` — ha új lépést adsz hozzá, frissítsd az összes `N/6`-ot a megfelelő `N/7`-re.
- **Interaktív bekérés:** `read -rp` (látható) és `read -rsp` (rejtett, jelszóhoz).
- **Idempotencia:** ahol fájlt módosít (`/etc/locale.gen`, sudoers), előbb ellenőriz.

---

## 4. Lépésről lépésre — mit csinál

### Előellenőrzések (a lépések előtt)
- Ha **nem root** → hibaüzenet és kilépés (exit 1).
- Ha **nincs `apt-get`** → hibaüzenet és kilépés (exit 1).

### 1/6 — Rendszer frissítése
- `export DEBIAN_FRONTEND=noninteractive` (ne kérdezzen apt-config dialógusokat).
- `apt-get update`
- `apt-get -y upgrade`

### 2/6 — Csomagok telepítése
A `PACKAGES` tömb tartalma (egy `apt-get install -y` hívásban):

| Csomag | Miért kell |
|---|---|
| `sudo` | a script további részei és a Marveen sudo-t használnak |
| `git` | repo klónozás |
| `curl` | a 2. fázis és sok installer ezzel tölt |
| `wget` | alternatív letöltő |
| `ca-certificates` | HTTPS működéséhez |
| `gnupg` | apt repo kulcsok (pl. NodeSource) |
| `build-essential` | `better-sqlite3` natív modul fordításához |
| `python3` | node-gyp / segédszkriptek |
| `zstd`, `xz-utils`, `bzip2` | `.tar.zst` / `.xz` / `.bz2` kibontás |
| `unzip`, `tar` | archívum kibontás (pl. bun installer) |
| `lsb-release` | a Marveen telepítő hibakezelője hívja |
| `apt-transport-https` | HTTPS apt repók |
| `locales` | UTF-8 locale generálásához (3. lépés) |
| `sqlite3` | a dream-engine és kanban-audit taskok parancssori sqlite3-at hívnak |

> **Bővítés:** új rendszer-csomagot ide, a `PACKAGES` tömbbe vegyél fel.

### 3/6 — UTF-8 locale beállítása
- `DEFAULT_LOCALE="en_US.UTF-8"`.
- Engedélyezi/legenerálja az `en_US.UTF-8` **és** `hu_HU.UTF-8` sorokat a `/etc/locale.gen`-ben (idempotens: kommentet vesz le vagy hozzáfűz).
- `locale-gen`
- `update-locale LANG=... LC_ALL=...`
- Az aktuális shellre is `export`-tal érvényesíti.
- Megjegyzés: teljes körű hatás új login után.

### 4/6 — Új felhasználó létrehozása
- **Felhasználónév bekérése** + validálás:
  - regex: `^[a-z_][a-z0-9_-]*$`
  - ha már létezik → újrakérdez.
- **Jelszó bekérése** rejtetten, kétszer, egyezés-ellenőrzéssel, üres tiltva.
- `useradd -m -s /bin/bash "$NEW_USER"` (home + bash shell).
- `chpasswd`-vel beállítja a jelszót, majd `unset` a jelszó-változókra.

### 5/6 — Sudo jogosultság
- `usermod -aG sudo "$NEW_USER"` (sudo csoport).

### 6/6 — Sudo jelszó-politika
- Kérdés: kelljen-e jelszó a `sudo`-hoz (`[I/n]`, alap = Igen).
- **Igen** → nem ír sudoers fájlt (a csoporttagság jelszavas sudo-t ad).
- **Nem** → létrehozza `/etc/sudoers.d/90-<user>-nopasswd`:
  - tartalom: `<user> ALL=(ALL) NOPASSWD:ALL`
  - jogok: `chmod 0440`
  - **validálás `visudo -cf`-fel**; ha hibás → törli a fájlt, visszaáll jelszavasra.

### Záró rész
- Összefoglaló (user, sudo-státusz).
- **IP kiderítése:** `ip -4 route get 1.1.1.1` (elsődleges), fallback `hostname -I`.
- Kiírja a kész belépő parancsot: `ssh <user>@<ip>`.
- Ha több IP van, mindet kilistázza külön `ssh ...` sorként.

---

## 5. Fontos változók

| Változó | Jelentés |
|---|---|
| `PACKAGES` | telepítendő apt csomagok tömbje |
| `DEFAULT_LOCALE` | alap locale (jelenleg `en_US.UTF-8`) |
| `NEW_USER` | a bekért felhasználónév |
| `SUDOERS_NOTE` | a végső összefoglalóban a sudo-státusz szövege |
| `PRIMARY_IP` / `ALL_IPS` | a kiírt SSH-parancshoz |

---

## 6. Amit a script **NEM** csinál (szándékosan)

- Nem telepít swapet (LXC-ben a swap a hostról jön; a Marveen telepítő amúgy felajánlja).
- Nem csinál `loginctl enable-linger`-t (a Marveen `install.sh` elintézi).
- Nem telepíti/indítja az `openssh-server`-t (feltételezi, hogy fut — bővíthető).
- Nem telepít Tailscale-t.
- Nem klónozza a Marveent és nem futtatja az installert (az a 2. fázis).
- Nem kezeli a Claude OAuth tokent (az a Marveen `install.sh` dolga).

---

## 7. Bővítési útmutató (AI-nak)

- **Új csomag:** add a `PACKAGES` tömbhöz.
- **Új lépés:** illeszd a megfelelő helyre, frissítsd az összes `=== N/6 ===` fejlécet (`/6` → `/7` stb.).
- **Új fájl-módosítás:** mindig idempotensen (előbb `grep`/`Test`, csak utána írj).
- **sudoers-szerű érzékeny írásnál** mindig validálj (`visudo -c`) és hibánál állj vissza biztonságos állapotra.
- A helper függvényeket (`ok/info/warn/err`) használd a kimenethez, ne nyers `echo`-t.
- Tartsd meg a `set -euo pipefail`-t; ahol a hiba megengedett, ott `|| true`.
