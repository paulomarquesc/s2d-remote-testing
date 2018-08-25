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

            Restart-Computer -Force

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
        $FileSuffix,
        $filesCount=1
    )
    
    CheckDiskSpdFolderParameter -parameter $diskSpdFolder

    $sb = {
        param
        (
            $client,
            $parameters,
            [pscredential]$credential,
            $diskSpdFolder="diskspd",
            $FileSuffix,
            $filesCount=1
        )
        
        Invoke-Command $client {
            param
            (
                $diskSpdParameters,
                $diskSpdFolder="c:\diskspd",
                $FileSuffix,
                $filesCount=1
            )

            function GetRandomSuffixString
            {
                return "-$([guid]::NewGuid().guid)"
            }

            $ext = "txt"
            if ($diskSpdParameters.Contains("xml"))
            {
                $ext = "xml"
            }

            $reportFile = "d:\$($env:computername)-$FileSuffix.$ext"

            $args = $diskSpdParameters.Split(" ")

            if ($filesCount -gt 1)
            {
                $args[$args.count-1]=[system.io.path]::Combine($args[$args.count-1],"$($env:computername)-$(GetRandomSuffixString).dat") 
                for ($i=1; $i -lt $filesCount; $i++) 
                {
                    # Creating multiple random file name
                    $newName=[system.io.path]::Combine([system.io.path]::GetDirectoryName($args[$args.count-1]),"$($env:computername)-$(GetRandomSuffixString).dat")
                    $args+=$newName
                }
            }
            else
            {
                # Creating random file name
                $args[$args.count-1]=[system.io.path]::Combine($args[$args.count-1],"$($env:computername)-$(GetRandomSuffixString).dat")

            }
           

            & "c:\$diskSpdFolder\DiskSpd.exe" $args | out-file $reportFile


        } -ArgumentList $parameters, $diskSpdFolder, $FileSuffix, $filesCount -Authentication Credssp -Credential $credential -EnableNetworkAccess
    }

    $clients | % {Start-Job -Scriptblock $sb -ArgumentList $_, $diskSpdParameters, $creds, $diskSpdFolder, $FileSuffix, $filesCount }
    Get-Job | Wait-Job | Receive-Job
}

Function New-RandomFile_Fast {
    Param(
        $Path = (Resolve-Path '.').Path, 
        $FileSize = 1kb, 
        $FileName = [guid]::NewGuid().Guid + '.dat'
        ) 

    $Chunk = { [guid]::NewGuid().Guid + [guid]::NewGuid().Guid + [guid]::NewGuid().Guid + [guid]::NewGuid().Guid +
               [guid]::NewGuid().Guid + [guid]::NewGuid().Guid + [guid]::NewGuid().Guid + [guid]::NewGuid().Guid +
               [guid]::NewGuid().Guid + [guid]::NewGuid().Guid + [guid]::NewGuid().Guid + [guid]::NewGuid().Guid +
               [guid]::NewGuid().Guid + [guid]::NewGuid().Guid + [guid]::NewGuid().Guid + [guid]::NewGuid().Guid +
               [guid]::NewGuid().Guid + [guid]::NewGuid().Guid + [guid]::NewGuid().Guid + [guid]::NewGuid().Guid +
               [guid]::NewGuid().Guid + [guid]::NewGuid().Guid + [guid]::NewGuid().Guid + [guid]::NewGuid().Guid +
               [guid]::NewGuid().Guid + [guid]::NewGuid().Guid + [guid]::NewGuid().Guid + [guid]::NewGuid().Guid +
               [guid]::NewGuid().Guid + [guid]::NewGuid().Guid + [guid]::NewGuid().Guid + [guid]::NewGuid().Guid -Replace "-" }
    $Chunks = [math]::Ceiling($FileSize/1kb)
    $ChunkString = $Chunk.Invoke()

    [io.file]::WriteAllText("$Path\$FileName","$(-Join (1..($Chunks)).foreach({ $ChunkString }))")
}

function PrepareSourceFiles
{
    param
    (
        $sharedFolder,
        $numberOfFiles=2048,
        $fileSize=50MB
    )

    for ($i=0;$i -lt $numberOfFiles;$i++)
    {
        New-RandomFile_Fast -path $sharedFolder -FileSize $fileSize
    }
}

