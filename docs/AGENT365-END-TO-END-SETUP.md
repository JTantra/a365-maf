---
title: Agent 365 End-to-End Setup Guide
description: Step-by-step setup guide for running, registering, and deploying this Microsoft Agent 365 Python sample
author: Microsoft
ms.date: 2026-06-12
ms.topic: tutorial
keywords:
  - Microsoft Agent 365
  - Agent Framework
  - Microsoft 365 Agents Toolkit
  - Azure Container Apps
  - MCP
estimated_reading_time: 35
---

## Setup goal

Use this guide when you want a single, followable path for this repository:

* Prepare your local machine
* Configure Azure OpenAI or Azure AI Foundry
* Run the agent in Microsoft 365 Agents Playground
* Register an Agent 365 blueprint
* Deploy the Python host to Azure Container Apps
* Enable production agentic authentication
* Register the blueprint-based agent and create an instance in Teams

The repo already contains deeper reference material in
[AGENT365-SETUP.md](./AGENT365-SETUP.md). Use this file as the practical
checklist, then go to the reference doc when you need background or alternate
paths.

## How this repo is wired

The runtime path is intentionally small:

1. `start_with_generic_host.py` starts the app.
2. `host_agent_server.py` hosts `/api/messages` and `/api/health` with the
   Microsoft 365 Agents SDK.
3. `agent.py` creates the Agent Framework agent, connects to Azure OpenAI, and
   attaches Microsoft 365 MCP tools from `ToolingManifest.json`.
4. `m365agents.playground.yml` drives local Playground setup.
5. `azure.yaml` and `infra/` deploy the app to Azure Container Apps.

The application needs an HTTPS messaging endpoint that Agent 365 can call. For
local debugging, that endpoint is provided by Agents Playground or a dev tunnel.
For production-style testing, the endpoint is the Azure Container Apps URL.

## Prerequisites

Install or confirm these tools before you start.

| Tool | Required for | Check |
| ------ | -------------- | ------- |
| Python 3.11 or later | Running this app | `python3 --version` |
| `uv` | Python dependency management | `uv --version` |
| Node.js | Microsoft 365 Agents Toolkit local tasks | `node --version` |
| Azure CLI | Azure login and resource checks | `az --version` |
| .NET 8 runtime or SDK | Agent 365 CLI | `dotnet --list-runtimes` |
| Agent 365 CLI | Blueprint and permissions setup | `a365 --version` |
| Azure Developer CLI | Azure Container Apps deployment | `azd version` |
| PowerShell 7 | Some admin-consent fallback scripts | `pwsh --version` |
| Microsoft 365 Agents Toolkit VS Code extension | Playground debug flow | VS Code extensions view |

> [!IMPORTANT]
> The Agent 365 CLI is a .NET global tool that needs the .NET 8 runtime. A newer
> .NET SDK alone is not enough unless `dotnet --list-runtimes` includes
> `Microsoft.NETCore.App 8.0.x`.

Install common tools on macOS with Homebrew where possible:

```bash
brew install python node azure-cli azure-developer-cli powershell
```

If an older guide suggests `brew install --cask powershell`, use the formula
command above instead. Homebrew has moved stable PowerShell from the cask tap to
Homebrew core on recent macOS installations.

Verify PowerShell after installation:

```bash
pwsh --version
```

Expected result:

```text
PowerShell 7.x.x
```

Install `uv` if it is missing:

```bash
python3 -m pip install uv
```

Install or update the Agent 365 CLI:

```bash
dotnet tool install --global Microsoft.Agents.A365.DevTools.Cli --prerelease
```

If the tool already exists, update it:

```bash
dotnet tool update --global Microsoft.Agents.A365.DevTools.Cli --prerelease
```

Confirm the global tool path is available:

```bash
a365 --version
```

If `a365` is not found, add the .NET tools directory to your shell profile:

