---
title: Agent 365 AI Teammate Hands-On Lab
description: Simplified workshop guide for creating an Agent 365 AI Teammate blueprint and deploying the backend messaging endpoint from a VS Code dev container
author: Microsoft
ms.date: 2026-06-19
ms.topic: tutorial
---

## Agent 365 AI Teammates Hands-On Lab

By the end of this lab, you will have:

* Created or reused an Agent 365 AI Teammate blueprint.
* Published the agent manifest to the tenant catalog.
* Deployed the Python backend to Azure Container Apps with `azd`.
* Registered the Container Apps `/api/messages` endpoint on the blueprint.
* Enabled agentic authentication so Teams messages are accepted by the backend.
* Verified the live endpoint and checked logs for incoming Teams activity.

This lab uses the repository's VS Code Dev Container so attendees can run the
same Linux-based toolchain without installing every CLI on their local machine.
The Dev Container already includes the required command-line tools, including
`az`, `azd`, `a365`, PowerShell, Python, and the project virtual environment.
Do not spend workshop time installing tools manually unless a validation step
fails.

## Before attendees start

The facilitator should confirm these tenant and Azure prerequisites before the
workshop:

* The tenant is enrolled in the Agent 365 preview program.
* Attendees have the required Entra role, usually Agent ID Developer.
* Attendees have access to the target Azure subscription.
* The tenant has the one-time `Agent 365 CLI` app registration configured.
* Microsoft 365 tool service principals have been provisioned by an admin.
* An Azure OpenAI or Azure AI Foundry resource and deployment are available.
* The repository opens successfully in the VS Code dev container.

## Keep secrets out of Git

Generated Agent 365 state files can contain client secrets. They should remain
local only.

The repository should ignore these files:

```text
a365.generated.config.json
a365.generated.config.*.json
.env
.azure/
```

Before pushing a branch, verify that no generated config file is tracked:

```bash
git ls-files 'a365.generated.config*.json'
git log --oneline --all -- 'a365.generated.config*.json'
```

Both commands should produce no output.

## Configuration files to review before deployment

Review these files before you create or deploy a lab agent. Most lab settings
are supplied through shell variables and `azd env set`, but these files explain
where the values land and which files should stay local.

### Agent 365 configuration

`a365.config.json` is the user-managed Agent 365 configuration. It is local-only
and should not be committed. Create it from the example before running setup:

```bash
cp a365.config.example.json a365.config.json
```

Then update these values so they match the tenant and agent name you plan to use:

* `tenantId`
* `clientAppId`
* `agentIdentityDisplayName`
* `agentBlueprintDisplayName`
* `agentDescription`
* `aiTeammate`

For this AI Teammate lab path, keep `aiTeammate` set to `true`. The display
name values should use the same base name as `AGENT_NAME`, such as
`$AGENT_NAME Identity` and `$AGENT_NAME Blueprint`. If you change `AGENT_NAME`,
rerun the setup commands so the Agent 365 CLI writes fresh local state for that
agent.

`a365.generated.config.json` is CLI-managed generated state. It can contain
resource IDs and the blueprint client secret. Do not edit it by hand and do not
commit it. The lab only reads this file after `a365 setup all` succeeds.

### Manifest files

`manifest/manifest.json` is the tenant catalog package metadata. Review and
update the attendee-facing values in Step 6 before publishing the package.
Common fields include `name`, `description`, `developer`, and `version`.

`manifest/agenticUserTemplateManifest.json` is used with the manifest package
for the agentic user template. The CLI can stamp blueprint-related IDs into the
manifest files, so review the generated values after setup and before upload.

### Azure deployment configuration

`azure.yaml` defines the `azd` application, the Python Container Apps service,
the Docker build settings, and the post-deploy reminder to register the public
`/api/messages` endpoint. Leave this file unchanged for the standard lab unless
you intentionally change the deployment shape, Dockerfile path, or build mode.

`infra/main.parameters.json` maps `azd` environment values into the Bicep
deployment. For the lab, prefer `azd env set` instead of editing this file.
The key values set later are `AZURE_LOCATION`, `AZURE_SUBSCRIPTION_ID`,
`AZURE_RESOURCE_GROUP`, the `AZURE_OPENAI_*` values, and the `BLUEPRINT_*`
values used for agentic authentication.