function RunCustomTestReadOnlyPS
{
    # This test reads x amount of files from a folder
    param
    (
        $clients,
        [pscredential]$credential,
        $sourceFolder,
        $ReportFileSuffix,
        $ThreadCount,
        $SecondsBetweenJobCheckForCompletion=10
    )
    
    #CheckDiskSpdFolderParameter -parameter $diskSpdFolder

    $sb = {
        param
        (
            $client,
            [pscredential]$credential,
            $sourceFolder,
            $ReportFileSuffix,
            $ThreadCount=4,
            $SecondsBetweenJobCheckForCompletion=10
        )
        
        # Client code
        Invoke-Command $client {

            param
            (
                $SourceFolder,
                $ReportFileSuffix,
                $ThreadCount = 4,
                $SecondsBetweenJobCheckForCompletion=10
            )
            
            function ExecuteReadTest
            {
                param
                (
                    $ThreadCount = 4,
                    $TestFilesPath,
                    $ReportFileSuffix,
                    $SecondsBetweenJobCheckForCompletion=10
                )

                $pool = [runspacefactory]::CreateRunspacePool(1, $threadCount)
                $pool.ThreadOptions = "UseNewThread"
                $pool.Open()   
                
                $Files = Get-ChildItem -Path $TestFilesPath

                if ($files.count -eq 0)
                {
                    throw "An error ocurred, no files were selected from criteria: $TestFilesPath "
                }

                                
                $result = New-Object -TypeName PSObject @{  "Items"=@();
                                                            "Summary"=@{"TestName"="ReadOnly";
                                                                        "AvgFileSizeBytes"=0;
                                                                        "FileCount"=$files.count;
                                                                        "ReadTotalBytes"=0;
                                                                        "ReadTotalMB"=0;
                                                                        "ReadAvgSecondsPerFile"=0;
                                                                        "ReadAvgMBpsPerFile"=0;
                                                                        "ThreadsUsed"=$ThreadCount;
                                                                        "Client"=$env:computername}}
                
                $FileIndex = 0
                for ($x=0; $x -lt $Files.Count; $x = $x + $threadCount )
                {
                    $jobs = @()   
                    $ps = @()  
                
                    for ($i = 0; $i -lt $threadCount ; $i++) {   
                        $ps += [powershell]::create()
                        $ps[$i].runspacepool = $pool  
                    
                        # reads the Files
                        [void]$ps[$i].AddScript({
                            param
                            (
                                $File,
                                $FileIndex
                            )
                            
                            if (Test-Path $File.FullName)
                            {
                                $result = Measure-Command {$data = [io.file]::ReadAllBytes($File.FullName)}
                
                                [PSCustomObject]@{
                                    Count = $FileIndex
                                    ThreadId = [appdomain]::GetCurrentThreadId()
                                    FileName = $File.FullName
                                    BytesRead = $data.Count
                                    Seconds= $result.TotalMilliseconds / 1000
                                }
                            }
                
                        }).AddParameter('File',$Files[$FileIndex]).AddParameter('FileIndex',$FileIndex)  
                    
                        # start job   
                        $jobs += $ps[$i].BeginInvoke();   
                    
                        $FileIndex += 1
                    }   
                
                    while ($finishedJobs -ne $jobs.Count)
                    {
                        $finishedJobs = ($jobs | ? {$_.iscompleted}).count
                        Start-Sleep $SecondsBetweenJobCheckForCompletion
                    }
                
                    # end async call   
                    for ($i = 0; $i -lt $threadCount; $i++)
                    {   
                        try
                        {   
                            # complete async job   
                            $result.items += $ps[$i].EndInvoke($jobs[$i])
                        }
                        catch
                        {   
                            write-warning "error: $_"  
                        }   
                    }
                }
                
                $pool.Close()  

                [double]$totalSeconds=0
                [uint64]$totalBytes=0
                [double]$totalMB=0
                [int32]$totalMBps=0
                
                ($result.items).foreach({ 
                                        $_ | Add-Member -Type NoteProperty -Name "MBRead" -Value ($_.BytesRead / 1024 / 1024)
                                        $_ | Add-Member -Type NoteProperty -Name "MBps" -Value (($_.BytesRead / 1024 / 1024)/$_.Seconds)
                
                                        $totalSeconds += $_.Seconds
                                        $totalBytes += $_.BytesRead
                                        $totalMB += $_.MBRead
                                        $totalMBps += $_.MBps
                            })
                
                $result.summary.ReadAvgSecondsPerFile = $totalSeconds / $result.items.Count
                $result.summary.ReadTotalBytes = $totalBytes
                $result.summary.AvgFileSizeBytes = $totalBytes / $result.items.Count
                $result.summary.ReadTotalMB = $totalMB
                $result.summary.ReadAvgMBpsPerFile = [math]::round($totalMBps / $result.items.Count)
                
                # Results list
                $reportFile = "d:\$($env:computername)-ReadOnly-$ReportFileSuffix.json"
                [io.file]::WriteAllText($reportFile, ($result | ConvertTo-Json -Depth 3))
            }

            $TestFiles = Join-Path $sourceFolder "*.dat"
            ExecuteReadTest -ThreadCount $ThreadCount -TestFilesPath $TestFiles -FileSuffix $ReportFileSuffix -SecondsBetweenJobCheckForCompletion $SecondsBetweenJobCheckForCompletion
            
        } -ArgumentList $sourceFolder,$ReportFileSuffix,$ThreadCount, $SecondsBetweenJobCheckForCompletion -Authentication Credssp -Credential $credential -EnableNetworkAccess
        # End of Client code
    }

    $clients | % {Start-Job -Scriptblock $sb -ArgumentList $_, $credential, $sourceFolder, $ReportFileSuffix, $ThreadCount, $SecondsBetweenJobCheckForCompletion }
    Get-Job | Wait-Job | Receive-Job
}

