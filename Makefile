SHELL := /bin/bash
.DEFAULT_GOAL := help

DOCKER ?= docker
IMAGE ?= pdparchitect/buzzbox:local
CONTAINER ?= buzzbox
NATIVE_ARCH := $(shell uname -m | sed \
	-e 's/^x86_64$$/amd64/' \
	-e 's/^aarch64$$/arm64/')
PLATFORM ?= linux/$(NATIVE_ARCH)
TARGETARCH ?= $(word 2,$(subst /, ,$(PLATFORM)))
BUZZ_VERSION ?= 0.5.0
BUZZ_DEB_SHA256 ?= 9674cf098eca88333e8d895ec9d0a5c56c796fbc358fe1087b645890b8e2faca
BUZZ_SOURCE_SHA ?= 4a977c588a540be38bd8ddb268cd24437bac8165
BUZZ_RELAY_IMAGE ?= ghcr.io/block/buzz:sha-4a977c5
CODEX_VERSION ?= 0.145.0
CLAUDE_CODE_VERSION ?= 2.1.220
CODEX_ACP_VERSION ?= 1.1.7
CLAUDE_ACP_VERSION ?= 0.62.0
GOOSE_VERSION ?= 1.44.0
GOOSE_AMD64_SHA256 ?= 07febc8b4f73bdfdc3ece3d34d0e21b005f3a4f43008f95b85d6538da8f6bac1
GOOSE_ARM64_SHA256 ?= da6cb005d421b0bdcb83fe8386ba5ae8060ef17adf64641a684d4fc4b9e1c15f
BIND_ADDRESS ?= 127.0.0.1
PORT ?= 6903
RELAY_PORT ?= 3000
BUZZ_NETWORK ?=
PUBLIC_RELAY_URL ?=
RESOLUTION ?= 1920x1080
VNC_STATS ?= false
VOLUME_PREFIX ?= buzzbox

# Pass render nodes only. `--device=/dev/dri` would also hand over card*, the
# DRM master/modesetting node, which nothing in this container has a use for.
GPU_DEVICE := $(shell for node in /dev/dri/renderD*; do \
	[ -e "$$node" ] && echo "--device=$$node"; done)
NETWORK_ARG := $(if $(strip $(BUZZ_NETWORK)),--network "$(BUZZ_NETWORK)",)
PUBLIC_RELAY_ENV := $(if $(strip $(PUBLIC_RELAY_URL)),--env "BUZZBOX_PUBLIC_RELAY_URL=$(PUBLIC_RELAY_URL)",)

.PHONY: help check build network run recreate up test smoke stop logs relay-log vnc-log status url size-report

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
	@echo "  make size-report  Report the graphical stack's share of the image"
	@echo
	@echo "Overrides: PORT=8080 RELAY_PORT=3001 RESOLUTION=1600x900"
	@echo "           PLATFORM=linux/arm64 (default: $(PLATFORM))"
	@echo "           BUZZ_NETWORK=buzz-local"
	@echo "           PUBLIC_RELAY_URL=ws://buzzbox:3000 VNC_STATS=true"

