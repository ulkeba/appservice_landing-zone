param servicePrefix string

param adminVmUsername string

@minLength(12)
@secure()
param adminVmPassword string

/* VIRTUAL NETWORKS AND NETWORK INFRASTRUCTURE*/

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
        name: 'AzureBastionSubnet'
        properties: {
          addressPrefix: '10.0.1.0/24'
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
        name: 'webapp-privateendpoint-subnet'
        properties: {
          addressPrefix: '10.1.1.0/24'
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }

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

      {
        name: 'other-services-privateendpoint-subnet'
        properties: {
          addressPrefix: '10.1.2.0/24'
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }

      {
        name: 'vm-subnet'
        properties: {
          addressPrefix: '10.1.3.0/24'
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}

resource vNetPeeringIdmzToHdmz 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2021-05-01' = {
  name: 'idmz-to-hdmz'
  parent: vNetIDMZ
  properties: {
    remoteVirtualNetwork: {
      id: vNetHDMZ.id
    }
  }
}

resource vNetPeeringHdmzToIdmz 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2021-05-01' = {
  name: 'hdmz-to-idmz'
  parent: vNetHDMZ
  properties: {
    remoteVirtualNetwork: {
      id: vNetIDMZ.id
    }
  }
}

resource prvDnsZoneAzureWebSites 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.azurewebsites.net'
  location: 'global'
}

resource prvDnsZoneAzureWebSitesVNetIDMZLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: prvDnsZoneAzureWebSites
  name: '${prvDnsZoneAzureWebSites.name}-to-${vNetIDMZ.name}'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vNetIDMZ.id
    }
  }
}

resource prvDnsZoneAzureWebSitesVNetHDMZLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: prvDnsZoneAzureWebSites
  name: '${prvDnsZoneAzureWebSites.name}-to-${vNetHDMZ.name}'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vNetHDMZ.id
    }
  }
}


resource prvDnsZoneVaultCore 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.vaultcore.azure.net'
  location: 'global'
}

resource prvDnsZoneVaultCoreVNetIDMZLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: prvDnsZoneVaultCore
  name: '${prvDnsZoneVaultCore.name}-to-${vNetIDMZ.name}'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vNetIDMZ.id
    }
  }
}

resource prvDnsZoneVaultCoreVNetHDMZLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: prvDnsZoneVaultCore
  name: '${prvDnsZoneVaultCore.name}-to-${vNetHDMZ.name}'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vNetHDMZ.id
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
    virtualNetworkSubnetId: vNetHDMZ.properties.subnets[1].id
    httpsOnly: true
    siteConfig: {
      vnetRouteAllEnabled: true
    }
  }
}


resource webAppPrivateEndpoint 'Microsoft.Network/privateEndpoints@2021-05-01' = {
  name: '${webApp.name}-privateendpoint'
  location: resourceGroup().location
  properties: {
    subnet: {
      id: vNetHDMZ.properties.subnets[0].id
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

/* KEY VAULT AND CERTIFICATE */
/* from https://github.com/Azure/azure-quickstart-templates/blob/master/quickstarts/microsoft.apimanagement/api-management-key-vault-create/main.bicep*/

resource keyVault 'Microsoft.KeyVault/vaults@2021-06-01-preview' = {
  name: '${servicePrefix}-kv'
  location: resourceGroup().location
  properties: {
    sku: {
      name: 'standard'
      family: 'A'
    }
    tenantId: appgwMi.properties.tenantId
    enableRbacAuthorization: true
  }
}


//TODO: FAR TOO HIGH ACCESS PRIVILEGES
var keyVaultAdminRoleDefinitionId = '00482a5a-887f-4fb3-b363-3b7fe8e74483'
resource kvRoleAssignment 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: guid(keyVaultAdminRoleDefinitionId,appgwMi.id,keyVault.id)
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultAdminRoleDefinitionId)
    principalId: appgwMi.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource deploymentScript_AddSelfSignedCertToKv 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: 'add-self-signed-cert-to-kv'
  location: resourceGroup().location
  kind: 'AzureCLI'
  dependsOn: [
    keyVault
    kvRoleAssignment
  ]
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${appgwMi.id}': {}
    }
  }
  properties: {
    forceUpdateTag: '1'
    containerSettings: {
      containerGroupName: 'mycustomaci'
    }
    azCliVersion: '2.32.0'
    environmentVariables: [
      {
        name: 'kv'
        value: '${servicePrefix}-kv'
      }
      {
        name: 'fqdn'
        value: '${servicePrefix}.westeurope.cloudapp.azure.com'
      }
      {
        name: 'certname'
        value: servicePrefix
      }
    ]
    scriptContent: loadTextContent('add-cert.sh')
    supportingScriptUris: []
    timeout: 'PT30M'
    cleanupPreference: 'OnSuccess'
    retentionInterval: 'P1D'
  }
}

/* BASTION HOST */

resource bastionHostPIP 'Microsoft.Network/publicIPAddresses@2021-05-01' = {
  name: '${servicePrefix}-bastion-pip'
  location: resourceGroup().location
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource bastionHost 'Microsoft.Network/bastionHosts@2020-05-01' = {
  name: '${servicePrefix}-bastion'
  location: resourceGroup().location
  properties: {
    ipConfigurations: [
      {
        name: 'ip-configuration'
        properties: {
          subnet: {
            id: vNetIDMZ.properties.subnets[1].id
          }
          publicIPAddress: {
            id: bastionHostPIP.id
          }
        }
      }
    ]
  }
}


/* ADMIN VM */

module adminVm 'vm-simple-windows.bicep' = {
  name: '${servicePrefix}-adminvm'
  params: {
    adminUsername: adminVmUsername
    adminPassword: adminVmPassword
    vmName:  '${servicePrefix}-vm'
    subnetId: vNetHDMZ.properties.subnets[3].id
  }
}

/* APPLICATION GATEWAY, REQUIRED RESOURCES AND WAF POLICY */

resource wafPolicy 'Microsoft.Network/ApplicationGatewayWebApplicationFirewallPolicies@2021-05-01' = {
  name: '${servicePrefix}-waf'
  location: resourceGroup().location
  dependsOn: [
    deploymentScript_AddSelfSignedCertToKv
  ]
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
    sslCertificates: [
      {
        name: servicePrefix
        properties: {
          keyVaultSecretId: 'https://${servicePrefix}-kv.vault.azure.net/secrets/${servicePrefix}'
        }
      }
    ]
    frontendPorts: [
      {
        name: 'https'
        properties: {
          port: 443
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
          protocol: 'Https'
          sslCertificate: {
            id: '${appgwResourceId}/sslCertificates/${servicePrefix}'
          }
          frontendIPConfiguration: {
            id: '${appgwResourceId}/frontendIPConfigurations/appgw-frontend-public-ip'
          }
          frontendPort: {
            id: '${appgwResourceId}/frontendPorts/https'
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

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2021-06-01' = {
  name: '${servicePrefix}-law'
  location: resourceGroup().location
  properties: {
    sku: {
        name: 'PerGB2018'
    }
  }
}

resource diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'to-law'
  scope: appgw
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }

}
