#!/bin/bash

set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
temporary_dir="$(mktemp -d)"
trap 'rm -rf "$temporary_dir"' EXIT

store="$temporary_dir/managed-agents.json"
private_key='0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
pubkey='abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789'
auth_tag='["oa","owner","conditions","signature"]'

jq -n \
    --arg private_key "$private_key" \
    --arg pubkey "$pubkey" \
    --arg auth_tag "$auth_tag" \
    '[
      {
          name: "Node template",
          pubkey: $pubkey,
          private_key_nsec: null,
          auth_tag: null,
          relay_url: "wss://team.example.com",
          runtime_pid: null,
          respond_to: "owner-only",
          respond_to_allowlist: []
      },
      {
          name: "Node agent",
          pubkey: $pubkey,
          private_key_nsec: $private_key,
          auth_tag: $auth_tag,
          relay_url: "wss://team.example.com",
          runtime_pid: null,
          respond_to: "allowlist",
          respond_to_allowlist: [
            "1111111111111111111111111111111111111111111111111111111111111111"
          ]
      }
    ]' > "$store"

cli="$project_dir/shell/buzznode-enrollment"
list_output="$(BUZZBOX_AGENT_STORE="$store" "$cli" list)"
grep -q 'Node agent' <<<"$list_output"
if grep -q 'Node template' <<<"$list_output"; then
    echo "agent list included a keyless agent definition" >&2
    exit 1
fi
if grep -Fq "$private_key" <<<"$list_output"; then
    echo "agent list leaked the private key" >&2
    exit 1
fi

export_output="$(
    BUZZBOX_AGENT_STORE="$store" "$cli" export --pubkey "$pubkey" 2>/dev/null
)"
bundle="$(grep '^buzznode-v1:' <<<"$export_output")"
test -n "$bundle"
decoded="$(printf '%s' "${bundle#buzznode-v1:}" | base64 --decode)"
test "$(jq -r '.version' <<<"$decoded")" = "1"
test "$(jq -r '.private_key' <<<"$decoded")" = "$private_key"
test "$(jq -r '.auth_tag' <<<"$decoded")" = "$auth_tag"
test "$(jq -r '.respond_to' <<<"$decoded")" = "allowlist"
test "$(jq -r '.respond_to_allowlist[0]' <<<"$decoded")" = \
    "1111111111111111111111111111111111111111111111111111111111111111"

public_relay_output="$(
    BUZZBOX_PUBLIC_RELAY_URL='wss://public.example.com' \
    BUZZBOX_AGENT_STORE="$store" \
        "$cli" export --pubkey "$pubkey" 2>/dev/null
)"
public_relay_bundle="$(grep '^buzznode-v1:' <<<"$public_relay_output")"
public_relay_decoded="$(
    printf '%s' "${public_relay_bundle#buzznode-v1:}" | base64 --decode
)"
test "$(jq -r '.relay_url' <<<"$public_relay_decoded")" = \
    "wss://team.example.com"

empty_relay_store="$temporary_dir/empty-relay.json"
jq 'map(.relay_url = "")' "$store" > "$empty_relay_store"
if env -u BUZZBOX_PUBLIC_RELAY_URL -u BUZZ_RELAY_URL \
    BUZZBOX_AGENT_STORE="$empty_relay_store" \
        "$cli" export --pubkey "$pubkey" >/dev/null 2>&1; then
    echo "enrollment exported a bundle without a relay URL" >&2
    exit 1
fi

local_relay_output="$(
    BUZZBOX_PUBLIC_RELAY_URL='wss://public.example.com' \
    BUZZ_RELAY_URL='ws://127.0.0.1:3000' \
    BUZZBOX_AGENT_STORE="$empty_relay_store" \
        "$cli" export --pubkey "$pubkey" 2>/dev/null
)"
local_relay_bundle="$(grep '^buzznode-v1:' <<<"$local_relay_output")"
local_relay_decoded="$(
    printf '%s' "${local_relay_bundle#buzznode-v1:}" | base64 --decode
)"
test "$(jq -r '.relay_url' <<<"$local_relay_decoded")" = \
    "wss://public.example.com"

