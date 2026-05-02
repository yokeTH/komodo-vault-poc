# Komodo + Vault POC

Komodo deploys application stacks. Vault injects their secrets at runtime
via Vault Agent (`exec` mode) baked into each app image. Secrets never
touch Komodo's database.

## Layout

```
infra/                    # long-lived infra: Komodo + Vault (manual `docker compose up`)
  docker-compose.yaml
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

- Vault UI: http://localhost:8200  (token: `root`)
- Komodo UI: http://localhost:9120

## 2. Seed secrets in Vault

UI: Secrets → `secret/` → Create → path `apps/api`, fields:
- `DB_PASSWORD`
- `JWT_SECRET`
- `STRIPE_KEY`

Or CLI:
```sh
docker compose -f infra/docker-compose.yaml exec vault sh -c '
  VAULT_TOKEN=root vault kv put secret/apps/api \
    DB_PASSWORD=db-pass-123 \
    JWT_SECRET=jwt-xyz \
    STRIPE_KEY=sk_test_abc'
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
# {"API_DB_PASSWORD":"db-pass-123","API_JWT_SECRET":"jwt-xyz","API_STRIPE_KEY":"sk_test_abc"}
```

## 5. Rotate

```sh
docker compose -f infra/docker-compose.yaml exec vault sh -c '
  VAULT_TOKEN=root vault kv put secret/apps/api \
    DB_PASSWORD=ROTATED JWT_SECRET=ROTATED STRIPE_KEY=ROTATED'
```

Within ~5s, vault-agent re-execs the api child process. The container
keeps running; Komodo sees no event. `curl localhost:3000` returns the
new values.

## What goes where

| Concern | Owner |
|---|---|
| Image tag, ports, replicas | Komodo (compose interpolation) |
| API keys, DB passwords, signing keys | Vault KV → vault-agent |
| Container lifecycle, redeploy, alerts | Komodo |
| Secret rotation | Vault (auto via agent re-exec) |

## Demo account (share with a friend)

After the `api` Stack exists in Komodo, run:

```sh
./infra/setup-demo.sh
```

This creates a single restricted `demo`/`demo` identity in both systems:

| System | What `demo` can do | What `demo` cannot do |
|---|---|---|
| Komodo (`:9120`) | Redeploy / start / stop the `api` Stack | Edit compose, create resources, see other stacks |
| Vault  (`:8200`) | Read & write `secret/apps/*` (rotate app secrets) | Touch any other path, change policies, see root |

Admin login stays separate: `admin` / `admin-change-me` (change in `infra/docker-compose.yaml`).

Override defaults via env vars before running the script: `KOMODO_ADMIN_PASS`,
`DEMO_USER`, `DEMO_PASS`, `STACK_NAME`.

## Production notes

- Replace dev-mode Vault with a sealed cluster.
- Replace `token_file` (root) auth with **AppRole**, **Kubernetes**, or cloud IAM. Bake the role_id into the image; deliver secret_id via Komodo's per-deployment env var (Komodo *Variables* are fine for non-secret-id-grade values, or use response-wrapped tokens).
- Pin image digests, not `:latest`.
- Lock down the policy: `path "secret/data/apps/api" { capabilities = ["read"] }`.
