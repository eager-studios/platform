// modules/function-app-flex.bicep — a .NET isolated Function App on Flex Consumption with:
// keyless storage, Entra-authenticated App Insights, built-in auth limited to named people,
// and a user-assigned runtime identity created by bootstrap.
param name string
param location string = resourceGroup().location
@description('Resource ID of the runtime identity (id-<app>-api-<env>).')
param identityId string
param identityClientId string
param identityPrincipalId string
param logAnalyticsWorkspaceId string

@description('Run `az functionapp list-flexconsumption-runtimes -l <region> --runtime dotnet-isolated` to confirm.')
param runtimeVersion string = '10.0'
param instanceMemoryMB int = 512
@description('Upper bound on scale-out; low on purpose for a household app.')
param maximumInstanceCount int = 10

param corsOrigins array
param appSettings object = {}

@description('Entra tenant, the API app registration client ID, and its Application ID URI.')
param tenantId string = tenant().tenantId
param apiClientId string
param apiAudience string
@description('Entra object IDs allowed to call the API (checked against the token oid claim).')
param allowedObjectIds array

var token = take(uniqueString(resourceGroup().id, name), 8)

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: 'st${replace(take(name, 14), '-', '')}${token}'
  location: location
  kind: 'StorageV2'
  sku: { name: 'Standard_LRS' }
  properties: {
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    minimumTlsVersion: 'TLS1_2'
    publicNetworkAccess: 'Enabled'
  }
  resource blob 'blobServices' = {
    name: 'default'
    resource deployments 'containers' = {
      name: 'deployments'
      properties: { publicAccess: 'None' }
    }
  }
}

resource appi 'Microsoft.Insights/components@2020-02-02' = {
  name: 'appi-${name}'
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspaceId
    DisableLocalAuth: true
  }
}

resource plan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: 'plan-${name}'
  location: location
  kind: 'functionapp'
  sku: { tier: 'FlexConsumption', name: 'FC1' }
  properties: { reserved: true }
}

resource site 'Microsoft.Web/sites@2024-04-01' = {
  name: name
  location: location
  kind: 'functionapp,linux'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: { '${identityId}': {} }
  }
  properties: {
    serverFarmId: plan.id
    httpsOnly: true
    siteConfig: {
      minTlsVersion: '1.2'
      cors: { allowedOrigins: corsOrigins }
    }
    functionAppConfig: {
      deployment: {
        storage: {
          type: 'blobContainer'
          value: '${storage.properties.primaryEndpoints.blob}deployments'
          authentication: {
            type: 'UserAssignedIdentity'
            userAssignedIdentityResourceId: identityId
          }
        }
      }
      scaleAndConcurrency: {
        maximumInstanceCount: maximumInstanceCount
        instanceMemoryMB: instanceMemoryMB
      }
      runtime: { name: 'dotnet-isolated', version: runtimeVersion }
    }
  }

  resource settings 'config' = {
    name: 'appsettings'
    properties: union({
      AzureWebJobsStorage__accountName: storage.name
      AzureWebJobsStorage__credential: 'managedidentity'
      AzureWebJobsStorage__clientId: identityClientId
      APPLICATIONINSIGHTS_CONNECTION_STRING: appi.properties.ConnectionString
      APPLICATIONINSIGHTS_AUTHENTICATION_STRING: 'ClientId=${identityClientId};Authorization=AAD'
      AZURE_CLIENT_ID: identityClientId
    }, appSettings)
  }

  // Built-in auth: no valid Entra token for this API from an allowed person -> 401 before code runs.
  resource auth 'config' = {
    name: 'authsettingsV2'
    properties: {
      platform: { enabled: true }
      globalValidation: {
        requireAuthentication: true
        unauthenticatedClientAction: 'Return401'
      }
      httpSettings: { requireHttps: true }
      identityProviders: {
        azureActiveDirectory: {
          enabled: true
          registration: {
            clientId: apiClientId
            openIdIssuer: '${environment().authentication.loginEndpoint}${tenantId}/v2.0'
          }
          validation: {
            allowedAudiences: [ apiAudience, apiClientId ]
            defaultAuthorizationPolicy: {
              allowedPrincipals: { identities: allowedObjectIds }
            }
          }
        }
      }
    }
  }
}

// Data roles for the runtime identity. These are the only roles the infra pipeline may grant.
resource blobOwner 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, identityPrincipalId, 'blob-data-owner')
  scope: storage
  properties: {
    principalId: identityPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b')
  }
}

resource metricsPublisher 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(appi.id, identityPrincipalId, 'metrics-publisher')
  scope: appi
  properties: {
    principalId: identityPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '3913510d-42f4-4e42-8a64-420c390055eb')
  }
}

output name string = site.name
output hostname string = site.properties.defaultHostName
