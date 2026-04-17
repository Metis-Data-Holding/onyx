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

1. Create `/opt/metis/onyx` on the ECS host.
2. Copy `.env.example` to `/opt/metis/onyx/.env` and update any secrets before launch.
3. Install the host Nginx snippet for `onyx.metisdata.ai`.
4. Bring up the Onyx Lite stack from `/opt/metis/onyx` using the approved deployment entry for this environment.
5. Verify the app responds through `https://onyx.metisdata.ai`.

## Rollback

Rollback starts from the same deployment root:

1. Restore the previous known-good `.env` and image tag.
2. Reapply the prior deployment entry from `/opt/metis/onyx`.
3. Reload or restart the host Nginx config if the gateway file changed.

If the failure is in the reverse proxy only, rollback can be limited to restoring the previous
`onyx.metisdata.ai` Nginx include and reloading Nginx.