function RunCustomTestWriteOnlyPS
{
    # This test writes files of x amount of size in a folder
    param
    (
        $clients,
        [pscredential]$credential,
        $destinationFolder,
        $FileCount=10,
        $FileSize=1kb,
        $ReportFileSuffix,
        $ThreadCount,
        $SecondsBetweenJobCheckForCompletion=10
    )
    
    #CheckDiskSpdFolderParameter -parameter $diskSpdFolder

    if (-Not (Test-Path $destinationFolder) )
    {
        mkdir $destinationFolder
    }

    $sb = {
        param
        (
            $client,
            [pscredential]$credential,
            $destinationFolder,
            $FileCount=10,
            $FileSize=1kb,
            $ReportFileSuffix,
            $ThreadCount=4,
            $SecondsBetweenJobCheckForCompletion=10
        )
        
        # Client code
        Invoke-Command $client {

            param
            (
                $DestinationFolder,
                $FileCount=10,
                $FileSize=1kb,
                $ReportFileSuffix,
                $ThreadCount = 4,
                $SecondsBetweenJobCheckForCompletion=10
            )
            
            function ExecuteWriteTest
            {
                param
                (
                    $ThreadCount = 4,
                    $DestinationPath,
                    $FileCount=10,
                    $FileSize=1kb,
                    $ReportFileSuffix,
                    $SecondsBetweenJobCheckForCompletion=10
                )

                $result = New-Object -TypeName PSObject @{  "Items"=@();
                                                            "Summary"=@{"TestName"="WriteOnly";
                                                                        "AvgFileSizeBytes"=0;
                                                                        "FileCount"=$FileCount;
                                                                        "WriteTotalBytes"=0;
                                                                        "WriteTotalMB"=0;
                                                                        "WriteAvgSecondsPerFile"=0;
                                                                        "WriteAvgMBpsPerFile"=0;
                                                                        "ThreadsUsed"=$ThreadCount;
                                                                        "Client"=$env:computername}}

                $pool = [runspacefactory]::CreateRunspacePool(1, $threadCount)
                $pool.ThreadOptions = "UseNewThread"
                $pool.Open()   
                
                $FileIndex = 0
                for ($x=0; $x -lt $FileCount; $x = $x + $threadCount )
                {
                    $jobs = @()   
                    $ps = @()  
                
                    for ($i = 0; $i -lt $threadCount ; $i++) {   
                        $ps += [powershell]::create()
                        $ps[$i].runspacepool = $pool  
                    
                        # reads the Files
                        $FileName = ([guid]::NewGuid().Guid)+".dat"

                        [void]$ps[$i].AddScript({
                            param
                            (
                                $DestinationFolder,
                                $FileName,
                                $FileSize,
                                $FileIndex
                            )

                            Function New-RandomFile_Fast {
                                Param
                                (
                                    $Path,
                                    $FileSize,
                                    $FileName
                                ) 
                            
                                $Chunk = { [guid]::NewGuid().Guid + [guid]::NewGuid().Guid + [guid]::NewGuid().Guid + [guid]::NewGuid().Guid +
                                           [guid]::NewGuid().Guid + [guid]::NewGuid().Guid + [guid]::NewGuid().Guid + [guid]::NewGuid().Guid +
                                           [guid]::NewGuid().Guid + [guid]::NewGuid().Guid + [guid]::NewGuid().Guid + [guid]::NewGuid().Guid +
                                           [guid]::NewGuid().Guid + [guid]::NewGuid().Guid + [guid]::NewGuid().Guid + [guid]::NewGuid().Guid +
                                           [guid]::NewGuid().Guid + [guid]::NewGuid().Guid + [guid]::NewGuid().Guid + [guid]::NewGuid().Guid +
                                           [guid]::NewGuid().Guid + [guid]::NewGuid().Guid + [guid]::NewGuid().Guid + [guid]::NewGuid().Guid +
                                           [guid]::NewGuid().Guid + [guid]::NewGuid().Guid + [guid]::NewGuid().Guid + [guid]::NewGuid().Guid +
                                           [guid]::NewGuid().Guid + [guid]::NewGuid().Guid + [guid]::NewGuid().Guid + [guid]::NewGuid().Guid -Replace "-" }
                                $Chunks = [math]::Ceiling($FileSize/1kb)
                                $ChunkString = $Chunk.Invoke()
                            
                                [io.file]::WriteAllText("$Path\$FileName","$(-Join (1..($Chunks)).foreach({ $ChunkString }))")
                            }

                            $result = Measure-Command { New-RandomFile_Fast -Path $DestinationFolder -FileName $FileName -FileSize $FileSize }
            
                            [PSCustomObject]@{
                                Count = $FileIndex
                                ThreadId = [appdomain]::GetCurrentThreadId()
                                FileName = [system.io.path]::Combine($DestinationFolder,$FileName)
                                BytesWrite = $FileSize
                                Seconds = $result.TotalMilliseconds / 1000
                            }
                
                        }).AddParameter('DestinationFolder',$DestinationFolder).AddParameter('FileName',$FileName).AddParameter('FileSize',$FileSize).AddParameter('FileIndex',$FileIndex)  
                    
                        # start job   
                        $jobs += $ps[$i].BeginInvoke();   
                    
                        $FileIndex += 1
                    }   
                
                    while ($finishedJobs -ne $jobs.Count)
                    {
                        $finishedJobs = ($jobs | ? {$_.iscompleted}).count
                        Start-Sleep $SecondsBetweenJobCheckForCompletion
                    }
                
                    # end async call   
                    for ($i = 0; $i -lt $threadCount; $i++)
                    {   
                        try
                        {   
                            # complete async job   
                            $result.items += $ps[$i].EndInvoke($jobs[$i])
                        }
                        catch
                        {   
                            write-warning "error: $_"  
                        }   
                    }
                }

                $pool.Close()  

                [double]$totalSeconds=0
                [uint64]$totalBytes=0
                [double]$totalMB=0
                [int32]$totalMBps=0
                
                ($result.items).foreach({ 
                                        $_ | Add-Member -Type NoteProperty -Name "MBWrite" -Value ($_.BytesWrite / 1024 / 1024)
                                        $_ | Add-Member -Type NoteProperty -Name "MBps" -Value (($_.BytesWrite / 1024 / 1024)/$_.Seconds)
                
                                        $totalSeconds += $_.Seconds
                                        $totalBytes += $_.BytesWrite
                                        $totalMB += $_.MBWrite
                                        $totalMBps += $_.MBps
                            })
                
                $result.summary.WriteAvgSecondsPerFile = $totalSeconds / $result.items.Count
                $result.summary.WriteTotalBytes = $totalBytes
                $result.summary.WriteTotalMB = $totalMB
                $result.summary.WriteAvgMBpsPerFile = [math]::round($totalMBps / $result.items.Count)
                $result.summary.AvgFileSizeBytes = [math]::round($totalBytes / $result.items.Count)
               
                # Results list
                $reportFile = "d:\$($env:computername)-WriteOnly-$ReportFileSuffix.json"
                [io.file]::WriteAllText($reportFile, ($result | ConvertTo-Json -Depth 3))
            }

            ExecuteWriteTest -ThreadCount $ThreadCount -DestinationPath $destinationFolder -FileCount $FileCount -FileSize $FileSize -ReportFileSuffix $ReportFileSuffix -SecondsBetweenJobCheckForCompletion $SecondsBetweenJobCheckForCompletion
            
        } -ArgumentList $destinationFolder, $FileCount, $FileSize, $ReportFileSuffix, $ThreadCount, $SecondsBetweenJobCheckForCompletion -Authentication Credssp -Credential $credential -EnableNetworkAccess
        # End of Client code
    }

    $clients | % {Start-Job -Scriptblock $sb -ArgumentList $_, $credential, $destinationFolder, $FileCount, $FileSize, $ReportFileSuffix, $ThreadCount, $SecondsBetweenJobCheckForCompletion }
    Get-Job | Wait-Job | Receive-Job
}

