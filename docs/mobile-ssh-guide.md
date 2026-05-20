# Mobile SSH Access — Codens VPS

This is a supplement to your original welcome kit. It enables SSH from a
phone or tablet using a native terminal app (Termius / Blink / JuiceSSH).

## Your VPS

| Field | Value |
|-------|-------|
| Slug | `{{SLUG}}` |
| WARP address (for mobile SSH) | `{{WARP_IP}}` |
| SSH username | `{{SLUG}}` |
| SSH key | `codens-vps-{{SLUG}}` (from your welcome kit) |
| Browser VS Code | `https://vps-{{SLUG}}.vps.example.com` |
| Browser SSH (fallback) | `ssh-{{SLUG}}.vps.example.com` (via cloudflared on PC) |

*Ask ops for your specific WARP address if you don't know it. A
per-member supplement with your values pre-filled will be distributed
separately.*

## 1. Install Cloudflare WARP (once)

- iOS: **Cloudflare One Agent** (App Store)
- Android: **Cloudflare One Agent** (Play Store) — link: https://play.google.com/store/apps/details?id=com.cloudflare.cloudflareoneagent

> ⚠️ Do **NOT** use the regular **`1.1.1.1` / WARP** app. Some Android devices
> get a "sign-in error" when trying to enroll in Zero Trust through the 1.1.1.1
> app. The dedicated **Cloudflare One Agent** is the team-grade app and works
> reliably for our setup.

## 2. Enroll in the team (once)

1. Open **Cloudflare One Agent**
2. When asked for the **Team name**, enter: **`corevice`**
3. A browser opens → enter your `@example.com` email →
   choose **One-time PIN** → check your email for the 6-digit PIN → enter it
4. Back in the app, tap **Accept** on the privacy notice
5. The app should now show your `corevice` team label and connected state

### Notes about the app's status

You may notice **`WARP` and `Gateway` status are OFF** even after successful
enrollment. **This is normal for our setup.** Zero Trust private network access
(reaching `10.200.0.X`) works independently of those toggles, as long as you
are enrolled in the `corevice` team.

If the app says you are signed in to `corevice`, you are good to go.

## 3. Import your SSH key into the terminal app

**Termius (iOS/Android):**
1. Keychain → **Import** → paste or open your private key file
   (`codens-vps-{{SLUG}}` from the welcome kit)
2. If you received the key over 1Password, open 1Password → copy the key
   → paste into Termius Keychain

**Blink Shell (iOS):**
1. Config → Keys → **+** → paste the private key content

## 4. Add the host and connect

**Termius:**
1. Hosts → **+** (New Host)
2. Label: `codens-vps`
3. Address: **`{{WARP_IP}}`**
4. Port: `22`
5. Username: **`{{SLUG}}`**
6. Key: select the key imported in step 3
7. Save → tap to connect

If WARP is On, you're in.

## 5. Keep your session alive (strongly recommended)

Mobile networks drop. Use `tmux` to keep your work running:

```bash
# First login
tmux new -s main

# Later (after disconnect, or from a different device)
tmux attach -t main
```

For even smoother reconnection, use **mosh** (pre-installed):
- Termius / Blink both support "Mosh" connection type
- Same host, port, key — just switch the protocol

## Connecting to a VPS-side service from your laptop

Your VPS does **not** accept direct connections from the public internet —
both the Contabo Cloud Firewall and the Docker daemon (which now binds
container ports to `127.0.0.1` by default) prevent that. To reach a service
running inside your VPS (a dev server, a Docker container, etc.) from your
laptop, use one of these patterns:

### 1. SSH local port forward (terminal)

In one terminal, start your service on the VPS:

```bash
ssh codens-vps
docker run -p 3000:3000 my-app    # binds to 127.0.0.1:3000 on the VPS
```

In another terminal on your laptop, open a tunnel:

```bash
ssh -L 3000:localhost:3000 codens-vps
```

Then open `http://localhost:3000` in your laptop's browser. The tunnel stays
up as long as the second SSH session is open.

You can also one-shot it: `ssh -L 3000:localhost:3000 codens-vps 'docker run -p 3000:3000 my-app'`

### 2. VS Code Remote-SSH — auto port forward

If you SSH into the VPS via the VS Code Remote-SSH extension, VS Code detects
listening ports automatically and offers a 1-click forward in the
**Forwarded Ports** panel. Works for Docker containers, native dev servers,
anything that listens.

### 3. code-server (browser VS Code) — no tunnel needed

When you open `https://vps-<slug>.vps.example.com`, the browser-side VS Code
runs on the VPS itself, so any service on `localhost:3000` is reachable from
the integrated terminal directly. To open the page in your laptop's browser
(rather than inside the integrated terminal), code-server's **Forward a Port**
feature spins up a proxied URL with Cloudflare Access auth.

### 4. Termius / Blink (mobile) — GUI port forward

Termius: **Settings → Port Forwarding** → add `Local 3000 → Remote localhost:3000`,
then connect. Same idea as `ssh -L`, just with a UI.

### 5. Long-lived public URL (e.g. webhook receiver)

If you need an internet-reachable URL (a Slack webhook, GitHub webhook, etc.),
ask ops to add a Cloudflare Tunnel ingress entry. The URL will be
authenticated by Cloudflare Access (your email-only) so it's not truly public.

## Troubleshooting

| Symptom | What to do |
|---------|------------|
| `curl http://<vps-ip>:8080` from my laptop times out | Expected — public ingress is closed. Use SSH tunnel (§1) or VS Code (§2). |
| `No route to host` / timeout | Check WARP is **On** in the WARP app |
| Login prompts for password | Key wasn't selected / wrong key — check Termius key binding |
| `Permission denied (publickey)` | Username is wrong — must be your slug exactly |
| One Agent login loops / "sign-in error" | You're using the `1.1.1.1` app instead of `Cloudflare One Agent`. Switch apps. |
| Cannot find team name field | Make sure the team domain is `corevice` (not `corevice-codens`) |
| Can reach `vps-<slug>` in browser but not `{{WARP_IP}}` over SSH | One Agent is OFF, or you're still connected to a captive portal Wi-Fi |
| `Connection refused` immediately | One Agent is connected to a different team or signed out. Re-sign in to `corevice`. |
| WARP / Gateway status shown OFF in One Agent | **This is normal — connection still works.** As long as you're signed in to `corevice` team. |

## Security notes

- WARP authenticates by your email domain (`@example.com` / `@corevice.com`).
  Logging out of WARP disables mobile SSH.
- Losing your phone? Ask ops to revoke your WARP device enrollment
  (Cloudflare Zero Trust → Devices → Revoke).
- Your SSH key is still the final gate — only YOUR key can log in as YOU.

## Contact

- ops@example.com / Slack DM: ops
