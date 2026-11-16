function Get-DateTime {
    $DateTimeCurrent = (Get-Date).ToUniversalTime().ToString("yyyyMMdd HHmmss UTC")
    return $DateTimeCurrent
}

Write-Host "`n$(Get-DateTime)
    The Copy-Files module loaded successfully" -ForegroundColor DarkYellow
Write-Host "`n$(Get-DateTime)
    The following scripts are available:

    1) Get-FolderHash
    2) Copy-Files
    3) Copy-FilesWithLog
    4) Copy-FilesWithLogAndHash
    5) Copy-FilesAndVerify

    Type 'Get-Help [Module-Name]' to see information about what each script does.

    Last Updated 2023-10-03 by [@mikespon]." -ForegroundColor DarkYellow

function Get-FolderHash {
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [String]$directory
    )

    $files = Get-ChildItem $directory -Recurse | Where-Object {-not $_.PSIsContainer}

    $allBytes = New-Object System.Collections.Generic.List[byte]
    foreach ($file in $files) {
        $allBytes.AddRange([System.IO.File]::ReadAllBytes($file.FullName))
        $allBytes.AddRange([System.Text.Encoding]::UTF8.GetBytes($file.Name))
    }
    $hasher = [System.Security.Cryptography.SHA1]::Create()
    $hashValue = [string]::Join("", $($hasher.ComputeHash($allBytes.ToArray()) | ForEach-Object {"{0:x2}" -f $_ }))

    return $hashValue
}


function Copy-Files {
<#
    .SYNOPSIS
        Copies files from one directory to another using the Windows "robocopy" command.
    .DESCRIPTION
        Copies files from one directory to another using the Windows "robocopy"
        command.
        Provide the path of the source directory [SOURCE_DIRECTORY] and the path
        of the destination directory [DESTINATION_DIRECTORY].
    .INPUTS
        None
    .OUTPUTS
        None
    .EXAMPLE
        Copy-Files [SOURCE_DIRECTORY] [DESTINATION_DIRECTORY]
    .LINK
        https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/robocopy
#>
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [string]$SourceDirectory,

        [Parameter(Mandatory=$true, Position=1)]
        [string]$DestinationDirectory
    )

    Robocopy.exe $SourceDirectory $DestinationDirectory /MIR /MT /TEE /DCOPY:DAT /V /TS /FP
}


