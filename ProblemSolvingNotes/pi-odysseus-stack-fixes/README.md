# Pi + Odysseus Stack — Cross-Machine Fixes & Runbook

**Date:** 2026-10-25
**Status:** ✅ Applied and verified on both machines (desktop + laptop, both named `omarchy`)
**Stack involved:** pi CLI/SDK, pi-web-ui, pi extensions, Odysseus (docker compose + bwrap sandbox)

---

## TL;DR — the commands you actually need

```bash
pi-stack-update            # update pi + pi-web-ui + all extensions, safely
pi-web-ui-repair           # after ANY pi-web-ui update, or after `pi update` (SDK re-point)
```

Equivalent manual steps:

```bash
pi update                  # 1. pi CLI + SDK (official managed install)
npm i -g pi-web-ui@latest  # 2. pi-web-ui
pi-web-ui-repair           # 3. re-apply both local patches + re-point web-sdk
pi update --extensions     # 4. extensions in ~/.pi/agent/npm
```

Reload the web UI afterwards: `pkill -f pi-web-ui && pi-web-ui`

---

## 1. Symptom

```
$ pi-web-ui
[pi-web-ui] following a newer pi SDK on this machine: \
  /home/aleks/.local/share/mise/installs/pi/1.3.0/pi/package.json (v1.3.0; ...)
✖ Cannot find module '/home/aleks/.local/share/mise/installs/pi/1.3.0/pi/dist/index.js'
  imported from /home/aleks/.local/share/mise/installs/pi/1.3.0/pi/package.json
```

Secondary symptoms seen along the way:

| Symptom | Real cause |
|---|---|
| `✖ pi-web-ui` right after the banner | `EADDRINUSE` — an instance was already on :8787 (single instance per port) |
| Server prints banner, port listens, `/api/health` never answers, browser never opens | `spawnSync("xdg-open")` blocked the event loop |
| `pi update --extensions` fails | stale `^0.85.1` devDependency → `ERESOLVE` |
| Extensions "work" but native parts dead after update | `allowScripts` skipped postinstalls (native builds, binary downloads) |

---

## 2. Root causes (5 independent problems)

