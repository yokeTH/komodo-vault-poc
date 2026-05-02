# Komodo + Vault POC

Komodo deploys application stacks. Vault injects their secrets at runtime
via Vault Agent (`exec` mode) baked into each app image. Secrets never
touch Komodo's database.

## Layout

```
infra/                    # long-lived infra: Komodo + Vault + Traefik (manual `docker compose up`)
  docker-compose.yaml
  vault/
    config.hcl
    policies/demo.hcl     # policy granted to the vault demo user
  traefik/dynamic/        # routers for api/vault/komodo behind Traefik
apps/
  api/                    # one app per directory
    main.go               # Fiber v3 service
    agent.hcl             # vault-agent config (exec mode)
    Dockerfile            # multi-stage; final image = vault-agent + binary
    compose.yaml          # what Komodo deploys
```

## 1. Start infra

```sh
cd infra
docker compose up -d
```

Vault runs in production mode (file storage), so on first boot it must be
initialized and unsealed:

```sh
docker compose exec vault vault operator init -key-shares=1 -key-threshold=1
# save the Unseal Key and Initial Root Token

docker compose exec vault vault operator unseal <UNSEAL_KEY>
```

Enable the KV v2 engine and write the token the api image expects
(`/etc/vault/token` is baked as `root` in `apps/api/Dockerfile` — keep them
aligned, or override the token file in production):

```sh
docker compose exec vault sh -c '
  export VAULT_TOKEN=<INITIAL_ROOT_TOKEN>
  vault secrets enable -path=secret kv-v2 || true'
```

UIs (via Traefik on `:443`, hosts in `infra/traefik/dynamic/`):

- Vault:  https://vault.yoke-th.me
- Komodo: https://komodo.yoke-th.me
- api:    https://api-demo.yoke-th.me/api

## 2. Seed secrets in Vault

The api reads a single `ENV_MESSAGE` field from `secret/apps/api`.

UI: Secrets → `secret/` → Create → path `apps/api`, field `ENV_MESSAGE`.

Or CLI:
```sh
docker compose -f infra/docker-compose.yaml exec vault sh -c '
  VAULT_TOKEN=<ROOT_TOKEN> vault kv put secret/apps/api \
    ENV_MESSAGE=hello-from-vault'
```

## 3. Build the api image

```sh
docker build -t komodo-vault-poc/api:latest apps/api
```

(In real life: push to a registry Komodo can pull from.)

## 4. Deploy with Komodo

In Komodo UI:
1. Add the local periphery as a **Server**.
2. Create a **Stack** pointing at `apps/api/compose.yaml`.
3. Click **Deploy**.

Verify:
```sh
curl http://localhost:3000
# {"ENV_MESSAGE":"hello-from-vault"}
```

## 5. Rotate

```sh
docker compose -f infra/docker-compose.yaml exec vault sh -c '
  VAULT_TOKEN=<ROOT_TOKEN> vault kv put secret/apps/api \
    ENV_MESSAGE=rotated-value'
```

Within ~5s, vault-agent re-execs the api child process. The container
keeps running; Komodo sees no event. `curl localhost:3000` returns the
new value.

## What goes where

| Concern | Owner |
|---|---|
| Image tag, ports, replicas | Komodo (compose interpolation) |
| App secrets (e.g. `ENV_MESSAGE`) | Vault KV → vault-agent |
| Container lifecycle, redeploy, alerts | Komodo |
| Secret rotation | Vault (auto via agent re-exec) |

## Demo accounts (share with a friend)

Admin login is created from the env in `infra/docker-compose.yaml`:
`admin` / `admin-change-me` (change before sharing).

Create a single restricted `demo` identity in both systems by hand:

### Komodo demo user (`:9120` / komodo.yoke-th.me)

Login as `admin`, then:

1. **Users** → **Create User** → username `demo`, password `demo`, enable login.
2. Open the user → set **Level** to `None` (no global access).
3. Go to the `api` Stack → **Permissions** → grant `demo` the `Execute`
   level (lets them deploy/start/stop, but not edit compose or see other
   resources).

### Vault demo user (`:8200` / vault.yoke-th.me)

The policy is already in `infra/vault/policies/demo.hcl` (read/write
`secret/apps/*`, list metadata, nothing else).

```sh
docker compose -f infra/docker-compose.yaml exec vault sh -c '
  export VAULT_TOKEN=<ROOT_TOKEN>
  vault policy write demo /vault/config/policies/demo.hcl || \
    vault policy write demo - <<EOF
$(cat)
EOF
  vault auth enable userpass || true
  vault write auth/userpass/users/demo \
    password=demo \
    token_policies=demo'
```

(`config.hcl` only mounts `/vault/config/config.hcl`; if you want the
policy file available inside the container, mount the `policies/` dir or
just pipe the file in via `vault policy write demo - < demo.hcl` from
the host.)

| System | What `demo` can do | What `demo` cannot do |
|---|---|---|
| Komodo | Redeploy / start / stop the `api` Stack | Edit compose, create resources, see other stacks |
| Vault  | Read & write `secret/apps/*` (rotate app secrets) | Touch any other path, change policies, see root |

## Production notes

- Replace dev-style root-token auth with **AppRole**, **Kubernetes**, or cloud IAM. Bake the role_id into the image; deliver secret_id via Komodo's per-deployment env var (Komodo *Variables* are fine for non-secret-id-grade values, or use response-wrapped tokens).
- Pin image digests, not `:latest`.
- Lock down the policy: `path "secret/data/apps/api" { capabilities = ["read"] }`.
- Persist and back up `infra/vault-data/` — losing it loses every secret.