```bash
echo 'export PATH="$HOME/.dotnet/tools:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

## VS Code Dev Container option

Use the Dev Container path when you want the Agent 365 development toolchain in
an isolated Linux container instead of installing every tool directly on macOS.
The repo includes `.devcontainer/devcontainer.json` and
`.devcontainer/setup-tools.sh` for this approach.

The Dev Container installs or configures:

* Python 3.11
* Node.js LTS
* .NET 8
* Azure CLI
* Azure Developer CLI
* PowerShell 7
* Microsoft Graph PowerShell modules used by Agent 365 admin fallback scripts
* Agent 365 CLI
* `uv`
* Azure CLI Bicep support
* Project Python dependencies in `.venv`
* VS Code extensions for Python, Bicep, Azure, Docker, YAML, PowerShell, and
  Microsoft 365 Agents Toolkit

The container forwards these ports:

| Port | Purpose |
| ---- | ------- |
| `3978` | Agent host `/api/messages` and `/api/health` |
| `56150` | Microsoft 365 Agents Playground local service |

The container also keeps these tool caches in named Docker volumes so rebuilds
are faster and sign-in state can persist between container recreations:

* Azure CLI cache
* Azure Developer CLI cache
* Agent 365 CLI cache
* .NET global tools
* PowerShell modules
* `uv` cache

### Open the repo in the Dev Container

1. Install Docker Desktop or another Dev Containers compatible container
   runtime on your machine.
2. Install the VS Code Dev Containers extension.
3. Open this repository in VS Code.
4. Run `Dev Containers: Reopen in Container` from the command palette.
5. Wait for `postCreateCommand` to finish. The first build can take several
   minutes because it installs SDKs, CLIs, PowerShell modules, and Python
   packages.

After the container opens, confirm the toolchain:

```bash
python3 --version
node --version
dotnet --list-runtimes
az --version
azd version
a365 --version
uv --version
pwsh --version
```

Sign in from inside the container:

```bash
az login --use-device-code
```

Then sign in to Azure Developer CLI:

```bash
azd auth login
```

> [!NOTE]
> You still need tenant permissions, Azure RBAC, and an Azure OpenAI or Foundry
> deployment. The Dev Container prepares tools; it does not grant cloud access.

### Re-run the Dev Container bootstrap

If you add a dependency or want to refresh tools, run:

```bash
bash .devcontainer/setup-tools.sh
```

The script is idempotent. It updates or reuses installed tools and refreshes
the project `.venv`.

### Skip Graph PowerShell modules

The Microsoft Graph PowerShell modules are useful for Agent 365 tenant setup
fallback steps, but they can take time to install. To skip them during a manual
bootstrap run, use:

```bash
INSTALL_GRAPH_PS_MODULES=false bash .devcontainer/setup-tools.sh
```

### Dev Container troubleshooting

If `a365`, `azd`, or `uv` is missing after the container starts, reload the
terminal or run:

```bash
source ~/.bashrc
```

If Docker volumes have stale state, rebuild without cache from VS Code:

```text
Dev Containers: Rebuild Container Without Cache
```

If you need to fully reset sign-in/tool caches, remove the named Docker volumes
that start with `a365-maf-`, then reopen the container.

## Tenant and Azure access checklist

You need access in both Microsoft Entra ID and Azure.

| Area | Minimum access |
| ------ | ---------------- |
| Microsoft Entra ID | Agent ID Developer |
| Agent 365 tenant setup | Application Administrator or Global Administrator for consent tasks |
| Azure subscription | Contributor on the target subscription |
| Azure role assignments | Owner or User Access Administrator when assigning managed identity access |
| Microsoft 365 preview | Frontier preview access if required by your tenant |
| Azure OpenAI or Foundry | An existing account with a model deployment |

Sign in to Azure CLI before running Agent 365 CLI commands:

```bash
az login --use-device-code
```

Set the subscription you want to use:

```bash
az account set --subscription "<subscription-id>"
```

Verify your active context:

```bash
az account show --query "{name:name, user:user.name, tenantId:tenantId, subscriptionId:id}" -o json
```

## Values to collect before setup

Choose and record these values. Keeping them in one place avoids mistakes when
you move between local, Agent 365 CLI, and Azure Developer CLI steps.

| Placeholder | Description | Example |
| ------------- | ------------- | --------- |
| `<agent-name>` | Base name for the Agent 365 blueprint | `contoso-support-agent` |
| `<subscription-id>` | Azure subscription ID | `00000000-0000-0000-0000-000000000000` |
| `<azure-location>` | Azure region for Container Apps | `southeastasia` |
| `<aoai-account-name>` | Existing Azure OpenAI or Foundry account | `contoso-foundry` |
| `<aoai-resource-group>` | Resource group containing the Azure OpenAI account | `rg-contoso-foundry` |
| `<aoai-endpoint>` | Azure OpenAI resource root endpoint | `https://contoso-foundry.openai.azure.com` |
| `<aoai-deployment>` | Model deployment name | `gpt-4.1` |
| `<aoai-api-version>` | API version used by the app | `preview` |

