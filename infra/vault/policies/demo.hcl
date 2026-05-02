path "secret/data/apps/*" {
  capabilities = ["create", "read", "update", "patch"]
}

path "secret/metadata/apps/*" {
  capabilities = ["read", "list"]
}

path "secret/metadata/apps" {
  capabilities = ["list"]
}
