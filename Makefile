-include .env
NOVNC_PORT ?= 6080
URL := http://127.0.0.1:$(NOVNC_PORT)/vnc.html?autoconnect=1&resize=remote

.PHONY: env build up upgrade open latest stop start restart logs sh destroy

# Writes .env with a random VNC password once; never overwrites it.
env:
	@test -f .env || { printf 'VNC_PASSWORD=%s\nNOVNC_PORT=6080\nGEOMETRY=1600x1000\nZCODE_VERSION=3.16.3\n' \
	  "$$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 8)" > .env && chmod 600 .env && echo "wrote .env"; }

build: env
	docker compose build

# Never recreates an existing container: the login and ~/work live in it (no volumes).
up: env
	docker compose up -d --no-recreate
	@echo "open $(URL)  (password: VNC_PASSWORD in .env)"

# Rebuild and recreate, carrying /home/zcode (login, settings, tasks, ~/work) across.
# The copy waits in a stopped container, zcode-carry, never on the host disk. It is removed
# only after the restore succeeded; if a step fails, the data is still in zcode-carry.
upgrade: env
	@! docker inspect zcode-carry >/dev/null 2>&1 || { echo "zcode-carry exists: a previous upgrade did not finish; restore from it before retrying" >&2; exit 1; }
	docker compose build
	docker create --name zcode-carry --entrypoint true zcode:$(ZCODE_VERSION)
	docker compose stop
	docker cp -a zcode:/home/zcode - | docker cp -a - zcode-carry:/home
	docker compose up -d --no-start --force-recreate
	docker cp -a zcode-carry:/home/zcode - | docker cp -a - zcode:/home
	docker compose start
	docker rm zcode-carry
	@echo "open $(URL)"

# macOS `open`, Linux `xdg-open`, WSL `wslview`; otherwise just print the URL.
open:
	@open '$(URL)' 2>/dev/null || xdg-open '$(URL)' 2>/dev/null || wslview '$(URL)' 2>/dev/null || echo 'open $(URL) in your browser'

# Version the install page lists now vs the one pinned in the Dockerfile.
latest:
	@echo "listed: $$(curl -fsSL https://zcode.z.ai/en/docs/install | grep -oE 'releases/[0-9.]+/' | head -1 | tr -dc '0-9.' | sed 's/\.$$//')"
	@echo "pinned: $$(sed -n 's/^ARG ZCODE_VERSION=//p' Dockerfile)"

stop:
	docker compose stop

start:
	docker compose start

restart:
	docker compose restart

logs:
	docker compose logs -f

sh:
	docker compose exec zcode bash

# Removes the container and with it the ZCode login, settings and ~/work.
destroy:
	docker compose down
