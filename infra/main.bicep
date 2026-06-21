// main.bicep — subscription-scope entry point. Creates a NEW resource group
// for the agent's workload resources, then delegates to resources.bicep for
// the Container App + supporting infra. The existing Azure OpenAI / Foundry
// account is referenced (not created); a role assignment grants the
// Container App's system-assigned MI access to it.
//
// Run via `azd up`. azd injects AZURE_ENV_NAME and AZURE_LOCATION; the rest
// of the parameters come from `azd env set ...` (see infra/main.parameters.json).

targetScope = 'subscription'

// ----- Parameters ----------------------------------------------------------

@description('Environment name (azd env). Used as the new resource group name suffix and a resource-name token.')
param environmentName string

@description('Azure region for the new resource group and all workload resources.')
param location string

@description('Name of the resource group to create for the workload.')
param resourceGroupName string = 'rg-${environmentName}'

@description('Existing Azure OpenAI / Foundry account name to grant the agent MI access to.')
param azureOpenAiAccountName string = 'terenceaifoundry-resource'

@description('Subscription ID containing the existing Azure OpenAI / Foundry account. Defaults to the deployment subscription.')
param azureOpenAiSubscriptionId string = subscription().subscriptionId

@description('Resource group containing the existing AOAI / Foundry account. The role assignment is created here.')
param azureOpenAiResourceGroup string = 'rg-admin-terenceaifoundry'

@description('Public endpoint of the AOAI / Foundry account. Use the **resource root** (no trailing `/openai/v1`) — `OpenAIChatClient(azure_endpoint=...)` appends `/openai/v1/responses` itself, so a `.../openai/v1` value produces a doubled path that 404s.')
param azureOpenAiEndpoint string = 'https://terenceaifoundry-resource.openai.azure.com'

@description('Model deployment name on the AOAI / Foundry account.')
param azureOpenAiDeployment string = 'gpt-5.4'

@description('Azure OpenAI API version the chat client will use. The `/openai/v1/responses` endpoint on some Foundry accounts only accepts the rolling `preview` literal; datestamped previews (e.g. `2025-04-01-preview`) return `API version not supported`.')
param azureOpenAiApiVersion string = 'preview'

@description('Container CPU (cores). 0.5 is the smallest sane size for Python aiohttp.')
param containerCpu string = '0.5'

@description('Container memory.')
param containerMemory string = '1.0Gi'

@description('Min replicas for autoscale. Must be >= 1 — the agent keeps in-memory per-channel sessions, so scaling to zero would drop conversation history on cold start.')
@minValue(1)
param minReplicas int = 1

@description('Max replicas for autoscale.')
@minValue(1)
param maxReplicas int = 3

// ----- Optional Agent 365 blueprint auth -----------------------------------
// Leave empty on the first `azd up` (the Container App will boot in anonymous
// mode), then populate after `a365 setup all` + `a365 setup blueprint --show-secret`
// and re-run `azd up` / `azd provision`.

@description('Blueprint app (client) ID from a365.generated.config.json. Leave empty for anonymous mode.')
param blueprintClientId string = ''

@description('Tenant ID for the blueprint app. Defaults to the deployment subscription tenant.')
param blueprintTenantId string = ''

@description('Blueprint client secret. Print with `a365 setup blueprint --agent-name <name> --show-secret`.')
@secure()
param blueprintClientSecret string = ''

@description('Initial container image reference for the first provision. Must listen on the Container App ingress target port before azd deploy replaces it with the real image.')
param initialImage string = 'mcr.microsoft.com/dotnet/samples:aspnetapp'

// ----- Resource group ------------------------------------------------------

resource workloadRg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: {
    'azd-env-name': environmentName
  }
}

// ----- Workload resources --------------------------------------------------

module workload 'resources.bicep' = {
  name: 'workload'
  scope: workloadRg
  params: {
    environmentName: environmentName
    location: location
    azureOpenAiAccountName: azureOpenAiAccountName
    azureOpenAiSubscriptionId: azureOpenAiSubscriptionId
    azureOpenAiResourceGroup: azureOpenAiResourceGroup
    azureOpenAiEndpoint: azureOpenAiEndpoint
    azureOpenAiDeployment: azureOpenAiDeployment
    azureOpenAiApiVersion: azureOpenAiApiVersion
    containerCpu: containerCpu
    containerMemory: containerMemory
    minReplicas: minReplicas
    maxReplicas: maxReplicas
    blueprintClientId: blueprintClientId
    blueprintTenantId: blueprintTenantId
    blueprintClientSecret: blueprintClientSecret
    initialImage: initialImage
  }
}

// ----- Outputs -------------------------------------------------------------
// `azd env get-values` reads these. AGENT_FQDN is what you bind to the
// Agent 365 blueprint via `a365 setup blueprint --endpoint-only`.

output AGENT_FQDN string = workload.outputs.AGENT_FQDN
output AGENT_RESOURCE_GROUP string = workloadRg.name
output AGENT_CONTAINER_APP_NAME string = workload.outputs.AGENT_CONTAINER_APP_NAME
output AGENT_PRINCIPAL_ID string = workload.outputs.AGENT_PRINCIPAL_ID
output AGENT_AUTH_MODE string = workload.outputs.AGENT_AUTH_MODE
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = workload.outputs.AZURE_CONTAINER_REGISTRY_ENDPOINT
output AZURE_CONTAINER_REGISTRY_NAME string = workload.outputs.AZURE_CONTAINER_REGISTRY_NAME