color_output="$(
    env -u NO_COLOR FORCE_COLOR=1 BUZZBOX_AGENT_STORE="$store" \
        "$cli" export --pubkey "$pubkey" 2>/dev/null
)"
grep -Fq $'\033[' <<<"$color_output"
plain_output="$(
    FORCE_COLOR=1 NO_COLOR=1 BUZZBOX_AGENT_STORE="$store" \
        "$cli" export --pubkey "$pubkey" 2>/dev/null
)"
if grep -Fq $'\033[' <<<"$plain_output"; then
    echo "NO_COLOR did not disable enrollment styling" >&2
    exit 1
fi
grep -Fq 'buzznode-enrollment create; exec bash' \
    "$project_dir/openbox/menu.xml"
grep -Fq 'buzznode-enrollment; exec bash' \
    "$project_dir/openbox/menu.xml"

draft_store="$temporary_dir/draft-managed-agents.json"
cp "$store" "$draft_store"
draft_relay_log="$temporary_dir/draft-relays.log"
draft_pubkey='4444444444444444444444444444444444444444444444444444444444444444'
draft_private_key='5555555555555555555555555555555555555555555555555555555555555555'
(
    sleep 0.2
    jq \
        --arg pubkey "$draft_pubkey" \
        --arg private_key "$draft_private_key" \
        '. + [{
            name: "Drafted node agent",
            pubkey: $pubkey,
            private_key_nsec: $private_key,
            auth_tag: "",
            relay_url: "",
            runtime_pid: null,
            respond_to: "anyone",
            respond_to_allowlist: []
        }]' "$draft_store" > "$temporary_dir/drafted.json"
    mv "$temporary_dir/drafted.json" "$draft_store"
) &
draft_output="$(
    printf '\nDrafted node agent\n\n' |
        PATH="$project_dir/tests/fixtures:$PATH" \
        BUZZBOX_TEST_RELAY_LOG="$draft_relay_log" \
        BUZZBOX_PUBLIC_RELAY_URL='ws://buzzbox:3000' \
        BUZZ_RELAY_URL='ws://127.0.0.1:3000' \
        BUZZBOX_AGENT_STORE="$draft_store" \
        BUZZBOX_CREATE_AGENT_POLL_INTERVAL=0.05 \
        BUZZBOX_CREATE_AGENT_MAX_POLLS=30 \
            "$cli" create 2>/dev/null
)"
if grep -Fqv 'wss://team.example.com' "$draft_relay_log"; then
    echo "agent draft used the advertised relay instead of its workspace relay" >&2
    exit 1
fi
draft_bundle="$(grep '^buzznode-v1:' <<<"$draft_output")"
draft_decoded="$(
    printf '%s' "${draft_bundle#buzznode-v1:}" | base64 --decode
)"
test "$(jq -r '.relay_url' <<<"$draft_decoded")" = \
    "wss://team.example.com"

new_pubkey='2222222222222222222222222222222222222222222222222222222222222222'
new_private_key='3333333333333333333333333333333333333333333333333333333333333333'
(
    sleep 0.2
    jq \
        --arg pubkey "$new_pubkey" \
        --arg private_key "$new_private_key" \
        '. + [{
            name: "Fresh node agent",
            pubkey: $pubkey,
            private_key_nsec: $private_key,
            auth_tag: "",
            relay_url: "wss://team.example.com",
            runtime_pid: null,
            respond_to: "anyone",
            respond_to_allowlist: []
        }]' "$store" > "$temporary_dir/created.json"
    mv "$temporary_dir/created.json" "$store"
) &
create_output="$(
    BUZZBOX_AGENT_STORE="$store" \
    BUZZBOX_SKIP_CREATE_AGENT_DRAFT=true \
    BUZZBOX_CREATE_AGENT_POLL_INTERVAL=0.05 \
    BUZZBOX_CREATE_AGENT_MAX_POLLS=30 \
        "$cli" create 2>/dev/null
)"
create_bundle="$(grep '^buzznode-v1:' <<<"$create_output")"
created="$(
    printf '%s' "${create_bundle#buzznode-v1:}" | base64 --decode
)"
test "$(jq -r '.name' <<<"$created")" = "Fresh node agent"
test "$(jq -r '.private_key' <<<"$created")" = "$new_private_key"

jq --argjson runtime_pid "$$" '.[1].runtime_pid = $runtime_pid' \
    "$store" > "$temporary_dir/running.json"
if BUZZBOX_AGENT_STORE="$temporary_dir/running.json" \
    "$cli" export --pubkey "$pubkey" >/dev/null 2>&1; then
    echo "export accepted an agent that is still running locally" >&2
    exit 1
fi

echo "Buzzbox-to-Buzznode enrollment tests passed."