check:
	bash -n init.sh openbox/autostart shell/buzzbox shell/chromium shell/welcome \
		shell/agent-runtime-login shell/buzznode-enrollment \
		tests/test-agent-runtime-login.sh tests/test-buzznode-enrollment.sh \
		tests/test-desktop-theme.sh tests/smoke-container.sh
	bash tests/test-agent-runtime-login.sh
	bash tests/test-buzznode-enrollment.sh
	bash tests/test-desktop-theme.sh
	@grep -q "^ARG BUZZ_VERSION=$(BUZZ_VERSION)$$" Dockerfile
	@grep -q "^ARG BUZZ_DEB_SHA256=$(BUZZ_DEB_SHA256)$$" Dockerfile
	@grep -q "^ARG BUZZ_SOURCE_SHA=$(BUZZ_SOURCE_SHA)$$" Dockerfile
	@grep -q "^ARG BUZZ_RELAY_IMAGE=$(BUZZ_RELAY_IMAGE)$$" Dockerfile
	@grep -q "^ARG CODEX_VERSION=$(CODEX_VERSION)$$" Dockerfile
	@grep -q "^ARG CLAUDE_CODE_VERSION=$(CLAUDE_CODE_VERSION)$$" Dockerfile
	@grep -q "^ARG CODEX_ACP_VERSION=$(CODEX_ACP_VERSION)$$" Dockerfile
	@grep -q "^ARG CLAUDE_ACP_VERSION=$(CLAUDE_ACP_VERSION)$$" Dockerfile
	@grep -q "^ARG GOOSE_VERSION=$(GOOSE_VERSION)$$" Dockerfile
	@grep -q "^ARG GOOSE_AMD64_SHA256=$(GOOSE_AMD64_SHA256)$$" Dockerfile
	@grep -q "^ARG GOOSE_ARM64_SHA256=$(GOOSE_ARM64_SHA256)$$" Dockerfile
	@grep -q 'assets/favicon.svg' kasm/patch.sh
	@grep -q 'COPY kasm/favicon.svg /usr/share/kasmvnc/www/assets/favicon.svg' Dockerfile
	@grep -q 'window.handle.width: 0' openbox/theme/themerc
	@grep -q 'window.client.padding.width: 6' openbox/theme/themerc
	@grep -q 'window.client.padding.height: 6' openbox/theme/themerc
	@grep -q 'cd /workspace' shell/bashrc
	@grep -q 'BUZZBOX_CODEX_SANDBOX_MODE' init.sh
	@grep -q 'BUZZBOX_CODEX_SANDBOX_MODE' README.md
	@grep -q '\[ -n "$${PS1:-}" \]' shell/bashrc
	@grep -q '<action name="Resize" />' openbox/rc.xml
	@echo "Buzzbox metadata and shell syntax are valid."

build:
	$(DOCKER) build \
		--platform "$(PLATFORM)" \
		--build-arg "TARGETARCH=$(TARGETARCH)" \
		--build-arg "BUZZ_VERSION=$(BUZZ_VERSION)" \
		--build-arg "BUZZ_DEB_SHA256=$(BUZZ_DEB_SHA256)" \
		--build-arg "BUZZ_SOURCE_SHA=$(BUZZ_SOURCE_SHA)" \
		--build-arg "BUZZ_RELAY_IMAGE=$(BUZZ_RELAY_IMAGE)" \
		--build-arg "CODEX_VERSION=$(CODEX_VERSION)" \
		--build-arg "CLAUDE_CODE_VERSION=$(CLAUDE_CODE_VERSION)" \
		--build-arg "CODEX_ACP_VERSION=$(CODEX_ACP_VERSION)" \
		--build-arg "CLAUDE_ACP_VERSION=$(CLAUDE_ACP_VERSION)" \
		--build-arg "GOOSE_VERSION=$(GOOSE_VERSION)" \
		--build-arg "GOOSE_AMD64_SHA256=$(GOOSE_AMD64_SHA256)" \
		--build-arg "GOOSE_ARM64_SHA256=$(GOOSE_ARM64_SHA256)" \
		--tag "$(IMAGE)" \
		.

network:
	@if [ -n "$(strip $(BUZZ_NETWORK))" ]; then \
		if ! $(DOCKER) network inspect "$(BUZZ_NETWORK)" >/dev/null 2>&1; then \
			$(DOCKER) network create "$(BUZZ_NETWORK)" >/dev/null; \
			echo "Created Docker network $(BUZZ_NETWORK)."; \
		fi; \
	fi

run: network
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
			$(NETWORK_ARG) \
			--publish "$(BIND_ADDRESS):$(PORT):6901" \
			--publish "$(BIND_ADDRESS):$(RELAY_PORT):3000" \
			$(PUBLIC_RELAY_ENV) \
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
	@DOCKER="$(DOCKER)" bash tests/smoke-container.sh \
		"$(CONTAINER)" "$(TARGETARCH)"
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

size-report:
	@DOCKER="$(DOCKER)" bash tools/size-report.sh "$(IMAGE)"
