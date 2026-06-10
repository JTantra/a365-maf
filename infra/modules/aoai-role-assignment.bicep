// aoai-role-assignment.bicep
// Assigns the given role on the existing Azure OpenAI / Foundry account to
// the supplied principal. Deployed at the AOAI account's resource group
// scope from main.bicep so the role assignment lives in the right RG.

targetScope = 'resourceGroup'

@description('Name of the existing Azure OpenAI / Foundry account in this resource group.')
param aoaiAccountName string

@description('Principal ID (object ID) of the managed identity to grant the role to.')
param principalId string

@description('Role definition GUID (just the GUID, no subscription prefix).')
param roleDefinitionId string

resource aoai 'Microsoft.CognitiveServices/accounts@2024-10-01' existing = {
  name: aoaiAccountName
}

resource assignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: aoai
  name: guid(aoai.id, principalId, roleDefinitionId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionId)
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}
