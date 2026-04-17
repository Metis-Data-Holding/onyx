# BytePlus Lite Deployment Scaffolding

This directory contains the minimal deployment helpers for the BytePlus-hosted Onyx Lite setup.

## Target

- Domain: `onyx.metisdata.ai`
- Recommended server directory: `/opt/metis/onyx`
- Copy `.env.example` to `.env` before starting the stack
- This `.env.example` is meant to be used with the BytePlus overlay under `deployment/byteplus-lite`, not
  with the raw official compose files by itself.

## Files in this directory

- `.env.example`: baseline runtime settings for the deployment
- `nginx.onyx.metisdata.ai.conf.example`: host-level Nginx reverse-proxy snippet

## Host Nginx setup

Add a server block for `onyx.metisdata.ai` on the gateway host and proxy traffic to the local app
listener at `http://127.0.0.1:39000`.

The included Nginx example shows the approved gateway shape:

- forward standard proxy headers
- forward upgrade headers for WebSocket support
- disable proxy buffering
- set `proxy_read_timeout 86400s`
- set `client_max_body_size 512m`

The Nginx example includes a top-level `map`, so place it in an `http`-level include on the host Nginx
configuration. Do not drop it into a standalone `server` include block.

Place the final gateway config in the host Nginx include path used by your BytePlus gateway and reload Nginx
after validation.

## Cloudflare DNS

Create DNS records for `onyx.metisdata.ai` so the hostname resolves to the BytePlus gateway.

- Add the `onyx` record to Cloudflare
- Point it at the public IP or load balancer for the host running Nginx
- Keep the record aligned with the gateway host used by the reverse proxy

## First deployment

1. Create `/opt/metis/onyx` on the ECS host and ensure this repository is checked out there.
2. Copy `deployment/byteplus-lite/.env.example` to `/opt/metis/onyx/.env`, then set at least:
   - `POSTGRES_PASSWORD`
   - `USER_AUTH_SECRET`
   - `WEB_DOMAIN=https://onyx.metisdata.ai`
3. Install the host Nginx snippet for `onyx.metisdata.ai`, test config, and reload host Nginx.
4. Run deployment from repo root:
   ```bash
   cd /opt/metis/onyx
   chmod +x deployment/byteplus-lite/deploy.sh
   ./deployment/byteplus-lite/deploy.sh
   ```

## First-run validation

After deployment finishes, run this checklist in order:

1. Compose status:
   Run `docker compose ps` with the BytePlus overlay:
   ```bash
   cd /opt/metis/onyx/deployment/docker_compose
   docker compose \
     --env-file /opt/metis/onyx/.env \
     -f docker-compose.yml \
     -f docker-compose.onyx-lite.yml \
     -f ../byteplus-lite/docker-compose.byteplus-lite.yml \
     ps
   ```
2. Local ingress health:
   ```bash
   curl http://127.0.0.1:39000
   ```
3. External access:
   - Open `https://onyx.metisdata.ai`
   - Confirm the login page loads
4. Authentication:
   - Sign in with `basic` auth credentials
5. Model setup:
   - Open admin settings
   - Configure your model provider and API key
   - Send a simple chat to verify model calls succeed

## Rollback

Rollback from the same deployment root:

1. Return to the previous known-good git revision:
   ```bash
   cd /opt/metis/onyx
   git checkout <previous-good-sha-or-tag>
   ```
2. Re-run deployment:
   ```bash
   ./deployment/byteplus-lite/deploy.sh
   ```
3. If the issue is gateway-only, restore the previous host Nginx config for `onyx.metisdata.ai` and reload host Nginx.
