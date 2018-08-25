#-----------------------
# Robocopy based testing
#
# Notes:
#     - Script designed to run on test environments only
#     - CredSSP is enabled on all VMs defined on $AllServers
#     - Preparation phase requires all VMs defined on $AllServers array to reboot since it enables CredSSP
#-----------------------

[CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact="High")]
param
(
    [switch]$PrepareEnvironment
)

. (Join-Path ([System.IO.Path]::GetDirectoryName($MyInvocation.MyCommand.Definition)) "PerformanceTestCoreHelper.ps1")

$ErrorActionPreference = "Stop"

#----------------
# Main Variables
#----------------

# All VMs to enable CredSSP (must include jumpboxes, clients and S2D Cluster Node servers
$AllServers = @("client-1","client-2","client-3","client-4","client-5","client-6","client-7","client-8","client-9","client-10","s2d-node-1","s2d-node-2","s2d-node-3","s2d-node-4","s2d-node-5","s2d-node-6","s2d-node-7","s2d-node-8","s2d-node-9","s2d-node-10","s2d-node-11","s2d-node-12","s2d-node-13","s2d-node-14","s2d-node-15","s2d-node-16")

# All VMs acting as Clients
$Clients = @("client-1","client-2","client-3","client-4","client-5","client-6","client-7","client-8","client-9","client-10")

# Domain Name
$domainName = "sofs.local"

# DiskSpd URL download, must be the URL that has the .exe file which is already hardcoded, e.g. a Storage Account: https://mystorage.blob.core.windows.net/public
$url = "https://raw.githubusercontent.com/paulomarquesc/s2d-remote-testing/master"

# Folder to store (don't add drive, it is hardcoded to c:\)
$DiskSpdFolder = "diskSpd"

# SOFS Share
$share="\\s2d-sofs\Share01"

#---------------
# Preparation
#     - Enables CredSSP
#     - Reboots all servers defined on $AllServers array
#     - Adds exceptions on Windows Firewall to group "File and Print Services"
#     - Downloads DiskSpd.exe from the URL defined in $URL variable above   
#---------------
if ($PrepareEnvironment)
{
    if (Test-Path ./PrepPhaseTestRobocopy.txt)
    {
        throw "Preparation phase of this test was already executed, plesae remove -PrepareEnvironment switch from command line"
    }

    if ($PSCmdlet.ShouldProcess([system.string]::join(", ", $allservers), "*** MANDATORY REBOOT ***"))
    {
        #--------
        # Uncomment line below to enable CredSSP on all VMs listed in -clients parameter
        #--------
        EnableCredSSP -clients $AllServers -domainName $domainName 

        Start-Sleep 600 # Waits for 10 minutes before moving forward in order to wait all VMs to reboot

        Write-Verbose "Preparation phase of this script executed, please run again without the -PrepareEnvironment" -Verbose
        "Done" | Add-Content ./PrepPhaseTestRobocopy.txt

        exit
    }
}

if (-Not (Test-Path ./PrepPhaseTestRobocopy.txt))
{
    throw "Preparation phase of this test was not executed, plesae read carefully the preparation section of this code to understand what needs to be done and implications."
}

# Cleaning up any oustanding jobs
Get-Job | Stop-Job
Get-Job | Remove-Job

# SOFS Share
$share="\\s2d-sofs\Share01"

# Getting Domain Admin credentials
$creds = Get-Credential

#------------------------------------------------------
# *** CUSTOM TESTING ROBOCOPY ***
#------------------------------------------------------

# Single test, single client Example
#-----------------------------------

#PrepareClientLocalSourceFilesRobocopy -Clients "client-1" -LocalFolder $localClientPath -Credential $creds -NumberOfFiles 10000 -FileSize 10KB
#RunCustomTestWriteOnlyRobocopy -Clients "client-1" -Credential $creds -SourceFolder $localClientPath -DestinationFolder  "$share\$([guid]::NewGuid().Guid)" -ReportFileSuffix  $executionFileSuffix  -ThreadCount 1 -Description "Xyz"

