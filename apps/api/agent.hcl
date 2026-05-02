vault {
  address = "http://vault:8200"
  retry { num_retries = 5 }
}

auto_auth {
  method "approle" {
    config = {
      role_id_file_path                   = "/etc/vault/roleid"
      secret_id_file_path                 = "/etc/vault/secretid"
      remove_secret_id_file_after_reading = false
    }
  }
}

template_config {
  static_secret_render_interval = "5s"
}

env_template "ENV_MESSAGE" {
  contents = "{{ with secret \"secret/data/apps/api\" }}{{ .Data.data.ENV_MESSAGE }}{{ end }}"
}

exec {
  command                   = ["/api"]
  restart_on_secret_changes = "always"
  restart_stop_signal       = "SIGTERM"
}