`infra/main.bicep` and `infra/resources.bicep` define the Azure resources,
including Azure Container Apps, Azure Container Registry, Log Analytics, managed
identity, and runtime environment variables. Leave these files unchanged unless
the facilitator asks you to alter the infrastructure design.

`.azure/<environment>/.env` is local `azd` environment state created by
`azd env new` and `azd env set`. It stores deployment settings and later stores
the blueprint client secret value. Keep `.azure/` ignored by Git.

### Local Playground configuration

`m365agents.playground.yml` and `env/.env.playground.user` are for the
Microsoft 365 Agents Playground path. They are useful for local testing, but the
Azure Container Apps deployment in this lab uses `azd` and the `azure.yaml` /
`infra/` path instead.

## Step 1: Open the repo in the VS Code Dev Container

The repository includes a Dev Container configuration in
`.devcontainer/devcontainer.json`. VS Code uses this file to build and connect
to a container with a well-defined runtime and tool stack for the lab.

Before opening the container, confirm these local prerequisites:

* [Visual Studio Code](https://code.visualstudio.com/) is installed.
* [Docker Desktop](https://www.docker.com/products/docker-desktop) or another
  Docker-compatible runtime is installed and running.
* [Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers)
  is installed in VS Code.

For a visual walkthrough, see the referenced
[VS Code Dev Containers video](https://youtu.be/X7guekGZM20?si=AjYbU_IAqK325oWE&t=83).
For deeper reference, see the official VS Code guide:
[Developing inside a container](https://code.visualstudio.com/docs/devcontainers/containers).

Open the repository in the Dev Container:

1. Start Docker and wait until it is running.
2. Open this repository folder in VS Code.
3. If VS Code prompts you to reopen the folder in a container, select
   **Reopen in Container**.
4. If no prompt appears, open the Command Palette with `F1` or `Ctrl+Shift+P`,
   then run **Dev Containers: Reopen in Container**.
5. Wait for the container build and `postCreateCommand` bootstrap to finish.
   The first build can take several minutes because it installs and configures
   SDKs, CLIs, PowerShell modules, and Python dependencies.
6. Open a new VS Code terminal. It should now run inside the container.

After the terminal opens, start from the repository root:

```bash
cd /workspaces/a365-maf
```

Quickly verify the expected tools are available:

```bash
a365 --version
az version -o table
azd version
python --version
pwsh --version
```

If these commands work, skip all installation instructions from the longer setup
guide.

If an expected tool is missing after the container starts, reload the terminal
profile:

```bash
source ~/.bashrc
```

If the tool is still missing, rerun the Dev Container bootstrap:

```bash
bash .devcontainer/setup-tools.sh
```

If the container still does not behave as expected, rebuild it from VS Code:

```text
Dev Containers: Rebuild Container Without Cache
```

> [!NOTE]
> VS Code Dev Containers can reuse local Git credentials inside the container.
> HTTPS credentials from a local credential helper are usually reused
> automatically. SSH-based Git workflows may require your local SSH agent to be
> running before you reopen the repo in the container.

## Step 2: Set lab variables

Choose a unique agent base name. Use lower-case letters, numbers, and hyphens.
The name should be short enough to fit Azure naming limits.

```bash
export AGENT_NAME="<your-unique-agent-name>"
export AZURE_LOCATION="southeastasia"
export AZURE_SUBSCRIPTION_ID="<your-subscription-id>"
```

Example:

```bash
export AGENT_NAME="sithu-a365-02"
export AZURE_LOCATION="southeastasia"
export AZURE_SUBSCRIPTION_ID="69ecbfc6-bfbb-4fa4-9933-a5ec21627a3f"
```

## Step 3: Sign in

Sign in to Azure CLI and Azure Developer CLI from inside the dev container:

```bash
az login --allow-no-subscriptions
az account set --subscription "$AZURE_SUBSCRIPTION_ID"
azd auth login
```

Confirm the active tenant and subscription:

```bash
az account show --query "{user:user.name, tenantId:tenantId, subscriptionId:id}" -o json
```

## Step 4: Validate Agent 365 prerequisites

Run the Agent 365 requirements check:

```bash
a365 setup requirements
```

The current dev container CLI validates the active Azure authentication context
and does not accept `--agent-name` on the `requirements` subcommand. If you see
`Unrecognized command or argument '--agent-name'`, rerun the command without
that flag.

Continue only when the command reports no failures. A Frontier preview warning
can be acceptable in the lab if the facilitator has already confirmed tenant
enrollment.

## Step 5: Create the AI Teammate blueprint

Run the AI Teammate setup command:

```bash
a365 setup all --aiteammate --agent-name "$AGENT_NAME"
```

For this lab path, the Agent 365 setup creates or reuses the blueprint and
configures permissions. The Python backend is deployed later with `azd`.

If the CLI reports that the blueprint already exists, continue. The setup
commands are idempotent and reuse resources by display name.

After setup completes, confirm the generated blueprint ID exists locally:

```bash
python3 -c "import json; print(json.load(open('a365.generated.config.json'))['agentBlueprintId'])"
```

## Step 6: Review and publish the manifest

Open `manifest/manifest.json` and update the attendee-facing details:

* `name.short`
* `name.full`
* `description.short`
* `description.full`
* `developer.name`
* `developer.websiteUrl`
* `developer.privacyUrl`
* `developer.termsOfUseUrl`
* `version`

Keep this value unchanged for this preview manifest:

```json
"manifestVersion": "devPreview"
```

Publish the manifest:

```bash
a365 publish
```

## Step 7: Create the azd environment

Create an `azd` environment for the backend deployment:

```bash
azd env new "$AGENT_NAME"
azd env set AZURE_LOCATION "$AZURE_LOCATION"
azd env set AZURE_SUBSCRIPTION_ID "$AZURE_SUBSCRIPTION_ID"
azd env set AZURE_RESOURCE_GROUP "rg-$AGENT_NAME"
```

If the environment already exists, select it instead:

```bash
azd env select "$AGENT_NAME"
```

If the workshop uses a shared Azure OpenAI or Azure AI Foundry resource, set the
expected values now. Adjust these values to match the facilitator-provided
resource:

```bash
azd env set AZURE_OPENAI_ACCOUNT_NAME "terenceaifoundry-resource"
azd env set AZURE_OPENAI_RESOURCE_GROUP "rg-admin-terenceaifoundry"
azd env set AZURE_OPENAI_ENDPOINT "https://terenceaifoundry-resource.openai.azure.com"
azd env set AZURE_OPENAI_DEPLOYMENT "gpt-5.4"
azd env set AZURE_OPENAI_API_VERSION "preview"
```

## Step 8: Deploy once to create the public endpoint

Deploy the backend with no blueprint credentials yet. This first pass creates
the Container App and produces the public FQDN.

```bash
azd up --no-prompt
```

Get the deployed endpoint:

```bash
FQDN=$(azd env get-values | grep AGENT_FQDN | cut -d= -f2 | tr -d '"')
echo "https://$FQDN/api/messages"
```

Verify the health endpoint:

```bash
curl "https://$FQDN/api/health"
```

Expected response:

```json
{"status": "ok", "agent_type": "AgentFrameworkAgent", "agent_initialized": true}
```

## Step 9: Register the backend endpoint with the blueprint

Bind the Container Apps messaging endpoint to the Agent 365 blueprint:

```bash
a365 setup blueprint --agent-name "$AGENT_NAME" --endpoint-only \
  --messaging-endpoint "https://$FQDN/api/messages"
```

The command should report that the endpoint was registered successfully.

## Step 10: Enable agentic authentication

Feed the blueprint ID, tenant ID, and blueprint client secret into the same
`azd` environment.

```bash
CLIENT_ID=$(python3 -c "import json; print(json.load(open('a365.generated.config.json'))['agentBlueprintId'])")
TENANT_ID=$(python3 -c "import json; print(json.load(open('a365.config.json'))['tenantId'])")
SECRET=$(python3 -c "import json; print(json.load(open('a365.generated.config.json'))['agentBlueprintClientSecret'])")

azd env set BLUEPRINT_CLIENT_ID "$CLIENT_ID"
azd env set BLUEPRINT_TENANT_ID "$TENANT_ID"
azd env set BLUEPRINT_CLIENT_SECRET "$SECRET"

unset SECRET
```

> [!NOTE]
> Some older instructions use `azd env set --secret`. The dev container version
> of `azd` used for this lab does not support that flag. Use
> `azd env set BLUEPRINT_CLIENT_SECRET "$SECRET"`. This stores the value in
> local `azd` state under `.azure/`, which must stay ignored by Git.

Redeploy so the Container App receives the agentic auth environment variables:

```bash
azd up --no-prompt
```

## Step 11: Verify the deployed auth configuration

Confirm the Container App is running and configured for the current blueprint:

```bash
RG=$(azd env get-values | awk -F= '/^AGENT_RESOURCE_GROUP=/{gsub(/"/,"",$2); print $2}')
APP=$(azd env get-values | awk -F= '/^AGENT_CONTAINER_APP_NAME=/{gsub(/"/,"",$2); print $2}')

az containerapp show -g "$RG" -n "$APP" \
  --query "{runningStatus:properties.runningStatus, latestReadyRevisionName:properties.latestReadyRevisionName, env:properties.template.containers[0].env[?name=='CLIENT_ID'||name=='TENANT_ID'||name=='AUTH_HANDLER_NAME'||name=='USE_AGENTIC_AUTH']}" \
  -o json
```

The `CLIENT_ID` should match the blueprint ID in
`a365.generated.config.json`.

Probe the endpoints again:

```bash
curl "https://$FQDN/api/health"
curl -i "https://$FQDN/api/messages"
```

The health endpoint should return `200`. The unauthenticated `/api/messages`
probe should return `401`, which is expected because Teams sends an authorized
POST.

## Step 12: Create and test an agent instance

Complete these steps in the browser:

1. Open the Microsoft 365 admin center.
2. Publish or approve the custom agent package for the tenant.
3. In Teams, find the published agent.
4. Create or request an instance.
5. Wait for the agent user account to appear in Teams.
6. Start a chat with the new agent user and send `hello`.

Every instance created from the same blueprint posts to the same backend
endpoint. The Python app uses the incoming activity metadata to distinguish
the human user and the agent instance.

## Step 13: Watch logs during the Teams test

Tail the Container App logs while sending a Teams message:

```bash
az containerapp logs show -g "$RG" -n "$APP" --tail 120 --follow
```

Useful success signals include:

```text
POST /api/messages HTTP/1.1" 200
Validating agent and setting up context
tenant_id=
agent_id=
Got it
```

Stop the log stream with `Ctrl+C`.

## Fast troubleshooting

If the Teams chat does not respond, check these items in order.

### Messages never reach the container

Run:

```bash
az containerapp logs show -g "$RG" -n "$APP" --tail 120 | grep '/api/messages' || true
```

If there is no `POST /api/messages`, re-register the endpoint:

```bash
a365 setup blueprint --agent-name "$AGENT_NAME" --endpoint-only \
  --messaging-endpoint "https://$FQDN/api/messages"
```

### Messages reach the container but return 401

Compare the deployed `CLIENT_ID` with the blueprint ID:

```bash
python3 -c "import json; print(json.load(open('a365.generated.config.json'))['agentBlueprintId'])"

az containerapp show -g "$RG" -n "$APP" \
  --query "properties.template.containers[0].env[?name=='CLIENT_ID'].value" \
  -o tsv
```

If the values differ, rerun Step 10 and Step 11.

### The agent starts but fails while answering

Check recent errors:

```bash
az containerapp logs show -g "$RG" -n "$APP" --tail 200 | grep -E 'Error|Exception|AADSTS|Failed|Invalid' || true
```

Common causes are missing Azure OpenAI permissions, incorrect model deployment
name, or MCP consent problems.

## Cleanup after the lab

Only run cleanup if the facilitator confirms the resources are no longer
needed.

Delete Azure resources created by `azd`:

```bash
azd down --purge
```

Do not run blueprint cleanup unless you intentionally want to remove the Agent
365 blueprint from the tenant.

```bash
a365 cleanup blueprint --agent-name "$AGENT_NAME"
```
