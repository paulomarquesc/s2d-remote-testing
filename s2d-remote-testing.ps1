function GenerateFiles
{
    param
    (
        $clients
    )

    $sb = {
        param($client)
    
        Invoke-Command $client { 
            delete-item d:\*.dat -force
            $fileName="$($env:computername)-$(get-random -Minimum 1000 -Maximum 3738173363251507200)-$([guid]::NewGuid().guid).dat"
            fsutil file createnew "d:\$fileName" 1024
        }
    }

    $clients | % {Start-Job -Scriptblock $sb -ArgumentList $_ }
    Get-Job | Wait-Job | Receive-Job

}

function CheckDiskSpdFolderParameter
{
    param
    (
        $parameter
    )

    if ($parameter.contains("c:"))
    {
        throw "Parameter can't contain drive letters, current value is: $parameter"
    }
}

function GetRandomSuffixString
{
    return "$(get-random -Minimum 1000 -Maximum 37381733632)-$([guid]::NewGuid().guid)"
}

function GenerateFiles
{
    param
    (
        $clients,
        $FileSuffix
    )

    $sb = {
        param($client)
    
        Invoke-Command $client { 
            delete-item d:\*.dat -force
            $fileName="$($env:computername)-$FileSuffix.dat"
            fsutil file createnew "d:\$fileName" 1024
        }
    }

    $clients | % {Start-Job -Scriptblock $sb -ArgumentList $_ }
    Get-Job | Wait-Job | Receive-Job

}

function EnableCredSSP
{
    param
    (
        $clients,
        $domainName
    )

    $sb = {
        param
        (
            $client,
            $domainName,
            $clientList
        )
    
        Invoke-Command $client { 
            param
            (
                $domainName,
                $clientList
            )

            Enable-PSRemoting -force -SkipNetworkProfileCheck -ErrorAction SilentlyContinue
            Enable-WSManCredSSP -Role Server -Force
            Enable-WSManCredSSP -Role Client -DelegateComputer locahost -Force
            Enable-WSManCredSSP -Role Client -DelegateComputer $env:COMPUTERNAME -Force
            Enable-WSManCredSSP -Role Client -DelegateComputer $domainName -Force
            Enable-WSManCredSSP -Role Client -DelegateComputer "*.$domainName" -Force
            Enable-WSManCredSSP -Role Client -DelegateComputer $clientList -Force

            #Restart-Computer -Force

        } -ArgumentList $domainName, $clientList 
    }

    $clients | % {Start-Job -Scriptblock $sb -ArgumentList $_,$domainName,$clients }
    Get-Job | Wait-Job | Receive-Job

}
function AllowFileServerServicesOnClients
{
    param
    (
        $clients
    )

    $sb = {
        param($client)
    
        Invoke-Command $client { 
                Set-NetFirewallRule -DisplayGroup 'File and Printer Sharing' -Enabled True -PassThru | Out-Null
            }
    }

    $clients | % {Start-Job -Scriptblock $sb -ArgumentList $_ }
    Get-Job | Wait-Job | Receive-Job
}

function DownLoadDiskSpd
{
    param
    (
        $clients,
        $diskSpdFolder="diskspd",
        $url
    )

    CheckDiskSpdFolderParameter -parameter $diskSpdFolder

    $sb = {
        param
        (
            $client,
            $diskSpdFolder,
            $url
        )
    
        Invoke-Command $client {
            param
            (
                $diskSpdFolder="diskspd",
                $url
            )

           mkdir "c:\$diskSpdFolder\" -force 
           $url = "$URL/diskspd.exe"
           $output = "c:\$diskSpdFolder\diskspd.exe"
           Start-BitsTransfer -Source $url -Destination $output

        } -ArgumentList $diskSpdFolder, $url
    }

    $clients | % {Start-Job -Scriptblock $sb -ArgumentList $_, $diskSpdFolder, $url }
    Get-Job | Wait-Job | Receive-Job
}

