# zcode

[ZCode](https://zcode.z.ai/en/docs/install) desktop app (Z.ai's agentic coding environment,
Electron) running in a Docker container. You use it in the browser through noVNC.

- Debian bookworm-slim with the official ZCode `.deb`. Its version and per-arch SHA-256 are pinned in the `Dockerfile`.
- The app runs on a TigerVNC virtual display with the openbox window manager. websockify/noVNC serve it on `127.0.0.1:6080`.
- The agent toolchain is installed too: Node 24 LTS with npm/npx, FFmpeg, and Playwright Chromium.
- No volumes or bind mounts. Everything lives in the container.

## Requirements

- Docker with Compose v2 (`docker compose version` works), and `make`, `git` and `curl`.
- About 4 GB of free disk for the image, and at least 4 GB of RAM for Docker.
- Supported architectures: x86-64 and ARM64. On macOS, both Apple silicon and Intel work.

### Installing Docker

<details>
<summary><b>macOS</b></summary>

1. Install [Docker Desktop for Mac](https://docs.docker.com/desktop/setup/install/mac-install/):
   download the Apple silicon or Intel build, open the `.dmg`, and drag Docker to Applications.
   With Homebrew instead: `brew install --cask docker`.
2. Start Docker from Applications and wait until the whale icon in the menu bar says it's running.
3. Install `make` and `git` (the Xcode Command Line Tools): `xcode-select --install`.
4. Check: `docker compose version && make --version`.

Docker Desktop needs a paid subscription for commercial use in larger companies
(more than 250 employees or more than $10M in revenue). OrbStack and Colima are alternatives.
</details>

<details>
<summary><b>Linux</b> (Debian, Ubuntu, Fedora and others)</summary>

1. Install Docker Engine with the Compose plugin. Either follow your distro's page under
   [docs.docker.com/engine/install](https://docs.docker.com/engine/install/), or use Docker's
   convenience script:
   ```sh
   curl -fsSL https://get.docker.com -o get-docker.sh
   sudo sh get-docker.sh
   sudo systemctl enable --now docker
   ```
2. Let your user run Docker without `sudo`, then log out and back in:
   ```sh
   sudo usermod -aG docker "$USER"
   ```
   Membership in the `docker` group is root-equivalent on that machine.
3. Install the tools: `sudo apt install make git curl` (or `sudo dnf install make git curl`).
4. Check: `docker compose version && make --version`.
</details>

<details>
<summary><b>Windows</b> (10/11, via WSL 2)</summary>

1. In PowerShell as Administrator, install WSL with Ubuntu, then reboot:
   ```powershell
   wsl --install -d Ubuntu
   ```
   Make sure you're on WSL 2.1.5 or newer: run `wsl --update`, then check with `wsl --version`.
2. Install [Docker Desktop for Windows](https://docs.docker.com/desktop/setup/install/windows-install/).
   Under Settings, turn on **General → Use WSL 2 based engine**, and
   **Resources → WSL Integration → Ubuntu**. Then click Apply.
3. Open the **Ubuntu** terminal and do everything from there (Linux commands, not PowerShell):
   ```sh
   sudo apt update && sudo apt install -y make git curl
   docker compose version   # should work through Docker Desktop's integration
   ```
4. Clone this repo inside the Ubuntu home directory (`~`), not under `/mnt/c`. Builds there are much faster.
5. `make open` uses `wslview` if it's installed (`sudo apt install wslu`). Otherwise open
   `http://127.0.0.1:6080/vnc.html` in your Windows browser yourself.

Don't install a second Docker Engine inside Ubuntu as well; Docker says it conflicts with Docker Desktop.
</details>

### Without `make`

The Makefile only wraps `docker compose`. The equivalent of `make up` is:

```sh
cp .env.example .env    # then set VNC_PASSWORD to 8+ random characters
docker compose up -d --no-recreate
```

Then open `http://127.0.0.1:6080/vnc.html`.
`make upgrade` has no one-line equivalent; see the `upgrade` target in the `Makefile` for its steps.

## Quick start

Clone the repo, then run everything from its folder (the one with the `Makefile`):

```sh
git clone https://github.com/dennis-akimov/zcode.git ~/zcode
cd ~/zcode
make up      # writes .env with a random VNC password on first run, builds, starts
make open    # opens http://127.0.0.1:6080/vnc.html; the password is VNC_PASSWORD in .env
```

Sign in from the app's welcome page: Connect to Z.ai, or use an API key.
No Z.ai account yet? [Register here for 10% off](https://z.ai/subscribe?ic=6ZMHQHAMKS) (referral link).
See `.env.example` for the settings.

## Make targets

| Target | What it does |
|---|---|
| `up` | Creates and starts the container. **Never recreates an existing one** (`--no-recreate`). |
| `upgrade` | Rebuilds the image and recreates the container, carrying `/home/zcode` across. |
| `stop` / `start` / `restart` | Container lifecycle. All three keep your data. |
| `open` | Opens noVNC in your browser. |
| `latest` | Compares the version on the ZCode install page with the one pinned in the `Dockerfile`. |
| `logs` / `sh` | Follow logs / open a shell as `zcode`. |
| `destroy` | `docker compose down`. **Deletes your login, chat history and `~/work`.** |

## Your data

There are no volumes, so all state lives in the container's writable layer under `/home/zcode`:

| What | Where |
|---|---|
| Z.ai login | `~/.zcode/v2/credentials.json` |
| Chat history (sessions, messages) | `~/.zcode/cli/db/db.sqlite` |
| Task list | `~/.zcode/v2/tasks-index.sqlite` |
| Settings, skills | `~/.zcode/v2/setting.json`, `~/.zcode/skills/` |
| Projects | `~/work` |

- **Survives:** `stop`, `start`, `restart`, Docker restarts, and `make upgrade`.
- **`make upgrade`:** before recreating, it copies `/home/zcode` into a stopped helper container, `zcode-carry`. That copy never touches the host disk. After the restore it deletes the helper. If a step fails, the data is still in `zcode-carry`, and the next `upgrade` refuses to run until you deal with it.
- **Lost:** `make destroy`, or anything else that recreates the container (`docker compose up --build`, `--force-recreate`, `down`).

A restart interrupts any agent turn that is still running.

## Updating ZCode

The in-app updater can't work here: it needs root, and the app runs as `zcode`.

1. Run `make latest` to see whether a newer version is listed.
2. In the `Dockerfile`, set the new `ZCODE_VERSION` and both `ZCODE_SHA256_*` values. The download server doesn't publish checksums; compute them from the new `.deb`s:
   ```sh
   v=X.Y.Z; for a in x64 arm64; do curl -fsSL "https://cdn-zcode.z.ai/zcode/electron/releases/$v/linux-$a/ZCode-$v-linux-$a.deb" | shasum -a 256; done
   ```
3. Set `ZCODE_VERSION` in `.env` too (it's the image tag), then run `make upgrade`.

## Agent toolchain

The `Dockerfile` installs Node 24 LTS into `/usr/local`, which shadows the Debian Node 18 that noVNC
pulls in. It also installs FFmpeg (with libx264) and Playwright Chromium into `/opt/ms-playwright`.
To change versions, edit the `NODE_*` and `PLAYWRIGHT_VERSION` args, then run `make upgrade`.

## Copy and paste

noVNC 1.3 has no automatic clipboard sharing; upstream declined it in
[noVNC#1902](https://github.com/novnc/noVNC/issues/1902). Use the clipboard panel instead.

- **Out of ZCode:** copy in the app, open the noVNC side tab and click the clipboard icon. The text appears there; copy it with Cmd+C.
- **Into ZCode:** paste into that panel, then press Ctrl+V in the app.

## Using it from a phone or another browser

The orange phone icon (bottom left) is ZCode's
[Remote Control](https://zcode.z.ai/en/docs/remote-control). It creates a
`https://zcode.z.ai/remote/v4?...` link, relayed through Z.ai, that controls this window's tasks
and chat. Commands still run in this container.

- Anyone with the link can operate the window, so don't share it.
- **Refresh** invalidates an old link; **Stop** ends the session.

## Security notes

- VNC password auth is DES-based and weak (RFC 6143 §7.2.2). noVNC listens only on `127.0.0.1`; for remote use, tunnel it over SSH.
- Docker's default seccomp profile blocks Chromium's sandbox, so the app runs with `--no-sandbox`. The container is the sandbox: it runs as non-root with `no-new-privileges`.
- `.env` holds the VNC password. It is git-ignored (`.gitignore`); `.env.example` is the template.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `zcode-carry exists` on `make upgrade` | An earlier upgrade stopped halfway; your data is in `zcode-carry`. Copy it back: `docker cp -a zcode-carry:/home/zcode - \| docker cp -a - zcode:/home`, then `docker rm zcode-carry`. |
| Black screen, no window | `make logs`. If it says `Xvnc did not start`, run `make restart`. |
| `Failed to connect to the bus` in logs | Fixed in the image: one D-Bus at `/tmp/dbus-session` serves both buses. Rebuild with `make upgrade` if you see it. |
| Sign-in link doesn't open a browser | The container has no browser; copy the link through the clipboard panel. |