function PrepareClientLocalSourceFilesRobocopy
{
    param
    (
        $Clients,
        $LocalFolder,
        [pscredential]$credential,
        $NumberOfFiles=2048,
        $FileSize=50MB
    )

    $sb = {
        param
        (
            $client,
            $LocalFolder,
            [pscredential]$credential,
            $NumberOfFiles=2048,
            $FileSize=50MB
        )
        
        Invoke-Command $client {
            param
            (
                $LocalFolder,
                $NumberOfFiles=2048,
                [uint64]$FileSize
            )

            if (-Not (Test-Path $LocalFolder) )
            {
                mkdir $LocalFolder
            }

            for ($i=0;$i -lt $NumberOfFiles; $i++)
            {
                $fileName=[system.io.path]::Combine($LocalFolder,"$($env:computername)-$([guid]::NewGuid().Guid).dat")
                $args=@()
                $args += "/c"
                $args += "fsutil file createnew $fileName $FileSize"

                & "cmd"  $args | out-null
            }
            
        } -ArgumentList $LocalFolder, $NumberOfFiles, $FileSize -Authentication Credssp -Credential $credential
    }

    $clients | % {Start-Job -Scriptblock $sb -ArgumentList $_, $LocalFolder, $creds, $NumberOfFiles, $FileSize }
    Get-Job | Wait-Job | Receive-Job
}

