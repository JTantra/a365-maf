// resources.bicep — workload resources deployed inside the resource group
// created by main.bicep. Provisions the Container App, its environment, the
// container registry, Log Analytics, and a role assignment on the existing
// Foundry / Azure OpenAI account.
//
// All identity / Foundry parameters are passed in from main.bicep; this file
// has no defaults so the top-level Bicep template stays the single source
// of truth.

targetScope = 'resourceGroup'

// ----- Parameters ----------------------------------------------------------

@description('Environment name (azd env). Used as a resource-name suffix.')
param environmentName string

@description('Azure region for all resources.')
param location string

@description('Existing Azure OpenAI / Foundry account name to grant the MI access to.')
param azureOpenAiAccountName string

@description('Resource group containing the existing AOAI / Foundry account.')
param azureOpenAiResourceGroup string

@description('Public endpoint of the AOAI / Foundry account.')
param azureOpenAiEndpoint string

@description('Model deployment name on the AOAI / Foundry account.')
param azureOpenAiDeployment string

@description('Azure OpenAI API version the chat client will use.')
param azureOpenAiApiVersion string

@description('Container CPU (cores).')
param containerCpu string

@description('Container memory.')
param containerMemory string

@description('Min replicas for autoscale. Must be >= 1 — the agent keeps in-memory per-channel sessions, so scaling to zero would drop conversation history on cold start.')
@minValue(1)
param minReplicas int

@description('Max replicas for autoscale.')
@minValue(1)
param maxReplicas int

// ----- Optional Agent 365 blueprint auth -----------------------------------
// Leave empty on the first `azd up` — the Container App boots in anonymous
// mode so you can grab the FQDN and register it with the blueprint via
// `a365 setup blueprint --endpoint-only --messaging-endpoint`. Then populate
// these via `azd env set BLUEPRINT_*` and re-run `azd up` / `azd provision`
// to enable agentic auth end-to-end.

@description('Blueprint app (client) ID from a365.generated.config.json. Leave empty for anonymous mode.')
param blueprintClientId string = ''

@description('Tenant ID for the blueprint app. Defaults to the deployment subscription tenant.')
param blueprintTenantId string = ''

@description('Blueprint client secret. Print with `a365 setup blueprint --agent-name <name> --show-secret`.')
@secure()
param blueprintClientSecret string = ''

@description('Agent 365 agentic scope. Default is the public production scope; override for sovereign clouds.')
param agentic365Scope string = 'ea9ffc3e-8a23-4a7d-836d-234d7c7565c1/.default'

@description('Microsoft Graph scope the SDK connection requests when acting as the blueprint identity.')
param graphScope string = 'https://graph.microsoft.com/.default'

// ----- Naming --------------------------------------------------------------
// Resource names embed both the environment/agent name (`envToken`) for
// human readability and a deterministic hash (`resourceToken`) for global
// uniqueness across redeploys and tenants.
//
// `envToken`      — lowercase, alphanumeric only (hyphens/underscores
//                   stripped so ACR is happy), capped at 12 chars to leave
//                   room for the 13-char hash inside the strictest length
//                   limit (Container App / ACA env = 32 chars).
// `resourceToken` — 13-char `uniqueString` hash; survives moves across
//                   resource groups and keeps ACR's globally-unique
//                   constraint satisfied.

var envSanitized = toLower(replace(replace(replace(environmentName, '-', ''), '_', ''), ' ', ''))
var envToken = take(envSanitized, 12)
var resourceToken = toLower(uniqueString(subscription().id, resourceGroup().id, environmentName))
var tags = {
  'azd-env-name': environmentName
}

// ----- Log Analytics + Container Apps environment --------------------------

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'log-${envToken}-${resourceToken}'
  location: location
  tags: tags
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
  }
}

resource containerAppsEnv 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: 'cae-${envToken}-${resourceToken}'
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
  }
}

// ----- Container Registry --------------------------------------------------

resource registry 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' = {
  name: 'acr${envToken}${resourceToken}'
  location: location
  tags: tags
  sku: { name: 'Basic' }
  properties: {
    adminUserEnabled: false
  }
}

// ----- Container App -------------------------------------------------------
// Image starts as a placeholder; `azd deploy` overrides it via the
// `containerapp update --image` call after pushing to the registry.

@description('Initial container image reference. Override on first provision when a real image already exists in ACR (k8se/quickstart listens on port 80 and fails the 3978 probe).')
param initialImage string = 'mcr.microsoft.com/k8se/quickstart:latest'
var placeholderImage = initialImage
var resolvedTenantId = empty(blueprintTenantId) ? subscription().tenantId : blueprintTenantId
var authEnabled = !empty(blueprintClientId) && !empty(blueprintClientSecret)

