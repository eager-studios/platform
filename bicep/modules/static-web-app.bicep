// modules/static-web-app.bicep — Free-plan Static Web App. The pipeline deploys built files
// with a deployment token it reads at run time; no repo link and no stored token.
param name string
@description('Static Web Apps runs in a few regions only; eastus2 is one.')
param location string = 'eastus2'

resource swa 'Microsoft.Web/staticSites@2024-04-01' = {
  name: name
  location: location
  sku: { name: 'Free', tier: 'Free' }
  properties: {}
}

output name string = swa.name
output hostname string = swa.properties.defaultHostname