> [!IMPORTANT]
> For this repo's Azure deployment path, use the Azure OpenAI resource root as
> the endpoint, such as `https://<resource>.openai.azure.com`. Do not append
> `/openai/v1` when setting `AZURE_OPENAI_ENDPOINT` for the Container Apps
> deployment.

## Step 1 Prepare the Python environment

Run these commands from the repo root.

```bash
uv venv
```

Activate the environment:

```bash
source .venv/bin/activate
```

Install the project and dependencies:

```bash
uv pip install -e .
```

Confirm the app imports successfully:

```bash
python -c "from agent import AgentFrameworkAgent; from host_agent_server import create_and_run_host; print('imports ok')"
```

Expected result:

```text
imports ok
```

## Step 2 Configure local Playground settings

The Microsoft 365 Agents Toolkit flow reads values from `env/.env.playground`
and `env/.env.playground.user`, then writes the runtime `.env` file during the
Playground deploy step.

Open `env/.env.playground.user` and set the values that match your model
provider. Do not commit real secrets.

For Azure OpenAI or Foundry, set:

```bash
SECRET_AZURE_OPENAI_API_KEY=<your-local-dev-key>
AZURE_OPENAI_ENDPOINT=<your-aoai-resource-root-endpoint>
AZURE_OPENAI_DEPLOYMENT_NAME=<your-model-deployment-name>
AZURE_OPENAI_API_VERSION=<api-version>
```

For OpenAI, set the OpenAI key only if you intentionally change the code to use
OpenAI instead of Azure OpenAI. The current `agent.py` path expects Azure
OpenAI settings.

Open `env/.env.playground` and confirm these values are present:

```bash
TEAMSFX_ENV=playground
TEAMSAPPTESTER_PORT=56150
USE_AGENTIC_AUTH=false
```

If the Playground flow requires a custom client app, set `CLIENT_APP_ID` in
`env/.env.playground`.

## Step 3 Run in Microsoft 365 Agents Playground

Use this path first. It validates the Python code, the model connection, and
the basic Agent 365 activity flow before you provision cloud infrastructure.

1. Open the repo in VS Code.
2. Select the Microsoft 365 Agents Toolkit icon.
3. Choose the Playground debug configuration.
4. Start debugging with F5.
5. Select `Debug in Microsoft 365 Agents Playground` if prompted.
6. Send a test message to the agent.

Expected behavior:

* The local host listens on port `3978`.
* The Playground listens on port `56150`.
* The agent sends an acknowledgement, a typing indicator, and a final response.
* The terminal logs show the user identity fields from the incoming activity.

If you want to start the host directly, run:

```bash
python start_with_generic_host.py
```

Then check the health endpoint:

```bash
curl http://localhost:3978/api/health
```

If port `3978` is already in use, `host_agent_server.py` automatically tries
the next port for local startup. Update any tunnel or tester configuration if
that happens.

