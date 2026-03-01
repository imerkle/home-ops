# GCP auth can be provided by Application Default Credentials (ADC),
# e.g. `gcloud auth application-default login`, or service account credentials.
gcp_project_id = "dev1-262513"
gcp_region     = "us-west1"
gcp_zone       = "us-west1-a"

# Domain + relay target
mail_domain          = "x3y.space"
hostname             = "mail"
relay_target_mesh_ip = "100.64.10.20"
relay_target_port    = 25

# Headscale hosted on this same VPS.
# Use HTTP for initial bootstrap; place a reverse proxy/TLS in front later if desired.
headscale_url         = "https://headscale.x3y.space"
headscale_listen_port = 8080
headscale_user        = "homelab"

# SSH
ssh_username        = "debian"
ssh_authorized_keys = "ssh-ed25519 AAAAC3... you@example"

# Cloudflare DNS (optional)
create_cloudflare_records = true
#cloudflare_api_token      = "cf_api_token_with_dns_edit"
#cloudflare_zone_id        = "cloudflare_zone_id"

# Optional overrides for free-tier compute
machine_type  = "e2-micro"
image_project = "debian-cloud"
image_family  = "debian-12"

# Use Vault for credentials when running in proper environment
use_vault = false  # Set to true when running with proper Vault access
