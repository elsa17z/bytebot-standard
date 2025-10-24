# ByteBot 2-Layer Build Architecture

**Version:** 2.0
**Date:** October 25, 2025
**Status:** Production

---

## Executive Summary

**Problem:** Building ByteBot desktop agents takes 20 minutes per service on Railway. Railway cannot share build cache across services, so 10 services = 200 minutes (3+ hours).

**Solution:** Split into 2 Docker layers:
1. **Layer 1 (PUBLIC):** Desktop environment + standard bytebotd → Built once, reused forever
2. **Layer 2 (PRIVATE):** Computer-control module only → Built per service (2 min)

**Result:** 90% faster builds (2 min vs 20 min), fully automated, code stays private.

---

## The Problem in Detail

### Current Monolithic Build

**File:** `Dockerfile` (monolithic, 20 minutes)

```
FROM ubuntu:22.04
├─ Install desktop (XFCE, X11, VNC) ............ 5 min
├─ Install apps (Firefox, VSCode, 1Password) ... 8 min
├─ Install Node.js ............................. 1 min
├─ Build standard bytebotd (NestJS, MCP) ....... 3 min
├─ Build computer-control (proprietary) ........ 2 min
└─ Build custom libnut ......................... 2 min
TOTAL: 20 minutes
```

**Railway's Limitation:**
- Build cache is **per-service**, not shared across services
- Service A builds for 20 min, Service B builds for 20 min (no sharing)
- 10 services = 10 × 20 min = **200 minutes** (3+ hours)

**Why Railway can't share cache:**
- Architectural decision: Services are isolated
- Cache is scoped by service ID
- No "build once, deploy many" feature for Dockerfiles
- Documented in `/v2/docs/RAILWAY-BUILD-CACHING.md`

---

## The Solution: 2-Layer Architecture

### Layer 1: Public Standard Image

**Image:** `ghcr.io/elsa17z/bytebot-standard:latest`
**Visibility:** PUBLIC
**Content:** Desktop environment + standard bytebotd (NO computer-control)
**Build time:** 18 minutes
**Build frequency:** Weekly (automated via GitHub Actions)
**Size:** ~2 GB

**What's inside:**
```
Ubuntu 22.04 base
├─ Desktop: XFCE4, X11, VNC, noVNC
├─ Apps: Firefox ESR, Thunderbird, 1Password, VSCode
├─ Runtime: Node.js 20, Python 3, supervisord
├─ Standard bytebotd:
│  ├─ NestJS framework
│  ├─ Anthropic MCP tools
│  ├─ Computer-use tools
│  ├─ Input tracking
│  ├─ uiohook, custom libnut
│  └─ ALL dependencies installed and compiled
└─ NO computer-control module (excluded)
```

**Why public?**
- Contains ZERO proprietary code
- All open-source components (Ubuntu, Firefox, NestJS, Anthropic MCP)
- Equivalent to distributing a Linux distro with apps pre-installed
- Anyone can inspect: `docker pull ghcr.io/elsa17z/bytebot-standard:latest`

---

### Layer 2: Private Computer-Control Extension

**Source:** Private GitHub repo `elsa17z/bytebot-agent-desktop`
**Build:** Railway (per service, from private repo)
**Content:** ONLY computer-control module (~450 lines of proprietary code)
**Build time:** 2 minutes
**Privacy:** PRIVATE (built on Railway, never pushed to any registry)

**What's inside:**
```
FROM ghcr.io/elsa17z/bytebot-standard:latest (public base)

ADD computer-control module (proprietary):
├─ computer-control.controller.ts
├─ computer-control.service.ts
├─ computer-control.module.ts
├─ keyboard-control.service.ts
├─ mouse-control.service.ts
├─ window-detection.service.ts
├─ human-typing.ts
└─ app.module.ts (imports computer-control)

BUILD: npm run build (2 minutes - only TypeScript compilation)
```

**Why private?**
- Contains orchestrator integration protocol
- Custom action handling logic
- Human behavior simulation algorithms
- Proprietary X11 window management

