path "secret/data/apps/api" {
  capabilities = ["read"]
}

path "secret/metadata/apps/api" {
  capabilities = ["read"]
}

path "auth/token/renew-self" {
  capabilities = ["update"]
}

path "auth/token/lookup-self" {
  capabilities = ["read"]
}
