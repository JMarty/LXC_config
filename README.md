# LXC_config

Marveen személyi asszisztens telepítése friss **Ubuntu LXC** konténerre, két lépésben.

---

## 1. lépés — Alaprendszer előkészítése

Futtasd **root-ként**, a friss konténerben.
Friss CT-n még **nincs `curl`**, ezért itt `wget`-tel töltjük le:

```bash
wget -qO bootstrap-ubuntu.sh https://raw.githubusercontent.com/JMarty/LXC_config/main/bootstrap-ubuntu.sh && bash bootstrap-ubuntu.sh
```

**Mit csinál:**
- rendszerfrissítés (`apt update && upgrade`)
- szükséges csomagok telepítése (`curl`, `git`, `build-essential`, `python3`, `sqlite3`, `zstd`, `locales`, …)
- UTF-8 locale beállítása (ékezetek)
- új felhasználó létrehozása (név + jelszó), `sudo` csoportba téve
- kérdés: kelljen-e jelszó a `sudo`-hoz
- a végén kiírja a `ssh user@ip` parancsot

A lépés végén jelentkezz be a kiírt paranccsal a létrehozott felhasználóval:

```bash
ssh <felhasznalo>@<gep-ip>
```

---

## 2. lépés — Claude Code + Marveen

Futtasd a **létrehozott felhasználóval** (NEM root), miután SSH-val beléptél.
Itt már van `curl` (az 1. lépés telepítette):

```bash
curl -fsSL https://raw.githubusercontent.com/JMarty/LXC_config/main/setup-claude-marveen.sh -o setup-claude-marveen.sh && bash setup-claude-marveen.sh
```

**Mit csinál:**
- Claude Code telepítése
- `claudegod` alias a `.bashrc`-be: `claude --dangerously-skip-permissions`
- belépési emlékeztető minden loginnál
- felkínálja a Marveen telepítését (`git clone` + `./install.sh`)

---

## Megjegyzések

- A scripteket **ne** `... | bash`-sel futtasd — interaktívan kérdeznek (felhasználónév/jelszó), és a pipe elnyelné a választ. Ezért előbb letöltés (`-o` / `-qO`), majd `bash <fajl>`.
- A Marveen-telepítő bejelentkezett Claude-ot vár. Headless gépen: a böngészős gépeden `claude setup-token`, majd az LXC-n `export CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-...` (ANTHROPIC_API_KEY nélkül).
