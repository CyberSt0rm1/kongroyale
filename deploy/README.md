# Homelab deployment

## Ray performance trial

The `trial/ray-performance` branch integrates RayFernando1337/kongroyale at `cad8bad` while retaining this homelab's
Docker deployment. It publishes `ghcr.io/cyberst0rm1/kongroyale:ray-trial` and an immutable `sha-<full commit>` tag.
The main branch and `latest` image remain available separately. The currently deployed image is pinned in the private
`homelab.env`; a rollback changes only `KR_IMAGE` to the previous tag and runs the same `pull` / `up -d` commands.

For the later performance test, open `https://kong.cyber.gs/?perfhud&seed=42`. The HUD records frame, GPU, memory and
network metrics. Press F8 when a stall occurs to save a report to this server; `KR_PLAYTEST_BUNDLES` controls its
storage folder, and the template places it under the persistent reports volume. Set it to `0` to disable bundle
storage. The fork caps bundle storage at 500 bundles or 1 GB. These tools do not establish a speedup until comparable
sessions have actually been measured.

The old image is `ghcr.io/cyberst0rm1/kongroyale:sha-39ad85c4c7cfb154242916083bde3665b35793cb`.

The image runs one Node server for HTTP, game WebSockets and voice signalling. Browser rendering and voice audio run
on the players' devices. MongoDB is optional; reports persist in the `kongroyale_reports` Docker volume without it.
The admin console is disabled until its key hash is configured. The upstream licence and credits are retained.

## Start and configure

```sh
cp deploy/homelab.env.example homelab.env
chmod 600 homelab.env
# Edit homelab.env for your hostname and trusted proxy address.
# Choose an unused subnet; these addresses are reserved for this deployment.
docker network create --subnet 172.16.42.0/24 kongroyale-tunnel
docker network connect --gw-priority -1 --ip 172.16.42.2 kongroyale-tunnel cloudflare-tunnel
docker compose --env-file homelab.env pull
docker compose --env-file homelab.env up -d --wait --wait-timeout 180
docker compose --env-file homelab.env ps
```

All runtime environment variables from HOSTING.md can be set in `homelab.env`. Apply changes with `up -d`, which
recreates the container as needed; `restart` alone does not reload environment variables. Restarting ends active matches.
Keep `KR_HOST=0.0.0.0`. Host publishing defaults to `0.0.0.0:3020`. Set `KR_ORIGINS` to the public HTTPS origin and
any LAN HTTP origin you actually use. LAN HTTP can play the game but cannot access the microphone in normal browsers.

Useful switches:

| Setting | Effect |
|---|---|
| `KR_EVENT_MODE=0` | Players can create rooms through Friends. |
| `KR_EVENT_MODE=1` | Only admin-created event lobbies can be joined. |
| `KR_ADMIN_KEY_SHA256` | Enables admin authentication at `/admin`; store only the key hash. |
| `KR_SECURE_COOKIE=1` | Secure admin cookies when HTTPS terminates at Cloudflare. |
| `KR_TRUST_PROXY=1`, `KR_PROXY_IPS` | Trust client-IP headers only from the listed connector address. |
| `KR_PERF_METRICS=1` | Include tick timing and memory metrics in `/health`. |
| `KR_MAX_CONNS`, `KR_MAX_PER_IP` | Bound socket counts; each player normally uses two. |
| `KR_MONGO_URI` | Optional report database; adding it does not save matches or player progress. |

Generate an admin key locally with `node tools/admin-lobby/key.mjs`, then obtain its hash with the same command plus
`--hash`. Keep `.admin-key` private and set only its hash in the server environment. Leave `KR_ANNOTATE=0` on a public
server. No database or admin credentials are baked into the image.

## Cloudflare route

Use the existing tunnel: add a Published application route for `kong.cyber.gs`, type HTTP, service
`http://kongroyale:3020`, with no path restriction. Cloudflare provides public HTTPS and forwards WebSocket
upgrades on the same port. The host also publishes `0.0.0.0:3020` for LAN access, but the tunnel must use the direct
container address: Docker's host-port hairpin route can hide the connector's IP. Do not use localhost.

The game and connector share the external `kongroyale-tunnel` network, at static addresses `.3` and `.2`. This network
does not replace the connector's existing networks or default route. Inspect the address without displaying its token:

```sh
docker inspect cloudflare-tunnel --format '{{with index .NetworkSettings.Networks "kongroyale-tunnel"}}{{.IPAddress}}{{end}}'
```

Set that exact IP in `KR_PROXY_IPS` and set `KR_TRUST_PROXY=1`. If the connector is recreated, repeat the network-connect
command above (or add this external network and static address to its own persistent Compose/Portainer configuration).
Container restarts retain the network attachment. Direct LAN connections remain untrusted. No router ports are needed.

Voice requires HTTPS, microphone permission and squadmates. This deployment retains upstream's direct WebRTC/STUN
voice: restrictive NATs may prevent audio. TURN support requires a separate integration; no relay is deployed here.

## Images and updates

The GitHub `checks` workflow builds and tests the source, scans for secrets, then publishes the container from `main`
to `ghcr.io/cyberst0rm1/kongroyale:latest` and `:sha-<full commit>`. Publication uses the workflow's GITHUB_TOKEN.
The homelab uses a commit tag, and Watchtower updates are disabled to avoid interrupting matches unexpectedly.
The GHCR package must be public for anonymous pulls; otherwise log in using a token with package read access.

To update, set `KR_IMAGE` to the desired commit tag, then run `pull` and `up -d --wait`. Roll back using the previous
commit tag with the same commands. The reports volume is retained; never use `down -v` unless intentionally deleting it.

Client flags `VITE_KR_PLAYTEST` and `DEPLOY_BASE` are build-time settings. The published image enables the full title
screen (`VITE_KR_PLAYTEST=0`) at `/`. For a custom build:

```sh
# Set KR_IMAGE=kongroyale:local and the desired build variables in homelab.env first.
docker compose --env-file homelab.env build
docker compose --env-file homelab.env up -d --pull never
```

For sub-path deployments, set matching `DEPLOY_BASE` (build) and `KR_BASE_PATH` (runtime).

## Checks and logs

```sh
curl --fail http://127.0.0.1:3020/health
docker compose --env-file homelab.env logs --tail 100 game
```

The health check allows two minutes for world construction. A healthy game can report `feedback.database=false`:
that means the optional database is absent, not that multiplayer is broken.
