targetScope = 'subscription'

param servicePrefix string

param adminVmUsername string

@minLength(12)
@secure()
param adminVmPassword string


resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  location: 'northeurope'
  name: servicePrefix
}

module resources_Internal 'appservice-landing-zone.bicep' = {
  scope: rg
  name: servicePrefix
  params: {
    servicePrefix: servicePrefix
    adminVmPassword: adminVmPassword
    adminVmUsername: adminVmUsername
  }
}