function RunCustomTestWriteOnlyRobocopy
{
    # This test writes files of x amount of size in a folder
    param
    (
        $Clients,
        [pscredential]$Credential,
        $SourceFolder,
        $DestinationFolder,
        $ReportFileSuffix,
        $ThreadCount=8,
        $Description
    )

    if (-Not (Test-Path $destinationFolder) )
    {
        mkdir $destinationFolder
    }

    $sb = {
        param
        (
            $client,
            [pscredential]$credential,
            $sourceFolder,
            $destinationFolder,
            $ReportFileSuffix,
            $ThreadCount=8,
            $Description

        )
        
        # Client code
        Invoke-Command $client {

            param
            (
                $SourceFolder,
                $DestinationFolder,
                $ReportFileSuffix,
                $ThreadCount = 8,
                $Description

            )
            
            if (-Not (Test-Path $SourceFolder) )
            {
                throw "An error ocurred, source folder does not exist, please execute PrepareClientLocalSourceFilesRobocopy funtion before this test."
            }

            $destinationFolder = [system.io.path]::Combine($destinationFolder,$env:computername)

            if (-Not (Test-Path $destinationFolder) )
            {
                mkdir $destinationFolder
            }

            $TestName = "WriteOnlyRoboCopy"
            
            # Executing Robocopy
            $result = Measure-Command {$output = robocopy /nfl /ndl /np /njh $sourceFolder $destinationFolder /bytes /MT:$ThreadCount}

            $reportFile = "d:\$($env:computername)-$TestName-$ReportFileSuffix.json"
            $output | Out-File "d:\$($env:computername)-$TestName-$ReportFileSuffix.txt"
            
            # Getting File Count from output
            [uint64]$FileCount = ($output | ? {$_.Contains('Files')}).split(":").split(" ",[System.StringSplitOptions]::RemoveEmptyEntries)[2]

            # Getting total bytes from output
            [uint64]$WriteTotalBytes = ($output | ? {$_.Contains('Bytes')}).split(":").split(" ",[System.StringSplitOptions]::RemoveEmptyEntries)[2]

            # # Getting total time from output
            [timespan]$time = ($output | ? {$_.Contains('Times')}).split("Times").split(" ",[System.StringSplitOptions]::RemoveEmptyEntries)[2]

            $result = New-Object -TypeName PSObject @{  "Items"=@();
                                                        "Summary"=@{"TestName"=$TestName;
                                                                    "Description"=$Description;
                                                                    "AvgFileSizeBytes"= $WriteTotalBytes / $FileCount ;
                                                                    "FileCount"=$FileCount;
                                                                    "WriteTotalBytes"=$WriteTotalBytes;
                                                                    "WriteTotalMB"=$WriteTotalBytes / 1024 / 1024;
                                                                    "Bps"=$WriteTotalBytes / $time.TotalSeconds ;
                                                                    "MBps"=($WriteTotalBytes/1024/1024) / $time.TotalSeconds ;
                                                                    "ThreadsUsed"=$ThreadCount;
                                                                    "ElapsedTimeSecPSMeasure"=$result.TotalSeconds;
                                                                    "ElapsedTimeSecRobocopyMeasure"=$time.TotalSeconds;
                                                                    "Client"=$env:computername}}

            # Results list
     
            [io.file]::WriteAllText($reportFile, ($result | ConvertTo-Json -Depth 3))
            
        } -ArgumentList $SourceFolder, $destinationFolder, $ReportFileSuffix, $ThreadCount, $Description -Authentication Credssp -Credential $credential -EnableNetworkAccess
        # End of Client code
    }

    $clients | % {Start-Job -Scriptblock $sb -ArgumentList $_, $credential, $sourceFolder, $destinationFolder, $ReportFileSuffix, $ThreadCount, $Description | out-null}
    Get-Job | Wait-Job | Receive-Job
}

