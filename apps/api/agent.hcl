vault {
  address = "http://vault:8200"
  retry { num_retries = 5 }
}

auto_auth {
  method "token_file" {
    config = {
      token_file_path = "/etc/vault/token"
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
