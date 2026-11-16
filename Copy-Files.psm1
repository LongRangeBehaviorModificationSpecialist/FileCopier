function Get-DateTime
{
    return (Get-Date).ToUniversalTime().ToString("yyyyMMdd HHmmss UTC")
}

Write-Host "$(Get-DateTime)
    The Copy-Files module loaded successfully" -ForegroundColor DarkYellow
Write-Host "$(Get-DateTime)
    The following scripts are available:

    1) Get-FolderHash
    2) Copy-Files
    3) Copy-FilesWithLog
    4) Copy-FilesWithLogAndHash
    5) Copy-FilesAndVerify

    Type 'Get-Help [Module-Name]' to see information about what each script does.

    Last Updated 16-Nov-2026 by [@mikespon]." -ForegroundColor DarkYellow

function Get-FolderHash
{
    param
    (
        [Parameter(Mandatory, Position=0)]
        [String]$Directory
    )

    $Files = Get-ChildItem $Directory -Recurse | Where-Object {-not $_.PSIsContainer}

    $AllBytes = New-Object System.Collections.Generic.List[byte]
    foreach ($File in $Files)
    {
        $AllBytes.AddRange([System.IO.File]::ReadAllBytes($File.FullName))
        $AllBytes.AddRange([System.Text.Encoding]::UTF8.GetBytes($File.Name))
    }
    $Hasher = [System.Security.Cryptography.SHA1]::Create()
    $HashValue = [string]::Join(
        "",
        $($Hasher.ComputeHash($AllBytes.ToArray()) | ForEach-Object {"{0:x2}" -f $_ })
    )

    return $HashValue
}


function Copy-Files
{
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
    param
    (
        [Parameter(Mandatory, Position=0)]
        [string]$SourceDirectory,

        [Parameter(Mandatory, Position=1)]
        [string]$DestinationDirectory
    )

    Robocopy.exe $SourceDirectory $DestinationDirectory /MIR /MT /TEE /DCOPY:DAT /V /TS /FP
}


function Copy-FilesWithLog
{
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
        need to input as ["C:\Users\JohnDoe"]).  The full name of the log
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
    param
    (
        [Parameter(Mandatory, Position=0)]
        [String]$SourceDirectory,

        [Parameter(Mandatory, Position=1)]
        [String]$DestinationDirectory,

        [Parameter(Mandatory, Position=2)]
        [String]$CaseNumber
    )

    # Test to see if the destination directory exists. If it does not exist, it will be created.
    if (Test-Path $DestinationDirectory)
    {
        Write-Host "$(Get-DateTime) | Copying files into destination directory...`n" `
            -ForegroundColor DarkYellow
    }
    else
    {
        # Create the destination directory if it does not already exist.
        New-Item -ItemType Directory -Path $DestinationDirectory | Out-Null
        Write-Host "$(Get-DateTime) | The destination directory does not exist. Creating it now..." `
            -ForegroundColor DarkYellow
        Write-Host "$(Get-DateTime) | Destination folder [$DestinationDirectory] was created successfully." `
            -ForegroundColor DarkYellow
    }

    # Get the current date and time to use in the .log file name.
    $DateTime = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd_HHmmss")

    # Sets the folder in which the copy .log files will be stored.
    $LogFolder = (Join-Path -Path (Split-Path $DestinationDirectory -Parent) -ChildPath "__COPY-LOGS")

    # Create the log directory if it does not exist.
    if (-Not (Test-Path $($LogFolder)))
    {
        New-Item -ItemType Directory -Path $LogFolder | Out-Null
        Write-Host "$(Get-DateTime) | The '__COPY-LOGS' directory does not exist. Creating it now..." `
            -ForegroundColor DarkYellow
        Write-Host "$(Get-DateTime) | '__COPY-LOGS' directory was created successfully" `
            -ForegroundColor DarkYellow
    }
    else
    {
        Write-Host "$(Get-DateTime) | The '__COPY-LOGS' directory already exists. Moving on..." `
            -ForegroundColor DarkYellow
        Write-Host ("$(Get-DateTime) | The Log file will be saved to : " +
            "'$( $LogFolder )\$( $DateTime )_$( $CaseNumber )_filecopy.log'") -ForegroundColor DarkYellow
    }

    # Command to copy the files.
    Robocopy.exe $SourceDirectory $DestinationDirectory /MIR /MT /LOG+:$( $LogFolder )\$( $DateTime )_$( $CaseNumber )_filecopy.log /TEE /DCOPY:DAT /V /TS /FP
}


