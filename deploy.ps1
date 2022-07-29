param(
    [string] $TemplateUri = ' https://raw.githubusercontent.com/martin77s/DomainLab/main/azuredeploy.json',
    [string] $ResourceGroupName = ('domainlab-{0:yyyyMMddHHmm}' -f (Get-Date)),
    [string] $Location = 'northeurope',
    [string] $Prefix = 'lab',
    [ValidatePattern('\.local$')] [string] $DomainName = 'domain1.local',
    [string] $AdminUsername = 'vmadmin',
    [string] $AdminPwd = 'P@55w0rd!P@55w0rd?',
    [int] $NumberOfMemberServers = 2,
    [string] $vmSizeDCs = 'Standard_D4s_v3',
    [string] $vmSizeMemberServers = 'Standard_D4s_v3'
)


# Understand the public IP address of the machine deploying the template
$publicIp = (Invoke-WebRequest -Uri 'https://api.ipify.org/?format=json').Content | ConvertFrom-Json
$clientAllowedIP = '{0}/32' -f $publicIp.ip


# Create the deployment template parameters hashtable
$deploymentParams = @{
    TemplateUri           = $TemplateUri
    ResourceGroupName     = $ResourceGroupName
    Name                  = $ResourceGroupName
    Force                 = $true
    Verbose               = $true
    Location              = $Location
    Prefix                = $Prefix
    ClientAllowedIP       = $clientAllowedIP
    DomainName            = $DomainName
    VmAdminUser           = $AdminUsername
    VmAdminPassword       = ($AdminPwd | ConvertTo-SecureString -AsPlainText -Force)
    NumberOfMemberServers = $NumberOfMemberServers
    vmSizeDCs             = $vmSizeDCs
    vmSizeMemberServers   = $vmSizeMemberServers
}

# Verify the ResourceGroup exists
if (-not (Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue)) {
    New-AzResourceGroup -Name $ResourceGroupName -Location $Location | Out-Null
}

# Run the deployment
New-AzResourceGroupDeployment @deploymentParams
