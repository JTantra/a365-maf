# Enable Agent 365 for this Template

This guide walks you through enabling **Microsoft Agent 365** for the agent in
this template so it can be provisioned, published, and deployed to your tenant
using the **Agent 365 CLI** (`a365`).

The quickest way to get started is to use an AI Coding agent with this prompt, but this guide can be used for self installation as well
> Help me provision this a365 agent following the step-by-step guide in this file. Some sections are marked as already configured and can be skipped. But otherwise, DO NOT skip steps. Ask users the right inputs (such as agent name) at the appropriate time. 

---

## Tooling inventory

These are a quick list of tools that will be used in this README. The step-by-step will also guide users on installing and configuring these tools so you can skip this section and go directly to the step-by-step if you are following along.

| Tool | Why it's needed | Used in | Install |
|---|---|---|---|
| **.NET 8 runtime** | Required by the `a365` global tool (it's a `net8.0` package). A newer SDK alone is *not* enough — `dotnet --list-runtimes` must include `Microsoft.NETCore.App 8.0.x`. | All paths | <https://dotnet.microsoft.com/download/dotnet/8.0> |
| **Agent 365 CLI (`a365`)** | Provisions the blueprint, registers the messaging endpoint, prints the blueprint client secret, etc. | All paths | `dotnet tool install --global Microsoft.Agents.A365.DevTools.Cli --version 1.1.214` |
| **Azure CLI (`az`)** | Cached login the `a365` CLI reuses; also used for direct resource inspection (`az containerapp logs`, `az role assignment`, etc.). | All paths | <https://learn.microsoft.com/cli/azure/install-azure-cli> |
| **Python 3.11+** + **`uv`** | Runs the agent locally; `uv` resolves and locks the SDK dependency graph. | All paths | Python: <https://www.python.org/downloads/>. `uv`: `pip install uv` or <https://docs.astral.sh/uv/getting-started/installation/> |
| **PowerShell 7+** | Needed for the `New-Agent365ToolsServicePrincipalProdPublic.ps1` script and assorted blueprint admin-consent fallbacks the CLI prints. | All paths (tenant setup) | <https://github.com/PowerShell/PowerShell> |
| **Microsoft.Graph PowerShell modules** | Used by the same admin-consent fallback scripts. | Tenant setup | `Install-Module Microsoft.Graph.Authentication, Microsoft.Graph.Applications` |
| **Azure Developer CLI (`azd`) v1.6+** | One-command provision + deploy for the Container Apps recipe (Recipe A). | Recipe A (`azd up`) | `winget install microsoft.azd` / <https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd> |
| **Docker Desktop** *(or Podman)* | Local container builds. **Optional** for this repo — `azure.yaml` ships with `remoteBuild: true`, so ACR Tasks build the image when Docker isn't installed. Install Docker if you want to iterate on the image locally or run the agent in a local container. | Recipe A (optional), local container dev | <https://www.docker.com/products/docker-desktop/> |
| **`devtunnel`** | Exposes a local `host_agent_server.py` over HTTPS so the blueprint can post Activities to your laptop while you debug. | Recipe B (dev-tunnel debugging) | <https://learn.microsoft.com/azure/developer/dev-tunnels/get-started> |
| **Git** | Cloning this template and the `Agent365-devTools` repo for the tenant-tool SP script. | All paths | <https://git-scm.com/downloads> |

> **Tenant prerequisites** (you don't install these — you request them):
> Membership in the [Frontier preview program](https://adoption.microsoft.com/copilot/frontier-program/),
> the **Agent ID Developer** Entra role (and **Application Administrator** /
> **Global Administrator** for the consent fallback), **Contributor** on the
> target Azure subscription, and an existing Azure OpenAI / Foundry account
> with at least one model deployment.

---

## Concepts at a glance

Four things you'll create, in order:

| Concept | What it is | Created by |
|---|---|---|
| **Custom client app** | One-time Entra app named `Agent 365 CLI` that the CLI itself signs in as. | Tenant admin, once per tenant (Step 2c). |
| **Blueprint** | The agent *template* — Entra app registration + service principal + permissions + messaging endpoint. Defines *what kind of agent* this is. | `a365 setup all --agent-name <name>` (Step 4). |
| **Agent code / Azure Web App** | Your Python code that handles incoming Activities. Deployed to the Web App provisioned by setup. | `a365 deploy` (Step 5). |
| **Agent instance** | A live **agent user** account in your tenant (its own UPN, mailbox, presence). Created from the blueprint by users or admins after the agent is published to the catalog. | User clicks **Create Instance** in Teams / admin approves (Step 6). |

Key relationship: **one blueprint can spawn many instances, and every instance
shares the same messaging endpoint** (your Azure Web App). Your code
disambiguates per-turn using `activity.recipient.aad_object_id` (the instance)
and `activity.from_property.aad_object_id` (the human).

## Useful `a365` commands

The full reference is at <https://learn.microsoft.com/microsoft-agent-365/developer/agent-365-cli>. The ones you'll actually reach for:

| Command | Purpose |
|---|---|
| `a365 --version` / `a365 -h` | Sanity check / browse the command tree. |
| `a365 setup requirements` | Validate everything (CLI, Azure login, Entra app, permissions, redirect URIs, optional claims) and print resolution guidance for anything missing. Safe to re-run. *(v1.1.214: this command no longer takes `--agent-name`; scope a single check with `--category <Azure\|Authentication\|PowerShell\|Tenant Enrollment>`.)* |
| `a365 setup all --agent-name <name> --dry-run` | Preview the full setup without making changes. |
| `a365 setup all --agent-name <name>` | Provision Azure infra + blueprint + permissions + endpoint. Idempotent — reuses existing resources by name. |
| `a365 setup all --aiteammate --agent-name <name>` | Same as above but for the AI Teammate path (richer infra + observability). |
| `a365 setup blueprint --agent-name <name> --update-endpoint <url>` | Change just the messaging endpoint (e.g. dev tunnel URL rotated). |
| `a365 setup blueprint --agent-name <name> --show-secret` | Print the blueprint's client secret (Windows, same machine/user that ran setup). |
| `a365 setup permissions mcp --agent-name <name>` | Re-grant MCP server OAuth2 grants on the existing blueprint. Also `permissions bot` / `permissions custom` / `permissions copilotstudio`. *(v1.1.214: add `--remove-legacy-scopes` to drop the shared `ea9ffc3e-…` audience scopes once the agent is confirmed on the V2 SDK — see Step 2f.)* |
| `a365 develop list-available` | List built-in MCP servers in the tenant catalog (what you can install). |
| `a365 develop list-configured` | List MCP servers currently wired into this agent (reads `ToolingManifest.json`). |
| `a365 develop add-mcp-servers <name> [<name>...]` | Add one or more built-in MCP servers to the agent (updates `ToolingManifest.json`). |
| `a365 develop remove-mcp-servers <name> [<name>...]` | Remove built-in MCP servers from the agent. |
| `a365 publish` | Inject IDs into `manifest/manifest.json`, package it, register with the tenant catalog. |
| `a365 setup blueprint --agent-name <name> --endpoint-only --messaging-endpoint <url>` | Register the URL of your deployed host with an existing blueprint. Run this **after** you ship the code to Container Apps / Web App / dev tunnel / etc. *(v1.1.214: `--endpoint-only` and `--update-endpoint` already use the M365 / Teams Graph path automatically. To register an endpoint as part of a full `setup all`, that run now needs the `--m365` flag.)* |
| `a365 query-entra blueprint-scopes` / `instance-scopes` / `inheritance` | Inspect scopes, permissions, and consent status. *(v1.1.214: `query-entra` now requires one of these subcommands — `blueprint-scopes` lists grants on the blueprint SP, `instance-scopes` shows the instance's scopes/consent, `inheritance` verifies the blueprint's `inheritablePermissions`.)* |
| `a365 logs` | Manage CLI diagnostic logs (`%APPDATA%/a365/logs/` on Windows, `~/.config/a365/logs/` on Linux/macOS). Add `-v` / `--verbose` to any command for live verbose output. |
| `a365 cleanup azure` / `a365 cleanup blueprint` | **Destructive.** Removes provisioned Azure resources or the Entra blueprint. Use only as a last resort — prefer re-running `setup all`, which is idempotent. |

> **No `a365 deploy` in v1.1.x.** The CLI does not ship your application code
> for you. `a365 setup all --aiteammate` provisions the infrastructure; you
> push code with your hosting tool of choice (Docker, `az webapp deploy`,
> `az containerapp up`, GitHub Actions, dev tunnel for local debugging), then
> bind the resulting HTTPS URL to the blueprint with
> `a365 setup blueprint --endpoint-only --messaging-endpoint <url>`.

> **Reusing an existing blueprint** — the CLI resolves blueprints by
> *display name* (`<agent-name> Blueprint`), not by GUID. Run
> `a365 setup all --agent-name <same-name>` from any machine signed into the
> same tenant and it will reuse the existing one. To carry CLI state
> (`a365.config.json` + `a365.generated.config.json`) between checkouts, copy
> those two files — they hold the resolved IDs the subcommands read.

---

## Before you start — what you need

Regardless of which option you choose, make sure you have:

- An **Entra ID (Azure AD) tenant** where you have at least the **Agent ID Developer** role (Application Administrator or Global Admin needed for some consent steps).
- A tenant where the well-known **"Agent 365 CLI"** Entra app has been registered and admin-consented (the CLI looks it up by display name; ask your tenant admin if it's missing).
- Membership in the [Frontier preview program](https://adoption.microsoft.com/copilot/frontier-program/) (required to create agent instances in Teams while Agent 365 is in preview).
- This template cloned locally and the Python virtual environment configured per the main [README.md](../README.md#python-environment-configuration).

---

## Step by step guide

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

3. **Install (or update) the Agent 365 CLI** — pin to **`1.1.214`**, the
   version this guide is validated against:

   ```bash
   # First time (pinned)
   dotnet tool install --global Microsoft.Agents.A365.DevTools.Cli --version 1.1.214

   # Or, if already installed, move it to the pinned version
   dotnet tool update --global Microsoft.Agents.A365.DevTools.Cli --version 1.1.214
   ```

   > **Why pin?** The `a365` CLI is moving fast and command surfaces change
   > between releases (for example, `setup requirements` dropped `--agent-name`,
   > and `query-entra` now requires a subcommand). Pinning `--version 1.1.214`
   > keeps the commands in this guide working as written. To intentionally move
   > to the latest preview later, run
   > `dotnet tool update --global Microsoft.Agents.A365.DevTools.Cli --prerelease`
   > and re-validate against any newer command changes.

4. **Verify it's on your PATH and on the pinned version:**

   ```bash
   a365 -h
   a365 --version   # should print 1.1.214+<build>
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
===For this tenant, this is already configured so you can skip this step.===

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
===For this tenant, we have already configured this so you can skip this step===

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
3. **Authentication** blade:
   - Set **Allow public client flows** = **Yes**.
   - Under **Mobile and desktop applications**, click **Add URI** and add **all** of the following (required by MSAL's WAM broker, MSAL native-client flows, and the CLI's local redirect listener on Windows):
     - `http://localhost`
     - `http://localhost:8400/`
     - `https://login.microsoftonline.com/common/oauth2/nativeclient`
     - `ms-appx-web://Microsoft.AAD.BrokerPlugin/<this-app's-client-id>` — copy the **Application (client) ID** from the app's **Overview** blade and substitute it for `<this-app's-client-id>`.
   - **Save**.
4. **API permissions → + Add a permission → Microsoft Graph → Delegated permissions** — add at minimum:
   - `User.Read`
   - `Application.ReadWrite.All`
   - `AppRoleAssignment.ReadWrite.All`
   - `Directory.ReadWrite.All`
   - `DelegatedPermissionGrant.ReadWrite.All`
   - `Group.ReadWrite.All`

   Then **+ Add a permission → APIs my organization uses**, search for **Agent 365** (or its service API), and add the **Delegated** permission:
   - `AgentRegistration.ReadWrite.All`
5. Click **Grant admin consent for \<tenant\>** at the top of the permissions list and confirm.
6. **Token configuration → + Add optional claim → Access** — select **`wids`** and click **Add**, then accept the prompt to enable the Microsoft Graph permission it needs.

   > Without the `wids` claim, the CLI can't detect that you have the Global Administrator role and silently skips `AllPrincipals` OAuth2 grants on the blueprint service principal — agents created from the blueprint will inherit no permissions.

##### Option B — Azure CLI one-liner

```bash
APP_ID=$(az ad app create \
  --display-name "Agent 365 CLI" \
  --sign-in-audience AzureADMyOrg \
  --is-fallback-public-client true \
  --query appId -o tsv)

# Add all four redirect URIs the CLI needs
az ad app update --id "$APP_ID" \
  --public-client-redirect-uris \
    http://localhost \
    http://localhost:8400/ \
    https://login.microsoftonline.com/common/oauth2/nativeclient \
    "ms-appx-web://Microsoft.AAD.BrokerPlugin/$APP_ID"

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

> The script above does **not** add the `AgentRegistration.ReadWrite.All`
> permission (it's exposed by the Agent 365 service API, not Microsoft Graph)
> or the `wids` optional claim. Add those in the portal per Option A, or run
> `a365 setup requirements` to confirm what's still missing — see below.

##### Validate

Rather than tracking every required permission, URI, and claim by hand, ask
the CLI itself. From your project directory:

```bash
a365 setup requirements
```

> **v1.1.214:** `setup requirements` no longer accepts `--agent-name`. Run it
> bare, or scope a single category with
> `a365 setup requirements --category <Azure|Authentication|PowerShell|Tenant Enrollment>`.

The `requirements` subcommand:

- Validates Azure CLI login, Entra roles, the `Agent 365 CLI` app registration, permissions, redirect URIs, and the `wids` optional claim.
- Continues through every check even if some fail, then prints a per-category **pass / warn / fail** summary.
- For anything missing, prints detailed resolution guidance (and the PowerShell to run for privileged actions such as role assignments or admin consent).

Apply any flagged fixes (in the portal per Option A, or by re-running
`a365 setup all ...` from Step 4, which performs the privileged steps it can).

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

#### 2e. Select built-in MCP tools (optional)

This template ships with one MCP server wired up in
[ToolingManifest.json](../ToolingManifest.json) — `mcp_MailTools`. If that's
all you need, **skip this step**. Otherwise pick the built-in MCP servers you
want the agent to call (Mail, SharePoint, Word, Excel, PowerPoint, etc.)
**before** running `a365 setup all`, because the CLI reads
`ToolingManifest.json` to decide which OAuth2 scopes to grant on the
blueprint.

1. **See the catalog** for your tenant:

   ```bash
   a365 develop list-available
   ```

   Prints each MCP server's name, unique name, audience GUID, and scope.

2. **Add** the servers you want:

   ```bash
   a365 develop add-mcp-servers mcp_MailTools mcp_SharePointTools mcp_WordTools
   ```

   This rewrites [ToolingManifest.json](../ToolingManifest.json) — do **not**
   hand-edit that file.

3. **Verify** what's now configured:

   ```bash
   a365 develop list-configured
   ```

4. **Remove** servers you no longer want:

   ```bash
   a365 develop remove-mcp-servers mcp_WordTools
   ```

> Selection is **per blueprint** — every agent instance created from this
> blueprint inherits the same MCP set. If you change the manifest *after*
> Step 4, re-grant the new scopes with
> `a365 setup permissions mcp --agent-name <name>` (or just re-run
> `a365 setup all`, which is idempotent). No agent code changes are needed —
> `McpToolRegistrationService` picks up the new servers on the next turn.

#### 2f. Use the canonical `McpServers.*.All` scopes (Word, OneDrive, Excel, Teams, etc.)

> ⚠️ **Changed in CLI v1.1.214 — the audience model is in transition (V1 → V2).**
> `a365 develop list-available` now returns a **mix** of two audience styles,
> and `a365 develop list-configured` tags each configured server `V1` or `V2`:
>
> - **V1 (shared audience):** scope `McpServers.<Workload>.All` on the
>   canonical **Agent 365 Tools** app `ea9ffc3e-8a23-4a7d-836d-234d7c7565c1`.
>   This is the path the rest of this section documents and it still works.
> - **V2 (per-server audience):** scope `Tools.ListInvoke.All` on a
>   **dedicated per-server app** (e.g. `mcp_MailTools` →
>   `16b1878d-…`, `mcp_WordServer` → `c2d0c2b6-…`,
>   `mcp_TeamsServer` → `ce5029ee-…`). In v1.1.214 these are **first-class**:
>   `a365 setup all` / `setup permissions mcp` detect any per-server SP that's
>   missing from your tenant and offer to create it inline
>   (`az ad sp create --id <appId>`). Pass `--skip-sp-provisioning` to opt out
>   (implicitly on when stdin is redirected, e.g. CI / coding-agent).
>
> Because the SDK is mid-migration, a blueprint can legitimately hold **both**
> the shared `ea9ffc3e-…` scopes (for V1 SDK builds) and the per-server V2
> scopes at once. Once your agent is confirmed running the **V2 SDK**, retire
> the shared scopes with `a365 setup permissions mcp --remove-legacy-scopes`
> (do **not** run it while still on V1 — agents on V1 lose tool access).
>
> The guidance below (force everything onto the `ea9ffc3e-…` audience) remains
> the **safest single-audience choice for V1 SDK agents**. If your project is
> on the V2 SDK, prefer the per-server audiences shown by `list-available` and
> let `setup permissions mcp` provision their SPs instead of hand-editing.

The `a365 develop list-available` catalog shows several "Work IQ" servers
(e.g. `mcp_WordServer`, `mcp_OneDriveRemoteServer`) listed against
*separate* audience apps with a generic `Tools.ListInvoke.All` scope.
**Don't use those audiences** — `a365 setup permissions mcp` can't grant
inheritable consent on them, so the agent *instance* will fail every
activity with `AADSTS65001 ... has not consented to use the application
'<agent-instance-id>'` and `Failed to obtain token for agentic activity`.

The canonical **Agent 365 Tools** resource app
(`ea9ffc3e-8a23-4a7d-836d-234d7c7565c1`) exposes a parallel
`McpServers.<Workload>.All` scope for each of those servers, and *that*
path supports inheritable consent on the instance. Use these in
[ToolingManifest.json](../ToolingManifest.json):

| MCP server | Scope (use this) | Audience |
|---|---|---|
| `mcp_MailTools` | `McpServers.Mail.All` | `ea9ffc3e-8a23-4a7d-836d-234d7c7565c1` |
| `mcp_CalendarTools` | `McpServers.Calendar.All` | `ea9ffc3e-8a23-4a7d-836d-234d7c7565c1` |
| `mcp_WordServer` | `McpServers.Word.All` | `ea9ffc3e-8a23-4a7d-836d-234d7c7565c1` |
| `mcp_ExcelServer` | `McpServers.Excel.All` | `ea9ffc3e-8a23-4a7d-836d-234d7c7565c1` |
| `mcp_ODSPRemoteServer` | `McpServers.OneDriveSharepoint.All` | `ea9ffc3e-8a23-4a7d-836d-234d7c7565c1` |
| `mcp_SharePointListsTools` | `McpServers.SharepointLists.All` | `ea9ffc3e-8a23-4a7d-836d-234d7c7565c1` |
| `mcp_PlannerServer` | `McpServers.Planner.All` | `ea9ffc3e-8a23-4a7d-836d-234d7c7565c1` |
| `mcp_TeamsServer` | `McpServers.Teams.All` | `ea9ffc3e-8a23-4a7d-836d-234d7c7565c1` |
| `mcp_M365Copilot` | `McpServers.CopilotMCP.All` | `ea9ffc3e-8a23-4a7d-836d-234d7c7565c1` |
| `mcp_KnowledgeTools` | `McpServers.Knowledge.All` | `ea9ffc3e-8a23-4a7d-836d-234d7c7565c1` |
| `mcp_DASearch` | `McpServers.DASearch.All` | `ea9ffc3e-8a23-4a7d-836d-234d7c7565c1` |
| `mcp_MeServer` | `McpServers.Me.All` | `ea9ffc3e-8a23-4a7d-836d-234d7c7565c1` |

Hand-edit `ToolingManifest.json` to set the audience and scope to the
values in the table (the `a365 develop add-mcp-servers` command may pick the
Work IQ audience by default — verify and replace).

Then a single command propagates everything end-to-end:

```bash
a365 setup permissions mcp --agent-name <your-agent-base-name>
```

It opens a browser tab; sign in and click Accept. The CLI then:

1. Adds each scope to the blueprint's `requiredResourceAccess`.
2. Grants the OAuth2 tenant-wide consent (`AllPrincipals`) to the blueprint SP.
3. Marks the resource as *inheritable* so each agent instance (Jojo, etc.) gets the same grant on activation.

Verify:

```bash
# Service-principal object id is in a365.generated.config.json
# (agentBlueprintServicePrincipalObjectId)
az rest --method GET \
  --url "https://graph.microsoft.com/v1.0/servicePrincipals/<sp-object-id>/oauth2PermissionGrants" \
  --query "value[].{resource:resourceId,scope:scope}" -o json
```

You should see all the `McpServers.*.All` scopes in a single grant against
resource `ee464f5a-3cdf-460f-b569-9eebae15d1b7` (the **Agent 365 Tools** SP).

Finally **restart the agent process** — MCP servers are discovered on first
request after startup, so a running server won't pick up newly-granted
scopes until restart.

> ⚠️ **V1 vs V2 audiences (updated for CLI v1.1.214).** A blueprint can now
> legitimately hold **both** the shared `ea9ffc3e-…` (`McpServers.*.All`)
> scopes **and** the per-server V2 audiences (e.g. `c2d0c2b6-…` Word,
> `ce5029ee-…` Teams, `16b1878d-…` Mail, `ab7c82de-…` Copilot) with
> `Tools.ListInvoke.All` — that's expected during the SDK migration, and
> `a365 query-entra blueprint-scopes` will show them side by side. **Do not
> blanket-delete the V2 audiences anymore** — V2 SDK agents need them. Only
> remove a per-server audience if your agent is still on the **V1 SDK** and
> failing to mint a token for that workload; otherwise prefer
> `a365 setup permissions mcp --remove-legacy-scopes` (after confirming V2) to
> retire the shared `ea9ffc3e-…` scopes. Use `query-entra inheritance` to
> confirm instances will inherit whatever grants you keep.

### Step 3 — Configure AI Teammate
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

**AI Teammate path:**

```bash
a365 setup all --dry-run
```

Review the resources the CLI proposes to create.

#### 4b. Apply

**AI Teammate path:**

```bash
a365 setup all
```

This single command will (the exact step list is printed by `--dry-run`):

- Validate prerequisites (Azure CLI, PowerShell modules).
- Create the Agent 365 **Blueprint** in Microsoft Entra ID, plus its service principal, client secret, federated identity credential (FIC), and managed identity.
- Configure **inheritable permissions** and attempt the blueprint **permission grants** (Global Administrator needed for tenant-wide consent — a consent URL / PowerShell snippet is printed if you lack it).
- For the AI Teammate path, also create the **agent identity** and **agent registration**.
- Write project settings to `appsettings.json`.

> **v1.1.214 — `setup all` no longer provisions Azure hosting or the endpoint
> inline.** The AI Teammate path reports *"Azure hosting — skip: hosting is
> externally managed"*, and the messaging endpoint is **deferred** (AI Teammate)
> or **skipped — non-M365 agent** (blueprint-only). You deploy the code
> yourself (Step 5c) and then register the URL with
> `a365 setup blueprint --endpoint-only --messaging-endpoint <url>` (add
> `--m365`, or run `setup all --m365`, if you want the endpoint registered as
> part of setup). This matches the "no `a365 deploy`" note above.

The command may take several minutes. Watch the output — the CLI emits
numbered `1.`, `2.` … step markers (8 steps for the blueprint-only path, 7 for
AI Teammate). If a sign-in dialog (WAM on Windows, browser tab elsewhere)
appears, complete it; the CLI resumes automatically.

After it finishes, copy the **Setup Summary** table from the output. If a
**Permission Grants** action item is printed, run the PowerShell script the
CLI prints (a Global Admin must run it) to complete admin consent.

> `a365 setup all` is **idempotent** — safe to re-run after fixing an issue.
> Use `a365 cleanup azure` or `a365 cleanup blueprint` only as a last resort.

### Step 5 — Publish & deploy (AI Teammate path only)

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

#### 5c. Deploy the agent code yourself, then register the endpoint

> `a365 deploy` **does not exist** in CLI v1.1.x. You ship the code with your
> `a365 deploy` **does not exist** in CLI v1.1.x. You ship the code with your
> own tool (azd + Bicep, `az containerapp up`, `az webapp deploy`, GitHub
> Actions, dev tunnel, on-prem), then point the blueprint at the resulting
> HTTPS URL.

Pick whichever target fits your environment. The template ships with a
[`Dockerfile`](../Dockerfile), an [`azure.yaml`](../azure.yaml), and a Bicep
template under [`infra/`](../infra) tuned for **Azure Container Apps**, which
is the recommended path because Container Apps natively supports
**system-assigned managed identity** — your agent can call Azure AI Foundry /
Azure OpenAI without secrets.

##### Recipe A: `azd up` (one command, recommended)

What's in the repo:

- `azure.yaml` — declares the `agent` service, points at the `Dockerfile`, and prints a follow-up reminder to bind the blueprint endpoint after deploy.
- `infra/main.bicep` — **subscription-scope** template that creates a new resource group (`rg-<env-name>` by default) and calls `resources.bicep` inside it.
- `infra/resources.bicep` — workload resources: Log Analytics, Container Apps environment, Azure Container Registry, and the Container App with system-assigned MI. Also grants the MI **Cognitive Services OpenAI User** on the existing Foundry / AOAI account (via the submodule below) and **AcrPull** on the registry. The Bicep also takes **optional blueprint auth parameters** (`blueprintClientId`, `blueprintTenantId`, `blueprintClientSecret`) — when supplied, the Container App gets the full agentic-auth env block plus a Container Apps secret. When omitted, the app boots in anonymous mode.
- `infra/modules/aoai-role-assignment.bicep` — the role assignment, deployed at the Foundry account's resource group scope.
- `infra/main.parameters.json` — reads everything from `azd` env vars. Defaults the Foundry account to **`terenceaifoundry-resource`** in resource group **`terenceaifoundry-rg`**.

Pre-reqs:

- [Azure Developer CLI (`azd`) v1.6+](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd).
- **Either** Docker (or Podman) on the build machine, **or** set `remoteBuild: true` under the `docker:` section in [`azure.yaml`](../azure.yaml) so the image is built by ACR Tasks instead. The repo ships with `remoteBuild: true` so `azd up` works out of the box without a local container runtime.
- An existing Azure OpenAI / Foundry account with at least one model deployment. By default this template targets `terenceaifoundry-resource` in `rg-admin-terenceaifoundry` (endpoint `https://terenceaifoundry-resource.openai.azure.com/openai/v1`, deployment `gpt-5.4`). Override with `AZURE_OPENAI_*` env vars below.
- Azure CLI logged in (`az login`) with **Contributor** on the target subscription and **User Access Administrator** (or **Owner**) on both the new workload RG and the Foundry account's RG, so role assignments can be created.

Deploying with auth is a **two-pass** flow because the Container App's public
URL has to exist before the Agent 365 blueprint endpoint can be registered,
and the blueprint client secret only exists after `a365 setup all` (Step 4)
has created the blueprint. Both passes use the same `azd up`.

###### Pass 1 — provision + deploy in anonymous mode

> **First-revision gotcha.** The Container App is created with a placeholder
> image (`mcr.microsoft.com/k8se/quickstart`) that listens on port 80, so the
> very first provision's port-3978 startup probe will fail and the deployment
> will time out with `ContainerAppOperationError: Operation expired`. There are
> two ways through this:
>
> 1. **Pre-build the image** with `az acr build --registry <acr> --image agent:initial .` after the registry exists (you can fast-fail the first `azd up` to create the ACR, then re-run), and pass `INITIAL_IMAGE=<acr>.azurecr.io/agent:initial` via `azd env set` before re-running `azd up`. The Bicep template uses that as the first-revision image so the probe passes immediately.
> 2. **Race-fix the AcrPull role assignment.** Even with the right image, the system MI's `AcrPull` role on the registry may not propagate before the first revision tries to pull. Grant it manually:
>
>    ```bash
>    MI=$(az containerapp show -n <container-app> -g <rg> --query identity.principalId -o tsv)
>    ACR_ID=$(az acr show -n <acr> -g <rg> --query id -o tsv)
>    az role assignment create --assignee-object-id $MI --assignee-principal-type ServicePrincipal --role AcrPull --scope $ACR_ID
>    ```
>
>    Then re-run `azd provision`.

```bash
# One-time: log in and choose the subscription.
azd auth login
az login                                          # used by Bicep deployments
az account set --subscription <your-subscription-id>

# Create the azd environment and set the location. The template creates a
# NEW resource group for the workload — no need to pre-create one.
azd env new <resource_group_name>                          # creates .azure/agent365-dev
azd env set AZURE_LOCATION southeastasia

# Optional overrides (defaults shown):
# azd env set AZURE_RESOURCE_GROUP        rg-agent365-dev
# azd env set AZURE_OPENAI_ACCOUNT_NAME   terenceaifoundry-resource
# azd env set AZURE_OPENAI_RESOURCE_GROUP rg-admin-terenceaifoundry
# azd env set AZURE_OPENAI_ENDPOINT       https://terenceaifoundry-resource.openai.azure.com/openai/v1
# azd env set AZURE_OPENAI_DEPLOYMENT     gpt-5.4
# azd env set AZURE_OPENAI_API_VERSION    2024-10-21

# Provision infra + build & push image + deploy. Auth env vars stay empty,
# so the Container App comes up in anonymous mode (good enough to verify the
# FQDN and the Foundry MI integration).
azd up
```

Once `azd up` finishes, grab the FQDN and register it with the blueprint
(the blueprint itself must already exist — see Step 4):

```bash
FQDN=$(azd env get-values | grep AGENT_FQDN | cut -d= -f2 | tr -d '"')

a365 setup blueprint --agent-name <your-agent-base-name> --endpoint-only \
  --messaging-endpoint "https://$FQDN/api/messages"
```

###### Pass 2 — enable agentic auth

Print the blueprint credentials and feed them back into the same `azd`
environment, then re-run `azd up`. The Bicep template flips the Container App
into agentic mode (sets `AUTH_HANDLER_NAME=AGENTIC`, the `CONNECTIONS__*` and
`AGENTAPPLICATION__*` block, and stores the client secret as a Container Apps
secret referenced via `secretRef:`).

```bash
# blueprint (client) ID is in the generated config; tenantId lives in a365.config.json.
CLIENT_ID=$(jq -r '.agentBlueprintId' a365.generated.config.json)
TENANT_ID=$(jq -r '.tenantId'         a365.config.json)

azd env set BLUEPRINT_CLIENT_ID  "$CLIENT_ID"
azd env set BLUEPRINT_TENANT_ID  "$TENANT_ID"

# Mark the secret as secure so azd encrypts it in the local env store.
azd env set --secret BLUEPRINT_CLIENT_SECRET \
  "$(a365 setup blueprint --agent-name <your-agent-base-name> --show-secret)"

# Re-deploy. Bicep redeploys the Container App with the agentic env block
# + secret; azd skips the image build because the source didn't change.
azd up
```

Verify the mode flipped:

```bash
azd env get-values | grep AGENT_AUTH_MODE
# AGENT_AUTH_MODE="agentic"
```

###### Iteration loop after the first two passes

| You changed... | Run |
|---|---|
| Application code (`agent.py`, `host_agent_server.py`, etc.) | `azd deploy` — rebuilds the image and rolls a new revision. |
| Bicep (`infra/*.bicep`) only | `azd provision` — re-applies infra without rebuilding the image. |
| Both | `azd up` — does both. |
| Hosting URL changed (region migration, rename) | Re-run `a365 setup blueprint --update-endpoint ...`. |
| Need to start over | `azd down --purge` — deletes everything `azd up` created. |

Need additional plain env vars? Edit the `baseEnv` array in
[`infra/resources.bicep`](../infra/resources.bicep) and `azd provision`. For
additional secrets, add a new `@secure()` parameter, plumb it through
`main.bicep`, append to the `authSecrets` / `authEnv` arrays, then set the
value with `azd env set --secret <NAME> <value>`.

See [`env/.env.production.example`](../env/.env.production.example) for the
full reference of every variable the agent reads at runtime.

##### Recipe B — Local debugging via dev tunnel

```bash
# In one terminal: run the agent locally.
python host_agent_server.py     # listens on :3978

# In another: expose it.
devtunnel host -p 3978 --allow-anonymous     # prints https://<id>-3978.devtunnels.ms

# Bind the tunnel URL.
a365 setup blueprint --agent-name <your-agent-base-name> --endpoint-only \
  --messaging-endpoint https://<id>-3978.devtunnels.ms/api/messages
```

Use `--update-endpoint` instead of `--endpoint-only` whenever the tunnel URL
rotates.

### Step 6 — Post-deploy actions (browser only)

These are manual and must be done by you in a browser.

1. **Configure the blueprint in Teams Developer Portal**:
   - Grab your blueprint ID from `a365.generated.config.json` (`agentBlueprintId`) or the Setup Summary.
   - Open `https://dev.teams.microsoft.com/tools/agent-blueprint/<your-blueprint-id>/configuration`.
   - Set **Agent Type** to `API Based`.
   - Set **Notification URL** to the `messagingEndpoint` from `a365.config.json`.
   - **Save**.

2. **Publish the blueprint to your tenant catalog** (Microsoft 365 admin center):
   To publish: https://admin.microsoft.com > Agents > All agents > Upload custom agent
   
   After upload, the admin center asks you to set two scopes — they control
   different things, so set them deliberately:

   | Scope | What it controls | Recommended starting value |
   |---|---|---|
   | **Publish** | Who can *see* the blueprint in Teams Apps and *request* an instance. Greyed at *All users* on first publish because catalog entries are inherently discoverable tenant-wide. | All users (default). |
   | **Activate** | Who can *create an instance* without admin approval. **None** routes every request through an admin via [admin.cloud.microsoft → Requested Agents](https://admin.cloud.microsoft/#/agents/all/requested). **All users** lets anyone self-serve. **Specific users/groups** lets a chosen Entra group self-serve and routes everyone else through approval. | **Specific users/groups** — scope to your dev team / pilot Entra group during preview. Widen later. |

   Each instance is a **real licensed agent user** in your tenant (with its
   own mailbox, OneDrive, presence) and inherits the blueprint's OAuth2
   grants. Treat *Activate* like "who can create a new M365 user" — because
   that's literally what it does.

3. **Create an agent instance**:
   - In Teams, open **Apps** and search for your agent.
   - Click **Request Instance** (or **Create Instance** if you're in the *Activate* scope).
   - If approval is required, the tenant admin approves the request in the [Microsoft admin center → Requested Agents](https://admin.cloud.microsoft/#/agents/all/requested).
   - Microsoft 365 then mints a new Entra **agent user** bound to your blueprint, with the inherited permissions, identity SP, and messaging endpoint.

4. **Test**:
   - Search for the new agent user in Teams (creation is async — minutes to hours during preview).
   - Start a new chat and send a test message. The Activity is POSTed to your blueprint's messaging endpoint (the Container App / Web App / dev tunnel you registered in Step 5c).
   - Every instance of the same blueprint hits the **same endpoint**. Your code uses `activity.recipient.aad_object_id` to tell instances apart and `activity.from_property.aad_object_id` to identify the human.
   - Tail Azure logs if needed:

     ```bash
     az webapp log tail --name <your-web-app> --resource-group <your-resource-group>
     ```

> Want a *second* agent with a different endpoint or different code? That's
> a **new blueprint** (`a365 setup all --agent-name <other-name>` against a
> different Azure Web App), not another instance. Instances of one blueprint
> are meant to be configuration-level variants of the same product.

---

## Appendix A — Register a custom MCP server

Use this when you need to call **your own** MCP server (one not in the A365
catalog returned by `a365 develop list-available`). The platform's
`McpToolRegistrationService` only discovers built-in catalog MCPs, so a
custom MCP is wired in via **Agent Framework primitives** alongside the
A365-managed ones.

### When you need this

- You operate the MCP server yourself (internal HR system, Dataverse-hosted
  MCP, on-prem connector, etc.).
- The MCP is published to a Dataverse environment (`a365 develop-mcp publish`)
  but not yet in the global catalog.
- You're prototyping locally against a `stdio` or `http` MCP before publishing.

If your MCP is **already in the A365 catalog**, use Step 2e instead — that path
gives you free per-audience OBO auth and zero code changes.

### A.1 — Pick a transport

| Transport | Agent Framework class | When to use |
|---|---|---|
| Streamable HTTP | `MCPStreamableHTTPTool` | Remote HTTP/HTTPS MCP servers (most common) |
| Stdio (local process) | `MCPStdioTool` | Local `npx`/`uvx` MCP servers for dev |
| WebSocket | `MCPWebsocketTool` | Servers that only expose a WS endpoint |

All three are imported from `agent_framework`.

### A.2 — Wire the MCP into the agent

There are two places to add it. Pick **A** (recommended) if you also want the
built-in A365 MCPs; pick **B** if your agent only uses custom tools.

**Option A — Pass it through `initial_tools` (keeps A365 MCPs)**

Edit `setup_mcp_servers()` in [agent.py](../agent.py) so the custom MCP is
included in `initial_tools` handed to
`McpToolRegistrationService.add_tool_servers_to_agent`:

```python
from agent_framework import MCPStreamableHTTPTool
import httpx

# Build any auth headers your MCP needs (the A365 service only injects
# per-audience tokens for catalog MCPs — your server is on its own).
custom_headers = {"Authorization": f"Bearer {os.getenv('CUSTOM_MCP_TOKEN', '')}"}
custom_http = httpx.AsyncClient(headers=custom_headers, timeout=90.0)

custom_mcp = MCPStreamableHTTPTool(
    name="my_custom_mcp",
    url=os.getenv("CUSTOM_MCP_URL"),       # e.g. https://my-mcp.example.com/mcp
    http_client=custom_http,
    description="My custom MCP server",
)

self.agent = await self.tool_service.add_tool_servers_to_agent(
    chat_client=self.chat_client,
    agent_instructions=agent_instructions,
    initial_tools=[custom_mcp],            # <-- your MCP joins A365 MCPs
    auth=auth,
    auth_handler_name=auth_handler_name,
    auth_token=self.auth_options.bearer_token,   # omit when use_agentic_auth=True
    turn_context=context,
)
```

Remember to `await custom_http.aclose()` in `cleanup()` so the connection
pool is released.

**Option B — Skip the A365 registration service entirely**

If you don't use any built-in A365 MCPs, build the agent directly in
`_create_agent()`:

```python
from agent_framework import Agent, MCPStreamableHTTPTool

custom_mcp = MCPStreamableHTTPTool(
    name="my_custom_mcp",
    url=os.getenv("CUSTOM_MCP_URL"),
)

self.agent = Agent(
    client=self.chat_client,
    instructions=self.AGENT_PROMPT,
    tools=[custom_mcp],
)
```

…then short-circuit `setup_mcp_servers()` (return early) so the registration
service doesn't rebuild the agent and drop your tool.

### A.3 — Authentication patterns

| Auth model | What to do |
|---|---|
| **Static key / PAT** | Inject `Authorization: Bearer <pat>` via the `httpx.AsyncClient` headers as shown above. |
| **OBO from the agent's identity** | Call `await auth.exchange_token(turn_context, [scope], auth_handler_name)` inside `setup_mcp_servers()` and use the returned token in the header. The scope must match the resource your MCP validates against (a custom Entra app you registered — see A.4). |
| **No auth (dev)** | Omit `http_client`; `MCPStreamableHTTPTool` will create its own. |

### A.4 — (Optional) Register the custom resource with the blueprint

Required only if your MCP validates **agent identity tokens** issued for a
custom Entra resource. Grant the scope on the blueprint so OBO exchange works:

```bash
a365 setup permissions custom \
  --agent-name <your-agent-base-name> \
  --resource-app-id <custom-mcp-app-id> \
  --scopes "MyMcp.Read,MyMcp.Write"
```

This adds an OAuth2 grant + inheritable permission on the blueprint SP, so
every agent instance spawned from it can OBO-exchange a token for your MCP.

### A.5 — (Optional) Publish into a Dataverse environment

If your custom MCP lives in Dataverse, the CLI can publish it so it appears
in `list-available` for callers in that environment:

```bash
a365 develop-mcp list-environments
a365 develop-mcp publish --environment <env-name> ...        # see --help
a365 develop-mcp register-external-mcp-server --help         # for external endpoints
```

After publish, your custom MCP becomes a regular catalog entry and you can
switch from the code path above to the simpler `a365 develop add-mcp-servers`
flow from Step 2e.

### A.6 — Smoke test

1. Start the host locally (`./scripts/run-local-agentic.ps1`).
2. Send a message that should trigger the tool.
3. Look for these log lines from `McpToolRegistrationService`:
   - `Created MCP plugin for 'my_custom_mcp' at <url>`
   - `Added MCP plugin 'my_custom_mcp' to agent tools`
   - `Agent created with N total tools` (N includes your custom MCP + catalog MCPs)
4. If the tool isn't called, check that the LLM has a clear description (set
   `description=` on the `MCPStreamableHTTPTool`) and that the MCP server's
   `tools/list` returns the tool you expect.

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
| `AADSTS50011: The redirect URI 'ms-appx-web://Microsoft.AAD.BrokerPlugin/<id>' ... does not match` | The `Agent 365 CLI` app is missing the WAM broker redirect URI. In **Authentication**, add `ms-appx-web://Microsoft.AAD.BrokerPlugin/<this-app's-client-id>` (and `https://login.microsoftonline.com/common/oauth2/nativeclient` while you're there). See Step 2c. |
| CLI reports missing `AgentRegistration.ReadWrite.All`, `http://localhost:8400/`, or `wids` claim | Re-run `a365 setup requirements` (v1.1.214: no `--agent-name`) to confirm the gap, then apply it in the portal per Step 2c Option A (steps 4 and 6) or by re-running `a365 setup all`. |
| `Operation cannot be completed without additional quota` | Azure region/SKU quota hit — pick a different region and retry. |
| Publish fails reaching admin center | Custom client app missing `Application.ReadWrite.All`; have an admin grant it. |
| Agent reply says "I don't have access to Word/OneDrive/SharePoint" even though the server is in `ToolingManifest.json` | First confirm which SDK the agent runs. **V1 SDK:** the per-server "Work IQ" audience (`c2d0c2b6-…` Word, `b0b2a2bb-…` OneDrive, etc.) won't propagate — switch that manifest entry to the canonical `ea9ffc3e-8a23-4a7d-836d-234d7c7565c1` audience with the matching `McpServers.<Workload>.All` scope (Step 2f), re-run `a365 setup permissions mcp --agent-name <name>`, and restart. **V2 SDK:** the per-server audience *is* correct — instead run `a365 query-entra inheritance` to confirm the grant is inheritable, re-run `setup permissions mcp`, and restart. |
| Agent server crashes every activity with `AADSTS65001 ... has not consented to use the application '<agent-instance-id>'` and `Failed to obtain token for agentic activity` right after adding a new MCP scope | The blueprint references a resource the agent instance can't get an inheritable grant for. Run `a365 query-entra inheritance` to see which resource isn't inheritable. On the **V1 SDK**, switch that workload to the canonical `ea9ffc3e-…` audience (`McpServers.<Workload>.All`) and re-run `a365 setup permissions mcp --agent-name <name>`; on the **V2 SDK**, make sure the per-server audience's SP exists in your tenant (`setup all` / `setup permissions mcp` provision it unless `--skip-sp-provisioning` was used) and re-run, then restart. |
| `a365 setup permissions custom` prints `OAuth2 permission grant failed (non-transient) ... Authorization_RequestDenied` even on a "Work IQ" audience as a Global Administrator | This usually means the resource doesn't support delegated tenant-wide consent through the CLI's path. Prefer the canonical `McpServers.*.All` scopes on the Agent 365 Tools resource (Step 2f) — they always work. |
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