**Where it stays:**
- Built on Railway's servers from private repo
- Stored in Railway's internal container registry
- **NEVER** pushed to GitHub Container Registry (public or private)
- Only accessible within your Railway project

---

## Design Choices & Reasoning

### Choice 1: Why 2 Layers Instead of 3?

**Considered:** Desktop (Layer 1) → Standard ByteBot (Layer 2) → Computer-Control (Layer 3)

**Rejected because:**
- Desktop (15 min) + Standard ByteBot (3 min) updated at similar frequencies
- Splitting them adds complexity (2 repos, 2 workflows) for zero benefit
- Pulling 1 large image (15 sec) ≈ Pulling 2 smaller images (10 sec + 10 sec)

**Chosen:** Desktop + Standard ByteBot combined (Layer 1, 18 min)

**Rationale:**
- Simpler: One public repo instead of two
- Same build time per service (2 min)
- Easier maintenance: Desktop and ByteBot updated together
- Less complexity: One GitHub Actions workflow

---

### Choice 2: Why Make Layer 1 Public?

**Considered:** Keep Layer 1 private, use Railway service pool with credentials

**Rejected because:**
- Service pool doesn't scale (max 10-20 services, manual credential setup)
- Requires Pro plan ($20/month vs $5/month Hobby)
- Manual credential rotation every 90 days (25 min × 4 = 100 min/year)
- PAT management overhead

**Chosen:** Make Layer 1 public

**Rationale:**
- Layer 1 contains ZERO proprietary code (inspected every file)
- 99% of build time is open-source (Ubuntu, Firefox, NestJS, Anthropic MCP)
- Only 1% is proprietary (computer-control), which stays private
- Enables fully automated deployments (no manual credential setup)
- No Pro plan required (saves $15/month)
- Scales infinitely (no service pool limit)

**Security analysis:**
- Public image = anyone can download and inspect
- Risk: ZERO (all open-source components, inspectable)
- Benefit: Fast deploys, zero auth complexity, infinite scale

---

### Choice 3: Why Build Layer 2 Per Service (Not Pre-Build)?

**Considered:** Pre-build Layer 2, push to private GHCR, deploy pre-built image

**Rejected because:**
- Requires manual credential setup per service (same as service pool problem)
- Railway GraphQL API cannot set registry credentials programmatically
- Back to manual UI steps: Service → Settings → Registry Credentials (2-3 min each)
- Documented limitation in `/v2/docs/RAILWAY-PRIVATE-DOCKER-AUTH.md`

**Chosen:** Build Layer 2 per service from private repo

**Rationale:**
- Railway OAuth handles authentication automatically (zero setup)
- Computer-control is small (~450 lines) → only 2 min to compile
- Fully automated (no manual steps)
- Code stays private (built on Railway, never pushed)
- Scales infinitely

**Trade-off:**
- 2 min build per service (vs 6 sec if pre-built)
- Acceptable: 2 min << 20 min, still 90% faster
- Benefit: Zero manual work, infinite scale

---

### Choice 4: Why GitHub Actions for Layer 1 (Not Railway)?

**Considered:** Build Layer 1 on Railway, push to GHCR

**Rejected because:**
- Railway would need to access private repo for source files
- Then push to public GHCR (mixing private repo access with public output)
- Conceptual confusion: Railway is for private builds, GitHub Actions for public

**Chosen:** Build on GitHub Actions, push to public GHCR

**Rationale:**
- Clear separation: GitHub Actions = public builds, Railway = private builds
- GitHub Actions has access to private repo (native integration)
- Free tier: 2,000 min/month (18 min/week = 72 min/month, well within limit)
- Automated: Weekly rebuild via cron schedule
- Transparent: Anyone can see what's in the public image (workflow visible)

---

## Security & Privacy Analysis

### What's Public? (Layer 1)