function RunDiskSpd
{
    param
    (
        $clients,
        $diskSpdParameters,
        [pscredential]$credential,
        $diskSpdFolder="diskspd",
        $FileSuffix
    )
    
    CheckDiskSpdFolderParameter -parameter $diskSpdFolder

    $sb = {
        param
        (
            $client,
            $parameters,
            [pscredential]$credential,
            $diskSpdFolder="diskspd",
            $FileSuffix
        )
        
        Invoke-Command $client {
            param
            (
                $diskSpdParameters,
                $diskSpdFolder="c:\diskspd",
                $FileSuffix
            )

            function GetRandomSuffixString
            {
                return "$(get-random -Minimum 1000 -Maximum 37381733632)-$([guid]::NewGuid().guid)"
            }

            $ext = "txt"
            if ($diskSpdParameters.Contains("xml"))
            {
                $ext = "xml"
            }

            $reportFile = "c:\$diskSpdFolder\$($env:computername)-$FileSuffix.$ext"

            $args = $diskSpdParameters.Split(" ")

            # Creating random file name
            $args[$args.count-1]=[system.io.path]::Combine($args[$args.count-1],"$($env:computername)-$(GetRandomSuffixString).dat")

            & "c:\$diskSpdFolder\DiskSpd.exe" $args | out-file $reportFile

            # Wait 5 minutes
            Start-Sleep (get-random -Minimum 100 -Maximum 300)

        } -ArgumentList $parameters, $diskSpdFolder, $FileSuffix -Authentication Credssp -Credential $credential -EnableNetworkAccess
    }

    $clients | % {Start-Job -Scriptblock $sb -ArgumentList $_, $diskSpdParameters, $creds, $diskSpdFolder, $FileSuffix }
    Get-Job | Wait-Job | Receive-Job
}

function CollectReports
{
    param
    (
        $clients,
        $diskSpdFolder="diskspd",
        $destination,
        $FileSuffix
    )
        
    CheckDiskSpdFolderParameter -parameter $diskSpdFolder

    foreach ($client in $clients)
    {
        $file = "\\$client\c$\$diskSpdFolder\$client-$FileSuffix.xml"

        if (test-path $file)
        {
            Copy-Item -Path $file -Destination "c:\$destination"
        }

        #remove-item $file -force
    } 
}

function CleanUpReports
{
    param
    (
        $clients,
        $diskSpdFolder="diskspd"
    )

    CheckDiskSpdFolderParameter -parameter $diskSpdFolder

    foreach ($client in $clients)
    {
        $reportFiles = Get-ChildItem -Path "\\$client\c$\$diskSpdFolder\$client-*.xml"
    
        foreach ($file in $reportFiles)
        {
            Remove-Item -Path $file.FullName -Force
        }
    }
}