// Container env always carries the basics (port + Foundry). Auth-related
// vars are appended only when the blueprint credentials have been supplied.
var baseEnv = [
  { name: 'HOST', value: '0.0.0.0' }
  { name: 'PORT', value: '3978' }
  { name: 'AZURE_OPENAI_ENDPOINT', value: azureOpenAiEndpoint }
  { name: 'AZURE_OPENAI_DEPLOYMENT', value: azureOpenAiDeployment }
  { name: 'AZURE_OPENAI_API_VERSION', value: azureOpenAiApiVersion }
  // Force the A365 tooling SDK into "production" mode so MCP server discovery
  // goes through the platform gateway (which uses the blueprint credentials
  // via OBO exchange), not the local ToolingManifest.json + BEARER_TOKEN_*
  // fallback. The tooling SDK's `is_development_environment()` defaults to
  // "Development" when no env var is set; without this override, the
  // Container App skips attaching an Authorization header on MCP requests and
  // gets 400 "Tenant id is invalid" from the MCP service.
  { name: 'PYTHON_ENVIRONMENT', value: 'Production' }
  // Ship traces/metrics/logs to the A365 observability backend. Without this
  // the microsoft-opentelemetry distro generates spans locally but does not
  // export them, so the A365 dashboard for this agent will be empty.
  { name: 'ENABLE_A365_OBSERVABILITY_EXPORTER', value: 'true' }
]

var authEnv = authEnabled ? [
  { name: 'AUTH_HANDLER_NAME', value: 'AGENTIC' }
  { name: 'USE_AGENTIC_AUTH', value: 'true' }
  { name: 'CLIENT_ID', value: blueprintClientId }
  { name: 'TENANT_ID', value: resolvedTenantId }
  { name: 'CLIENT_SECRET', secretRef: 'blueprint-client-secret' }
  { name: 'CONNECTIONS__SERVICE_CONNECTION__SETTINGS__CLIENTID', value: blueprintClientId }
  { name: 'CONNECTIONS__SERVICE_CONNECTION__SETTINGS__TENANTID', value: resolvedTenantId }
  { name: 'CONNECTIONS__SERVICE_CONNECTION__SETTINGS__CLIENTSECRET', secretRef: 'blueprint-client-secret' }
  { name: 'CONNECTIONS__SERVICE_CONNECTION__SETTINGS__SCOPES', value: graphScope }
  { name: 'AGENTAPPLICATION__USERAUTHORIZATION__HANDLERS__AGENTIC__SETTINGS__TYPE', value: 'AgenticUserAuthorization' }
  { name: 'AGENTAPPLICATION__USERAUTHORIZATION__HANDLERS__AGENTIC__SETTINGS__SCOPES', value: agentic365Scope }
  { name: 'AGENTAPPLICATION__USERAUTHORIZATION__HANDLERS__AGENTIC__SETTINGS__ALTERNATEBLUEPRINTCONNECTIONNAME', value: 'SERVICE_CONNECTION' }
  { name: 'CONNECTIONSMAP_0_SERVICEURL', value: '*' }
  { name: 'CONNECTIONSMAP_0_CONNECTION', value: 'SERVICE_CONNECTION' }
] : []

var authSecrets = authEnabled ? [
  { name: 'blueprint-client-secret', value: blueprintClientSecret }
] : []

resource agentApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: 'ca-${envToken}-${resourceToken}'
  location: location
  tags: union(tags, {
    // Marks this Container App as the deploy target for the 'agent' service
    // declared in azure.yaml. Required for `azd deploy` to find it.
    'azd-service-name': 'agent'
  })
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    managedEnvironmentId: containerAppsEnv.id
    configuration: {
      ingress: {
        external: true
        targetPort: 3978
        transport: 'auto'
        allowInsecure: false
      }
      registries: [
        {
          server: registry.properties.loginServer
          identity: 'system'
        }
      ]
      secrets: authSecrets
    }
    template: {
      containers: [
        {
          name: 'agent'
          image: placeholderImage
          resources: {
            cpu: json(containerCpu)
            memory: containerMemory
          }
          env: concat(baseEnv, authEnv)
        }
      ]
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
      }
    }
  }
}

// ----- Role assignments ----------------------------------------------------
// Built-in role definition IDs (constants):
//   AcrPull                         = 7f951dda-4ed3-4680-a7ca-43fe172d538d
//   Cognitive Services OpenAI User = 5e0bd9bd-7b93-4f28-af87-19fc36ad61bd

var acrPullRoleId = '7f951dda-4ed3-4680-a7ca-43fe172d538d'
var cogSvcOpenAIUserRoleId = '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'

// Let the Container App MI pull images from our registry.
resource acrPullAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: registry
  name: guid(registry.id, agentApp.id, acrPullRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleId)
    principalId: agentApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Grant the MI Cognitive Services OpenAI User on the existing AOAI / Foundry
// account. The submodule targets that account's resource group so the role
// assignment is created in the right place even when it lives in a different
// RG than the workload.
module aoaiRoleAssignment 'modules/aoai-role-assignment.bicep' = {
  name: 'aoai-role-assignment'
  scope: resourceGroup(azureOpenAiResourceGroup)
  params: {
    aoaiAccountName: azureOpenAiAccountName
    principalId: agentApp.identity.principalId
    roleDefinitionId: cogSvcOpenAIUserRoleId
  }
}

// ----- Outputs -------------------------------------------------------------

output AGENT_FQDN string = agentApp.properties.configuration.ingress.fqdn
output AGENT_CONTAINER_APP_NAME string = agentApp.name
output AGENT_PRINCIPAL_ID string = agentApp.identity.principalId
output AGENT_AUTH_MODE string = authEnabled ? 'agentic' : 'anonymous'
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = registry.properties.loginServer
output AZURE_CONTAINER_REGISTRY_NAME string = registry.name
