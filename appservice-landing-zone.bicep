param servicePrefix string

/* VIRTUAL NETWORKS */

resource vNetIDMZ 'Microsoft.Network/virtualNetworks@2019-11-01' = {
  name: '${servicePrefix}-vnet-idmz'
  location: resourceGroup().location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'app-gateway-subnet'
        properties: {
          addressPrefix: '10.0.0.0/24'
        }
      }
      {
        name: 'privateendpoints-subnet'
        properties: {
          addressPrefix: '10.0.1.0/24'
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}

resource vNetHDMZ 'Microsoft.Network/virtualNetworks@2019-11-01' = {
  name: '${servicePrefix}-vnet-hdmz'
  location: resourceGroup().location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.1.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'app-service-subnet'
        properties: {
          addressPrefix: '10.1.10.0/24'
          delegations: [
            {
              name: 'delegation'
              properties: {
                serviceName: 'Microsoft.Web/serverFarms'
              }
            }
          ]
        }
      }
    ]
  }
}

resource prvDnsZoneAzureWebSites 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.azurewebsites.net'
  location: 'global'
}

resource prvDnsZoneAzureWebSitesVNetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: prvDnsZoneAzureWebSites
  name: '${prvDnsZoneAzureWebSites.name}-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vNetIDMZ.id
    }
  }
}
/* APP SERVICE */
/* see https://github.com/Azure/azure-quickstart-templates/blob/master/quickstarts/microsoft.web/app-service-regional-vnet-integration/main.bicep */

resource appServicePlan 'Microsoft.Web/serverfarms@2020-06-01' = {
  name: '${servicePrefix}-appsvc-plan'
  location: resourceGroup().location
  sku: {
    tier: 'PremiumV2'
    name: 'P2v2'
  }
  kind: 'app'
}

resource webApp 'Microsoft.Web/sites@2021-01-01' = {
  name: '${servicePrefix}-appsvc'
  location: resourceGroup().location
  kind: 'app'
  properties: {
    serverFarmId: appServicePlan.id
    virtualNetworkSubnetId: vNetHDMZ.properties.subnets[0].id
    httpsOnly: true
    siteConfig: {
      vnetRouteAllEnabled: true
    }
  }
}


resource webAppPrivateEndpoint 'Microsoft.Network/privateEndpoints@2021-05-01' = {
  name: '${servicePrefix}-privateendpoint'
  location: resourceGroup().location
  properties: {
    subnet: {
      id: vNetIDMZ.properties.subnets[1].id
    }
    privateLinkServiceConnections: [
      {
        name: 'for-webapp'
        properties: {
          privateLinkServiceId: webApp.id
          groupIds: [
            'sites'
          ]
        }
      }
    ]
  }
}

resource webAppPrivateDnsEntry 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2021-05-01' = {
  parent: webAppPrivateEndpoint
  name: 'dns-zone-group'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'config'
        properties: {
          privateDnsZoneId: prvDnsZoneAzureWebSites.id
        }
      }
    ]
  }
}



resource wafPolicy 'Microsoft.Network/ApplicationGatewayWebApplicationFirewallPolicies@2021-05-01' = {
  name: '${servicePrefix}-waf'
  location: resourceGroup().location
  properties: {
    customRules: [
        {
            name: 'blockcountries'
            priority: 100
            ruleType: 'MatchRule'
            action: 'Block'
            matchConditions: [
                {
                    matchVariables: [
                        {
                            variableName: 'RemoteAddr'
                        }
                    ]
                    operator: 'GeoMatch'
                    negationConditon: false
                    matchValues: [
                        'NL'
                        'IE'
                    ]
                    transforms: []
                }
            ]
        }
    ]
    policySettings: {
        requestBodyCheck: true
        maxRequestBodySizeInKb: 128
        fileUploadLimitInMb: 100
        state: 'Enabled'
        mode: 'Detection'
    }
    managedRules: {
        managedRuleSets: [
            {
                ruleSetType: 'OWASP'
                ruleSetVersion: '3.1'
                ruleGroupOverrides: []
            }
        ]
    }
  }
}

resource appgwMi 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' = {
  name: '${servicePrefix}-appgw-mi'
  location: resourceGroup().location
}

resource appgwPIP 'Microsoft.Network/publicIPAddresses@2021-05-01' = {
  name: '${servicePrefix}-appgw-pip'
  location: resourceGroup().location
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}


var appgwResourceId = resourceId('Microsoft.Network/applicationGateways', '${servicePrefix}-appgw')
resource appgw 'Microsoft.Network/applicationGateways@2021-05-01' = {
  name: '${servicePrefix}-appgw'
  location: resourceGroup().location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${appgwMi.id}': {}
    }
  }
  properties: {
    sku: {
      name: 'WAF_v2'
      tier: 'WAF_v2'
    }
    autoscaleConfiguration: {
      minCapacity: 0
      maxCapacity: 2
    }
    webApplicationFirewallConfiguration: {
      enabled: true
      firewallMode: 'Detection'
      ruleSetType: 'OWASP'
      ruleSetVersion: '3.1'
    }
    firewallPolicy: {
      id: wafPolicy.id
    }
    gatewayIPConfigurations: [
      {
      name: 'appgw-ip-config'
      properties: {
        subnet: {
          id: resourceId('Microsoft.Network/virtualNetworks/subnets', vNetIDMZ.name, 'app-gateway-subnet')
        }
      }
    }
    ]
    frontendIPConfigurations: [
      {
        name: 'appgw-frontend-public-ip'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: appgwPIP.id
          }
        }
      }
    ]
    frontendPorts: [
      {
        name: 'http'
        properties: {
          port: 80
        }
      }
    ]


    backendAddressPools: [
      {
        name: '${servicePrefix}-appsvc--backend'
        properties: {
          backendAddresses: [
            {
              fqdn: '${servicePrefix}-appsvc.azurewebsites.net'
            }
          ]
        }
      }
    ]

    probes: [
      {
        name: '${servicePrefix}-appsvc--probe'
        properties: {
          protocol: 'Https'
          path: '/'
          pickHostNameFromBackendHttpSettings: true
          timeout: 30
          interval: 30
        }
      }
    ]

    backendHttpSettingsCollection: [
      {
        name: '${servicePrefix}-appsvc--settings'
        properties: {
          port: 443
          protocol: 'Https'
          pickHostNameFromBackendAddress: true
          probe: {
            id: '${appgwResourceId}/probes/${servicePrefix}-appsvc--probe'
          }
        }
      }
    ]
    
    httpListeners: [
      {
        name: '${servicePrefix}-appsvc--listener'
        properties: {
          protocol: 'Http'
          frontendIPConfiguration: {
            id: '${appgwResourceId}/frontendIPConfigurations/appgw-frontend-public-ip'
          }
          frontendPort: {
            id: '${appgwResourceId}/frontendPorts/http'
          }
        }
      }
    ]
    
    requestRoutingRules: [
      {
        name: '${servicePrefix}-appsvc--rule'
        properties: {
          ruleType: 'Basic'
          httpListener: {
            id: '${appgwResourceId}/httpListeners/${servicePrefix}-appsvc--listener'
          }
          backendAddressPool: {
            id: '${appgwResourceId}/backendAddressPools/${servicePrefix}-appsvc--backend'
          }
          backendHttpSettings: {
            id: '${appgwResourceId}/backendHttpSettingsCollection/${servicePrefix}-appsvc--settings'
          }
        }
      }
    ]
  }
}
