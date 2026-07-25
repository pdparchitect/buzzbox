SHELL := /bin/bash
.DEFAULT_GOAL := help

DOCKER ?= docker
IMAGE ?= pdparchitect/buzzbox:local
CONTAINER ?= buzzbox
PLATFORM ?= linux/amd64
BUZZ_VERSION ?= 0.4.26
BUZZ_DEB_SHA256 ?= 1b520756ecfc28ad81981a2cd5cc6688f785f447b3f5d8d553544906f59bf521
BUZZ_RELAY_IMAGE ?= ghcr.io/block/buzz:sha-0096d71
CODEX_VERSION ?= 0.145.0
CLAUDE_CODE_VERSION ?= 2.1.220
CODEX_ACP_VERSION ?= 1.1.7
CLAUDE_ACP_VERSION ?= 0.62.0
GOOSE_VERSION ?= 1.44.0
GOOSE_ARCHIVE_SHA256 ?= 07febc8b4f73bdfdc3ece3d34d0e21b005f3a4f43008f95b85d6538da8f6bac1
BIND_ADDRESS ?= 127.0.0.1
PORT ?= 6903
RELAY_PORT ?= 3000
RESOLUTION ?= 1920x1080
VNC_STATS ?= false
VOLUME_PREFIX ?= buzzbox

GPU_DEVICE := $(shell test -d /dev/dri && echo --device=/dev/dri)

.PHONY: help check build run recreate up test smoke stop logs relay-log vnc-log status url

help:
	@echo "Buzzbox local Docker workflow"
	@echo
	@echo "  make check      Validate local scripts and pinned metadata"
	@echo "  make build      Build $(IMAGE)"
	@echo "  make run        Start or create the Buzzbox container"
	@echo "  make recreate   Recreate the container without rebuilding"
	@echo "  make up         Build and recreate the container"
	@echo "  make test       Check, build, run, and smoke-test the environment"
	@echo "  make smoke      Test the running desktop, relay, services, and agents"
	@echo "  make logs       Follow container logs"
	@echo "  make relay-log  Follow Buzz relay logs"
	@echo "  make vnc-log    Follow the KasmVNC session log"
	@echo "  make status     Show container and health status"
	@echo "  make stop       Stop and remove the container"
	@echo "  make url        Print the local desktop and relay URLs"
	@echo
	@echo "Overrides: PORT=8080 RELAY_PORT=3001 RESOLUTION=1600x900"
	@echo "           VNC_STATS=true"

check:
	bash -n init.sh openbox/autostart shell/buzzbox shell/chromium shell/welcome
	@grep -q "^ARG BUZZ_VERSION=$(BUZZ_VERSION)$$" Dockerfile
	@grep -q "^ARG BUZZ_DEB_SHA256=$(BUZZ_DEB_SHA256)$$" Dockerfile
	@grep -q "^ARG BUZZ_RELAY_IMAGE=$(BUZZ_RELAY_IMAGE)$$" Dockerfile
	@grep -q "^ARG CODEX_VERSION=$(CODEX_VERSION)$$" Dockerfile
	@grep -q "^ARG CLAUDE_CODE_VERSION=$(CLAUDE_CODE_VERSION)$$" Dockerfile
	@grep -q "^ARG CODEX_ACP_VERSION=$(CODEX_ACP_VERSION)$$" Dockerfile
	@grep -q "^ARG CLAUDE_ACP_VERSION=$(CLAUDE_ACP_VERSION)$$" Dockerfile
	@grep -q "^ARG GOOSE_VERSION=$(GOOSE_VERSION)$$" Dockerfile
	@grep -q "^ARG GOOSE_ARCHIVE_SHA256=$(GOOSE_ARCHIVE_SHA256)$$" Dockerfile
	@echo "Buzzbox metadata and shell syntax are valid."

build:
	$(DOCKER) build \
		--platform "$(PLATFORM)" \
		--build-arg TARGETARCH=amd64 \
		--build-arg "BUZZ_VERSION=$(BUZZ_VERSION)" \
		--build-arg "BUZZ_DEB_SHA256=$(BUZZ_DEB_SHA256)" \
		--build-arg "BUZZ_RELAY_IMAGE=$(BUZZ_RELAY_IMAGE)" \
		--build-arg "CODEX_VERSION=$(CODEX_VERSION)" \
		--build-arg "CLAUDE_CODE_VERSION=$(CLAUDE_CODE_VERSION)" \
		--build-arg "CODEX_ACP_VERSION=$(CODEX_ACP_VERSION)" \
		--build-arg "CLAUDE_ACP_VERSION=$(CLAUDE_ACP_VERSION)" \
		--build-arg "GOOSE_VERSION=$(GOOSE_VERSION)" \
		--build-arg "GOOSE_ARCHIVE_SHA256=$(GOOSE_ARCHIVE_SHA256)" \
		--tag "$(IMAGE)" \
		.

