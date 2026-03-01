# Mail Relay with Stalwart Integration

This setup provisions:
1. A mail relay server on GCP (via Terraform/Tofu)
2. A Stalwart mail server with Tailscale sidecar in Kubernetes

## Setup Process

1. Apply the mail relay Terraform configuration:
   ```bash
   kubectl apply -f kubernetes/apps/home-system/mail-relay/
   ```

2. Once the Terraform completes, retrieve the headscale preauth key:
   ```bash
   # The Terraform outputs a command to retrieve the key
   kubectl get secret mail-relay-outputs -n home-system -o jsonpath='{.data.headscale_authkey_read_cmd}' | base64 -d
   # Or check the Terraform output directly
   ```

3. Update the Tailscale auth secret with the retrieved key:
   ```bash
   kubectl create secret generic tailscale-auth -n home-system \
     --from-literal=authkey="YOUR_HEADSCALE_PREAUTH_KEY" \
     --dry-run=client -o yaml | kubectl apply -f -
   ```

4. Apply the Stalwart configuration:
   ```bash
   # This will deploy Stalwart with Tailscale sidecar that connects to your headscale
   ```

## Architecture

- Mail relay server (GCP) hosts headscale server
- Stalwart mail server (Kubernetes) connects to headscale via Tailscale sidecar
- Mail flows: Internet -> Mail Relay -> Stalwart (over Tailscale mesh network)