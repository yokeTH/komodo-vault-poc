#!/usr/bin/env bash
# Bootstraps a restricted "demo" account in Vault and Komodo.
#
#   Vault demo : userpass login, can only read/write secret/apps/*
#   Komodo demo: local login, can only Execute (redeploy) the api stack
#
# Run after `docker compose up -d` and after the api Stack exists in Komodo.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
COMPOSE="docker compose -f $HERE/docker-compose.yaml"

KOMODO_URL="${KOMODO_URL:-http://localhost:9120}"
KOMODO_ADMIN_USER="${KOMODO_ADMIN_USER:-admin}"
KOMODO_ADMIN_PASS="${KOMODO_ADMIN_PASS:-admin-change-me}"

DEMO_USER="${DEMO_USER:-demo}"
DEMO_PASS="${DEMO_PASS:-demo}"
STACK_NAME="${STACK_NAME:-api}"

need() { command -v "$1" >/dev/null || { echo "missing: $1" >&2; exit 1; }; }
need curl
need jq

say() { printf '\n=== %s ===\n' "$*"; }

# ---------------------------------------------------------------- Vault
say "Vault: enable userpass + apply demo policy"
$COMPOSE cp "$HERE/vault/policies/demo.hcl" vault:/tmp/demo.hcl >/dev/null
$COMPOSE exec -T -e VAULT_TOKEN=root vault sh <<EOF
set -e
vault auth enable -path=userpass userpass 2>/dev/null || true
vault policy write demo /tmp/demo.hcl
vault write auth/userpass/users/$DEMO_USER \
  password=$DEMO_PASS \
  token_policies=demo
EOF

# ---------------------------------------------------------------- Komodo
say "Komodo: login as admin"
ADMIN_JWT=$(curl -fsS "$KOMODO_URL/auth" \
  -H 'content-type: application/json' \
  -d "{\"type\":\"LoginLocalUser\",\"params\":{\"username\":\"$KOMODO_ADMIN_USER\",\"password\":\"$KOMODO_ADMIN_PASS\"}}" \
  | jq -r .jwt)
[ -n "$ADMIN_JWT" ] && [ "$ADMIN_JWT" != "null" ] || { echo "admin login failed" >&2; exit 1; }

AUTH=(-H "authorization: $ADMIN_JWT" -H 'content-type: application/json')

say "Komodo: ensure demo user exists"
DEMO_ID=$(curl -fsS "$KOMODO_URL/read" "${AUTH[@]}" \
  -d '{"type":"ListUsers","params":{}}' \
  | jq -r ".[] | select(.username==\"$DEMO_USER\") | ._id[\"\$oid\"] // ._id" | head -n1)

if [ -z "$DEMO_ID" ] || [ "$DEMO_ID" = "null" ]; then
  CREATE=$(curl -fsS "$KOMODO_URL/write" "${AUTH[@]}" \
    -d "{\"type\":\"CreateLocalUser\",\"params\":{\"username\":\"$DEMO_USER\",\"password\":\"$DEMO_PASS\"}}")
  DEMO_ID=$(echo "$CREATE" | jq -r '._id["$oid"] // ._id // .id')
fi
echo "demo user id: $DEMO_ID"

say "Komodo: enable demo, deny resource creation"
curl -fsS "$KOMODO_URL/write" "${AUTH[@]}" -d "$(cat <<JSON
{"type":"UpdateUserBasePermissions","params":{
  "user_id":"$DEMO_ID",
  "enabled":true,
  "create_servers":false,
  "create_builds":false
}}
JSON
)" >/dev/null

say "Komodo: locate stack '$STACK_NAME'"
STACK_ID=$(curl -fsS "$KOMODO_URL/read" "${AUTH[@]}" \
  -d '{"type":"ListStacks","params":{}}' \
  | jq -r ".[] | select(.name==\"$STACK_NAME\") | .id" | head -n1)
[ -n "$STACK_ID" ] && [ "$STACK_ID" != "null" ] || {
  echo "stack '$STACK_NAME' not found. Create it in the Komodo UI first, then re-run." >&2
  exit 1
}

say "Komodo: grant Execute on stack to demo"
curl -fsS "$KOMODO_URL/write" "${AUTH[@]}" -d "$(cat <<JSON
{"type":"UpdatePermissionOnTarget","params":{
  "user_target":   {"type":"User",  "id":"$DEMO_ID"},
  "resource_target":{"type":"Stack","id":"$STACK_ID"},
  "permission":    {"level":"Execute","specific":[]}
}}
JSON
)" >/dev/null

cat <<EOF

Done. Share with your friend:

  Komodo  $KOMODO_URL
    user: $DEMO_USER
    pass: $DEMO_PASS
    can : Execute (redeploy) the '$STACK_NAME' stack only

  Vault   http://localhost:8200
    auth: userpass
    user: $DEMO_USER
    pass: $DEMO_PASS
    can : read/write secret/apps/*  (KV v2)

EOF