## Step 4 Validate the Agent 365 CLI setup

The Agent 365 CLI uses Azure CLI sign-in context and a tenant app named
`Agent 365 CLI`. Validate requirements before creating the blueprint:

```bash
a365 setup requirements
```

> [!NOTE]
> In Agent 365 CLI `1.1.206`, `a365 setup requirements` does not accept
> `--agent-name`. Use `--agent-name` only with commands whose help explicitly
> lists it, such as `a365 setup permissions mcp`.

Review the output carefully. If the CLI offers to apply safe changes such as
redirect URIs, optional claims, or app permissions, accept the prompt when it
matches your tenant setup plan.

Expected checkpoint:

* Azure CLI login is valid.
* The `Agent 365 CLI` app registration exists.
* Required delegated permissions are present.
* Redirect URIs are configured.
* The signed-in user has the needed roles or receives a clear admin action.

If the CLI reports that the `Agent 365 CLI` app is missing, ask an Application
Administrator or Global Administrator to create and consent it. The detailed
tenant app instructions are in [AGENT365-SETUP.md](./AGENT365-SETUP.md).

## Step 5 Review MCP tooling configuration

`ToolingManifest.json` controls which Microsoft 365 MCP servers this agent can
discover and attach. Check what is configured:

```bash
a365 develop list-configured
```

If you need to inspect the tenant catalog, run:

```bash
a365 develop list-available
```

