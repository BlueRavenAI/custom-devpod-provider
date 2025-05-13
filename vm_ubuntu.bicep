@description('The name of your Virtual Machine.')
param vmName string

@description('Username for the Virtual Machine.')
param adminUsername string

@description('SSH Key or password for the Virtual Machine. SSH key is recommended.')
@secure()
param adminPasswordOrKey string

@description('Docker registry username.')
param dockerUsername string

@description('Docker registry token.')
@secure()
param dockerToken string

@description('Location for all resources.')
param location string

@description('The VM size to deploy.')
param vmSize string

@description('The Disk size to deploy.')
param diskSize int

// Replace the single vault parameters with location-specific vault mappings
@description('Mapping of locations to Recovery Services vaults.')
param vaultMapping object = {
  southeastasia: {
    vaultName: 'singapore-vault'
    vaultResourceGroup: 'backup'
    policyName: 'daily-keep-30'
  }, westus: {
    vaultName: 'us-vault'
    vaultResourceGroup: 'backup'
    policyName: 'daily-keep-30'
  }, uksouth: {
    vaultName: 'uk-vault'
    vaultResourceGroup: 'backup'
    policyName: 'daily-keep-30'
  }, japaneast: {
    vaultName: 'japan-vault'
    vaultResourceGroup: 'backup'
    policyName: 'daily-keep-30'
  }, polandcentral: {
    vaultName: 'poland-vault'
    vaultResourceGroup: 'backup'
    policyName: 'daily-keep-30'
  }
}

var selectedVault = vaultMapping[location]

// Determines if the VM is GPU-enabled by checking if vmSize starts with "Standard_N"
var isGpuMachine = startsWith(vmSize, 'Standard_N')

resource vm 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: vmName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    storageProfile: {
      osDisk: {
        deleteOption: 'Delete'
        createOption: 'FromImage'
        diskSizeGB: diskSize
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
      }
      imageReference: {
        publisher: 'Canonical'
        offer: 'ubuntu-24_04-lts'
        sku: 'server'
        version: 'latest'
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: networkInterface.id
        }
      ]
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      adminPassword: adminPasswordOrKey
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: adminPasswordOrKey
            }
          ]
        }
      }
    }
  }
}

resource networkInterface 'Microsoft.Network/networkInterfaces@2023-09-01' = {
  name: '${vmName}NetInt'
  location: location
  properties: {
    enableAcceleratedNetworking: true
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: virtualNetwork.properties.subnets[0].id
          }
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: publicIPAddress.id
          }
        }
      }
    ]
    networkSecurityGroup: {
      id: networkSecurityGroup.id
    }
  }
}

resource networkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: '${vmName}SecGroupNet'
  location: location
  properties: {
    securityRules: [
      {
        name: 'SSH'
        properties: {
          priority: 1000
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '22'
        }
      }
    ]
  }
}

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: '${vmName}VNet'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.1.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'Subnet'
        properties: {
          addressPrefix: '10.1.0.0/24'
          privateEndpointNetworkPolicies: 'Enabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
    ]
  }
}

resource publicIPAddress 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: '${vmName}PublicIP'
  location: location
  sku: {
    name: 'Basic'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
    dnsSettings: {
      domainNameLabel: toLower('${vmName}-${uniqueString(resourceGroup().id)}')
    }
    idleTimeoutInMinutes: 4
  }
}

resource gpuDriverExtension 'Microsoft.Compute/virtualMachines/extensions@2015-06-15' = if (isGpuMachine) {
  parent: vm
  name: 'NvidiaGpuDriverLinux'
  location: location
  properties: {
    publisher: 'Microsoft.HpcCompute'
    type: 'NvidiaGpuDriverLinux'
    typeHandlerVersion: '1.9'
    autoUpgradeMinorVersion: true
    settings: {}
  }
}

var dockerCommands = format('''
if ! command -v docker &> /dev/null; then
  echo "Docker not found. Installing Docker..."
  sudo apt-get update
  sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common
  curl -fsSL https://get.docker.com -o get-docker.sh
  sudo sh get-docker.sh
else
  echo "Docker already installed."
fi
sudo systemctl start docker

sudo mkdir -p /root/.docker
auth=$(echo -n "{1}:{2}" | base64)
echo "{{\"auths\":{{\"ghcr.io\":{{\"auth\":\"$auth\"}}}}}}" | sudo tee /root/.docker/config.json

sudo cp -r /root/.docker /home/{0}/
sudo chown -R {0}:{0} /home/{0}/.docker
''', adminUsername, dockerUsername, dockerToken)

var nvidiaCommands = '''
sudo apt-get update && sudo apt-get install -y nvidia-container-toolkit
sudo systemctl restart docker
'''

var commandToExecute = '${dockerCommands}${isGpuMachine ? nvidiaCommands : ''}'

resource installExtraModules 'Microsoft.Compute/virtualMachines/extensions@2022-03-01' = {
  parent: vm
  name: 'installDockerAndSetupFileShare'
  location: location
  dependsOn: isGpuMachine ? [gpuDriverExtension] : []
  properties: {
    publisher: 'Microsoft.Azure.Extensions'
    type: 'CustomScript'
    typeHandlerVersion: '2.1'
    autoUpgradeMinorVersion: true
    settings: {
      commandToExecute: commandToExecute
    }
  }
}

output hostname string = publicIPAddress.properties.dnsSettings.fqdn
output vaultName string = selectedVault.vaultName
output vaultResourceGroup string = selectedVault.vaultResourceGroup
output vmName string = vm.name
output vmId string = vm.id
output backupPolicyName string = selectedVault.policyName
