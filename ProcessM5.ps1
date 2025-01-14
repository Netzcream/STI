#########################################################################
#                                                                       #
#       Script para procesar líneas M50101 y generar nuevas filas       #
#                                                                       #
#########################################################################

# Variables
$FolderPath = "C:\workspace\py\STI\process"
$FolderDestination = "C:\workspace\py\STI\processed" # Carpeta para respaldo
$FileAccounts = "C:\workspace\py\STI\cuentas.txt" # Archivo de cuentas

function Verify-Folder {
    param (
        [string]$Folder
    )
    if (-not (Test-Path $Folder)) {
        New-Item -Path $Folder -ItemType Directory | Out-Null
        Write-Host "Carpeta no existe, creada: $Folder"
    }
}

function Load-Accounts {
    param (
        [string]$FileAccounts
    )
    if (-not (Test-Path $FileAccounts)) {
        throw "El archivo de cuentas no existe: $FileAccounts"
    }
    return Get-Content -Path $FileAccounts
}

function Add-M3Line {
    param (
        [array]$Content,
        [string]$Date
    )

    $LastM3Line = $Content | Where-Object { $_ -match "^M3\d{4}" } | Select-Object -Last 1
    if ($LastM3Line) {
        $LastM3Number = [int]($LastM3Line.Substring(2, 2))
        $NextM3Number = $LastM3Number + 1
        $FormattedNextM3Number = $NextM3Number.ToString("00")
        $NewM3Line = "M3${FormattedNextM3Number}8A0GK${Date}OTH 01               MIA/RECREATE A/C LINES FOR AGENCY CREDIT CARD TICKETS"

        $ExistingLine = $Content | Where-Object { $_ -match "OTH 01\s+MIA/RECREATE A/C LINES FOR AGENCY CREDIT CARD TICKETS" }
        if (-not $ExistingLine) {
            $Content += $NewM3Line
        }
    }
    return $Content
}

function Process-Files {
    param (
        [string]$FolderPath,
        [string]$FolderDestination,
        [array]$Accounts
    )

    $Files = Get-ChildItem -Path $FolderPath -File

    foreach ($File in $Files) {
        $FilePath = $File.FullName
        $Content = Get-Content -Path $FilePath

        # Verificar la línea que comienza con AA
        $FirstLine = $Content | Where-Object { $_ -match "^AA" } | Select-Object -First 1
        if (-not $FirstLine) {
            Write-Host "Archivo $FilePath no contiene una línea que comience con 'AA'. Se ignora."
            continue
        }

        $FirstSegment = ($FirstLine -split " ")[0]
        $AccountToCheck = $FirstSegment.Substring($FirstSegment.Length - 10)
        if (-not $Accounts.Contains($AccountToCheck)) {
            Write-Host "Cuenta $AccountToCheck de $FilePath no está en el archivo de cuentas. Se ignora."
            continue
        }

        $ModifiedContent = @()
        $LinesToAdd = @()
        $QtLines = 0
        $LastM5Index = -1

        $CountM5 = ($Content | Where-Object { $_ -match "^M5\d{4}(?!A)" }).Count
        $CountM5A = ($Content | Where-Object { $_ -match "^M5\d{4}A" }).Count
        if ($CountM5A -gt $CountM5) {
            Write-Host "Archivo $FilePath tiene más líneas M5A que M5, revisar manualmente, se ignora."
            continue
        }
        if ($CountM5 -eq $CountM5A -and $CountM5 -gt 0) {
            Write-Host "Archivo $FilePath parece que ya fue procesado, se ignora."
            continue
        }
        foreach ($Line in $Content) {
            if ($Line -match "^M5\d{4}(?!A)") {
                $QtLines++
                $LastM5Index = $ModifiedContent.Count
            }
            $ModifiedContent += $Line
        }

        foreach ($Line in $Content) {
            if ($Line -match "^M5\d{4}(?!A)") {
                try {
                    $Parts = $Line -split "/"
                    if ($Parts.Count -lt 6) {
                        throw "La línea no tiene suficientes partes después del split. Contenido: $Line"
                    }

                    $Iteration = $Line.Substring(2, 3).Trim()
                    $LineNumber = $Line.Substring(4, 2).Trim()
                    $TicketNumber = ($Parts[0] -split "#")[1].Trim()
                    $Segment = $Parts[0].Trim()
                    $Airline = ($Segment -split "#")[0].Trim()
                    $Code = $Airline[-2..-1] -join ""

                    $Amount1String = $Parts[2].Trim()
                    $Amount2String = $Parts[3].Trim()
                    if ($Amount1String -match "\s+\d+(\.\d+)?$") {
                        $Amount1String = $Amount1String -replace ".*\s+(\d+(\.\d+)?)$", '$1'
                    }
                    if ($Amount2String -match "\s+\d+(\.\d+)?$") {
                        $Amount2String = $Amount2String -replace ".*\s+(\d+(\.\d+)?)$", '$1'
                    }

                    if (-not ([decimal]::TryParse($Amount1String, [ref]$null)) -or -not ([decimal]::TryParse($Amount2String, [ref]$null))) {
                        throw "Montos inválidos en la línea. Contenido: $Line"
                    }
                    $Amount1 = [decimal]$Amount1String
                    $Amount2 = [decimal]$Amount2String

                    if (-not $Parts[5]) {
                        throw "El campo de nombre no está presente. Contenido: $Line"
                    }
                    $Name = ($Parts[5] -split "\s")[1..(($Parts[5] -split "\s").length - 1)] -join " "

                    $Sum = $Amount1 + $Amount2
                    $QtLines++
                    $FormattedQtLines = $QtLines.ToString("00")
                    $NewLine = "M5${FormattedQtLines}${LineNumber}A ACC000/FPT/ 0.00/$Sum/0.00/ONE/CASH $Name/1-*CF$TicketNumber*VC$Code*TT8*FPCK*SG"
                    $LinesToAdd += $NewLine
                }
                catch {
                    Write-Host "Error procesando línea: $Line" -ForegroundColor Red
                    Write-Host "Descripción del error: $($_.Exception.Message)" -ForegroundColor Yellow
                    continue
                }
            }
        }
        if ($LastM5Index -ne -1) {
            $ModifiedContent = $ModifiedContent[0..$LastM5Index] + $LinesToAdd + $ModifiedContent[($LastM5Index + 1)..($ModifiedContent.Count - 1)]
        }
        $Content = Add-M3Line -Content $Content -Date (Get-Date -Format "ddMMMyy").ToUpper()
        Verify-Folder -Folder $FolderDestination
        $OriginalFilePath = Join-Path -Path $FolderDestination -ChildPath $File.Name
        Move-Item -Path $FilePath -Destination $OriginalFilePath -Force
        Set-Content -Path $FilePath -Value $ModifiedContent
        Write-Host "Archivo modificado y guardado en: $FilePath"
    }
}

Write-Host "Procesando archivos..."
Verify-Folder -Folder $FolderPath
Verify-Folder -Folder $FolderDestination
$Accounts = Load-Accounts -FileAccounts $FileAccounts
Process-Files -FolderPath $FolderPath -FolderDestination $FolderDestination -Accounts $Accounts
Write-Host "Proceso completado."