function GenerateReport
{
    param
    (
        $reportsFolder="diskspd",
        $FileSuffix
    )

    CheckDiskSpdFolderParameter -parameter $reportsFolder
    
    $reportFiles = Get-ChildItem -Path (join-path "c:\$reportsFolder" "*$FileSuffix.xml")
    
    $report = @()

    [uint64]$TotalIOCount = 0
    [uint64]$TotalReadMB = 0
    [uint64]$TotalWriteMB = 0
    [uint64]$TotalReadMBps = 0
    [uint64]$TotalWriteMBps = 0
    [uint64]$TotalIOPs = 0

    foreach ($file in $reportFiles)
    {
        $xml = New-Object XML
        $xml.Load($file.FullName)

        # Getting total time in seconds
        $ComputerName = $xml.results.system.computername
        $TestPath = $xml.Results.TimeSpan.Thread[0].Target.Path
        $TotalTimeInSec = $xml.Results.TimeSpan.TestTimeSeconds

        [uint64]$IOCount = 0
        [uint64]$ReadBytes = 0
        [uint64]$WriteBytes = 0

        foreach ($thread in  $xml.Results.TimeSpan.Thread)
        {
            $IOCount = $IOCount + $thread.target.IOCount
            $ReadBytes = $ReadBytes + $thread.target.ReadBytes
            $WriteBytes =   $WriteBytes + $thread.target.WriteBytes
        }

        [uint64]$ReadMBps =  ($ReadBytes / $TotalTimeInSec) / 1024 / 1024
        [uint64]$WriteMBps = ($WriteBytes / $TotalTimeInSec) / 1024 / 1024
        [uint64]$IOPs = $IOCount / $TotalTimeInSec

        $report += New-Object -TypeName PSObject -Property @{"ComputerName" = $ComputerName; `
                                                             "TestPath" = $TestPath; `
                                                             "TotalTimeInSec" =  $TotalTimeInSec; `
                                                             "IOCount" = $IOCount; `
                                                             "IOPs" = [math]::round($IOPs); `
                                                             "ReadMB" = [math]::round($ReadBytes / 1024 / 1024); `
                                                             "ReadMBps" = [math]::round($ReadMBps); `
                                                             "WriteMB" = [math]::round($WriteBytes / 1024 / 1024); `
                                                             "WriteMBps" = [math]::round($WriteMBps); `
                                                            } 
        
        # Totals
        $TotalIOCount = $TotalIOCount + $IOCount
        $TotalReadMB = $TotalReadMB + [math]::round($ReadBytes / 1024 / 1024)
        $TotalWriteMB = $TotalWriteMB + [math]::round($WriteBytes / 1024 / 1024)
        $TotalReadMBps = $TotalReadMBps + [math]::round($ReadMBps)
        $TotalWriteMBps = $TotalWriteMBps + [math]::round($WriteMBps)
        $TotalIOPs = $TotalIOPs + [math]::round($IOPs)

        $xml=$null

    }

    $report += New-Object -TypeName PSObject -Property @{"ComputerName" = "TOTAL=>"; `
                                                         "TestPath" = ""; `
                                                         "TotalTimeInSec" =  $TotalTimeInSec; `
                                                         "IOCount" = $TotalIOCount; `
                                                         "IOPs" = $TotalIOPs; `
                                                         "ReadMB" = $TotalReadMB; `
                                                         "ReadMBps" = $TotalReadMBps; `
                                                         "WriteMB" = $TotalWriteMB; `
                                                         "WriteMBps" = $TotalWriteMBps; `
                                                        } 

    return $report | Select-Object ComputerName, TestPath, TotalTimeInSec, IOCount, IOPs, ReadMB, ReadMBps, WriteMB, WriteMBps | format-table

}

$ErrorActionPreference = "Stop"

# Cleaning up any oustanding jobs
Get-Job | Stop-Job
Get-Job | Remove-Job

# Clients

# All VMs to enable CredSSP (must include jumpboxes, clients and S2D Cluster Node server
$AllServers = @("client-1","client-2","client-3","client-4","client-5","client-6","client-7","client-8","client-9","client-10","jumpbox","s2d-node-1","s2d-node-2","s2d-node-3")

# All VMs acting as Clientes
$Clients = @("client-1","client-2","client-3","client-4","client-5")

# Domain Name
$domainName = "sofs.local"

# DiskSpd URL download, must be the URL that has the .exe file which is already hardcoded, e.g. a Storage Account: https://mystorage.blob.core.windows.net/public
$url = "https://raw.githubusercontent.com/paulomarquesc/s2d-remote-testing/master"

# Folder to store (don't add drive, it is hardcoded to c:\)
$diskSpdFolder = "diskSpd"

# SOFS Share
$share="\\s2d-sofs\Share01"

# Getting random suffix
$executionFileSuffix = GetRandomSuffixString
Write-Verbose "Working with file suffix $executionFileSuffix" -Verbose

# Getting Domain Admin credentials
#$creds = Get-Credential

# Cleaning up old reports from clients
#CleanUpReports -clients $clients -diskSpdFolder "diskspd"

#--------
# Uncomment line below to enable CredSSP on all VMs listed in -clients parameter
#--------
#EnableCredSSP -clients $AllServers -domainName $domainName 

#--------
# Uncomment line below to add Firewall exceptions for "File and Print Sharing" ports on Windows firewall of VMs acting as clients
#--------
#AllowFileServerServicesOnClients -clients $clients

#--------
# Uncomment line below to add Firewall exceptions for "File and Print Sharing" ports on Windows firewall of VMs acting as clients
#--------
#DownLoadDiskSpd -clients $clients -diskSpdFolder "diskspd" -url $url

#
# Notice that the file path on DiskSpd must be only up to the folder level, the file name will be randomized
#

#--------------
# 1 Client Testing
# Xml report
#RunDiskSpd -clients "client-5" -diskSpdParameters "-c10G -d10 -r -w100 -t12 -b8M -Sh -Rxml \\s2d-sofs\Share01" -credential $creds -diskSpdFolder $DiskSpdFolder -FileSuffix $executionFileSuffix
# Collect Report
#CollectReports -clients "client-5" -FileSuffix $executionFileSuffix -destination $DiskSpdFolder"

#--------------
# All Clients Testing
# Xml report
#$diskSpeedCommandLine = "-c10G -d30 -r -w100 -t12 -b8M -Sh -W20 -C45 -Rxml \\s2d-sofs\Share01"
#RunDiskSpd -clients $clients -diskSpdParameters $diskSpeedCommandLine -credential $creds -diskSpdFolder $DiskSpdFolder -FileSuffix $executionFileSuffix
# Collect Report
#CollectReports -clients $clients -FileSuffix $executionFileSuffix -destination $DiskSpdFolder

# Generate Report
GenerateReport -reportsFolder $DiskSpdFolder -FileSuffix $executionFileSuffix

# If execution fails, remember to run line below anyways, this will delete local copies of the reports
#remove-item C:\diskspd\*.xml -Force
