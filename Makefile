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
BUZZ_VERSION ?= 0.5.2
BUZZ_DEB_SHA256 ?= 3f022bc31ed579e045946e6acab8483639bcb94e62c1e70f67b97b22f8f879c5
BUZZ_SOURCE_SHA ?= 3e48f1b2365d326ee1c9582448d86a99b44ecd5d
BUZZ_RELAY_IMAGE ?= ghcr.io/block/buzz:sha-3e48f1b
DESKTOP_IMAGE ?= ghcr.io/pdparchitect/launcher-image-base-desktop:0.1.7
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
# The container-side ports. 6901 is the desktop base's and is not redeclared
# here, the same way hermes, openclaw, and petbox do not redeclare it.
RELAY_CONTAINER_PORT ?= 3000
HEALTH_PORT ?= 8080
BUZZ_NETWORK ?=
PUBLIC_RELAY_URL ?=
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
	@echo "Overrides: PORT=8080 RELAY_PORT=3001"
	@echo "           PLATFORM=linux/arm64 (default: $(PLATFORM))"
	@echo "           BUZZ_NETWORK=buzz-local"
	@echo "           PUBLIC_RELAY_URL=ws://buzzbox:3000 VNC_STATS=true"

check:
	bash -n \
		overlay/etc/desktop/session.d/10-buzz-desktop \
		overlay/etc/desktop/startup.d/05-agent-runtime-trust \
		overlay/etc/desktop/startup.d/10-buzz-stack \
		overlay/usr/local/bin/agent-runtime-login \
		overlay/usr/local/bin/buzzbox \
		overlay/usr/local/bin/buzzbox-greeting \
		overlay/usr/local/bin/buzznode-enrollment \
		overlay/usr/local/bin/desktop-harness \
		overlay/usr/local/bin/desktop-panel-status \
		overlay/usr/local/bin/desktop-welcome \
		tests/test-agent-runtime-login.sh tests/test-buzznode-enrollment.sh \
		tests/test-desktop-theme.sh tests/smoke-container.sh
	bash tests/test-agent-runtime-login.sh
	bash tests/test-buzznode-enrollment.sh
	bash tests/test-desktop-theme.sh
	@grep -q "^ARG DESKTOP_IMAGE=$(DESKTOP_IMAGE)$$" Dockerfile
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
	@grep -q 'RUN kasm-patch "Buzzbox"' Dockerfile
	@grep -q '    BUZZ_RELAY_PORT=$(RELAY_CONTAINER_PORT) \\' Dockerfile
	@grep -q '    BUZZ_HEALTH_PORT=$(HEALTH_PORT) \\' Dockerfile
	@grep -q '^EXPOSE $(RELAY_CONTAINER_PORT)$$' Dockerfile
	@grep -q 'http://127.0.0.1:6902/healthz' Dockerfile
	@grep -q 'cd /workspace' overlay/etc/bash.bashrc.d/buzzbox-prompt.sh
	@grep -q 'BUZZBOX_CODEX_SANDBOX_MODE' overlay/etc/desktop/startup.d/05-agent-runtime-trust
	@grep -q 'BUZZBOX_CODEX_SANDBOX_MODE' README.md
	@grep -Fq 'service_user=agent' overlay/etc/desktop/startup.d/10-buzz-stack
	@grep -Fq 'runtime-managed volume' overlay/etc/desktop/startup.d/10-buzz-stack
	@grep -q '\[ -n "$${PS1:-}" \]' overlay/etc/bash.bashrc.d/buzzbox-prompt.sh
	@test "$$(jq -er '.schemaVersion' launcher/application.json)" = 2
	@test "$$(jq -er '.mounts[] | select(.name == "private/services") | .storage' launcher/application.json)" = volume
	@! jq -e 'has("image")' launcher/application.json >/dev/null
	@jq -e '.interfaces.health.kind == "health" and .interfaces.health.port == 6902 and .interfaces.health.path == "/healthz"' launcher/application.json >/dev/null
	@jq -e '.interfaces.notifications.kind == "notifications" and .interfaces.notifications.port == 6902 and .interfaces.notifications.path == "/notifications"' launcher/application.json >/dev/null
	@jq -e '.interfaces.preview.kind == "preview" and .interfaces.preview.port == 6902 and .interfaces.preview.path == "/preview.jpg"' launcher/application.json >/dev/null
	@for asset in $$(jq -er '.media.icon, .media.cover, .media.screenshots[].source' launcher/application.json); do \
		test -f "launcher/$$asset"; \
	done
	@echo "Buzzbox metadata and shell syntax are valid."

build:
	$(DOCKER) build \
		--platform "$(PLATFORM)" \
		--build-arg "TARGETARCH=$(TARGETARCH)" \
		--build-arg "DESKTOP_IMAGE=$(DESKTOP_IMAGE)" \
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
			--publish "$(BIND_ADDRESS):$(RELAY_PORT):$(RELAY_CONTAINER_PORT)" \
			$(PUBLIC_RELAY_ENV) \
			--env "DESKTOP_VNC_STATS=$(VNC_STATS)" \
			--volume "$(VOLUME_PREFIX)-workspace:/workspace" \
			--volume "$(VOLUME_PREFIX)-services:/var/lib/buzzbox" \
			--volume "$(VOLUME_PREFIX)-config:/home/agent/.config" \
			--volume "$(VOLUME_PREFIX)-data:/home/agent/.local/share" \
			--volume "$(VOLUME_PREFIX)-nest:/home/agent/.buzz" \
			--volume "$(VOLUME_PREFIX)-codex:/home/agent/.codex" \
			--volume "$(VOLUME_PREFIX)-claude:/home/agent/.claude" \
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
				http://127.0.0.1:$(HEALTH_PORT)/_readiness >/dev/null; then \
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
		tail --lines=200 --follow /var/log/launcher-desktop/buzz-relay.log

vnc-log:
	$(DOCKER) exec "$(CONTAINER)" \
		bash -c 'tail --lines=200 --follow /home/agent/.vnc/*:1.log'

status:
	@$(DOCKER) ps --all \
		--filter "name=^/$(CONTAINER)$$" \
		--format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'

url:
	@echo "Desktop: http://$(BIND_ADDRESS):$(PORT)"
	@echo "Relay:   ws://$(BIND_ADDRESS):$(RELAY_PORT)"

size-report:
	@DOCKER="$(DOCKER)" bash tools/size-report.sh "$(IMAGE)"
