# Enable Agent 365 for this Template

This guide walks you through enabling **Microsoft Agent 365** for the agent in
this template so it can be provisioned, published, and deployed to your tenant
using the **Agent 365 CLI** (`a365`).

You have two options:

- **[Option 1 — AI-guided setup](#option-1--ai-guided-setup-recommended)**: Hand the work off to an AI coding agent (GitHub Copilot, Claude, etc.) that follows the official Microsoft setup prompt end-to-end.
- **[Option 2 — Manual setup](#option-2--manual-setup-step-by-step)**: Run every command yourself, step by step.

Both options follow the same source of truth:
[https://aka.ms/agent365enable](https://aka.ms/agent365enable).

---

## Before you start — what you need

Regardless of which option you choose, make sure you have:

- An **Entra ID (Azure AD) tenant** where you have at least the **Agent ID Developer** role (Application Administrator or Global Admin needed for some consent steps).
- A tenant where the well-known **"Agent 365 CLI"** Entra app has been registered and admin-consented (the CLI looks it up by display name; ask your tenant admin if it's missing).
- Membership in the [Frontier preview program](https://adoption.microsoft.com/copilot/frontier-program/) (required to create agent instances in Teams while Agent 365 is in preview).
- This template cloned locally and the Python virtual environment configured per the main [README.md](../README.md#python-environment-configuration).

---

## Option 1 — AI-guided setup (recommended)

Microsoft publishes an official prompt designed to be executed by an AI coding
agent that has shell access. The prompt asks you a few questions, then runs the
CLI commands and validates each step for you.

### Steps

1. **Open this workspace** in VS Code (or any IDE that hosts a tool-using AI agent — e.g. GitHub Copilot Chat in Agent Mode, Claude Code, Cursor).
2. **Make sure the AI agent can:**
   - Run shell commands in your terminal.
   - Read files in this repo.
   - Fetch web pages.
3. **Send the agent this prompt:**

   > Please follow the official Microsoft Agent 365 setup instructions at
   > <https://aka.ms/agent365enable> to enable Agent 365 for this project.
   > Use this repository as the project directory. Ask me the path-determination
   > questions first, then execute every step end-to-end.

4. **Answer the three path-determination questions** the agent will ask:
   - **Is your agent already available in Teams or Copilot?** (Yes / No)
   - **How will your agent authenticate to downstream APIs?** (OBO / S2S / Both)
   - **Which Agent 365 capabilities do you want to enable?** (Register / Observability / AI Teammate)
5. **Complete any interactive sign-in prompts** when they appear:
   - `az login --allow-no-subscriptions` (Azure CLI sign-in).
   - A Windows Account Manager (WAM) dialog or browser sign-in for the CLI's first Microsoft Graph token.
6. **Review the dry-run output** the agent shows you before it applies changes, and reply `yes` to proceed.
7. **Follow the post-deploy instructions** the agent surfaces (Teams Developer Portal configuration and agent instance creation — these are browser actions only you can do).

That's it — the agent installs the CLI, validates prerequisites, runs
`a365 setup all`, then `a365 publish` and `a365 deploy` (for the AI Teammate
path), and reports the Setup Summary back to you.

---

## Option 2 — Manual setup (step by step)

If you'd rather drive every step yourself, run the commands below in order.
This mirrors the official prompt but condenses it for a human operator.

### Step 1 — Install the Agent 365 CLI

The CLI is a .NET global tool. It ships as a `net8.0` tool, so **the .NET 8
runtime must be installed** even if you already have a newer SDK
(`dotnet --list-sdks` showing only `10.x` isn't enough — `dotnet --list-runtimes`
must include `Microsoft.NETCore.App 8.0.x`). Without it, `dotnet tool install`
fails with the misleading error
`Settings file 'DotnetToolSettings.xml' was not found in the package`.

1. **Check what you already have:**

   ```bash
   dotnet --list-runtimes
   ```

   - If you see `Microsoft.NETCore.App 8.0.x` in the output, **skip to step 2**.
   - If `dotnet` itself isn't found, or only `10.x` runtimes are listed,
     install .NET 8 below.

2. **Install .NET 8** (runtime is sufficient; the SDK works too if you prefer):

   **Windows / macOS** — installer: <https://dotnet.microsoft.com/download/dotnet/8.0>
   (pick *Runtime* for the smaller download or *SDK* if you'll do other .NET work).

   **Linux / WSL** — use the official install script (no `sudo`, no apt
   conflicts):

   ```bash
   curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh
   chmod +x /tmp/dotnet-install.sh

   # Runtime only (smallest, what the CLI actually needs):
   /tmp/dotnet-install.sh --channel 8.0 --runtime dotnet --install-dir "$HOME/.dotnet"
   # — or — full SDK (also covers building .NET projects):
   # /tmp/dotnet-install.sh --channel 8.0 --install-dir "$HOME/.dotnet"

   # Persist for future shells
   cat >> ~/.bashrc <<'EOF'

   # .NET + global tools
   export DOTNET_ROOT="$HOME/.dotnet"
   export PATH="$DOTNET_ROOT:$DOTNET_ROOT/tools:$PATH"
   EOF
   source ~/.bashrc
   ```

   Verify:

   ```bash
   dotnet --list-runtimes   # should include Microsoft.NETCore.App 8.0.x
   ```

   > **Ubuntu 24.04+ apt note**: Microsoft's `dotnet-*` packages on
   > `packages.microsoft.com` conflict with Ubuntu's own `dotnet-host-*`
   > package over `/usr/bin/dnx`. If you must use apt, append
   > `-o Dpkg::Options::="--force-overwrite"` to the install command.
   > The `dotnet-install.sh` route above avoids the conflict entirely.

3. **Install (or update) the Agent 365 CLI**:

   ```bash
   # First time
   dotnet tool install --global Microsoft.Agents.A365.DevTools.Cli --prerelease

   # Or, if already installed
   dotnet tool update --global Microsoft.Agents.A365.DevTools.Cli --prerelease
   ```

3. **Verify it's on your PATH:**

   ```bash
   a365 -h
   a365 --version
   ```

   If `a365` is not found, ensure your tools directory is on `PATH`:
   `~/.dotnet/tools` (Linux/macOS) or `%USERPROFILE%\.dotnet\tools` (Windows).

### Step 2 — Validate prerequisites

#### 2a. Azure CLI sign-in (critical)

```bash
az --version           # Install from https://learn.microsoft.com/cli/azure/install-azure-cli if missing
az login --allow-no-subscriptions # Select the subscription terencelim-3 (69ecbfc6-bfbb-4fa4-9933-a5ec21627a3f)
az account show --query "{user:user.name, tenantId:tenantId}" -o json
```

`az account show` **must** return a valid account before you run any `a365`
command. Otherwise the CLI will trigger an interactive auth prompt that may
block in headless environments.

> Use `az login --allow-no-subscriptions` even if you do have a subscription —
> the standard flow does not require one.

#### 2b. Roles check

Two different role systems apply — don't confuse them:

| Role system | Examples | Where to manage |
|---|---|---|
| **Entra ID (directory) roles** | *Agent ID Developer*, *Application Administrator*, *Global Administrator* | Entra admin center → **Roles & admins** |
| **Azure RBAC roles** | *Contributor*, *Owner*, *Reader* | Azure portal → the subscription → **Access control (IAM)** |

Confirm your account has at least:

- **Agent ID Developer** *(Entra)* — required for all paths.
- **Contributor** *(Azure RBAC, on the target subscription)* — required additionally for the **AI Teammate** path. Assign it in the Azure portal: **Subscriptions → \<your sub\> → Access control (IAM) → Add role assignment → Contributor**.
- **Agent ID Administrator / Application Administrator / Global Administrator** *(Entra)* — required to grant S2S admin consent (the CLI prints a PowerShell fallback script if you don't have one of these).

Quick CLI check for your Azure RBAC role on the subscription:

```bash
az role assignment list \
  --assignee "$(az account show --query user.name -o tsv)" \
  --subscription <your-subscription-id> \
  --include-inherited \
  -o table
```

#### 2c. Register the "Agent 365 CLI" Entra app and M365 Tools (one-time, per tenant)

The CLI auto-resolves a tenant Entra app by the **exact display name**
`Agent 365 CLI`. You do **not** need to provide a client ID, but the app must
exist with the right permissions and admin consent before any `a365` command
will run. If you see:

```text
App "Agent 365 CLI" was not found in tenant <tenant-id>.
```

an Application Administrator or Global Administrator must register it. There
is **no official script** that does this end-to-end — pick one of the two
options below.

##### Option A — Manual registration in the Entra portal

1. Open [entra.microsoft.com](https://entra.microsoft.com) as an Application Administrator or Global Administrator, switched to your target tenant.
2. **Identity → Applications → App registrations → + New registration**.
   - **Name**: `Agent 365 CLI` (exact — the CLI matches on display name).
   - **Supported account types**: *Accounts in this organizational directory only (Single tenant)*.
   - **Redirect URI**: platform **Public client/native (mobile & desktop)** → `http://localhost`.
   - Click **Register**.
3. **Authentication** blade: set **Allow public client flows** = **Yes**, then **Save**.
4. **API permissions → + Add a permission → Microsoft Graph → Delegated permissions** — add at minimum:
   - `User.Read`
   - `Application.ReadWrite.All`
   - `AppRoleAssignment.ReadWrite.All`
   - `Directory.ReadWrite.All`
   - `DelegatedPermissionGrant.ReadWrite.All`
   - `Group.ReadWrite.All`
5. Click **Grant admin consent for \<tenant\>** at the top of the permissions list and confirm.

> If the CLI later complains about a missing scope, add it the same way and re-consent. The exact set evolves with CLI versions.

##### Option B — Azure CLI one-liner

```bash
APP_ID=$(az ad app create \
  --display-name "Agent 365 CLI" \
  --sign-in-audience AzureADMyOrg \
  --public-client-redirect-uris http://localhost \
  --is-fallback-public-client true \
  --query appId -o tsv)

az ad sp create --id "$APP_ID"

GRAPH=00000003-0000-0000-c000-000000000000
for SCOPE_ID in \
  e1fe6dd8-ba31-4d61-89e7-88639da4683d \
  bdfbf15f-ee85-4955-8675-146e8e5296b5 \
  84bccea3-f856-4a8a-967b-dbe0a3d53a64 \
  19dbc75e-c2e2-444c-a770-ec69d8559fc7 \
  41ce6ca6-6826-4807-84f1-1c82854f7ee5 \
  4e46008b-f24c-477d-8fff-7bb4ec7aafe0 \
; do
  az ad app permission add --id "$APP_ID" --api $GRAPH --api-permissions "${SCOPE_ID}=Scope"
done

az ad app permission admin-consent --id "$APP_ID"
echo "App Id: $APP_ID"
```

Scope IDs above (in order): `User.Read`, `Application.ReadWrite.All`,
`AppRoleAssignment.ReadWrite.All`, `Directory.ReadWrite.All`,
`DelegatedPermissionGrant.ReadWrite.All`, `Group.ReadWrite.All`.

##### Verify

```bash
az ad app list --display-name "Agent 365 CLI" -o table
```

You should see exactly one app with that display name. Re-run
`a365 setup all ...` once it's there.

##### Provision Microsoft 365 tool service principals (admin-only)

The `Agent 365 CLI` app above lets the CLI itself run. To let your agent
*invoke* Microsoft 365 MCP tools (Mail, Calendar, Teams, OneDrive, SharePoint,
…), an admin also needs to create service principals for those tool apps in
your tenant. The Agent 365 devtools repo ships a script for exactly that:

```powershell
# Requires PowerShell 7+, run as admin
git clone https://github.com/microsoft/Agent365-devTools.git
cd Agent365-devTools/scripts/cli/Auth
.\New-Agent365ToolsServicePrincipalProdPublic.ps1            # provisions V1 + V2 SPs
# Or, to provision only one mode:
# .\New-Agent365ToolsServicePrincipalProdPublic.ps1 -Mode V2
```

The script is idempotent (existing SPs are skipped) and requires
`Application.ReadWrite.All` or an Application Administrator / Global
Administrator role. Run it once per tenant; you'll know you need it if `a365`
tool-related commands later fail with `Insufficient privileges` against an MCP
server app ID.

#### 2d. Python build tools (this project)

```bash
python --version       # 3.11 or higher per this template's prerequisites
pip --version
```

Then create and activate the venv exactly as in
[README.md → Python Environment Configuration](../README.md#python-environment-configuration).

### Step 3 — Configure (AI Teammate path only)
From the **root of this repository**:

```bash
a365 setup all --aiteammate --agent-name <your-agent-base-name>
```

`<your-agent-base-name>` rules:

- Globally unique across Azure.
- Letters, numbers, hyphens; start with a letter.
- 3–20 characters recommended.
- Example: `contoso-support-agent`.

The CLI auto-detects `tenantId`, `subscriptionId`, the client app ID, and the
project type (Python is detected by `pyproject.toml` in this repo).

### Step 4 — Provision with `a365 setup all`

#### 4a. Dry-run first (always)

**Standard path:**

```bash
a365 setup all --agent-name <your-agent-base-name> --dry-run
```

**AI Teammate path:**

```bash
a365 setup all --dry-run
```

Review the resources the CLI proposes to create.

#### 4b. Apply

**Standard path:**

```bash
a365 setup all --agent-name <your-agent-base-name>
```

**AI Teammate path:**

```bash
a365 setup all
```

This single command will:

- Create / validate the Azure infrastructure (Resource Group, App Service Plan, Web App, Managed Identity).
- Create the Agent 365 **Blueprint** in Microsoft Entra ID.
- Configure blueprint permissions.
- Register the messaging endpoint.

The command may take several minutes. Watch the output — the CLI emits
`[1/5]`, `[2/5]`-style progress markers. If a sign-in dialog (WAM on Windows,
browser tab elsewhere) appears, complete it; the CLI resumes automatically.

After it finishes, copy the **Setup Summary** table from the output. If a
**Permission Grants** action item is printed, run the PowerShell script the
CLI prints (a Global Admin must run it) to complete admin consent.

> `a365 setup all` is **idempotent** — safe to re-run after fixing an issue.
> Use `a365 cleanup azure` or `a365 cleanup blueprint` only as a last resort.

### Step 5 — Publish & deploy (AI Teammate path only)

> Skip this step on the Standard path.

#### 5a. Review your manifest

The CLI expects `manifest/manifest.json` inside this project (it will scaffold
one on first publish if missing). Update at least:

| Field | What to set |
|---|---|
| `name.short` / `name.full` | Your agent's display names |
| `description.short` / `description.full` | One-line and long-form descriptions |
| `developer.name` / `websiteUrl` / `privacyUrl` / `termsOfUseUrl` | Your org details |
| `icons.color` / `icons.outline` | 192×192 and 32×32 PNG icons in the project |
| `accentColor` | Brand hex color, e.g. `#0078D4` |
| `version` | Semantic version, e.g. `1.0.0` |

Leave `id` and `agenticUserTemplates[].id` empty — the CLI fills them in.

#### 5b. Publish

```bash
a365 publish
```

Registers the agent package with your tenant's catalog.

#### 5c. Deploy code to Azure

```bash
a365 deploy
```

Builds your Python project, ships it to the Azure Web App that was provisioned
in Step 4, and applies any final Microsoft 365 permission updates.

For subsequent iterations you can target:

- `a365 deploy app` — code only.
- `a365 deploy mcp` — tool permissions only.

### Step 6 — Post-deploy actions (browser only)

These are manual and must be done by you in a browser.

1. **Configure the blueprint in Teams Developer Portal**:
   - Grab your blueprint ID from `a365.generated.config.json` (`agentBlueprintId`) or the Setup Summary.
   - Open `https://dev.teams.microsoft.com/tools/agent-blueprint/<your-blueprint-id>/configuration`.
   - Set **Agent Type** to `API Based`.
   - Set **Notification URL** to the `messagingEndpoint` from `a365.config.json`.
   - **Save**.

2. **Create an agent instance**:
   - In Teams, open **Apps** and search for your agent.
   - Click **Request Instance** (or **Create Instance**).
   - A tenant admin approves the request in the [Microsoft admin center → Requested Agents](https://admin.cloud.microsoft/#/agents/all/requested).

3. **Test**:
   - Search for the new agent user in Teams (creation is async — may take minutes to hours).
   - Start a new chat and send a test message.
   - Tail Azure logs if needed:

     ```bash
     az webapp log tail --name <your-web-app> --resource-group <your-resource-group>
     ```

---

## Troubleshooting quick reference

| Symptom | Fix |
|---|---|
| `a365` command not found after install | Restart your terminal; verify `~/.dotnet/tools` (Linux/macOS) or `%USERPROFILE%\.dotnet\tools` (Windows) is on `PATH`. |
| `Settings file 'DotnetToolSettings.xml' was not found in the package` during `dotnet tool install` | Missing the **.NET 8 runtime** — even with a newer SDK, the `net8.0` tool can't install. Run `dotnet --list-runtimes` and add `Microsoft.NETCore.App 8.0.x` per Step 1. |
| Ubuntu apt error `trying to overwrite '/usr/bin/dnx', which is also in package dotnet-host-*` | Microsoft's `dotnet-sdk` package collides with Ubuntu's `dotnet-host`. Prefer the `dotnet-install.sh` route in Step 1, or use `apt-get install -o Dpkg::Options::="--force-overwrite" dotnet-sdk-8.0`. |
| Interactive auth prompt blocks in CI / headless VM | Run `az login --allow-no-subscriptions` in an interactive session first so the CLI can reuse the cached token silently. |
| `Authenticating via Windows Account Manager...` then silence | A native Windows sign-in dialog opened — check your screen / taskbar and complete it. Do not kill the process. |
| `Forbidden` / `Authorization_RequestDenied` during blueprint creation | Missing directory role or admin consent — revisit Step 2b. |
| `App "Agent 365 CLI" was not found in tenant <id>` | The tenant client app isn't registered — follow Step 2c. |
| `Operation cannot be completed without additional quota` | Azure region/SKU quota hit — pick a different region and retry. |
| Publish fails reaching admin center | Custom client app missing `Application.ReadWrite.All`; have an admin grant it. |
| Need detailed logs | Re-run with `-v` / `--verbose`. Logs live at `%APPDATA%/a365/logs/` (Windows) or `~/.config/a365/logs/` (Linux/macOS). |

For deeper diagnostics see the
[Agent 365 Troubleshooting Guide](https://learn.microsoft.com/en-us/microsoft-agent-365/developer/troubleshooting)
and the
[Agent 365 CLI Reference](https://learn.microsoft.com/en-us/microsoft-agent-365/developer/agent-365-cli).

---

## References

- Official setup prompt: <https://aka.ms/agent365enable>
- Agent 365 CLI docs: <https://learn.microsoft.com/en-us/microsoft-agent-365/developer/agent-365-cli>
- Agent 365 developer docs: <https://learn.microsoft.com/en-us/microsoft-agent-365/developer/>
- Create agent instances: <https://learn.microsoft.com/en-us/microsoft-agent-365/developer/create-instance>
- Microsoft Agent 365 SDK (Python): <https://github.com/microsoft/Agent365-python>