function Copy-FilesWithLog {
<#
    .SYNOPSIS
        Copies files from one directory to another using the Windows "robocopy" command.
    .DESCRIPTION
        Copies files from one directory to another using the
        "robocopy" command and will output a .log file in a
        seperate directory named '__COPY-LOGS'.

        Provide the path of the source directory [SOURCE_DIRECTORY]
        and the path of the destination directory [DESTINATION_DIRECTORY].

        You will need to enclose the directory paths in double quotes in
        there are spaces in the path name (i.e., [C:\Users\JohnDoe] will
        need to input as ["C:\Users\JohnDoe"]). The full name of the log
        file will be as follows: "[yyyy-MM-DD_HHmmss]_[case-number]_filecopy.log".
        Adding the case number to the CLI will add the case number to the
        log file for easy identification.
    .INPUTS
        None
    .OUTPUTS
        None
    .EXAMPLE
        Copy-FilesWithLog [SOURCE_DIRECTORY] [DESTINATION_DIRECTORY] [CASE_NUMBER]
    .LINK
        https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/robocopy
#>
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [String]$sourceDirectory,

        [Parameter(Mandatory=$true, Position=1)]
        [String]$destinationDirectory,

        [Parameter(Mandatory=$true, Position=2)]
        [String]$caseNumber
    )

    # Test to see if the destination directory exists. If it does not exist, it will be created.
    if (Test-Path $destinationDirectory) {
        Write-Host "`n$(Get-DateTime) | Copying files into destination directory...`n" -ForegroundColor DarkYellow
    }
    else {
        # Create the destination directory if it does not already exist.
        New-Item -ItemType Directory -Path $destinationDirectory | Out-Null
        Write-Host "`n$(Get-DateTime) | The destination directory does not exist. Creating it now..." -ForegroundColor DarkYellow
        Write-Host "`n$(Get-DateTime) | Destination folder [$destinationDirectory] was created successfully." -ForegroundColor DarkYellow
    }

    # Get the current date and time to use in the .log file name.
    $dateTime = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd_HHmmss")

    # Sets the folder in which the copy .log files will be stored.
    $logFolder = (Join-Path (Split-Path $destinationDirectory -Parent) "__COPY-LOGS")

    # Create the log directory if it does not exist.
    if (-Not (Test-Path $($logFolder))) {
        New-Item -ItemType Directory -Path $logFolder | Out-Null
        Write-Host "`n$(Get-DateTime) | The '__COPY-LOGS' directory does not exist. Creating it now..." -ForegroundColor DarkYellow
        Write-Host "`n$(Get-DateTime) | '__COPY-LOGS' directory was created successfully" -ForegroundColor DarkYellow
    }
    else {
        Write-Host "`n$(Get-DateTime) | The '__COPY-LOGS' directory already exists. Moving on..." -ForegroundColor DarkYellow
        Write-Host "`n$(Get-DateTime) | The Log file will be saved to : '$($logFolder)\$($dateTime)_$($caseNumber)_filecopy.log'" -ForegroundColor DarkYellow
    }

    # Command to copy the files.
    Robocopy.exe $sourceDirectory $destinationDirectory /MIR /MT /LOG+:$($logFolder)\$($dateTime)_$($caseNumber)_filecopy.log /TEE /DCOPY:DAT /V /TS /FP


    # # Hashing the source directory
    # $sourceDirectoryDirHash = Get-FolderHash $sourceDirectory
    # Write-Host "`nHashing the Source directory, please wait..." -ForegroundColor DarkYellow
    # Write-Host "The SHA1 hash value of $sourceDirectory is: $($sourceDirectoryDirHash)." -ForegroundColor DarkYellow

    # # Hashing the destination directory after all the files are copied
    # $destinationDirectoryDirHash = Get-FolderHash $destinationDirectory
    # Write-Host "`nHashing the Destination directory, please wait..." -ForegroundColor DarkYellow
    # Write-Host "The SHA1 hash value of $destinationDirectory is: $($destinationDirectoryDirHash)." -ForegroundColor DarkYellow

    # # Comparing the source and destination directory to make sure the hash values match
    # if (($sourceDirectoryDirHash) -eq $destinationDirectoryDirHash)
    # {
    #     Write-Host "`nThe hash value of the source directory MATCHES the hash value of the destination directory.  No further action necessary." -ForegroundColor DarkYellow
    # }
    # else
    # {
    #     Write-Host "[-] Well, shit.  Something bad happened.  The hash values of the folders DO NOT MATCH.  Better try it again." -ForegroundColor DarkYellow
    # }
}


