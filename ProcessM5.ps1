#########################################################################
#                                                                       #
#       Script para procesar líneas M50101 y generar nuevas filas       #
#                                                                       #
#########################################################################

# Variables
$FolderPath = "C:\workspace\py\STI\process"
$FolderDestination = "C:\workspace\py\STI\processed" # Carpeta para respaldo

function Verify-Folder {
    param (
        [string]$Folder
    )
    if (-not (Test-Path $Folder)) {
        New-Item -Path $Folder -ItemType Directory | Out-Null
        Write-Host "Carpeta no existe, creada: $Folder"
    }
}

function Process-Files {
    param (
        [string]$FolderPath,
        [string]$FolderDestination
    )

    $Files = Get-ChildItem -Path $FolderPath -File -Filter *.txt

    foreach ($File in $Files) {
        $FilePath = $File.FullName
        $Content = Get-Content -Path $FilePath
        $ModifiedContent = @()
        $LinesToAdd = @()
        $QtLines = 0
        $LastM5Index = -1 # Variable para almacenar el índice de la última línea que comienza con M5

        Write-Host "Procesando archivo: $FilePath"

        foreach ($Line in $Content) {
            if ($Line -match "^M5\d{1}\d{1}01") {
                $QtLines++
                $LastM5Index = $ModifiedContent.Count # Actualizar el índice de la última línea M5
            }
            $ModifiedContent += $Line
        }

        # Generar nuevas líneas y agregarlas al lugar correcto
        foreach ($Line in $Content) {
            if ($Line -match "^M5\d{1}\d{1}01") {
                try {
                    # Extraer valores clave
                    $Parts = $Line -split "/"
                    $Iteration = $Line.Substring(2, 3).Trim() # Iteración (e.g., 501, 502)
                    $TicketNumber = ($Parts[0] -split "CM#")[1].Trim()
                    $Amount1 = [decimal]$Parts[2].Trim()
                    $Amount2 = [decimal]$Parts[3].Trim()
                    
                    $Name = ($Parts[5] -split "\s")[1..(($Parts[5] -split "\s").length-1)] -join " " # Obtener el nombre completo

                    $Sum = $Amount1 + $Amount2

                    $QtLines++
                    $FormattedQtLines = $QtLines.ToString("00") # Asegurar que tenga dos dígitos
                    $NewLine = "M5${FormattedQtLines}01A ACC000/FPT/ 0.00/$Sum/0.00/ONE/CASH $Name/1-CF*$TicketNumber*VCCM*TT8*FPCK*SG"
                    $LinesToAdd += $NewLine

                } catch {
                    Write-Host "Error procesando línea: $Line" -ForegroundColor Red
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

Write-Host "Iniciando procesamiento de archivos..."

# Verifico carpetas
Verify-Folder -Folder $FolderPath
Verify-Folder -Folder $FolderDestination

# Procesar archivos
Process-Files -FolderPath $FolderPath -FolderDestination $FolderDestination

Write-Host "Proceso completado."
