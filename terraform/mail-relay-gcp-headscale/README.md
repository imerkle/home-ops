# Mail Relay VPS (GCP + Headscale)

This Terraform stack provisions:
- GCP VPC network + public subnet + firewall rule (TCP 22/25/8080 open by default)
- GCE compute instance (default `e2-micro`)
- Cloud-init bootstrap of Postfix relay
- Headscale server on the same VPS
- Tailscale client on the VPS joined to that Headscale
- Optional Cloudflare `A`, `MX`, `SPF`, `DMARC` DNS records

## Why this works behind CGNAT

Public SMTP servers deliver to your `MX` target over TCP 25.
Because your home server cannot expose 25 publicly, the VPS receives mail and forwards it over Headscale mesh to Stalwart.

## Flow

1. Internet MTA -> VPS (`mail.example.com:25`)
2. VPS Postfix -> Stalwart mesh IP (`100.x.y.z:25`)

## Prerequisites

- GCP project with billing enabled
- Compute Engine API enabled
- Vault running in Kubernetes (accessible at `vault.vault:8200`)
- Vault with GCP and Cloudflare credentials stored:
  - GCP credentials in `secret/ai` (with gcp_project_id and service account keys as base64-encoded JSON)
  - Cloudflare credentials in `secret/cloudflare` (with DNS1_TOKEN and DNS1_ZONE_ID)
- Vault configured with Kubernetes authentication method for the tofu-controller/tf-runner ServiceAccount
- No existing Headscale required (this stack creates one on VPS)
- Stalwart reachable on mesh IP:25
- Cloudflare zone/API token (optional, can be retrieved from Vault)

## Usage

### Running Locally (Outside Kubernetes)
```bash
cd terraform/mail-relay-gcp-headscale
# If not using Vault for all credentials, copy and edit tfvars:
# cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars (only if overriding Vault values)

# Configure Vault authentication for local access
export VAULT_ADDR=https://vault.x3y.space
export VAULT_TOKEN=YOUR_VAULT_TOKEN

terraform init -upgrade
terraform plan
terraform apply

# Fetch generated reusable key for your cluster clients:
terraform output headscale_authkey_read_cmd
# Run that printed ssh command to get the key value.
```

#### Getting a Vault Token

If you have access to the Kubernetes cluster, you can get a token by authenticating to Vault:

```bash
# If vault CLI is available
vault login -method=kubernetes role=YOUR_ROLE_NAME

# Or get a token from a service account if configured
kubectl get secret YOUR_SA_SECRET_NAME -n NAMESPACE -o jsonpath='{.data.token}' | base64 --decode
```

### Running in Kubernetes
```bash
# When running in Kubernetes, ensure:
# 1. Pod has appropriate ServiceAccount for Vault K8s auth
# 2. Vault is accessible at vault.vault:8200
# 3. Vault has been configured with the pod's ServiceAccount

terraform init -upgrade
terraform plan
terraform apply
```

## Vault Secret Structure

Store your credentials in Vault with the following structure:

### GCP Credentials
```hcl
vault kv put secret/ai \
  gcp_project_id="your-project-id" \
  type="service_account" \
  project_id="your-project-id" \
  private_key_id="..." \
  private_key="-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n" \
  client_email="terraform@your-project-id.iam.gserviceaccount.com" \
  client_id="..." \
  auth_uri="https://accounts.google.com/o/oauth2/auth" \
  token_uri="https://oauth2.googleapis.com/token" \
  auth_provider_x509_cert_url="https://www.googleapis.com/oauth2/v1/certs" \
  client_x509_cert_url="https://www.googleapis.com/robot/v1/metadata/x509/terraform%40your-project-id.iam.gserviceaccount.com"
```

### Cloudflare Credentials
```hcl
vault kv put secret/cloudflare \
  DNS1_TOKEN="your-cloudflare-api-token" \
  DNS1_ZONE_ID="your-zone-id"
```

### Alternative Secret Structure (if using nested keys)
If your GCP credentials are stored as a JSON string under the 'gcp' key:

```hcl
vault kv put secret/ai \
  gcp='{"type":"service_account","project_id":"your-project-id","private_key_id":"...","private_key":"-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n","client_email":"terraform@your-project-id.iam.gserviceaccount.com",...}'
  gcp_project_id="your-project-id"
```

## Notes

- `e2-micro` can be Always Free only in eligible US regions and within quota limits.
- Capacity and anti-abuse controls can still affect VM creation and SMTP behavior.
- Port 25 ingress/egress behavior may vary by account/project restrictions.
- This setup relays an entire domain (`relay_domains = your domain`) to Stalwart.
- Add SPF/DKIM/DMARC in Stalwart and DNS once inbound works.
- `headscale_url` must be reachable by your cluster clients (usually `http://<vps-ip>:8080` first, then move to HTTPS behind a reverse proxy).
