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

@description('Subscription ID containing the existing AOAI / Foundry account.')
param azureOpenAiSubscriptionId string

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

// ----- Application Insights ------------------------------------------------
// Workspace-based App Insights component. The microsoft-opentelemetry distro
// exports a SECOND copy of traces/metrics/logs here (in addition to the A365
// observability backend) when enable_azure_monitor=True in host_agent_server.py
// and the APPLICATIONINSIGHTS_CONNECTION_STRING env var below is present.
// A365 export and Azure Monitor export are independent pipelines.
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'appi-${envToken}-${resourceToken}'
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
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

// Give Container Apps a registry pull identity that exists before the app
// revision is created. Using the Container App system identity for registry
// pulls creates a first-provision cycle: the app revision needs AcrPull to
// start, but the system identity principal does not exist until the app exists.
resource registryPullIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'id-acrpull-${resourceToken}'
  location: location
  tags: tags
}

// Built-in role definition IDs (constants):
//   AcrPull = 7f951dda-4ed3-4680-a7ca-43fe172d538d
var acrPullRoleId = '7f951dda-4ed3-4680-a7ca-43fe172d538d'

resource acrPullAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: registry
  name: guid(registry.id, registryPullIdentity.id, acrPullRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleId)
    principalId: registryPullIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// ----- Container App -------------------------------------------------------
// Image starts as a placeholder; `azd deploy` overrides it via the
// `containerapp update --image` call after pushing to the registry.

@description('Initial container image reference. Must listen on the Container App ingress target port before azd deploy replaces it with the real image.')
param initialImage string = 'mcr.microsoft.com/dotnet/samples:aspnetapp'
var placeholderImage = initialImage
var resolvedTenantId = empty(blueprintTenantId) ? subscription().tenantId : blueprintTenantId
var authEnabled = !empty(blueprintClientId) && !empty(blueprintClientSecret)

// Container env always carries the basics (port + Foundry). Auth-related
// vars are appended only when the blueprint credentials have been supplied.
var baseEnv = [
  { name: 'HOST', value: '0.0.0.0' }
  { name: 'PORT', value: '3978' }
  // The first provision uses the public .NET sample placeholder image. Make it
  // listen on the same port as the real Python app so Container Apps can create
  // the initial revision before `azd deploy` replaces the image.
  { name: 'ASPNETCORE_HTTP_PORTS', value: '3978' }
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
  // Application Insights connection string. The microsoft-opentelemetry distro
  // auto-detects this env var when enable_azure_monitor=True and ships a second
  // copy of telemetry to App Insights for ops/dev dashboards (independent of the
  // A365 observability export above).
  { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: appInsights.properties.ConnectionString }
  // Max wall-clock time for a single agent turn before it is cancelled and the
  // session is reset. Default in code is 75s; bumped here so longer MCP tool
  // chains (broad mailbox/Teams searches, async file copy + status polling)
  // have room to finish instead of hitting the "request took too long" reset.
  { name: 'AGENT_RUN_TIMEOUT_SECONDS', value: '150' }
]

// The Microsoft Agents SDK connection manager requires a service connection
// entry to exist even during the first anonymous deployment. Keep the shape in
// place with empty credentials until blueprint credentials are supplied.
var serviceConnectionEnv = [
  { name: 'CONNECTIONSMAP__0__SERVICEURL', value: '*' }
  { name: 'CONNECTIONSMAP__0__CONNECTION', value: 'SERVICE_CONNECTION' }
  { name: 'CONNECTIONS__SERVICE_CONNECTION__SETTINGS__CLIENTID', value: authEnabled ? blueprintClientId : '' }
  { name: 'CONNECTIONS__SERVICE_CONNECTION__SETTINGS__TENANTID', value: authEnabled ? resolvedTenantId : '' }
  { name: 'CONNECTIONS__SERVICE_CONNECTION__SETTINGS__SCOPES', value: graphScope }
]

var serviceConnectionSecretEnv = authEnabled ? [
  { name: 'CONNECTIONS__SERVICE_CONNECTION__SETTINGS__CLIENTSECRET', secretRef: 'blueprint-client-secret' }
] : [
  { name: 'CONNECTIONS__SERVICE_CONNECTION__SETTINGS__CLIENTSECRET', value: '' }
]

var authEnv = authEnabled ? [
  { name: 'AUTH_HANDLER_NAME', value: 'AGENTIC' }
  { name: 'USE_AGENTIC_AUTH', value: 'true' }
  { name: 'CLIENT_ID', value: blueprintClientId }
  { name: 'TENANT_ID', value: resolvedTenantId }
  { name: 'CLIENT_SECRET', secretRef: 'blueprint-client-secret' }
  { name: 'AGENTAPPLICATION__USERAUTHORIZATION__HANDLERS__AGENTIC__SETTINGS__TYPE', value: 'AgenticUserAuthorization' }
  { name: 'AGENTAPPLICATION__USERAUTHORIZATION__HANDLERS__AGENTIC__SETTINGS__SCOPES', value: agentic365Scope }
  { name: 'AGENTAPPLICATION__USERAUTHORIZATION__HANDLERS__AGENTIC__SETTINGS__ALTERNATEBLUEPRINTCONNECTIONNAME', value: 'SERVICE_CONNECTION' }
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
    type: 'SystemAssigned, UserAssigned'
    userAssignedIdentities: {
      '${registryPullIdentity.id}': {}
    }
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
          identity: registryPullIdentity.id
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
          env: concat(baseEnv, serviceConnectionEnv, serviceConnectionSecretEnv, authEnv)
        }
      ]
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
      }
    }
  }
  dependsOn: [
    acrPullAssignment
  ]
}

// ----- Role assignments ----------------------------------------------------
// Built-in role definition IDs (constants):
//   Cognitive Services OpenAI User = 5e0bd9bd-7b93-4f28-af87-19fc36ad61bd

var cogSvcOpenAIUserRoleId = '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'

// Grant the MI Cognitive Services OpenAI User on the existing AOAI / Foundry
// account. The submodule targets that account's resource group so the role
// assignment is created in the right place even when it lives in a different
// RG than the workload.
module aoaiRoleAssignment 'modules/aoai-role-assignment.bicep' = {
  name: 'aoai-role-assignment'
  scope: resourceGroup(azureOpenAiSubscriptionId, azureOpenAiResourceGroup)
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
output APPLICATIONINSIGHTS_CONNECTION_STRING string = appInsights.properties.ConnectionString
output APPLICATIONINSIGHTS_NAME string = appInsights.name
