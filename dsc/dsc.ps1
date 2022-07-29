<#
After updating the DCS configuration below, you need to "recompile" the zip file using:
Publish-AzVMDscConfiguration -ConfigurationPath .\dsc\dsc.ps1 -OutputArchivePath .\dsc\dsc.zip -Force
#>

Configuration PDC {

    [CmdletBinding()]

    param (
        [string] $DomainName,
        [PSCredential] $DomainCreds
    )

    Import-DscResource -ModuleName PSDesiredStateConfiguration
    Import-DscResource -ModuleName ActiveDirectoryDsc
    Import-DscResource -ModuleName NetworkingDsc
    Import-DscResource -ModuleName ComputerManagementDsc

    Set-Item -Path WSMan:\localhost\Client\TrustedHosts -Value * -Force

    node localhost {

        LocalConfigurationManager {
            RebootNodeIfNeeded   = $true
            AllowModuleOverwrite = $true
            ActionAfterReboot    = 'ContinueConfiguration'
        }

        $Features = @(
            'AD-Domain-Services',
            'RSAT-ADDS',
            'RSAT-AD-Tools',
            'RSAT-AD-PowerShell',
            'RSAT-AD-AdminCenter',
            'RSAT-Role-Tools',
            'RSAT-DNS-Server',
            'GPMC',
            'DNS'
        )

        $Features.ForEach( {
                Write-Verbose "`t - $_" -Verbose
                WindowsFeature "$_" {
                    Ensure = 'Present'
                    Name   = $_
                }
            } )

        DnsServerAddress DnsServerAddress {
            AddressFamily  = 'IPv4'
            Address        = '127.0.0.1'
            InterfaceAlias = (Get-NetAdapter | Where-Object { $_.Name -like 'Ethernet*' } | Select-Object -First 1).Name
            DependsOn      = '[WindowsFeature]DNS'
        }

        File ADDSFolder {
            Ensure          = 'Present'
            Type            = 'Directory'
            DestinationPath = 'C:\ADDS'
        }

        ADDomain CreateForest {
            DomainName                    = $DomainName
            Credential                    = $DomainCreds
            SafemodeAdministratorPassword = $DomainCreds
            DatabasePath                  = 'C:\ADDS\NTDS'
            LogPath                       = 'C:\ADDS\NTDS'
            SysvolPath                    = 'C:\ADDS\Sysvol'
            ForestMode                    = 'Win2012R2'
            DomainMode                    = 'Win2012R2'
            DependsOn                     = '[WindowsFeature]AD-Domain-Services', '[File]ADDSFolder'
        }

        PendingReboot RebootAfterPromotion {
            Name      = 'RebootAfterDCPromotion'
            DependsOn = '[ADDomain]CreateForest'
        }

    }
}