**Components:**
- Ubuntu 22.04 (open-source OS)
- XFCE4 desktop (open-source desktop environment)
- Firefox ESR (open-source browser)
- Thunderbird (open-source email)
- 1Password (proprietary app, but publicly available)
- VSCode (open-source editor)
- Node.js (open-source runtime)
- NestJS (open-source framework)
- Anthropic MCP tools (open-source, Apache 2.0 license)
- uiohook, libnut (open-source libraries)

**Inspection:**
```bash
# Anyone can pull and inspect:
docker pull ghcr.io/elsa17z/bytebot-standard:latest
docker run -it ghcr.io/elsa17z/bytebot-standard:latest /bin/bash

# Can inspect all files:
ls -la /bytebot/bytebotd/src/
# Will NOT see computer-control directory
```

**Risk assessment:** ZERO proprietary code exposure

---

### What's Private? (Layer 2)

**Components:**
- `computer-control.controller.ts` - Orchestrator API endpoint
- `computer-control.service.ts` - Action execution logic
- `keyboard-control.service.ts` - Keyboard automation
- `mouse-control.service.ts` - Mouse automation
- `window-detection.service.ts` - X11 focus management
- `human-typing.ts` - Behavior simulation algorithms
- `app.module.ts` - NestJS module imports

**Total:** ~450 lines of proprietary code (1% of codebase)

**Where it lives:**
1. Source: Private GitHub repo `elsa17z/bytebot-agent-desktop`
2. Build: Railway's build servers (ephemeral, deleted after build)
3. Storage: Railway's internal container registry (project-scoped)
4. Runtime: Railway service containers (project-scoped)

**Where it NEVER goes:**
- ❌ GitHub Container Registry (public or private)
- ❌ Docker Hub
- ❌ Any public registry
- ❌ Layer 1 public image

**Access control:**
- Source repo: Private (only you have access)
- Railway OAuth: Authenticated (Railway has read-only access)
- Built image: Railway project-scoped (only your services)

**Risk assessment:** Same privacy as current "build from repo" approach

---

### Attack Surface Analysis

**Threat model:**

1. **Attacker pulls public Layer 1 image**
   - Can inspect: Desktop, standard bytebotd, dependencies
   - Cannot see: Computer-control logic, orchestrator protocol
   - Impact: ZERO (all inspectable code is open-source)