For built-in Microsoft 365 tools, prefer canonical `McpServers.*.All` scopes on
the Agent 365 Tools resource where supported. The reference table and the
reasoning are in [AGENT365-SETUP.md](./AGENT365-SETUP.md#2f-use-the-canonical-mcpserversall-scopes-word-onedrive-excel-teams-etc).

Do not run `a365 setup permissions mcp` yet if the blueprint does not exist. MCP
permission setup needs the blueprint ID from Entra or from
`a365.generated.config.json`.

## Step 6 Create or reuse the Agent 365 blueprint

Preview blueprint creation first:

```bash
a365 setup blueprint -n <agent-name> --dry-run
```

If the plan looks correct and you do not have a deployed HTTPS endpoint yet,
create the blueprint without registering an endpoint:

```bash
a365 setup blueprint -n <agent-name> --no-endpoint
```

If you already have the deployed messaging endpoint, create the blueprint and
register it in the same step:

```bash
a365 setup blueprint -n <agent-name> --messaging-endpoint https://<host>/api/messages
```

Expected output:

* Blueprint application created or reused.
* Blueprint service principal created or reused.
* Client secret created or available.
* Setup summary includes IDs you will need later.

> [!IMPORTANT]
> If the CLI prints a blueprint client secret, copy it immediately into a secure
> secret store. Do not commit it, paste it into documentation, or leave it in
> shared logs. If the secret is exposed, rotate it before using the blueprint in
> production.

Create the local Agent 365 config from the example before setup:

```bash
cp a365.config.example.json a365.config.json
```

Then update `a365.config.json` for your tenant and agent name. Keep this file
local-only; do not commit participant-specific IDs or names.

Save these generated files locally if they are created:

* `a365.config.json`
* `a365.generated.config.json`

These files contain resolved IDs for later CLI operations. Treat generated
configuration with care because it can include sensitive tenant and app details.

## Step 7 Configure MCP permissions

After the blueprint exists, dry-run MCP permission setup:

```bash
a365 setup permissions mcp -n <agent-name> --dry-run
```

If the dry run references the expected blueprint and scopes, apply the MCP
permissions:

```bash
a365 setup permissions mcp -n <agent-name>
```

You can also use the long option when supported by your installed CLI:

```bash
a365 setup permissions mcp --agent-name <agent-name>
```

Restart the agent process after MCP permission changes. MCP discovery happens
on the first request after startup.

## Step 8 Configure Bot API permissions

After MCP permissions are configured, configure Messaging Bot API permissions.
The Agent 365 CLI help lists this as the next required permission step before
final blueprint-based registration.

Dry-run Bot API permission setup first:

```bash
a365 setup permissions bot -n <agent-name> --dry-run
```

If the dry run references the expected blueprint, apply the Bot API permissions:

```bash
a365 setup permissions bot -n <agent-name>
```

You can also use the long option when supported by your installed CLI:

```bash
a365 setup permissions bot --agent-name <agent-name>
```

Expected result:

* Messaging Bot API OAuth2 grants are configured.
* Inheritable permissions are configured on the blueprint.
* If tenant-wide OAuth2 consent requires a Global Administrator, the CLI prints
   an admin-consent URL or PowerShell fallback for an administrator to run.

> [!NOTE]
> Run `a365 setup permissions mcp` before `a365 setup permissions bot`. The CLI
> reports MCP permissions as a prerequisite for Bot API permissions.

## Step 9 Finalize blueprint-based setup and registration

For this blueprint-based agent flow, registration is handled by
`a365 setup all`. Do not use `a365 publish` as the registration step. Current
Agent 365 CLI versions report:

```text
Blueprint-based agent registration is handled by 'a365 setup all'.
Nothing to publish for blueprint-based agents.
```

Preview the full setup first:

```bash
a365 setup all --agent-name <agent-name> --dry-run
```

Then run setup:

```bash
a365 setup all --agent-name <agent-name>
```

Expected result:

* Prerequisites are validated.
* Blueprint is created or reused.
* Inheritable permissions are configured.
* Blueprint permission grants are already granted or configured.
* Agent identity is created.
* Agent registration is registered.
* Project settings are written to `.env` and local Agent 365 config files.

For a non-M365 agent run, the CLI may report:

```text
Messaging endpoint skipped (non-M365 agent)
```

That is expected. Register the deployed endpoint later after Azure Container
Apps has a public HTTPS URL. If you want setup to register an M365 messaging
endpoint in the same command, use `--m365` with `--messaging-endpoint` after you
have the endpoint URL.

> [!IMPORTANT]
> `a365 setup all` may create a new blueprint client secret and stamp project
> settings into `.env`. Keep `.env` out of source control, store secrets in a
> secure secret store, and rotate any secret that appears in shared terminal
> output or logs.

## Step 10 Deploy the host to Azure Container Apps

This repo's production-style path uses `azd`, Bicep, Azure Container Apps, ACR,
Log Analytics, and a system-assigned managed identity.

Sign in to Azure Developer CLI:

```bash
azd auth login
```

Create an `azd` environment:

```bash
azd env new <agent-name>
```

Set the Azure region:

```bash
azd env set AZURE_LOCATION <azure-location>
```

Set the Azure OpenAI or Foundry values:

```bash
azd env set AZURE_OPENAI_ACCOUNT_NAME <aoai-account-name>
azd env set AZURE_OPENAI_RESOURCE_GROUP <aoai-resource-group>
azd env set AZURE_OPENAI_ENDPOINT <aoai-endpoint>
azd env set AZURE_OPENAI_DEPLOYMENT <aoai-deployment>
azd env set AZURE_OPENAI_API_VERSION <aoai-api-version>
```

Optional: set a custom workload resource group name:

```bash
azd env set AZURE_RESOURCE_GROUP rg-<agent-name>
```

Run the first deployment in anonymous mode:

```bash
azd up
```

Expected resources:

* Resource group
* Log Analytics workspace
* Azure Container Apps environment
* Azure Container Registry
* Container App with system-assigned managed identity
* Role assignment from the container app identity to Azure OpenAI

The Bicep templates grant the managed identity the `Cognitive Services OpenAI
User` role on the configured Azure OpenAI account. You need permission to
create that role assignment.

## Step 11 Register the deployed endpoint with the blueprint

Get the deployed Container App FQDN:

```bash
FQDN=$(azd env get-values | grep AGENT_FQDN | cut -d= -f2 | tr -d '"')
```

Register the messaging endpoint:

```bash
a365 setup blueprint --agent-name <agent-name> --endpoint-only --messaging-endpoint "https://$FQDN/api/messages"
```

Verify the health endpoint:

```bash
curl "https://$FQDN/api/health"
```

Expected result:

```json
{"status":"ok","agent_type":"AgentFrameworkAgent","agent_initialized":true}
```

## Step 12 Enable production agentic authentication

The first deployment is intentionally anonymous so the endpoint exists before
the blueprint is bound to it. After the blueprint is ready, feed the blueprint
credentials back into the `azd` environment.

Read the blueprint client and tenant IDs:

```bash
CLIENT_ID=$(python -c "import json; print(json.load(open('a365.generated.config.json'))['agentBlueprintId'])")
TENANT_ID=$(python -c "import json; print(json.load(open('a365.generated.config.json'))['tenantId'])")
```

Store them in the `azd` environment:

```bash
azd env set BLUEPRINT_CLIENT_ID "$CLIENT_ID"
azd env set BLUEPRINT_TENANT_ID "$TENANT_ID"
```

Store the blueprint client secret as an `azd` secret:

```bash
azd env set --secret BLUEPRINT_CLIENT_SECRET "$(a365 setup blueprint --agent-name <agent-name> --show-secret)"
```

Redeploy with agentic authentication enabled:

```bash
azd up
```

Confirm the auth mode changed:

```bash
azd env get-values | grep AGENT_AUTH_MODE
```

Expected result:

```text
AGENT_AUTH_MODE="agentic"
```

## Step 13 Verify the running Container App

Get the resource names from `azd`:

```bash
azd env get-values | grep -E 'AGENT_FQDN|AGENT_RESOURCE_GROUP|AGENT_CONTAINER_APP_NAME|AGENT_AUTH_MODE'
```

Stream logs if the app does not respond:

```bash
RESOURCE_GROUP=$(azd env get-values | grep AGENT_RESOURCE_GROUP | cut -d= -f2 | tr -d '"')
CONTAINER_APP=$(azd env get-values | grep AGENT_CONTAINER_APP_NAME | cut -d= -f2 | tr -d '"')
az containerapp logs show --resource-group "$RESOURCE_GROUP" --name "$CONTAINER_APP" --follow
```

Expected runtime log patterns:

* `AgentFrameworkAgent` initializes successfully.
* `OpenAIChatClient (Azure) created` appears.
* MCP allowlist logs show kept and dropped servers.
* `/api/health` returns `200`.

## Step 14 Create an agent instance

Do not run `a365 publish` for this blueprint-based agent registration path.
`a365 setup all --agent-name <agent-name>` handles agent registration.

Complete the browser-based tenant actions that apply to your tenant process:

1. Open the Teams Developer Portal blueprint configuration page if your tenant
   requires manual review.
2. Set the agent type to API based.
3. Set the notification URL or messaging endpoint to `https://<fqdn>/api/messages`.
4. Save the blueprint configuration.
5. Upload or approve the custom agent in the Microsoft 365 admin center.
6. Configure who can activate or request the agent.
7. Create an agent instance from Teams.
8. Start a Teams chat with the agent instance and send a message.

The created instance is a real agent identity in your tenant. Every instance
created from the same blueprint calls the same `/api/messages` endpoint.

## Step 15 Test the main scenarios

Use these prompts and events to validate the full setup.

| Scenario | How to test | Expected result |
| ---------- | ------------- | ----------------- |
| Basic chat | Send `Hello, can you help me?` | Agent replies with a normal chat response |
| User identity | Send any Teams message | Logs show display name, user ID, and AAD object ID when available |
| Typing indicator | Send a prompt that takes several seconds | Teams shows typing while the agent works |
| MCP tools | Ask about a task that needs configured M365 data | Agent attempts MCP tool discovery and invocation |
| Email notification | Trigger or mock an email notification | Agent produces an email-style response body |
| Word comment notification | Trigger or mock a Word comment notification | Agent retrieves context and responds to the comment |
| Health check | Call `/api/health` | Endpoint returns `status: ok` |

## Normal development loop

Use the smallest command for the change you made.

| Change | Command |
| -------- | --------- |
| Python source only | `azd deploy` |
| Bicep or infrastructure only | `azd provision` |
| Source and infrastructure | `azd up` |
| MCP server list or scopes | `a365 setup permissions mcp --agent-name <agent-name>` then restart the host |
| Bot API permissions | `a365 setup permissions bot --agent-name <agent-name>` |
| Blueprint-based registration | `a365 setup all --agent-name <agent-name>` |
| Blueprint endpoint changed | `a365 setup blueprint --agent-name <agent-name> --endpoint-only --messaging-endpoint <url>` |
| Local Playground settings changed | Restart the debug session |

## Troubleshooting

### `a365` command not found

Add the .NET global tools directory to `PATH`:

```bash
echo 'export PATH="$HOME/.dotnet/tools:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

### `Settings file DotnetToolSettings.xml was not found`

Install the .NET 8 runtime or SDK, then retry the `dotnet tool install` or
`dotnet tool update` command.

### Agent 365 requirements says PowerShell is not available

On macOS, install PowerShell 7 with Homebrew:

```bash
brew install powershell
```

Verify it is available on `PATH`:

```bash
pwsh --version
```

Then rerun the requirements check:

```bash
a365 setup requirements
```

If Homebrew reports that `powershell` is unavailable as a cask, use the formula
command above. Stable PowerShell is installed from Homebrew core, not from the
old cask name, on current Homebrew versions.

If Homebrew reports a `dotnet` symlink conflict but `pwsh --version` works, you
can continue. Only fix the symlink if `pwsh` or `dotnet` is actually broken.

### Agent cannot connect to Azure OpenAI

Check these values:

```bash
azd env get-values | grep AZURE_OPENAI
```

For Container Apps, confirm the endpoint is the resource root and that the
managed identity has `Cognitive Services OpenAI User` on the Azure OpenAI or
Foundry account.

### Container App health check fails

Check that the app listens on `0.0.0.0:3978` and that the image contains the
current source code. The provided `Dockerfile` sets `HOST=0.0.0.0` and
`PORT=3978`.

### MCP tools fail with consent or audience errors

Review `ToolingManifest.json` and prefer canonical `McpServers.*.All` scopes
where supported. Re-run MCP permissions and restart the app:

```bash
a365 setup permissions mcp --agent-name <agent-name>
```

### Blueprint setup reports OAuth2 permission grant failed

During blueprint setup, you may see an error like this:

```text
OAuth2 permission grant failed ... Authorization_RequestDenied
Failed to configure Microsoft Graph inheritable permissions
```

This means the blueprint was created, but the signed-in user or client app did
not have enough privilege to create or update the inheritable OAuth2 permission
grant. Agent instances may not be able to access Microsoft Graph resources until
the missing grants are configured.

Use this recovery flow:

1. Confirm the blueprint exists:

   ```bash
   a365 setup blueprint -n <agent-name> --dry-run
   ```

2. Configure MCP permissions:

   ```bash
   a365 setup permissions mcp -n <agent-name> --dry-run
   a365 setup permissions mcp -n <agent-name>
   ```

3. Configure Bot API permissions:

   ```bash
   a365 setup permissions bot -n <agent-name> --dry-run
   a365 setup permissions bot -n <agent-name>
   ```

4. If the CLI prints an admin-consent URL or PowerShell fallback, have a Global
   Administrator complete that action.

Also confirm the `Agent 365 CLI` client app has the required consented
permissions, including `AgentIdentityBlueprint.ReadWrite.All`. Re-run the
requirements check after any admin changes:

```bash
a365 setup requirements
```

### `a365 publish` says nothing to publish

For blueprint-based agents, current CLI versions require an agent name for
`a365 publish`, but then report that registration is handled by setup:

```text
Blueprint-based agent registration is handled by 'a365 setup all'.
Nothing to publish for blueprint-based agents.
```

Use this command instead:

```bash
a365 setup all --agent-name <agent-name>
```

This creates or reuses the blueprint, configures permissions, creates the agent
identity, registers the agent, and writes project settings.

### Notifications return connector errors

Some Agent 365 notification channels require buffered expected replies instead
of connector POST replies. This repo sets `delivery_mode` to `expect_replies`
inside the notification handler. Check logs around `notification:` and
`buffered_reply_activities`.

### Local Playground starts but the agent errors immediately

Check that `.env` was created by the Playground deploy step and includes:

```text
AZURE_OPENAI_ENDPOINT=<value>
AZURE_OPENAI_DEPLOYMENT=<value>
AZURE_OPENAI_API_VERSION=<value>
```

The file `env/.env.playground.user` uses `AZURE_OPENAI_DEPLOYMENT_NAME`; the
Playground task maps it to runtime variable `AZURE_OPENAI_DEPLOYMENT`.

### Startup fails with no service connection configuration

This error appears during host startup:

```text
ValueError: No service connection configuration provided.
```

The Microsoft Agents SDK connection manager requires a `SERVICE_CONNECTION`
entry in the loaded environment, even when `AUTH_HANDLER_NAME` is not set and
the host is running in anonymous local mode. Directly running
`python start_with_generic_host.py` fails if `.env` is missing or if the
connection keys use the older lower-camel shape.

First check whether `.env` exists:

```bash
ls -la .env
```

For direct local startup, `.env` must include the uppercase SDK keys:

```text
USE_AGENTIC_AUTH=false
CONNECTIONS__SERVICE_CONNECTION__SETTINGS__CLIENTID=
CONNECTIONS__SERVICE_CONNECTION__SETTINGS__TENANTID=
CONNECTIONS__SERVICE_CONNECTION__SETTINGS__CLIENTSECRET=
CONNECTIONS__SERVICE_CONNECTION__SETTINGS__SCOPES=https://graph.microsoft.com/.default
CONNECTIONSMAP__0__SERVICEURL=*
CONNECTIONSMAP__0__CONNECTION=SERVICE_CONNECTION
```

The empty client values are acceptable only for local anonymous startup. For
production agentic auth, replace them with the blueprint client ID, tenant ID,
and client secret as described in the production setup steps.

Also confirm your local model settings are present:

```text
AZURE_OPENAI_ENDPOINT=<value>
AZURE_OPENAI_DEPLOYMENT=<value>
AZURE_OPENAI_API_VERSION=<value>
```

If you use Microsoft 365 Agents Playground, run the Playground deploy task again
after updating `m365agents.playground.yml` so it regenerates `.env` with the
uppercase connection keys.

## Cleanup

Delete Azure resources created by `azd`:

```bash
azd down --purge
```

Use Agent 365 cleanup commands only when you intentionally want to remove the
blueprint or Azure resources managed by the Agent 365 CLI. Confirm the target
tenant and agent name before running destructive cleanup.

## Completion checklist

You are done when each item is complete:

* Local Python environment is created and dependencies install successfully.
* Microsoft 365 Agents Playground can send a message to the local agent.
* `a365 setup requirements` passes or lists only approved admin follow-ups.
* `a365 setup blueprint -n <agent-name>` creates or reuses the blueprint.
* `a365 setup permissions mcp -n <agent-name>` configures MCP permissions.
* `a365 setup permissions bot -n <agent-name>` configures Bot API permissions.
* `a365 setup all --agent-name <agent-name>` creates the agent identity and registers the agent.
* `azd up` deploys the Container App and `/api/health` returns `status: ok`.
* The deployed `/api/messages` endpoint is registered with the blueprint.
* `AGENT_AUTH_MODE` is `agentic` after the second `azd up`.
* A Teams agent instance can be created and responds to a test message.