1. **pi-web-ui followed a broken pi copy.** pi-web-ui's default "follow a newer SDK" hook
   (`dist/server/sdk-origin.js`, upstream issue #260/#321) treats *any*
   `@earendil-works/pi-coding-agent/package.json` it can find as usable. The **mise binary
   distribution** ships `package.json` + an ELF binary and **no `dist/` by design** → the hook
   redirected the SDK import there → crash.
2. **Two pi channels.** Official self-managed install (`~/.pi/agent/install`, updated by `pi update`)
   **plus** a mise-managed copy. Two update surfaces = guaranteed version skew.
3. **Two upstream pi-web-ui bugs**, present in 0.104.4 … 0.111.0:
   - A: the SDK scan above (no entry-file existence check).
   - B: `openBrowser()` uses `spawnSync("xdg-open")`; on this setup `xdg-open` blocks until the
     launched browser exits, freezing the whole server event loop.
4. **Extension updates were self-blocking.** `~/.pi/agent/npm/package.json` had
   `devDependencies: { "@earendil-works/pi-coding-agent": "^0.85.1" }`, while extensions peer-require
   `>=1.0.0` → every `npm update` died with ERESOLVE. Its `allowScripts` only listed
   `@demigodmode/pi-web-agent@1.7.1` (an old version), so ~7 postinstalls were silently skipped.
5. **Odysseus bash sandbox (bwrap)** was lost on every container recreate: the image ships without
   bubblewrap and `src/containment.py`'s recipe lacks `--unshare-user`; both fixes live in the
   container's writable layer. Worse, the **NVIDIA GPU overlay injects
   `/proc/driver/nvidia/params`**, which makes the kernel refuse bwrap's fresh `/proc` mount
   (`Can't mount proc on /proc: Operation not permitted`). `CONTAINMENT_MODE` is hardcoded to
   `MODE_ENFORCING`, so an unusable sandbox **fails every approved bash call closed**.

---

## 3. What was changed (both machines)

### 3.1 Single pi channel

```bash
# keep the official managed install, remove the mise one
sed -i '/^pi = "latest"$/d' ~/.config/mise/config.toml
rm -f ~/.local/bin/pi                       # wrapper that ran `mise use -g pi`
mise uninstall pi --all
rm -rf ~/.local/share/mise/installs/pi ~/.local/share/mise/shims/pi
```

`pi` then resolves only to `~/.pi/agent/bin/pi` (v1.4.0). Every remaining entry point
(managed bin, npm-global copy, stale mise shim) was aligned to 1.4.0 so no PATH order matters.

### 3.2 pi-web-ui pointed at the real SDK

```bash
ln -sfn ~/.pi/agent/install/releases/$(cat ~/.pi/agent/install/current-version)/node_modules/@earendil-works/pi-coding-agent \
        ~/.pi/agent/web-sdk
# in ~/.bashrc:
export PI_WEB_SDK_DIR="$HOME/.pi/agent/web-sdk"
```

`PI_WEB_SDK_DIR` is upstream's own host-SDK override (issue #482). The symlink carries the version,
the env var never changes — a `pi update` only needs `pi-web-ui-repair` to re-point the symlink.

### 3.3 The two local dist patches (re-applied automatically)

- **Patch A** — `dist/server/sdk-origin.js`, `addCopy()`: skip any copy whose declared entry
  (`exports["."]` / `main`) is missing on disk.
- **Patch B** — `bin/pi-web-ui.mjs`, `openBrowser()`: async `spawn(..., {detached:true})` + `unref()`
  instead of `spawnSync`.

Both are wiped by `npm i -g pi-web-ui@latest` — that is why `pi-web-ui-repair` exists.

### 3.4 Extension workspace

`~/.pi/agent/npm/package.json`:

- `devDependencies["@earendil-works/pi-coding-agent"]`: `^0.85.1` → `^1.4.0` (fixes ERESOLVE).
- `allowScripts`: added **bare package names** (version-independent, so future versions stay allowed):
  `@demigodmode/pi-web-agent`, `@hypabolic/pi-hypa`, `@hypabolic/hypa-linux-x64`, `context-mode`,
  `pi-lens`, `@ast-grep/cli`, `better-sqlite3`, `tree-sitter-bash`, `protobufjs`, `node-pty`,
  `@google/genai`.
- Note: when `package.json` declares `allowScripts`, the `.npmrc allow-scripts` list is **ignored**.

### 3.5 Odysseus sandbox (self-healing + kernel-aware)

`docker-compose.yml` (odysseus service):

```yaml
    volumes:
      - ./scripts/ensure-bwrap-sandbox.sh:/usr/local/lib/ensure-bwrap-sandbox.sh:ro
    privileged: true                                  # bwrap needs real CAP_SYS_ADMIN
    entrypoint: ["/usr/local/lib/ensure-bwrap-sandbox.sh"]
    command: ["/usr/local/bin/entrypoint.sh", "uvicorn", "app:app", "--host", "0.0.0.0", "--port", "7000"]
```

`scripts/ensure-bwrap-sandbox.sh` (entrypoint wrapper, runs as root before the stock entrypoint
drops privileges) on **every start**:

1. installs `bubblewrap` if missing;
2. patches `/app/src/containment.py` to add `--unshare-user` to the bwrap probe + runtime prefix;
3. **probes as the app user via `gosu "$PUID:$PGID"`** — root succeeds even where the app user cannot;
4. if that probe fails, flips `CONTAINMENT_MODE` to `MODE_REPORT_ONLY` (upstream's documented
   degraded mode) with loud warnings, so bash keeps working instead of failing closed.

Also: `docker/gpu.nvidia.yml` documents that enabling the GPU overlay **breaks the sandbox**
(nvidia runtime bind-mounts `/proc/driver/nvidia/params`; the kernel then refuses bwrap's `/proc`).

`ODYSSEUS_IMAGE=odysseus-local:dev` is pinned in `.env` so a stray `docker compose pull` cannot
replace the locally built image (this happened once and silently reverted the patched build).

---

## 4. Helper scripts (`~/.local/bin/`, on both machines)

### `pi-web-ui-repair`

Idempotent, syntax-checks after patching. It does **not** trust `npm root -g` alone — in a
non-interactive SSH session that resolves the *distro* npm (`/usr/lib/node_modules`) and silently
patches nothing. It scans: `npm root -g`, every `~/.local/share/mise/installs/node/*/lib/node_modules`,
nvm layouts, `/usr/lib`, `/usr/local/lib`; patches every pi-web-ui it finds (skipping old versions
without `dist/server/sdk-origin.js`), then re-points `~/.pi/agent/web-sdk` at the active release.
Exits non-zero if no copy got both patches.

### `pi-stack-update`

```sh
pi update  →  npm i -g pi-web-ui@latest  →  pi-web-ui-repair  →  pi update --extensions
```

Preflight: verifies the resolved `npm` global root is writable, otherwise aborts with a hint
(the `EACCES /usr/lib/node_modules` failure mode when the wrong npm wins).

---

## 5. Updating — rules of thumb

| Action | Result |
|---|---|
| `pi-stack-update` | everything updated, patches re-applied, SDK pointer re-pointed |
| `pi update` only | nothing breaks; web-sdk keeps pointing at the previous release on disk → temporary skew until `pi-web-ui-repair` |
| `npm i -g pi-web-ui@latest` only | **both patches wiped** → run `pi-web-ui-repair` immediately after |
| ODYSSEUS: `git pull` | source only — container keeps running old code until `docker compose build odysseus && docker compose up -d --force-recreate odysseus` |

After an Odysseus pull, confirm the wrapper still matches upstream code:

```bash
docker logs odysseus-odysseus-1 2>&1 | grep ensure-bwrap
```

Expected on a capable kernel: `sandbox probe passed as uid 1000 - containment stays enforcing`.
If upstream changed `containment.py` such that the wrapper's anchors no longer match, it prints
`anchor(s) not found` and skips the patch — the probe then fails and it degrades to `report_only`,
so bash keeps working. Fix by updating the anchor strings in the wrapper.

---

## 6. Verification checklist

```bash
# pi stack
pi --version                                             # 1.4.0
readlink ~/.pi/agent/web-sdk                             # .../releases/1.4.0/node_modules/@earendil-works/pi-coding-agent
grep -c PI_WEB_SDK_DIR ~/.bashrc                         # 1
R=$(npm root -g)/pi-web-ui
grep -c 'entry.startsWith'        "$R/dist/server/sdk-origin.js"   # 1  (patch A)
grep -c 'Local fix (reapplied'    "$R/bin/pi-web-ui.mjs"           # 1  (patch B)
ls ~/.pi/agent/install/releases/                         # active version present

# extensions
node -e 'const p=require(process.env.HOME+"/.pi/agent/npm/package.json");console.log(p.devDependencies["@earendil-works/pi-coding-agent"], Object.keys(p.allowScripts).length)'
# -> ^1.4.0 16

# pi-web-ui actually boots on the intended SDK
pi-web-ui --no-browser --port 9199   # banner: "following ... /web-sdk ... v1.4.0", "pi SDK : v1.4.0"

# odysseus
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:7011/api/health    # 200
docker exec odysseus-odysseus-1 grep -m1 '^CONTAINMENT_MODE' /app/src/containment.py
docker exec -u 1000:1000 -w /app odysseus-odysseus-1 \
  python -c 'import src.containment as c; print(c.CONTAINMENT_MODE, c._bwrap_available())'
  # capable kernel + no GPU overlay -> enforcing True
  # kernel too old OR nvidia /proc injection -> report_only False (bash still works)
```

---

## 7. Odysseus repo / branch / port notes

- Upstream default port moved to **7011** (`${APP_PORT:-7011}`). An explicit `APP_PORT=7000` had been
  pinned in `.env` to keep an old bookmark working; it was removed so the repo default applies.
- Local branch is **`dev`**, tracking **`origin/dev`** (`pull.rebase=true`). A stale `dev`
  (pre-upgrade, 5 redundant commits: dns, listmonk volume, mychanges) was archived as
  **`dev-stale-20261024`**; `main` was renamed to `dev`.
- `git pull` on `dev` rebases local commits onto upstream. Realistic conflict zone is
  `docker-compose.yml` (host mounts, DNS, searxng port, bwrap block). Resolve, then
  `git add docker-compose.yml && git rebase --continue`, or `git rebase --abort`.
- `.env` and `data/` are gitignored — `.env` changes (ODYSSEUS_IMAGE, APP_PORT, COMPOSE_FILE) and the
  database survive pulls and rebuilds.

---

## 8. Lessons / traps worth remembering

1. **Never let two package managers own the same CLI.** `mise` + official installer = the crash.
2. **A `package.json` without its entry file is a landmine.** Any hook that scans for packages must
   verify the declared entry exists on disk.
3. **Probe as the user that will run the tool.** Root succeeded where the app user failed; the first
   probe implementation gave a false "sandbox available".
4. **`--privileged` is not enough for `/proc`.** A nested userns can't mount a fresh `/proc` on some
   kernels, and **the nvidia runtime's `/proc/driver/nvidia/params` injection breaks it even on
   capable kernels**. Debian's bwrap is built `--disable-setuid`, so setuid/file-cap workarounds don't
   apply ("setuid use of bubblewrap is not supported").
5. **`docker compose pull` will happily overwrite a locally built image** — pin `ODYSSEUS_IMAGE` to a
   local tag.
6. **Non-interactive SSH ≠ your shell.** `npm root -g` resolved `/usr/lib/node_modules` there, causing
   both a silent no-op patch run and an `EACCES` install. Scripts must discover paths, not trust PATH.
7. **`allowScripts` must be version-independent** (bare names), otherwise every version bump silently
   skips install scripts.
8. **Both machines are named `omarchy`** → `omarchy.local` mDNS is ambiguous. Use IPv4 addresses.
9. Runtime secrets live in `data/` (e.g. an HF token in `data/.bashrc`); `data/` is gitignored —
   keep it that way, and rotate the token if that tree was ever copied around.

---

## 9. Rollback

| Change | Rollback |
|---|---|
| pi-web-ui patches | reinstall: `npm i -g pi-web-ui@latest` (patches gone, upstream behaviour) or `PI_WEB_SDK=bundled pi-web-ui` |
| SDK pointer | `export PI_WEB_SDK=bundled` (pins pi-web-ui's own bundled SDK) |
| Extension workspace | `cp ~/.pi/agent/npm/package.json.bak-* ~/.pi/agent/npm/package.json && npm install` |
| Odysseus compose/sandbox | `git checkout docker-compose.yml docker/gpu.nvidia.yml && docker compose up -d --force-recreate odysseus` |
| Odysseus repo upgrade | bundles + DB copies in `~/odysseus-backup-*`; old image tagged `odysseus-odysseus:pre-upgrade` / `:pre-align` |
