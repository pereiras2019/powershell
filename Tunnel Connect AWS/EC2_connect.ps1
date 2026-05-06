# ------------------------------------------------------------
# 1. Configuración de Codificación (Fix para caracteres raros)
# ------------------------------------------------------------
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# ------------------------------------------------------------
# 2. Verificar Requisitos (AWS CLI y Session Manager)
# ------------------------------------------------------------
Write-Host "--- Verificando Requisitos ---" -ForegroundColor Cyan
$awsCli = Get-Command "aws" -ErrorAction SilentlyContinue
if (-not $awsCli) {
    Write-Host "AWS CLI no encontrado. Instálalo antes de continuar." -ForegroundColor Red; exit
}

$sessionManager = Get-Command "session-manager-plugin" -ErrorAction SilentlyContinue
if (-not $sessionManager) {
    Write-Host "Instalando plugin Session Manager..." -ForegroundColor Yellow
    Invoke-WebRequest "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/windows/SessionManagerPluginSetup.exe" -OutFile "$env:TEMP\SessionManagerPluginSetup.exe"
    Start-Process "$env:TEMP\SessionManagerPluginSetup.exe" -Wait
}

# ------------------------------------------------------------
# 3. Selección de Perfil (Cuentas configuradas)
# ------------------------------------------------------------
Write-Host "`n--- Selección de Cuenta/Perfil ---" -ForegroundColor Magenta
$perfiles = aws configure list-profiles
if ($perfiles.Count -eq 0) {
    Write-Host "No hay perfiles configurados. Corre 'aws configure --profile nombre'." -ForegroundColor Red; exit
}

for ($i = 0; $i -lt $perfiles.Count; $i++) {
    Write-Host "$($i+1)) $($perfiles[$i])"
}
$indicePerfil = Read-Host "`nElegí el número de perfil/cuenta"
$perfilElegido = $perfiles[$indicePerfil - 1]
$env:AWS_PROFILE = $perfilElegido

# Validar acceso
Write-Host "Validando acceso a la cuenta..." -ForegroundColor Yellow
$identidad = aws sts get-caller-identity --output json 2>$null
if (-not $identidad) {
    Write-Host "Error: Credenciales inválidas para el perfil '$perfilElegido'." -ForegroundColor Red; exit
}

# ------------------------------------------------------------
# 4. Selección de Región (Desde archivo regiones.txt)
# ------------------------------------------------------------
$rutaArchivo = Join-Path -Path $PSScriptRoot -ChildPath "regiones.txt"
$regionesConfiguradas = @()

if (Test-Path $rutaArchivo) {
    $regionesConfiguradas = Get-Content $rutaArchivo -Encoding UTF8 | Where-Object { $_.Trim() -ne "" }
} else {
    # Backup si el archivo no existe
    $regionesConfiguradas = @("us-east-1", "us-east-2", "sa-east-1")
}

Write-Host "`n--- Selección de Región ---" -ForegroundColor Cyan
for ($i = 0; $i -lt $regionesConfiguradas.Count; $i++) {
    Write-Host "$($i+1)) $($regionesConfiguradas[$i])"
}
$indiceReg = Read-Host "`nElegí el número de región"
$regionElegida = $regionesConfiguradas[$indiceReg - 1].Trim()
$env:AWS_DEFAULT_REGION = $regionElegida

# ------------------------------------------------------------
# 5. Listar Instancias EC2
# ------------------------------------------------------------
Write-Host "`nBuscando instancias en $regionElegida..." -ForegroundColor Yellow
$instancias = aws ec2 describe-instances `
    --query "Reservations[].Instances[].{ID:InstanceId,Name:Tags[?Key=='Name']|[0].Value,State:State.Name}" `
    --output json | ConvertFrom-Json

if ($instancias.Count -eq 0) {
    Write-Host "No se encontraron instancias en esta región." -ForegroundColor Red; exit
}

for ($i = 0; $i -lt $instancias.Count; $i++) {
    $item = $instancias[$i]
    $nombre = if ($item.Name) { $item.Name } else { "(sin nombre)" }
    Write-Host "$($i+1)) [$($item.State)] $($item.ID) - $nombre"
}

$indiceInstancia = Read-Host "`nElegí el número de la instancia"
$ec2Id = $instancias[$indiceInstancia - 1].ID

# ------------------------------------------------------------
# 6. Selección de Protocolo e Inicio de Túnel
# ------------------------------------------------------------
Write-Host "`nProtocolos disponibles:"
Write-Host "1) RDP (Puerto local 33389)"
Write-Host "2) SSH (Puerto local 2222)"
$opcion = Read-Host "Elige 1 o 2"

if ($opcion -eq "1") {
    $pRemoto = 3389; $pLocal = 33389
} else {
    $pRemoto = 22; $pLocal = 2222
}

Write-Host "`nIniciando túnel hacia $ec2Id..." -ForegroundColor Green
Write-Host "Conecta tu cliente (Remote Desktop o SSH) a localhost:$pLocal" -ForegroundColor Gray

aws ssm start-session `
    --target $ec2Id `
    --document-name AWS-StartPortForwardingSession `
    --parameters portNumber=$pRemoto,localPortNumber=$pLocal