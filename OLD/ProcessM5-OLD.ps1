#########################################################################
#                                                                       #
#                    Script para procesar líneas M50101                 #
#                                                                       #
#########################################################################

# Variables
$FolderPath = "C:\workspace\py\STI\process"
$FolderDestination = "C:\workspace\py\STI\processed" # Carpeta de bkp de lo procesado
$ReplaceWith = "CASH" # Texto para reemplazar, ajustable
$SearchPatterns = @("M50101") # Descomentar la siguiente línea si incluye M50201A
# $SearchPatterns = @("M50101", "M50201A")

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
        [string]$FolderDestination,
        [string]$ReplaceWith,
        [array]$SearchPatterns
    )

    $Files = Get-ChildItem -Path $FolderPath -File -Filter *.txt

    foreach ($File in $Files) {
        $FilePath = $File.FullName
        $Content = Get-Content -Path $FilePath
        $ModifiedContent = @()
        $AlreadyModified = $false

        for ($i = 0; $i -lt $Content.Count; $i++) {
            $Line = $Content[$i]
            $ModifiedContent += $Line

            foreach ($Pattern in $SearchPatterns) {
                if ($Line -match "^$Pattern") {
                    $ModifiedLine = $Line -replace "/CC\S+", "/$ReplaceWith"

                    # Verifico si ya no está modificado el archivo, entonces no hago nada.
                    if ($i + 1 -lt $Content.Count -and $Content[$i + 1] -eq $ModifiedLine) {
                        $AlreadyModified = $true
                        break
                    }
                    $ModifiedContent += $ModifiedLine
                }
            }

            if ($AlreadyModified) {
                Write-Host "Archivo ya modificado, se omite: $FilePath"
                break
            }
        }

        if (-not $AlreadyModified) {
            # Creo una copia del archivo original en Proceessed 
            if (-not [string]::IsNullOrWhiteSpace($FolderDestination)) {
                Verify-Folder -Folder $FolderDestination
                $OriginalFilePath = Join-Path -Path $FolderDestination -ChildPath $File.Name
                Move-Item -Path $FilePath -Destination $OriginalFilePath -Force
                Write-Host "Archivo original copiado en: $OriginalFilePath"
            } 

            # Sobrescribir archivo con contenido modificado
            Set-Content -Path $FilePath -Value $ModifiedContent
            Write-Host "Archivo modificado y guardado en: $FilePath"
        }
    }
}

Write-Host "Iniciando procesamiento de archivos..."

# Verifico si las carpetas existen
Verify-Folder -Folder $FolderPath
Verify-Folder -Folder $FolderDestination

# Arrancamos!
Process-Files -FolderPath $FolderPath -FolderDestination $FolderDestination -ReplaceWith $ReplaceWith -SearchPatterns $SearchPatterns

Write-Host "Proceso completado."
