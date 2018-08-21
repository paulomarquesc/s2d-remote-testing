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
        $diskSpdFolder="diskspd"
    )

    $sb = {
        param(
            $client,
            $diskSpdFolder)
    
        Invoke-Command $client {
            param
            (
                $diskSpdFolder="diskspd"
            )

           mkdir "c:\$diskSpdFolder\" -force 
           $url = "https://pmcstorage01.blob.core.windows.net/public/diskspd.exe"
           $output = "c:\$diskSpdFolder\diskspd.exe"
           Start-BitsTransfer -Source $url -Destination $output

        } -ArgumentList $diskSpdFolder
    }

    $clients | % {Start-Job -Scriptblock $sb -ArgumentList $_, $diskSpdFolder }
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

        } -ArgumentList $parameters, $diskSpdFolder, $FileSuffix -Authentication Credssp -Credential $credential
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
        $destination=".",
        $FileSuffix
    )

    foreach ($client in $clients)
    {
        $file = "\\$client\c$\$diskSpdFolder\$client-$FileSuffix.xml"

        if (test-path $file)
        {
            Copy-Item -Path $file -Destination $destination
        }

        remove-item $file -force
    } 
}

function GenerateReport
{
    param
    (
        $reportsFolder="c:\diskspd"
    )

    $reportFiles = Get-ChildItem -Path $reportsFolder -Filter "*.xml"
    
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



# Clients

$clients = @("client-1","client-2","client-3","client-4","client-5","client-6","client-7","client-8","client-9","client-10")
$domainName = "sofs.local"
$localDiskSpdFolder = "diskSpd"

$executionFileSuffix = GetRandomSuffixString

#$secpasswd = ConvertTo-SecureString "" -AsPlainText -Force
#$creds = New-Object System.Management.Automation.PSCredential ("sofs\pmcadmin", $secpasswd)

$creds = Get-Credential

#EnableCredSSP -clients $clients -domainName $domainName 
#AllowFileServerServicesOnClients -clients $clients
#GenerateFiles -clients $clients -FileSuffix $executionFileSuffix
#DownLoadDiskSpd -clients $clients -diskSpdFolder "diskspd"

#------
# Notice that the file path on DiskSpd must be only up to the folder leve, the file name will be randomized
#------

#--------------
# 1 Client
# Xml report
#RunDiskSpd -clients "client-1" -diskSpdParameters "-c500G -d10 -r -w100 -t12 -b8M -h -L -Rxml \\s2d-sofs\Share01\testfile01.dat" -credential $creds -diskSpdFolder $localDiskSpdFolder -FileSuffix $executionFileSuffix
# Collect Report
#CollectReports -clients "client-1" 

#--------------
# All Clients
# Xml report
RunDiskSpd -clients $clients -diskSpdParameters "-c500G -d10 -r -w100 -t12 -b8M -h -L -Rxml \\s2d-sofs\Share01" -credential $creds -diskSpdFolder $localDiskSpdFolder -FileSuffix $executionFileSuffix
# Collect Report
CollectReports -clients $clients -FileSuffix $executionFileSuffix

# Generate Report
GenerateReport -FileSuffix $executionFileSuffix

#remove-item C:\diskspd\*.xml -Force