# Multiple test, multiple clients example
#----------------------------------------
$sourcefolders = @("d:\sources_100000_Files_10240_10KB",
                   "d:\sources_2000_Files_52428800_50MB",
                   "d:\sources_100_Files_524288000_500MB",
                   "d:\sources_50_Files_1048576000_1GB")

$reportFilePrefix="S2D-3NodeCluster"

$descriptions = @("$($reportFilePrefix)_100Kfiles_10KB_each",
                  "$($reportFilePrefix)_2K_files_50MB_each",
                  "$($reportFilePrefix)_100_files_500MB_each",
                   "$($reportFilePrefix)_50_files_1GB_each")

$Clients = @("client-1","client-2","client-3","client-4","client-5","client-6","client-7","client-8","client-9","client-10")

# Restarting VMs before test starts
# if ($PSCmdlet.ShouldProcess([system.string]::join(", ", $Clients), "*** MANDATORY REBOOT ON ALL CLIENTS ***"))
# {
#     RestartVMs -clients $Clients
# }

# # Uncomment for Preparing the test source files
# # foreach ($folder in $sourcefolders)
# # {
# #     $fileCount=$folder.split("_")[1]
# #     $fileSize=$folder.split("_")[3]
# #     PrepareClientLocalSourceFilesRobocopy $Clients -LocalFolder $folder -Credential $creds -NumberOfFiles $fileCount -FileSize $fileSize
# #     Write-Host "Folder=$Folder,CompletionTimeSec=$($result.TotalSeconds)" | Add-Content ./FolderPrepTimings.txt
# # }

# # Running  tests

$i=0
foreach ($folder in $sourcefolders )
{
    $executionFileSuffix = GetRandomSuffixString
    Write-Verbose "Working with file suffix $executionFileSuffix" -Verbose

    $result = Measure-Command {RunCustomTestWriteOnlyRobocopy -Clients $Clients -Credential $creds -SourceFolder $folder -DestinationFolder  "$share\$([guid]::NewGuid().Guid)" -ReportFileSuffix  "$reportFilePrefix-$executionFileSuffix" -ThreadCount 32 -Description $descriptions[$i]}
    CollectReports -clients $clients -FileSuffix "*$reportFilePrefix-$executionFileSuffix.json" -destination "c:\myReports-$($descriptions[$i])"

    Write-Verbose "Test $($descriptions[$i]) completed in $($result.TotalSeconds) end to end." -Verbose
    $i++
}


# Small scale test
# # # # $sourcefolders = @("d:\sources_3_Files_52428800_50MB",
# # # #                     "d:\sources_50_Files_1048576000_1GB")

# # # # $reportFilePrefix="S2D-3NodeCluster"

# # # # $descriptions = @("$($reportFilePrefix)_3files_50MB_each",
# # # #                   "$($reportFilePrefix)_50_files_1GB_each")

# # # # $Clients = @("client-1","client-2","client-3")

# # # # # Running  tests

# # # # $i=0
# # # # foreach ($folder in $sourcefolders )
# # # # {
# # # #     $executionFileSuffix = GetRandomSuffixString
    
# # # #     Write-Verbose "Working with file suffix $executionFileSuffix" -Verbose

# # # #     $result = Measure-Command {RunCustomTestWriteOnlyRobocopy -Clients $Clients -Credential $creds -SourceFolder $folder -DestinationFolder  "$share\$([guid]::NewGuid().Guid)" -ReportFileSuffix  "$reportFilePrefix-$executionFileSuffix" -ThreadCount 32 -Description $descriptions[$i]}
# # # #     CollectReports -clients $clients -FileSuffix "*$reportFilePrefix-$executionFileSuffix.json" -destination "c:\myReports-$($descriptions[$i])"

# # # #     Write-Verbose "Test $($descriptions[$i]) completed in $($result.TotalSeconds) end to end." -Verbose
# # # #     $i++
# # # # }



Write-Verbose "Script execution finished." -Verbose