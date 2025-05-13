@description('Name of the existing Recovery Services vault')
param vaultName string

@description('Name of the existing backup policy')
param backupPolicyName string

@description('Name of the VM to back up')
param vmName string

@description('Resource group where the VM is located')
param vmResourceGroup string

@description('Resource ID of the VM to back up')
param vmResourceId string

var backupFabric = 'Azure'
var v2VmType = 'Microsoft.Compute/virtualMachines'
var v2VmContainer = 'iaasvmcontainer;iaasvmcontainerv2;'
var v2Vm = 'vm;iaasvmcontainerv2;'

// Reference to existing Recovery Services vault
resource recoveryServicesVault 'Microsoft.RecoveryServices/vaults@2024-10-01' existing = {
  name: vaultName
}

// Reference to existing backup policy
resource backupPolicy 'Microsoft.RecoveryServices/vaults/backupPolicies@2024-10-01' existing = {
  parent: recoveryServicesVault
  name: backupPolicyName
}

// Configure backup for VM using existing vault and policy
resource backupProtectedItem 'Microsoft.RecoveryServices/vaults/backupFabrics/protectionContainers/protectedItems@2024-10-01' = {
  name: '${vaultName}/${backupFabric}/${v2VmContainer}${vmResourceGroup};${vmName}/${v2Vm}${vmResourceGroup};${vmName}'
  properties: {
    protectedItemType: v2VmType
    policyId: backupPolicy.id
    sourceResourceId: vmResourceId
  }
}

// Output the protected item ID
output protectedItemId string = backupProtectedItem.id
