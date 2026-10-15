<p align="center">
  <img src="https://capsule-render.vercel.app/api?type=slice&color=gradient&height=250&section=header&text=Windows%2011%20Ultimate%20RDP&fontSize=60&fontAlignY=40" />
</p>

<p align="center">
    <img src="https://img.shields.io/badge/Version-v7.4-blue?style=for-the-badge">
    <img src="https://img.shields.io/badge/Platform-Windows-0078D6?style=for-the-badge&logo=windows">
    <img src="https://img.shields.io/badge/License-MIT-green?style=for-the-badge">
</p>

A fully automated, customizable remote desktop session deployed from GitHub Actions and reachable only through your own private Tailscale network. Sessions are ephemeral: the machine exists for the lifetime of the workflow run and is destroyed afterwards.

---

## ⚠️ Read before running

- **This is not CI/CD.** Running an interactive desktop on GitHub-hosted runners falls outside GitHub's intended use for Actions ("any other activity unrelated to the production, testing, deployment, or publication of the software project associated with the repository"). GitHub actively monitors for this pattern and may suspend accounts that abuse Actions resources. Run sparingly, and understand that you accept this risk yourself.
- **Credentials are visible to repository readers.** The run Summary shows the session IP and passwords, and anyone who can view your repository's Actions can read them while the session is live. Use a **private fork** if you need privacy.
- **The environment is ephemeral.** Everything on the machine is destroyed when the session ends or the run is cancelled. Never store personal or sensitive data inside it.
- **No gaming.** The runner has no GPU, and running games or anti-cheat-protected software on it violates those products' terms on top of the risks above.

### What you actually get

| Property | Value |
|----------|-------|
| Operating system | Windows Server 2025 (GitHub's `windows-latest` image — despite the project name, it is not a Windows 11 desktop) |
| Hardware | 4 vCPUs, 16 GB RAM, ~14 GB free disk |
| Session lifetime | 1–6 hours, your choice (default 6) |
| Access | RDP over Tailscale only — no public IPs, no open ports |
| Accounts | `runneradmin` and `ditzz`, both with **randomly generated passwords per run** |

---

## 🚀 Quick Start

### 1. Fork this repository

Click **Fork**, then work from your fork — not from this upstream copy.

### 2. Create a Tailscale auth key

1. Open [Tailscale Admin Console > Settings > Keys](https://login.tailscale.com/admin/settings/keys).
2. Generate an auth key that is **Ephemeral** and **Reusable** (a pre-signed key also works if your tailnet uses Tailnet Lock).
3. Ephemeral nodes are removed from your tailnet automatically when the session ends.

### 3. Store the key as a GitHub secret

In your fork: **Settings > Secrets and variables > Actions > New repository secret**

- Name: `TAILSCALE_AUTH_KEY`
- Value: your Tailscale auth key

### 4. Run the workflow

Go to **Actions > Windows Ultimate RDP > Run workflow** and pick your options:

| Input | Choices | Meaning |
|-------|---------|---------|
| Theme | `dark` / `light` | Desktop color mode |
| Application bundle | `all` / `streaming` / `minimal` / `clean` | `all`: Chrome, Steam, OBS, Google Drive, Rainmeter + Mond · `streaming`: Chrome, OBS, Rainmeter + Mond · `minimal`: Chrome · `clean`: nothing |
| Wallpaper URL | any direct image URL | Optional; validated before setup starts, ignored if it is not a reachable image |
| Session hours | `1` – `6` | How long the session stays up (shuts down gracefully a few minutes before the platform cap) |

If a second run starts while a session is live, the new run replaces the old one (concurrency is enabled — the previous session is cancelled).

### 5. Connect

1. Wait for the run to finish the setup steps (a few minutes).
2. Open the **Summary** tab of the run — it shows the Tailscale IP, both accounts, the end time, and step-by-step connection instructions.
3. Install the Tailscale client on your device, sign in to the same tailnet, then connect with any RDP client to the `100.x.x.x` address.

---

## ✨ What the setup does

- **Pre-flight validation** — fails in seconds with a clear message if the Tailscale key is missing or the wallpaper URL is not an image, instead of wasting minutes of setup first.
- **Secure provisioning** — enables RDP with Network Level Authentication and creates two accounts whose passwords are cryptographically random per run and masked in logs.
- **Debloat and tuning** — removes consumer bloatware, disables telemetry services, activates the Ultimate Performance power plan, and disables mouse acceleration.
- **Personalization** — applies the chosen theme and a validated custom wallpaper.
- **Application bundles** — installs the selected packages in parallel via winget, with a sequential retry for anything that failed; a failed package never blocks the session.
- **Health-checked keep-alive** — every 5 minutes the session verifies that the Tailscale service and the RDP listener are alive (any deviation is reported), and the session ends gracefully at the requested time.
- **Quality gate** — pull requests are linted with actionlint (workflow files) and PSScriptAnalyzer (PowerShell scripts) so a broken change never reaches a run.

All provisioning logic lives in `scripts/*.ps1`; the workflow file is a thin orchestrator that passes user inputs through environment variables (never text interpolation), which closes the script-injection vector that earlier versions had.

---

## 🩺 Troubleshooting

| Symptom | Likely cause and fix |
|---------|----------------------|
| Run fails at pre-flight: `TAILSCALE_AUTH_KEY secret is not set` | Add the secret as described in step 3 |
| Run fails at the Tailscale step | The auth key expired, is single-use, or was already consumed — generate a new Ephemeral + Reusable key |
| Cannot connect from your device | Your device must be signed in to the **same tailnet**; check the Tailscale client status before blaming the session |
| Wrong credentials | Read them from the run's Summary tab of **that specific run** — passwords differ per run |
| An application failed to install | The session still comes up; check the install step log and `%TEMP%\winget-<appId>.log` details, then rerun |
| Session ended earlier than expected | The `session_hours` input elapsed; the Summary shows the planned end time |
| Job killed at exactly 6 hours | The platform cap — choose a lower `session_hours` value for graceful shutdown |

---

## 📜 Changelog

### v7.4
- **Security:** randomly generated per-run passwords (masked in logs) replace hardcoded credentials; user inputs are passed via environment variables, closing the template-injection vector in the wallpaper/theme inputs; `permissions: contents: read` limits the workflow token; the Tailscale connection moved to the official `tailscale/github-action` with a pinned SHA instead of an unpinned installer download; dead and untrustworthy third-party binaries (Steam Achievement Manager, system-info spoofing, Universal Watermark Disabler — its source URL no longer exists) were removed.
- **Reliability:** pre-flight validation, per-step timeouts, download retries, parallel winget installs with sequential fallback, explicit error handling in every script (`pwsh` + strict mode), fixed the brittle power-plan GUID parsing and the `GITHUB_ENV` UTF-16 encoding hazard.
- **UX:** fully English interface, application bundles instead of all-or-nothing installs, a `session_hours` input with graceful shutdown, a rewritten Summary page with connection steps and common issues, and concurrency protection against overlapping sessions.
- **Project:** provisioning logic extracted from the workflow into `scripts/`, a Quality Gate workflow added, and this README rewritten to describe the environment honestly.

### v7.3 and earlier
See the git history of the original project.

---

## ⚖️ Disclaimer

This project is for educational and experimental purposes. It is an **ephemeral environment** — the machine and all its data are permanently destroyed when the workflow is cancelled or completes. Do not store critical or sensitive data in a session, and use GitHub's resources responsibly and in accordance with their terms of service.

## 📄 License

[MIT](LICENSE)

Maintained by **[LazyByte0x](https://github.com/LazyByte0x)** — based on the original v7.3 project by **ditzz**.
