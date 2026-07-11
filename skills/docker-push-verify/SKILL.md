---
name: docker-push-verify
description: "After `docker buildx build --push`, always verify the image actually landed on the upstream registry. `buildx exit 0` does not prove the push succeeded — buildx can silently fail on the push step (network stall, expired auth, layer corruption) and still exit 0 without an actual upload. Without verification, a deploy is declared successful while downstream consumers keep pulling the old image."
---
# Docker Push Verify

> Origin: a production incident where `buildx --push` twice silent-failed without an actual upload. The build reported `exit 0` and `naming to ...:latest done`, but the registry still held the previous image. A downstream GPU inference service kept failing for an hour until `docker manifest inspect` revealed the truth.

`docker buildx build --push` has 4 finalization steps:
1. `exporting layers` — local manifest packing
2. `exporting manifest sha256:...` — local manifest hash
3. `naming to <registry>/<image>:<tag> done` — **local tag**, not a push
4. `pushing manifest` / `pushing layer` → upstream

Steps 1-3 can exit 0 WITHOUT step 4. Especially when:
- Network stall between the Docker VM and the upstream registry
- Auth token expired mid-push (no re-auth happens)
- buildx `tail -N` buffering hides live progress
- Build process killed before push completes (but buildx exits 0 after `naming`)

## When to Activate

MANDATORY after any:
- `docker buildx build --push`
- `docker push <image>`
- any rebuild script that uses `buildx --push` internally
- any CI/CD job that declares an image deployed

## 3-Step Verification Protocol

### Step 1: Inspect the manifest on upstream

```bash
docker manifest inspect <registry>/<org>/<image>:<tag> 2>&1 | head -5
```

**If `manifest unknown` or `not found`** — the push did NOT happen. Do not declare the deploy successful.

### Step 2: Compare timestamp with the build moment

```bash
# Example: GitHub Container Registry API
curl -s -u "$USER:$REGISTRY_TOKEN" \
  "https://api.github.com/users/$USER/packages/container/$IMAGE/versions?per_page=3" \
  | python3 -c "import sys,json; d=json.load(sys.stdin); [print(v['metadata']['container'].get('tags',[]), v['created_at'][:19]) for v in d[:3]]"
```

Check that **created_at** matches your build moment (not yesterday's). If the latest tag is stale — the push never landed.

### Step 3: Pull via an external pipe and grep for a fix marker

If there is a concrete fix in `src/` (e.g. a distinctive comment marker):

```bash
docker run --rm --platform linux/amd64 --entrypoint=/bin/sh \
  $IMAGE -c 'grep -nc "FIX-MARKER" /app/src/main.py'
```

If 0 — the fix is not in the image. Push didn't land, or a cache hit reused an old layer.

## What to Do on Detected Failure

1. **Do NOT declare the deploy complete** in your report.
2. Try `docker push $IMAGE` directly (shows progress by default) — without going through `buildx`, which buffers the upload.
3. If a direct push hangs 5+ min — kill it, try splitting the flow:
   - `docker buildx build --load --platform ... .` (build to local)
   - `docker push <registry>/...:tag` (push separately with live progress)
4. If pushing to an empty registry for the first time — check `docker login`.

## Incident Reconstruction

```bash
# What was done (WRONG):
bash scripts/rebuild.sh --tag <tag> 2>&1 | tail -60
# Monitor showed:
#   #19 naming to <registry>/<image>:latest done
#   #19 naming to <registry>/<image>:<tag> done
# Background task exit code 0
# Assumed: "image deployed"

# What should have been done AFTER:
docker manifest inspect <registry>/<image>:<tag>
# → manifest unknown ← push never landed!

curl -u "$USER:$REGISTRY_TOKEN" \
  "https://api.github.com/users/$USER/packages/container/<image>/versions" \
  | jq '.[0].created_at'
# → stale timestamp ← previous build, not today's

# Fix: direct push
docker push <registry>/<image>:latest
# → "1bfd9b3da406: Pushed" ← now it's real
```

## Anti-Patterns (don't)

- ❌ Rely on `exit code 0` from buildx as proof of push
- ❌ Rely on the `naming to ... done` event as proof of push
- ❌ `| tail -N` on buildx — the buffer blocks live progress, causing premature kills
- ❌ Assume a cache hit means the image is on upstream (cache lives in local Docker, not the registry)

## Quick-Reference One-Liner

After any `buildx --push`:

```bash
docker manifest inspect "$IMAGE" >/dev/null 2>&1 \
  && echo "✅ verified on upstream" \
  || echo "❌ push failed silently — direct docker push needed"
```