function CollectReportsDiskSpd
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
        $file = "\\$client\d$\$client-$FileSuffix.xml"

        if (test-path $file)
        {
            Copy-Item -Path $file -Destination "c:\$destination"
        }

        #remove-item $file -force
    } 
}

function CleanUpReportsDiskSpd
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

function GenerateReportDiskSpd
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

function RestartVMs
{
    param
    (
        $clients
    )

    $sb = {
        param
        (
            $client
        )
    
        Invoke-Command $client { 

            Restart-Computer -Force

        }
    }

    $clients | % {Start-Job -Scriptblock $sb -ArgumentList $_ }
    Get-Job | Wait-Job | Receive-Job
}

function InstallWindowsNFSClient
{
    
    param
    (
        $clients
    )

    $sb = {
        param
        (
            $client
        )
    
        Invoke-Command $client { 

            Install-WindowsFeature -Name NFS-Client -Confirm:$false

        }
    }

    $clients | % {Start-Job -Scriptblock $sb -ArgumentList $_ }
    Get-Job | Wait-Job | Receive-Job
}

function CollectReports
{
    param
    (
        $clients,
        $destinationFolder,
        $FileSuffix
    )
    
    if (-Not (Test-Path $destinationFolder))
    {
        mkdir $destinationFolder -force
    }

    foreach ($client in $clients)
    {
        $file = "\\$client\d$\$client-$FileSuffix"

        if (test-path $file)
        {
            Copy-Item -Path $file -Destination $destinationFolder
        }

    } 
}