function Copy-FilesWithLogAndHash
{
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

    function Get-SourceFolder
    {
        [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms") | Out-Null

        # Select the folder dialog.
        $PathSelect = New-Object System.Windows.Forms.FolderBrowserDialog
        $PathSelect.RootFolder = "MyComputer"
        $PathSelect.Description = "Choose Source Directory"

        # Dialog show.
        $PathSelect.ShowDialog()

        # If a folder was choosen (do not abort >> "-ne" for no exit).
        if ($PathSelect.SelectedPath -ne "")
        {
            $SelectedItem = $PathSelect.SelectedPath
            $TextBoxSource.Clear()
            $TextBoxSource.Paste($SelectedItem)
        }
    }

    function Get-DestFolder
    {
        [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms") | Out-Null

        # Select the folder dialog.
        $DestSelect = New-Object System.Windows.Forms.FolderBrowserDialog
        $DestSelect.RootFolder = "MyComputer"
        $DestSelect.Description = "Choose Destination Directory"

        # Dialog show.
        $DestSelect.ShowDialog()

        # If a folder was choosen (do not abort >> "-ne" for no exit).
        if ($DestSelect.SelectedPath -ne "")
        {
            $SelectedItem = $DestSelect.SelectedPath
            $TextBoxDest.Clear()
            $TextBoxDest.Paste($SelectedItem)
        }
    }

    # Define the form.
    $Form = New-Object Windows.Forms.Form

    # Add title to the form window.
    $Form.Text = "File Copy and Hash Verification"
    $Form.Width = 775
    $Form.Height = 350
    $Form.StartPosition = "CenterScreen"

    # Define label and text boxes for source and destination directories.
    $LeaderLabel = New-Object Windows.Forms.Label
    $LeaderLabel.Text = "Input the full path to the directory below:"
    $LeaderLabel.Font = New-Object System.Drawing.Font("Arial", 10, [System.Drawing.FontStyle]::Italic)
    $LeaderLabel.Width = 400
    $LeaderLabel.Location = New-Object Drawing.Point(10, 15)

    $LabelSource = New-Object Windows.Forms.Label
    $LabelSource.Text = "Source Directory:"
    $LabelSource.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $LabelSource.Font = New-Object System.Drawing.Font("Arial", 10)
    $LabelSource.Width = 200
    $LabelSource.Height = 35
    $LabelSource.Location = New-Object Drawing.Point(10, 60)

    $TextBoxSource = New-Object Windows.Forms.TextBox
    $TextBoxSource.Multiline = $True
    $TextBoxSource.Font = New-Object System.Drawing.Font("Arial", 10)
    $TextBoxSource.Width = 300
    $TextBoxSource.Height = 35
    $TextBoxSource.Location = New-Object Drawing.Point(220, 60)

    $BtnChooseSource = New-Object Windows.Forms.Button
    $BtnChooseSource.Text = "Choose Source"
    $BtnChooseSource.Font = New-Object System.Drawing.Font("Arial", 10)
    $BtnChooseSource.Width = 175
    $BtnChooseSource.Height = 35
    $BtnChooseSource.Location = New-Object Drawing.Point(550, 60)
    $BtnChooseSource.Add_Click({ Get-SourceFolder })

    $LabelDest = New-Object Windows.Forms.Label
    $LabelDest.Text = "Destination Directory:"
    $LabelDest.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $LabelDest.Font = New-Object System.Drawing.Font("Arial", 10)
    $LabelDest.Width = 200
    $LabelDest.Height = 35
    $LabelDest.Location = New-Object Drawing.Point(10, 125)

    $TextBoxDest = New-Object Windows.Forms.TextBox
    $TextBoxDest.Multiline = $True
    $TextBoxDest.Font = New-Object System.Drawing.Font("Arial", 10)
    $TextBoxDest.Width = 300
    $TextBoxDest.Height = 35
    $TextBoxDest.Location = New-Object Drawing.Point(220, 125)

    $BtnChooseDest = New-Object Windows.Forms.Button
    $BtnChooseDest.Text = "Choose Destination"
    $BtnChooseDest.Font = New-Object System.Drawing.Font("Arial", 10)
    $BtnChooseDest.Width = 175
    $BtnChooseDest.Height = 35
    $BtnChooseDest.Location = New-Object Drawing.Point(550, 125)
    $BtnChooseDest.Add_Click({ Get-DestFolder })

    # Define a button for initiating the copy and hash verification.
    $ButtonCopy = New-Object Windows.Forms.Button
    $ButtonCopy.Text = "Copy and Verify"
    $ButtonCopy.Font = New-Object System.Drawing.Font("Arial", 10)
    $ButtonCopy.Width = 150
    $ButtonCopy.Height = 50
    $ButtonCopy.Location = New-Object Drawing.Point(10, 190)
    $ButtonCopy.Add_Click({
        $SourceDirectory = $TextBoxSource.Text
        $DestinationDirectory = $TextBoxDest.Text

        # Verify that both directories exist.
        if (-Not (Test-Path -Path $SourceDirectory -PathType Container))
        {
            # If the source directory does not exit, show an error message and exit the script.
            [System.Windows.Forms.MessageBox]::Show(
                "The Source directory does not exist. " +
                "Please check the directory name and try again.",
                "Error",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
            return
        }

        if (-Not (Test-Path -Path $DestinationDirectory -PathType Container))
        {
            # If the destination directory does not exist, show a message.
            [System.Windows.Forms.MessageBox]::Show(
                "The Destination directory does not exist. It will be created...",
                "Information",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )
            New-Item -ItemType Directory -Path $DestinationDirectory | Out-Null
        }

        # Create a directory for log file(s) on the user's desktop.
        $DesktopPath = [Environment]::GetFolderPath("Desktop")
        $LogDirectory = (Join-Path -Path $DesktopPath -ChildPath "HashCheckLogs")

        if (-Not (Test-Path -Path $LogDirectory))
        {
            New-Item -Path $LogDirectory -ItemType Directory | Out-Null
            Write-Host "$(Get-DateTime) | The log directory was not found. Creating it now..." `
                -ForegroundColor DarkYellow
            Write-Host "$(Get-DateTime) | The logs will be stored in the $LogDirectory folder" `
                -ForegroundColor DarkYellow
        }
        else
        {
            Write-Host "$(Get-DateTime) | The log directory already exists. Still working..." `
                -ForegroundColor DarkYellow
        }

        # Get the current date and time to use in the .log file name.
        $DateTime = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd_HHmmss")

        # Copy files recursively from source to destination.
        Robocopy.exe $SourceDirectory $DestinationDirectory /MIR /MT /LOG+:$( $LogDirectory )\$( $DateTime )_filecopy.log /TEE /DCOPY:DAT /V /TS /FP

        # Initialize an array to store results.
        $Results = @()

        # Resolve the source root once so each file's relative path can be calculated reliably.
        $SourceRoot = (Resolve-Path -LiteralPath $SourceDirectory).ProviderPath.TrimEnd("\")

        # Check the SHA-1 hash of every source file against its copy.
        Get-ChildItem -LiteralPath $SourceRoot -File -Recurse | ForEach-Object {
            $SourceDirectoryFile = $_

            # Keep the subfolder path (e.g. "docs\2023\report.pdf"), not just the file name.
            $RelativePath = $SourceDirectoryFile.FullName.Substring( $SourceRoot.Length ).TrimStart("\")
            $DestinationDirectoryFile = Join-Path -Path $DestinationDirectory -ChildPath $RelativePath

            $HashSource = Get-FileHash -LiteralPath $SourceDirectoryFile.FullName -Algorithm SHA1

            # A missing copy is reported as unverified instead of throwing an error.
            $DestinationHash = $null

            if (Test-Path -LiteralPath $DestinationDirectoryFile -PathType Leaf)
            {
                $DestinationHash = (Get-FileHash -LiteralPath $DestinationDirectoryFile -Algorithm SHA1).Hash
            }

            $Result = [PSCustomObject]@{
                "FileName"            = $SourceDirectoryFile.FullName
                "DestinationFileName" = $DestinationDirectoryFile
                "SourceHash"          = $HashSource.Hash
                "DestinationHash"     = $DestinationHash
                "Verified"            = ($null -ne $DestinationHash) -and ($HashSource.Hash -eq $DestinationHash)
            }

            # Log the result to a CSV file.
            $Result | Export-Csv -Path (Join-Path -Path $LogDirectory -ChildPath "$( $DateTime )_HashCheckLog.csv") -Append -NoTypeInformation

            # Add the result to the results array.
            $Results += $Result
        }

        # Display a 'Success' Message.
        [System.Windows.Forms.MessageBox]::Show(
            "Files copied and hashes verified successfully.`n`n" +
            "The log file was saved to => " +
            "'$( $LogDirectory )\$( $DateTime )_filecopy.log'",
            "Success",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )

        $ViewResults = [System.Windows.Forms.MessageBox]::Show(
            "Would you like to view the hash results?",
            "View Hashes?",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )

        if ($ViewResults -eq 6)
        {
            # Display the results in a GUI window if the user chooses "Yes".
            $Results | Out-GridView -Title "File Hash Verification Results"
        }
        if ($ViewResults -eq 7)
        {
            return
        }
    })

    # Define a button for initiating the copy and hash verification.
    $ButtonClear = New-Object Windows.Forms.Button -Property @{
        Location = New-Object System.Drawing.Point -Property @{
            X = 190
            Y = 190
        }
        Font = New-Object System.Drawing.Font("Arial", 10)
        Text = "Clear"
        Width = 130
        Height = 50
    }
    $ButtonClear.Add_Click({
        $TextBoxSource.Clear()
        $TextBoxDest.Clear()
    })

    # Define a button for initiating the copy and hash verification.
    $ButtonClose = New-Object Windows.Forms.Button -Property @{
        Location = New-Object System.Drawing.Point -Property @{
            X = 350
            Y = 190
        }
        Font = New-Object System.Drawing.Font("Arial", 10)
        Text = "Close"
        Width = 130
        Height = 50
    }
    $ButtonClose.Add_Click({ $Form.Close() })

    # Add controls to the form
    $Form.Controls.Add($HeaderLabel)
    $Form.Controls.Add($LabelSource)
    $Form.Controls.Add($TextBoxSource)
    $Form.Controls.Add($BtnChooseSource)
    $Form.Controls.Add($LabelDest)
    $Form.Controls.Add($TextBoxDest)
    $Form.Controls.Add($BtnChooseDest)
    $Form.Controls.Add($ButtonCopy)
    $Form.Controls.Add($ButtonClear)
    $Form.Controls.Add($ButtonClose)

    # Display the form
    $Form.ShowDialog()
}

# =======================================

function Copy-FilesAndVerify
{
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
    param
    (
        [Parameter(Mandatory, Position=0)]
        [string]$SourceDirectory,

        [Parameter(Mandatory, Position=1)]
        [string]$DestinationDirectory
    )

    function Copy-Verify
    {
        # Get a list of all files and subdirectories in the source directory.
        $Items = Get-ChildItem -Path $SourceDirectory -Recurse -Force

        # Initialize an array to store results.
        $Results = @()

        foreach ($Item in $Items)
        {
            # Calculate SHA-1 hash for the source file.
            $HashSource = Get-FileHash -Path $Item.FullName -Algorithm SHA1

            # Calculate SHA-1 hash for the destination file (if it exists).
            $DestinationDirectoryFile = Join-Path `
                -Path $DestinationDirectory `
                -ChildPath $Item.FullName.Substring( $SourceDirectory.Length )

            Copy-Item `
                -Path $Item.FullName `
                -Destination $DestinationDirectoryFile `
                -Force `
                -Container:$True

            if ($($Item).PSIsContainer)
            {
                $HashDestination = 0
            }
            elseif (Test-Path -Path $DestinationDirectoryFile)
            {
                $HashDestination = Get-FileHash `
                    -Path $DestinationDirectoryFile `
                    -Algorithm SHA1
            }
            else
            {
                $HashDestination = $null
            }

            # Verifing the hash values of each folder.
            if (-Not $HashDestination)
            {
                $Verified = "Destination file not found."
            }
            elseif ($HashDestination -eq 0)
            {
                $Verified = "Is Directory."
            }
            elseif ($HashSource.Hash -eq $HashDestination.Hash)
            {
                $Verified = "Verified."
            }
            else
            {
                $Verified = "Hash mismatch."
            }

            # Add the result to the results array.
            $Results += [PSCustomObject]@{
                "SourceFile"      = $Item.FullName
                "DestinationFile" = $DestinationDirectoryFile
                "SourceHash"      = $HashSource.Hash
                "DestinationHash" = $HashDestination.Hash
                "HashVerified"    = $Verified
            }
        }
        # Return the results
        return $Results
    }

    # Perform the recursive copy and verification using the path variables passed
    # as arguments when the function was called.
    $Results = Copy-Verify `
        -SourcePath $SourceDirectory `
        -DestinationPath $DestinationDirectory

    # Display the results in a standard GUI window.
    $Results | Out-GridView -Title "File Hash Verification Results"

    Write-Host "$(Get-DateTime) | File hash verification complete." `
        -ForegroundColor DarkYellow
}