run:
	@if $(DOCKER) container inspect "$(CONTAINER)" >/dev/null 2>&1; then \
		if [ "$$($(DOCKER) container inspect --format '{{.State.Running}}' "$(CONTAINER)")" = "true" ]; then \
			echo "Container $(CONTAINER) is already running."; \
		else \
			$(DOCKER) start "$(CONTAINER)"; \
		fi; \
	else \
		$(DOCKER) run --detach \
			--name "$(CONTAINER)" \
			--platform "$(PLATFORM)" \
			--restart unless-stopped \
			--shm-size 1g \
			$(GPU_DEVICE) \
			--publish "$(BIND_ADDRESS):$(PORT):6901" \
			--publish "$(BIND_ADDRESS):$(RELAY_PORT):3000" \
			--env "BUZZBOX_RESOLUTION=$(RESOLUTION)" \
			--env "BUZZBOX_VNC_STATS=$(VNC_STATS)" \
			--volume "$(VOLUME_PREFIX)-workspace:/workspace" \
			--volume "$(VOLUME_PREFIX)-services:/var/lib/buzzbox" \
			--volume "$(VOLUME_PREFIX)-config:/home/buzzbox/.config" \
			--volume "$(VOLUME_PREFIX)-data:/home/buzzbox/.local/share" \
			--volume "$(VOLUME_PREFIX)-nest:/home/buzzbox/.buzz" \
			--volume "$(VOLUME_PREFIX)-codex:/home/buzzbox/.codex" \
			--volume "$(VOLUME_PREFIX)-claude:/home/buzzbox/.claude" \
			"$(IMAGE)"; \
	fi
	@$(MAKE) --no-print-directory url

recreate:
	@$(MAKE) --no-print-directory stop
	@$(MAKE) --no-print-directory run

up: build recreate

test: check up smoke

smoke:
	@echo "Waiting for Buzzbox at http://$(BIND_ADDRESS):$(PORT) ..."
	@ready=false; \
	for attempt in $$(seq 1 60); do \
		if curl --fail --silent "http://$(BIND_ADDRESS):$(PORT)/index.html" >/dev/null && \
			$(DOCKER) exec "$(CONTAINER)" curl --fail --silent \
				http://127.0.0.1:8080/_readiness >/dev/null; then \
			ready=true; \
			break; \
		fi; \
		sleep 2; \
	done; \
	if [ "$$ready" != "true" ]; then \
		echo "Buzzbox did not become ready within 120 seconds."; \
		$(DOCKER) logs --tail 150 "$(CONTAINER)" || true; \
		exit 1; \
	fi
	@$(DOCKER) exec "$(CONTAINER)" bash -ec '\
		for command in buzz-desktop buzz buzz-acp buzz-agent buzz-relay \
			codex codex-acp claude claude-agent-acp goose; do \
			command -v "$$command" >/dev/null; \
		done; \
		redis-cli ping | grep -q PONG; \
		pg_isready -h 127.0.0.1 -p 5432 -U buzz >/dev/null; \
		curl -fsS http://127.0.0.1:9000/minio/health/live >/dev/null; \
		pgrep -x buzz-relay >/dev/null; \
		pgrep -f buzz-desktop >/dev/null'
	@echo "Buzzbox is ready with the desktop, relay, and agent runtimes."

stop:
	@if $(DOCKER) container inspect "$(CONTAINER)" >/dev/null 2>&1; then \
		$(DOCKER) rm --force "$(CONTAINER)"; \
	else \
		echo "Container $(CONTAINER) does not exist."; \
	fi

logs:
	$(DOCKER) logs --follow "$(CONTAINER)"

relay-log:
	$(DOCKER) exec "$(CONTAINER)" \
		tail --lines=200 --follow /var/log/buzzbox/buzz-relay.log

vnc-log:
	$(DOCKER) exec "$(CONTAINER)" \
		bash -c 'tail --lines=200 --follow /home/buzzbox/.vnc/*:1.log'

status:
	@$(DOCKER) ps --all \
		--filter "name=^/$(CONTAINER)$$" \
		--format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'

url:
	@echo "Desktop: http://$(BIND_ADDRESS):$(PORT)"
	@echo "Relay:   ws://$(BIND_ADDRESS):$(RELAY_PORT)"