function Copy-FilesWithLogAndHash {
<#
    .SYNOPSIS
        Copies files from one directory to another using the Windows "robocopy" command.
        Created by: [@mikespon]
        DLU: 2023-09-25
    .DESCRIPTION
        Copies files from one directory to another using the "robocopy" command
        and will output a .log file in a seperate directory named '__COPY-LOGS'.
        Provide the path of the source directory [SOURCE_DIRECTORY] and the path
        of the destination directory [DESTINATION_DIRECTORY].

        You will need to enclose the directory paths in double quotes in there
        are spaces in the path name (i.e., [C:\Users\JohnDoe] will need to input
        as ["C:\Users\JohnDoe"]).

        The full name of the log file will be as follows:
        "[yyyy-MM-DD_HHmmss]_[case-number]_filecopy.log".
        Adding the case number to the CLI will add the case number to the log
        file for easy identification.
    .INPUTS
        None
    .OUTPUTS
        None
    .EXAMPLE
        Copy-FilesWithLog [SOURCE_DIRECTORY] [DESTINATION_DIRECTORY] [CASE_NUMBER]
    .LINK
        https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/robocopy
#>
    # Load Windows Forms for GUI.
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    function Get-SourceFolder {
        [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms") | Out-Null

        # Select the folder dialog.
        $pathSelect = New-Object System.Windows.Forms.FolderBrowserDialog
        $pathSelect.RootFolder = "MyComputer"
        $pathSelect.Description = "Choose Source Directory"

        # Dialog show.
        $pathSelect.ShowDialog()

        # If a folder was choosen (do not abort >> "-ne" for no exit).
        if ($pathSelect.SelectedPath -ne "") {
            $selectedItem = $pathSelect.SelectedPath
            $textBoxSource.Clear()
            $textBoxSource.Paste($selectedItem)
        }
    }

    function Get-DestFolder {
        [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms") | Out-Null

        # Select the folder dialog.
        $destSelect = New-Object System.Windows.Forms.FolderBrowserDialog
        $destSelect.RootFolder = "MyComputer"
        $destSelect.Description = "Choose Destination Directory"

        # Dialog show.
        $destSelect.ShowDialog()

        # If a folder was choosen (do not abort >> "-ne" for no exit).
        if ($destSelect.SelectedPath -ne "") {
            $selectedItem = $destSelect.SelectedPath
            $textBoxDest.Clear()
            $textBoxDest.Paste($selectedItem)
        }
    }

    # Define the form.
    $form = New-Object Windows.Forms.Form

    # Add title to the form window.
    $form.Text = "File Copy and Hash Verification"
    $form.Width = 775
    $form.Height = 350
    $form.StartPosition = "CenterScreen"

    # Define label and text boxes for source and destination directories.
    $leaderLabel = New-Object Windows.Forms.Label
    $leaderLabel.Text = "Input the full path to the directory below:"
    $leaderLabel.Font = New-Object System.Drawing.Font('Arial', 10, [System.Drawing.FontStyle]::Italic)
    $leaderLabel.Width = 400
    $leaderLabel.Location = New-Object Drawing.Point(10, 15)

    $labelSource = New-Object Windows.Forms.Label
    $labelSource.Text = "Source Directory:"
    $labelSource.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $labelSource.Font = New-Object System.Drawing.Font('Arial', 10)
    $labelSource.Width = 200
    $labelSource.Height = 35
    $labelSource.Location = New-Object Drawing.Point(10, 60)

    $textBoxSource = New-Object Windows.Forms.TextBox
    $textBoxSource.Multiline = $True
    $textBoxSource.Font = New-Object System.Drawing.Font('Arial', 10)
    $textBoxSource.Width = 300
    $textBoxSource.Height = 35
    $textBoxSource.Location = New-Object Drawing.Point(220, 60)

    $btnChooseSource = New-Object Windows.Forms.Button
    $btnChooseSource.Text = "Choose Source"
    $btnChooseSource.Font = New-Object System.Drawing.Font('Arial', 10)
    $btnChooseSource.Width = 175
    $btnChooseSource.Height = 35
    $btnChooseSource.Location = New-Object Drawing.Point(550, 60)
    $btnChooseSource.Add_Click({ Get-SourceFolder })

    $labelDest = New-Object Windows.Forms.Label
    $labelDest.Text = "Destination Directory:"
    $labelDest.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $labelDest.Font = New-Object System.Drawing.Font('Arial', 10)
    $labelDest.Width = 200
    $labelDest.Height = 35
    $labelDest.Location = New-Object Drawing.Point(10, 125)

    $textBoxDest = New-Object Windows.Forms.TextBox
    $textBoxDest.Multiline = $True
    $textBoxDest.Font = New-Object System.Drawing.Font('Arial', 10)
    $textBoxDest.Width = 300
    $textBoxDest.Height = 35
    $textBoxDest.Location = New-Object Drawing.Point(220, 125)

    $btnChooseDest = New-Object Windows.Forms.Button
    $btnChooseDest.Text = "Choose Destination"
    $btnChooseDest.Font = New-Object System.Drawing.Font('Arial', 10)
    $btnChooseDest.Width = 175
    $btnChooseDest.Height = 35
    $btnChooseDest.Location = New-Object Drawing.Point(550, 125)
    $btnChooseDest.Add_Click({ Get-DestFolder })

    # Define a button for initiating the copy and hash verification.
    $buttonCopy = New-Object Windows.Forms.Button
    $buttonCopy.Text = "Copy and Verify"
    $buttonCopy.Font = New-Object System.Drawing.Font('Arial', 10)
    $buttonCopy.Width = 150
    $buttonCopy.Height = 50
    $buttonCopy.Location = New-Object Drawing.Point(10, 190)
    $buttonCopy.Add_Click({
        $sourceDirectory = $textBoxSource.Text
        $destinationDirectory = $textBoxDest.Text

        # Verify that both directories exist.
        if (-Not (Test-Path -Path $sourceDirectory -PathType Container)) {
            # If the source directory does not exit, show an error message and exit the script.
            [System.Windows.Forms.MessageBox]::Show("The Source directory does not exist. Please check the directory name and try again.", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            return
        }
        if (-Not (Test-Path -Path $destinationDirectory -PathType Container)) {
            # If the destination directory does not exist, show a message.
            [System.Windows.Forms.MessageBox]::Show("The Destination directory does not exist. It will be created...", "Information", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
            New-Item -ItemType Directory -Path $destinationDirectory | Out-Null
        }

        # Create a directory for log file(s) on the user's desktop.
        $desktopPath = [Environment]::GetFolderPath("Desktop")
        $logDirectory = (Join-Path $desktopPath HashCheckLogs)

        if (-Not (Test-Path -Path $logDirectory)) {
            New-Item -Path $logDirectory -ItemType Directory | Out-Null
            Write-Host "`n$(Get-DateTime) | The log directory was not found. Creating it now..." -ForegroundColor DarkYellow
            Write-Host "`n$(Get-DateTime) | The logs will be stored in the $logDirectory folder" -ForegroundColor DarkYellow
        }
        else {
            Write-Host "`n$(Get-DateTime) | The log directory already exists. Still working..." -ForegroundColor DarkYellow
        }

        # Get the current date and time to use in the .log file name.
        $dateTime = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd_HHmmss")

        # Copy files recursively from source to destination.
        Robocopy.exe $sourceDirectory $destinationDirectory /MIR /MT /LOG+:$($logDirectory)\$($dateTime)_filecopy.log /TEE /DCOPY:DAT /V /TS /FP

        # Initialize an array to store results.
        $results = @()

        # Forensically copy files and check SHA-1 hash.
        foreach ($sourceDirectoryFile in $sourceDirectory) {
            Get-ChildItem -Path $sourceDirectory -File -Recurse | ForEach-Object {
                $sourceDirectoryFile = $_
                $destinationDirectoryFile = Join-Path -Path $destinationDirectory -ChildPath $sourceDirectoryFile.Name
                $hashSource = Get-FileHash -Path $sourceDirectoryFile.FullName -Algorithm SHA1
                $hashDestination = Get-FileHash -Path $destinationDirectoryFile -Algorithm SHA1

                $result = [PSCustomObject]@{
                    "File-Name"             = $sourceDirectoryFile.FullName
                    "Destination-File-Name" = $destinationDirectoryFile
                    "Source-Hash"           = $hashSource.Hash
                    "Destination-Hash"      = $hashDestination.Hash
                    "Verified"              = $hashSource.Hash -eq $hashDestination.Hash
                }

                # Log the result to a CSV file.
                $Result | Export-Csv -Path (Join-Path -Path $logDirectory -ChildPath "$($dateTime)_HashCheckLog.csv") -Append -NoTypeInformation

                # Add the result to the results array.
                $Results += $Result
            }
        }

        # Display a 'Success' Message.
        [System.Windows.Forms.MessageBox]::Show("Files copied and hashes verified successfully.`n`nThe log file was saved to : '$($logDirectory)\$($dateTime)_filecopy.log'", "Success", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)

        $viewResults = [System.Windows.Forms.MessageBox]::Show("Would you like to view the hash results?", "View Hashes?", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)

        if ($viewResults -eq 6) {
            # Display the results in a GUI window if the user chooses 'Yes'.
            $results | Out-GridView -Title "File Hash Verification Results"
        }
        if ($viewResults -eq 7) {
            return
        }
    })

    # Define a button for initiating the copy and hash verification.
    $buttonClear = New-Object Windows.Forms.Button -Property @{
        Location = New-Object System.Drawing.Point -Property @{
            X = 190
            Y = 190
        }
        Font = New-Object System.Drawing.Font('Arial',10)
        Text = "Clear"
        Width = 130
        Height = 50
    }
    $buttonClear.Add_Click({
        $textBoxSource.Clear()
        $textBoxDest.Clear()
    })

    # Define a button for initiating the copy and hash verification.
    $buttonClose = New-Object Windows.Forms.Button -Property @{
        Location = New-Object System.Drawing.Point -Property @{
            X = 350
            Y = 190
        }
        Font = New-Object System.Drawing.Font('Arial', 10)
        Text = "Close"
        Width = 130
        Height = 50
    }
    $buttonClose.Add_Click({ $form.Close() })

    # Add controls to the form.
    $form.Controls.Add($headerLabel)
    $form.Controls.Add($labelSource)
    $form.Controls.Add($textBoxSource)
    $form.Controls.Add($btnChooseSource)
    $form.Controls.Add($labelDest)
    $form.Controls.Add($textBoxDest)
    $form.Controls.Add($btnChooseDest)
    $form.Controls.Add($buttonCopy)
    $form.Controls.Add($buttonClear)
    $form.Controls.Add($buttonClose)

    # Display the form.
    $form.ShowDialog()
}

# =======================================

function Copy-FilesAndVerify {
<#
    .SYNOPSIS
        Function to recursively copy files and verify their hash values
    .DESCRIPTION
        Copies files from one directory to another and then will
        display the results in a GUI window.

        Provide the path of the source directory [SOURCE_DIRECTORY] containing
        the original files. Provide the path of the destination directory
        [DESTINATION_DIRECTORY] where the files are going to be copied to.

        You will need to enclose the directory paths in double quotes if there
        are spaces in the path name (i.e., [C:\Users\JohnDoe] will need to input
        as ["C:\Users\JohnDoe"]).
    .INPUTS
        None
    .OUTPUTS
        None
    .EXAMPLE
        Copy-FilesAndVerify [SOURCE_DIRECTORY] [DESTINATION_DIRECTORY]
    .LINK
        https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/robocopy
#>

    param (
        [Parameter(Mandatory=$True, Position=0)]
        [string]$sourceDirectory,

        [Parameter(Mandatory=$True, Position=1)]
        [string]$destinationDirectory
    )

    function Copy-Verify {
        # Get a list of all files and subdirectories in the source directory.
        $items = Get-ChildItem -Path $sourceDirectory -Recurse

        # Initialize an array to store results.
        $results = @()

        foreach ($item in $items) {
            # Calculate SHA-1 hash for the source file.
            $hashSource = Get-FileHash -Path $item.FullName -Algorithm SHA1

            # Calculate SHA-1 hash for the destination file (if it exists).
            $destinationDirectoryFile = Join-Path -Path $destinationDirectory -ChildPath $item.FullName.Substring($sourceDirectory.Length)

            Copy-Item -Path $item.FullName -Destination $destinationDirectoryFile -Force -Container:$True

            if ($($item).PSIsContainer) {
                $hashDestination = 0
            }
            elseif (Test-Path -Path $destinationDirectoryFile) {
                $hashDestination = Get-FileHash -Path $destinationDirectoryFile -Algorithm SHA1
            }
            else {
                $hashDestination = $null
            }

            # Verifing the hash values of each folder.
            if (-Not $hashDestination) {
                $verified = "Destination file not found."
            }
            elseif ($hashDestination -eq 0) {
                $verified = "Is Directory."
            }
            elseif ($hashSource.Hash -eq $hashDestination.Hash) {
                $verified = "Verified."
            }
            else {
                $verified = "Hash mismatch."
            }

            # Add the result to the results array.
            $results += [PSCustomObject]@{
                "Source-File"      = $item.FullName
                "Destination-File" = $destinationDirectoryFile
                "Source-Hash"      = $hashSource.Hash
                "Destination-Hash" = $hashDestination.Hash
                "Hash-Verified"    = $verified
            }
        }
        # Return the results
        return $results
    }

    # Perform the recursive copy and verification using the path variables passed as arguments when the function was called.
    $results = Copy-Verify -sourcePath $sourceDirectory -destinationPath $destinationDirectory

    # Display the results in a standard GUI window.
    $results | Out-GridView -Title "File Hash Verification Results"

    Write-Host "$(Get-DateTime) | File hash verification complete." -ForegroundColor DarkYellow
}