Configuration BDC {

    [CmdletBinding()]

    param (
        [string] $DomainName,
        [PSCredential] $DomainCreds
    )

    Import-DscResource -ModuleName PSDesiredStateConfiguration
    Import-DscResource -ModuleName ActiveDirectoryDsc
    Import-DscResource -ModuleName ComputerManagementDsc

    $ComputerName = $env:ComputerName
    $DomainName = Split-Path $DomainCreds.UserName

    Get-WmiObject -Class Win32_NetworkAdapterConfiguration -Filter 'IPEnabled=true and DHCPEnabled=true' | ForEach-Object {
        $_.InvokeMethod('ReleaseDHCPLease', $null)
        $_.InvokeMethod('RenewDHCPLease', $null)
    }

    node localhost {

        LocalConfigurationManager {
            RebootNodeIfNeeded   = $true
            AllowModuleOverwrite = $true
            ActionAfterReboot    = 'ContinueConfiguration'
        }

        $Features = @(
            'AD-Domain-Services',
            'RSAT-ADDS',
            'RSAT-AD-Tools',
            'RSAT-AD-PowerShell',
            'RSAT-AD-AdminCenter',
            'RSAT-Role-Tools',
            'RSAT-DNS-Server',
            'GPMC',
            'DNS'
        )

        $Features.ForEach( {
                Write-Verbose "`t - $_" -Verbose
                WindowsFeature "$_" {
                    Ensure = 'Present'
                    Name   = $_
                }
            } )

        WaitForADDomain WaitForDomain {
            DomainName   = $DomainName
            WaitTimeout  = 60
        }

        Computer DomainJoin {
            Name       = $ComputerName
            DomainName = $DomainName
            Credential = $DomainCreds
            DependsOn  = '[WaitForADDomain]WaitForDomain'
        }

        File ADDSFolder {
            Ensure          = 'Present'
            Type            = 'Directory'
            DestinationPath = 'C:\ADDS'
        }

        ADDomain CreateForest {
            DomainName                    = $DomainName
            Credential                    = $DomainCreds
            SafemodeAdministratorPassword = $DomainCreds
            DatabasePath                  = 'C:\ADDS\NTDS'
            LogPath                       = 'C:\ADDS\NTDS'
            SysvolPath                    = 'C:\ADDS\Sysvol'
            ForestMode                    = 'Win2012R2'
            DomainMode                    = 'Win2012R2'
            DependsOn                     = '[WindowsFeature]AD-Domain-Services', '[File]ADDSFolder', '[Computer]DomainJoin'
        }

        PendingReboot RebootAfterPromotion {
            Name      = 'RebootAfterDCPromotion'
            DependsOn = '[ADDomain]CreateForest'
        }

        Script CreateADUsers {

            TestScript           = {
                Test-Path -Path 'C:\ADDS\Sysvol\postDeploy.flag'
            }

            GetScript            = {
                @{Result = (Get-Content -Path 'C:\ADDS\Sysvol\postDeploy.flag') }
            }

            SetScript            = {
                $password = ConvertTo-SecureString -String 'Lt-3@DTr00m4!' -AsPlainText -Force
                1..200 | ForEach-Object {
                    $userName = 'testuser-{0}' -f $_
                    New-ADUser -Name $userName -SamAccountName $userName -DisplayName $userName -PasswordNeverExpires $true -AccountPassword $password -Enabled $true
                }
                Set-Content -Path 'C:\ADDS\Sysvol\postDeploy.flag' -Value (Get-Date -Format yyyy-MM-dd-HH-mm-ss-ff)
            }
            DependsOn            = '[ADDomain]CreateForest'
            PsDscRunAsCredential = $DomainCreds
        }
    }
}


Configuration MemberServer {

    [CmdletBinding()]

    param (
        [string] $DomainName,
        [PSCredential] $DomainCreds
    )

    Import-DscResource -ModuleName PSDesiredStateConfiguration
    Import-DscResource -ModuleName ComputerManagementDsc
    Import-DscResource -ModuleName ActiveDirectoryDsc

    $ComputerName = $env:ComputerName
    $DomainName = Split-Path $DomainCreds.UserName

    Get-WmiObject -Class Win32_NetworkAdapterConfiguration -Filter 'IPEnabled=true and DHCPEnabled=true' | ForEach-Object {
        $_.InvokeMethod('ReleaseDHCPLease', $null)
        $_.InvokeMethod('RenewDHCPLease', $null)
    }

    node localhost {

        LocalConfigurationManager {
            RebootNodeIfNeeded   = $true
            AllowModuleOverwrite = $true
            ActionAfterReboot    = 'ContinueConfiguration'
        }

        WaitForADDomain WaitForDomain {
            DomainName  = $DomainName
            WaitTimeout = 60
        }

        Computer DomainJoin {
            Name       = $ComputerName
            DomainName = $DomainName
            Credential = $DomainCreds
            DependsOn  = '[WaitForADDomain]WaitForDomain'
        }
    }
}
