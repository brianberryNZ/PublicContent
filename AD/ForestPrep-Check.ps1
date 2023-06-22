<#
.SYNOPSIS
  The script must be run from a server which has the Active Directory PowerShell module installed.
  Access rights will need to be Domain Admin to be able to read some of the attributes.

.DESCRIPTION
  Script to read various Active Directory version and replication status info.

.COMPONENT
  None

.PARAMETER DomainName
  Comma seperated list of new IPs. Two maximum, using the format: "10.0.0.1,10.0.0.2"

.PARAMETER LogFilePath
  Path to the report folder to which reports will be written in a CSV format. Leave off the trailing \ e.g. C:\Temp.
  !!! Note !!! This path must exist on the target server. The log cannot be written to the source server or an alternate location.

.PARAMETER ActiontoTake
  This is either:
    DCReplication - Check and log more AD replication info from the forest, but each server is queried for its "Version of the truth"
    ADReplMetaData - Check and log the replication status of all domain controllers in the domain. Note! need to run this for each target domain.
    ForestVersion - Check and log the Schema version (objectVersion), Forest Update version (Revision) and Domain Update version (Revision)

.INPUTS
  DomainName - The domain name for the DC replication you want to check
  LogFilePath - Path to the log file. Leave off the trailing \
  ActiontoTake - Which info do you want to gather? See .PARAMETER ActiontoTake

.OUTPUTS
  Log files stored in $LogFilePath + "\"

.NOTES
  Version:        0.2
  Author:         Brian Berry
  Creation Date:  21/06/2023
  Purpose/Change: Initial script development
  
.EXAMPLE
  .\ForestPrep-Check.ps1 -LogFilePath c:\scripts\Reports -ActiontoTake ForestVersion

.EXAMPLE
  .\ForestPrep-Check.ps1 -LogFilePath c:\scripts\Reports -ActiontoTake DCReplication

 .EXAMPLE
  .\ForestPrep-Check.ps1 -DomainName contoso2022.com -LogFilePath c:\scripts\Reports -ActiontoTake ADReplMetaData
#>

Param (
        [Parameter(Mandatory = $True)]
        [string]$LogFilePath,
        [Parameter(Mandatory = $True)]
        [string]$ActiontoTake,
        [Parameter(Mandatory = $False)]
        [string]$DomainName
)

Import-Module ActiveDirectory

# Check and log the Schema version (objectVersion), Forest Update version (Revision) and Domain Update version (Revision)
function ForestCheck {
  $ADSIDom = Get-ADRootDSE | Select-Object rootDomainNamingContext, forestFunctionality, domainFunctionality
  $SchemaPath = "AD:\CN=Schema,CN=Configuration,$($ADSIDom.rootDomainNamingContext)"
  $ForestUPath = "AD:\CN=ActiveDirectoryUpdate,CN=DomainUpdates,CN=System,$($ADSIDom.rootDomainNamingContext)"
  $DomainUPath = "AD:\CN=ActiveDirectoryUpdate,CN=ForestUpdates,CN=Configuration,$($ADSIDom.rootDomainNamingContext)"
  $Schema = Get-ItemProperty "$SchemaPath" -Name objectVersion | Select-Object objectVersion, PSPath
  $ForestUpdate = Get-ItemProperty "$ForestUPath" -Name Revision | Select-Object Revision, PSPath
  $DomainUpdate = Get-ItemProperty "$DomainUPath" -Name Revision | Select-Object Revision, PSPath

  $Newrow = [pscustomobject] @{
      "Schema PSPath" = $Schema.PSPath
      "Forest PSPath" = $ForestUpdate.PSPath
      "Domain PSPath" = $DomainUpdate.PSPath
      "Schema Version" = $Schema.objectVersion
      "Forest Version" = $ForestUpdate.Revision
      "Domain Version" = $DomainUpdate.Revision
      "Forest Function" = $ADSIDom.forestFunctionality
      "Domain Function" = $ADSIDom.domainControllerFunctionality
      "Date" = Get-Date -Format "dd/MM/yyyy HH:mm:ss"
  }
  $NewRow | Out-File -FilePath $($LogFilePath + "\" + "ForestUpdateInfo.csv") -Append
}

# Check and log the replication status of all domain controllers in the domain. Note! need to run this for each target domain.
function ADReplMetaData {
        $Meta = Get-ADReplicationPartnerMetadata -Target $DomainName -scope Domain -PartnerType Both -Partition * | Select-Object Server, Partner, LastReplicationAttempt, LastReplicationResult, LastReplicationSuccess, Partition, PartnerType, ConsecutiveReplicationFailures
        # Get-ADReplicationPartnerMetadata -target $Server -scope server | Where-Object {$_.lastreplicationresult -ne "0"} | Select-Object server,lastreplicationattempt,lastreplicationresult,partner
        $Meta | Export-CSV -Path $($LogFilePath + "\" + "ADReplMetaData.csv") -Append -NoTypeInformation
}

# Check and log more AD replication info from the forest, but each server is queried for its "Version of the truth"
function DCReplication {
  $DCs = Get-ADDomainController -filter * | Select-Object HostName
    foreach ($DCServer in $DCs) {
        $Vector = Get-ADReplicationUpToDatenessVectorTable -Scope Forest | Select-Object LastReplicationSuccess, Partition, Partner, Server, UsnFilter # This can take a while to run for the forest
        $ReplFail = Get-ADReplicationFailure -Target $DCServer -Scope Server | Select-Object FailureCount, FailureType, Partner, LastError
        # $Vector | Get-member -MemberType NoteProperty | Select-Object -ExpandProperty Name | Out-File -FilePath $($LogFilePath + "\" + $DCServer.HostName + "_ForestVectorTable.csv") -Append
        if ($Null -eq $ReplFail) {
          Write-Host -ForegroundColor DarkGreen -BackgroundColor White "There were no replication failures detected."
          $ReplFail | Out-File -FilePath $($LogFilePath + "\" + $DCServer.HostName + "_ForestReplFailures.csv")
        }
        else {
          $ReplFail | Export-CSV -Path $($LogFilePath + "\" + $DCServer.HostName + "_ForestReplFailures.csv") -Append -NoTypeInformation -Force
        }

        $Vector | Export-CSV -Path $($LogFilePath + "\" + $DCServer.HostName + "_ForestVectorTable.csv") -Append -NoTypeInformation
    }
}

# Check that the file path for reports exists, if not create it.
Function FileCheck {
  $PathExist = Test-Path -Path ($LogFilePath + "\")
  if (!$PathExist) {
    New-Item -ItemType "directory" -Path "$LogFilePath"
  }
}

# Script section to run the various functions to get stuff done
if ($ActiontoTake -eq "ForestVersion") {
  Write-Host -ForegroundColor DarkGreen "Getting version information"
  FileCheck
  ForestCheck
}
elseif ($ActiontoTake -eq "ADReplMetaData") {
  Write-Host -ForegroundColor Green "Getting the AD Replication MetaData"
  FileCheck
  ADReplMetaData
}
elseif ($ActiontoTake -eq "DCReplication") {
  Write-Host -ForegroundColor Black -BackgroundColor White "Getting the DCReplication info. !!This will take a while!!"
  FileCheck
  DCReplication
}