2. **Attacker gains access to Railway project**
   - Can see: Built Layer 2 image (but it's compiled JavaScript)
   - Cannot see: TypeScript source code (not in image)
   - Impact: LOW (reverse-engineering compiled JS is possible but difficult)
   - Mitigation: Railway project access is protected by Railway auth

3. **Attacker gains access to GitHub private repo**
   - Can see: Full source code including computer-control
   - Impact: HIGH (full source code exposure)
   - Mitigation: GitHub auth, 2FA, PAT with minimal scope

**Comparison to current approach:**

| Aspect | Current (Monolithic) | 2-Layer |
|--------|---------------------|---------|
| **Source code privacy** | ✅ Private repo | ✅ Private repo |
| **Built image privacy** | ✅ Railway internal | ✅ Railway internal (Layer 2) |
| **Desktop environment** | ⚠️ Built privately (unnecessary) | ✅ Public (appropriate) |
| **Attack surface** | Same | Same |

**Conclusion:** 2-layer approach has **identical security** to monolithic, with better separation of concerns.

---

## Build Time Analysis

### Monolithic Build Breakdown

```
Layer 1: Ubuntu base ........................... 30 sec
Layer 2: Desktop (XFCE, X11, VNC) .............. 4 min
Layer 3: Apps (Firefox, VSCode, 1Password) ..... 8 min
Layer 4: Node.js ............................... 1 min
Layer 5: noVNC ................................. 1 min
Layer 6: User setup ............................ 30 sec
Layer 7: bytebotd dependencies ................. 3 min
Layer 8: Custom libnut ......................... 2 min
Layer 9: TypeScript compilation ................ 1 min
Layer 10: System configs ....................... 30 sec
─────────────────────────────────────────────────────
TOTAL: 20 minutes
```

**Per service:** 20 min
**10 services:** 200 min (no cache sharing)

---

### 2-Layer Build Breakdown

**Layer 1 (Built once, weekly):**
```
Layers 1-8 (same as above) ..................... 18 min
(Excluding Layer 9: computer-control compilation)
─────────────────────────────────────────────────────
BUILD ONCE: 18 minutes
PULL FROM GHCR: 15 seconds
```

**Layer 2 (Built per service):**
```
Pull Layer 1 from GHCR ......................... 15 sec
Copy computer-control files .................... 1 sec
TypeScript compilation (changed files only) .... 2 min
─────────────────────────────────────────────────────
TOTAL PER SERVICE: 2.25 minutes
```

**Per service:** 2.25 min (89% faster ✅)
**10 services:** 22.5 min (89% faster ✅)

---

## Cost Analysis

### Build Costs

**Monolithic approach:**
- Railway build time: 20 min/service × $0.01/min = $0.20/service
- 100 services: $20 in Railway build costs

**2-Layer approach:**
- Layer 1 build: 18 min in GitHub Actions (FREE, within 2,000 min/month tier)
- Layer 2 build: 2 min/service × $0.01/min = $0.02/service
- 100 services: $2 in Railway build costs

**Savings:** $18 per 100 services (90% cheaper)

---

### Railway Plan Requirements

**Monolithic:** Hobby plan ($5/month) sufficient

**2-Layer:**
- Layer 1 is public: No private registry auth needed
- Layer 2 built from repo: Railway OAuth (no extra cost)
- **Result:** Hobby plan ($5/month) sufficient ✅

**Alternative (Service pool with private GHCR):**
- Requires Pro plan ($20/month) for private registry support
- **Avoided:** $15/month savings

---

### Human Time Costs

**Setup time:**
- Monolithic: 0 min (already working)
- 2-Layer: 60 min one-time (repo creation, testing)

**Ongoing maintenance:**
- Monolithic: 0 min (no maintenance)
- 2-Layer: 0 min (automated weekly rebuilds)

**Per-service deployment:**
- Monolithic: 0 min manual (fully automated, but 20 min build)
- 2-Layer: 0 min manual (fully automated, 2 min build)

**Credential rotation:**
- Monolithic: N/A
- 2-Layer: 0 min (Layer 1 is public, Layer 2 uses OAuth)

---

## Scaling Analysis

### Service Pool Approach (Rejected Alternative)

**Concept:** Pre-create 10-20 services with credentials, reuse by updating env vars

**Pros:**
- 6-second "deployments" (fastest possible)
- Private image

**Cons:**
- Limited scale: 10-20 services max (pool size)
- Manual setup: 2.5 min × 10 services = 25 min one-time
- PAT rotation: Every 90 days, 25 min manual work
- Doesn't scale beyond pool size

**When pool exhausts:** Must create more services (back to manual credential setup)

---

### 2-Layer Approach (Chosen)

**Concept:** Build Layer 2 per service from private repo

**Pros:**
- Infinite scale (no service pool limit)
- Fully automated (zero manual steps)
- No credential management
- No Pro plan required

**Cons:**
- 2 min build per service (vs 6 sec for pool)

**Scaling math:**
- 10 services: 20 min (vs 60 sec for pool, but pool has 25 min setup)
- 50 services: 100 min (pool cannot handle, would need 5× pool size)
- 100 services: 200 min (pool cannot handle)

**Break-even:** After 10 services, 2-layer is faster than service pool (no setup overhead)

---

## Operational Procedures

### Weekly Layer 1 Rebuild (Automated)

**Trigger:** GitHub Actions cron (Sunday midnight)

**Process:**
1. GitHub Actions checks out bytebot-standard repo
2. Checks out bytebot-agent-desktop repo (using GH_PAT secret)
3. Copies files excluding computer-control
4. Builds Docker image (~18 min)
5. Pushes to ghcr.io/elsa17z/bytebot-standard:latest
6. Done (no manual steps)

**Why weekly?**
- Desktop apps: Security updates (Firefox, VSCode)
- Node.js: Minor version updates
- ByteBot dependencies: Regular updates

**Impact on existing services:** NONE (services use already-built image)

**Impact on new services:** Automatically use latest Layer 1

---

### Per-Service Deployment (Automated)

**Trigger:** Orchestrator creates new service via Railway API

**Process:**
1. Railway receives service creation request
2. Clones elsa17z/bytebot-agent-desktop (Railway OAuth)
3. Reads Dockerfile
4. Pulls ghcr.io/elsa17z/bytebot-standard:latest (public, no auth)
5. Copies computer-control from private repo
6. Builds Layer 2 (~2 min)
7. Deploys service
8. Done (no manual steps)

**Authentication:** Railway OAuth (already configured, zero setup)

---

### Manual Layer 1 Rebuild (When Needed)

**When:** Urgent security patch or major desktop app update

**Process:**
```bash
# 1. Go to GitHub Actions
https://github.com/elsa17z/bytebot-standard/actions

# 2. Click "Build ByteBot Standard Image"

# 3. Click "Run workflow" > "Run workflow"

# 4. Wait ~18 minutes

# 5. New services automatically use latest image
```

**Impact:** Existing services continue using old Layer 1 (until redeployed)

---

## Failure Modes & Recovery

### Failure 1: Layer 1 Build Fails

**Symptoms:** GitHub Actions workflow fails

**Causes:**
- GitHub Actions timeout (>40 min)
- Network issues downloading packages
- Broken package dependency

**Impact:**
- New services cannot deploy (old Layer 1 still works)
- Existing services unaffected

**Recovery:**
1. Check GitHub Actions logs
2. Fix Dockerfile error
3. Re-run workflow
4. Total downtime: 0 (old Layer 1 still available)

---

### Failure 2: Layer 2 Build Fails

**Symptoms:** Railway deployment fails, logs show build error

**Causes:**
- TypeScript compilation error in computer-control
- Missing dependency
- Dockerfile.2layer error

**Impact:**
- Specific service deployment fails
- Other services unaffected

**Recovery:**
1. Check Railway deployment logs
2. Fix error in private repo
3. Push fix
4. Railway auto-rebuilds
5. Total downtime: 0 (service never deployed)

---

### Failure 3: Layer 1 Image Unavailable

**Symptoms:** Railway logs show "Failed to pull ghcr.io/elsa17z/bytebot-standard:latest"

**Causes:**
- GHCR outage (rare)
- Image accidentally deleted
- Network issues

**Impact:**
- New services cannot deploy
- Existing services unaffected (already have image)

**Recovery:**
1. If GHCR outage: Wait for GHCR to recover
2. If image deleted: Re-run GitHub Actions workflow (~18 min)
3. If network issue: Retry deployment

**Fallback:** Use Dockerfile.monolithic.backup temporarily

---

### Failure 4: GitHub PAT Expires

**Symptoms:** GitHub Actions workflow fails with "Permission denied"

**Causes:**
- GH_PAT secret expired (90 days)

**Impact:**
- Weekly automated rebuilds stop
- Existing Layer 1 still works
- New services use old Layer 1 (not ideal but functional)

**Recovery:**
1. Create new PAT: https://github.com/settings/tokens/new
2. Update secret: bytebot-standard repo → Settings → Secrets → GH_PAT
3. Re-run workflow
4. Total downtime: 0 (old Layer 1 still usable)

---

## Testing Strategy

### Phase 1: Layer 1 Build Test

**Objective:** Verify Layer 1 builds successfully without computer-control

**Steps:**
1. Push to bytebot-standard repo
2. GitHub Actions builds image
3. Verify workflow succeeds (~18 min)
4. Pull image: `docker pull ghcr.io/elsa17z/bytebot-standard:latest`
5. Inspect: Verify computer-control directory absent

**Success criteria:**
- ✅ Build completes in 15-20 minutes
- ✅ Image is ~2 GB
- ✅ No computer-control directory in /bytebot/bytebotd/src/

---

### Phase 2: Layer 2 Build Test

**Objective:** Verify Layer 2 builds on Railway in ~2 minutes

**Steps:**
1. Update private repo Dockerfile
2. Create test service via orchestrator
3. Monitor Railway build logs
4. Verify build completes in ~2 minutes
5. Test computer-control endpoint

**Success criteria:**
- ✅ Railway pulls Layer 1 (15 sec)
- ✅ Build completes in 2-3 minutes total
- ✅ Logs show "Pulling ghcr.io/elsa17z/bytebot-standard:latest"
- ✅ Computer-control endpoint responds

---

### Phase 3: End-to-End Test

**Objective:** Verify full deployment workflow

**Steps:**
1. Create 3 test services in parallel
2. Measure total time
3. Verify all services healthy
4. Test computer-control on all services
5. Delete test services

**Success criteria:**
- ✅ 3 services deploy in 6-8 minutes total (parallel)
- ✅ All services pass health check
- ✅ Computer-control works on all services

---

## Rollback Plan

### If 2-Layer Build Fails

**Step 1:** Restore monolithic Dockerfile

```bash
cd /tmp/bytebot-agent-desktop-setup
cp Dockerfile.monolithic.backup Dockerfile
git add Dockerfile
git commit -m "Rollback: restore monolithic build"
git push origin main
```

**Step 2:** Delete test services

```bash
# Via Railway dashboard or API
```

**Step 3:** Verify monolithic build works

```bash
# Create new service, should build in 20 min (old behavior)
```

**Total rollback time:** 5 minutes (code rollback) + 20 minutes (monolithic build test)

---

## Maintenance Schedule

### Weekly (Automated)

- ✅ Layer 1 rebuild (GitHub Actions, Sunday midnight)
- ✅ No manual work required

### Monthly (Manual, 5 min)

- Review GitHub Actions logs (verify builds succeed)
- Review Railway deployment logs (verify Layer 2 builds succeed)
- Check Layer 1 image size (should stay ~2 GB)

### Quarterly (Manual, 10 min)

- Review GH_PAT expiration (create new if <30 days remaining)
- Review desktop app versions (Firefox, VSCode)
- Consider manual Layer 1 rebuild if major updates

### Annually (Manual, 30 min)

- Review entire architecture (any improvements?)
- Update documentation
- Celebrate time savings! 🎉

---

## Success Metrics

### Target Metrics

- ✅ Build time: < 3 minutes per service (vs 20 min before)
- ✅ 10 services deploy: < 30 minutes (vs 200 min before)
- ✅ Automation: 100% (zero manual steps)
- ✅ Code privacy: Maintained (computer-control stays private)
- ✅ Cost: < $3 per 100 services (vs $20 before)

### Tracking

**Monitor via Railway logs:**
```bash
# Track build times
grep "Build complete" railway.log | awk '{print $4}'

# Expected output: "2m 18s", "2m 12s", "2m 25s"
```

**Alert if:**
- Build time > 5 minutes (investigate Layer 1 pull issue)
- Build failure rate > 5% (investigate Dockerfile or dependency issue)

---

## Conclusion

The 2-layer build architecture achieves:

✅ **90% faster builds** (2 min vs 20 min)
✅ **Infinite scalability** (no service pool limit)
✅ **Zero manual steps** (fully automated)
✅ **Code stays private** (computer-control built on Railway)
✅ **90% cost savings** ($2 vs $20 per 100 services)
✅ **Same security** (identical to current approach)

By separating generic open-source components (Layer 1) from proprietary code (Layer 2), we achieve maximum caching while maintaining privacy.

**Key insight:** 99% of build time is open-source components that don't need to be private. Only 1% (computer-control) is proprietary. Separating them unlocks massive performance gains.

---

**Document maintained by:** Development team
**Last updated:** October 25, 2025
**Next review:** November 25, 2025
**Related docs:**
- `/v2/docs/RAILWAY-BUILD-CACHING.md` - Why Railway can't share cache
- `/v2/docs/RAILWAY-PRIVATE-DOCKER-AUTH.md` - Why private images require manual setup
- `/tmp/bytebot-standard/IMPLEMENTATION-STEPS.md` - Step-by-step implementation guide
