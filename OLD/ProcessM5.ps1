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

                    if (-not ([decimal]::TryParse($Parts[2].Trim(), [ref]$null)) -or -not ([decimal]::TryParse($Parts[3].Trim(), [ref]$null))) {
                        throw "Montos inválidos en la línea. Contenido: $Line"
                    }
                    $Amount1 = [decimal]$Parts[2].Trim()
                    $Amount2 = [decimal]$Parts[3].Trim()

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
                }
            }
        }
        if ($LastM5Index -ne -1) {
            $ModifiedContent = $ModifiedContent[0..$LastM5Index] + $LinesToAdd + $ModifiedContent[($LastM5Index + 1)..($ModifiedContent.Count - 1)]
        }
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
Write-Host $Accounts  
Process-Files -FolderPath $FolderPath -FolderDestination $FolderDestination -Accounts $Accounts
Write-Host "Proceso completado."