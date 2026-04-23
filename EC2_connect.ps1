# ------------------------------------------------------------
# Verificar instalaciï¿½n de AWS CLI
# ------------------------------------------------------------
Write-Host "Verificando si AWS CLI estï¿½ instalado..."

$awsCli = Get-Command "aws" -ErrorAction SilentlyContinue

if (-not $awsCli) {
    Write-Host "AWS CLI no estï¿½ instalado."
    $instalarCli = Read-Host "ï¿½Deseas instalar AWS CLI? (s/n)"

    if ($instalarCli -eq "s") {
        Write-Host "Instalando AWS CLI..."

        $msi = "$env:TEMP\AWSCLIV2.msi"
        Invoke-WebRequest "https://awscli.amazonaws.com/AWSCLIV2.msi" -OutFile $msi

        # Ejecutar MSI con privilegios y esperar correctamente
        Start-Process "msiexec.exe" -ArgumentList "/i `"$msi`" /qn" -Verb RunAs -Wait

        # Forzar recarga del PATH en la sesiï¿½n actual
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine")

        # Verificar instalaciï¿½n
        $awsCli = Get-Command "aws" -ErrorAction SilentlyContinue

        if ($awsCli) {
            Write-Host "AWS CLI instalado correctamente."
        } else {
            Write-Host "ERROR: AWS CLI no se instalï¿½ correctamente."
        }
    } else {
        Write-Host "Saliendo del script."
        exit
    }
} else {
    Write-Host "AWS CLI ya estï¿½ instalado."
}

# ------------------------------------------------------------
# Verificar instalaciï¿½n del plugin Session Manager
# ------------------------------------------------------------
Write-Host "Verificando si el plugin de Session Manager estï¿½ instalado..."

$sessionManager = Get-Command "session-manager-plugin" -ErrorAction SilentlyContinue

if (-not $sessionManager) {
    Write-Host "El plugin de Session Manager no estï¿½ instalado."
    $instalarPlugin = Read-Host "ï¿½Deseas instalar el plugin? (s/n)"

    if ($instalarPlugin -eq "s") {
        Write-Host "Instalando plugin Session Manager..."
        Invoke-WebRequest "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/windows/SessionManagerPluginSetup.exe" -OutFile "$env:TEMP\SessionManagerPluginSetup.exe"
        Start-Process "$env:TEMP\SessionManagerPluginSetup.exe" -Wait
    } else {
        Write-Host "Saliendo del script."
        exit
    }
} else {
    Write-Host "El plugin de Session Manager ya estï¿½ instalado."
}

# ------------------------------------------------------------
# AWS Login (abre navegador para autenticaciï¿½n)
# ------------------------------------------------------------
Write-Host "Iniciando sesiï¿½n en AWS..."
aws login

# ------------------------------------------------------------
# Configurar regiï¿½n
# ------------------------------------------------------------
Write-Host "Buscando regiones donde tenés instancias EC2..."

# Obtener todas las regiones como array real
$regiones = aws ec2 describe-regions --query "Regions[].RegionName" --output json --no-cli-pager | ConvertFrom-Json

$regionesConInstancias = @()

foreach ($r in $regiones) {

    Write-Host "Probando región: $r..."

    # Ejecutar describe-instances con timeout y sin paginador
    $instancias = try {
        $output = aws ec2 describe-instances `
            --region $r `
            --query "Reservations[].Instances[].InstanceId" `
            --output text `
            --no-cli-pager `
            2>$null

        $output
    } catch {
        ""
    }

    # Si devuelve algo, hay instancias
    if ($instancias -and $instancias.Trim() -ne "") {
        $regionesConInstancias += $r
    }
}

if ($regionesConInstancias.Count -eq 0) {
    Write-Host "`nNo se encontraron instancias EC2 en ninguna región."
    Write-Host "Posibles causas:"
    Write-Host "- La sesión SSO expiró"
    Write-Host "- El perfil SSO no tiene permisos EC2"
    Write-Host "- No se seleccionó el perfil correcto"
    Write-Host "- No hay instancias en el perfil actual"
    exit
}

Write-Host "`nRegiones donde tenés instancias EC2:`n"

for ($i = 0; $i -lt $regionesConInstancias.Count; $i++) {
    Write-Host "$($i+1)) $($regionesConInstancias[$i])"
}

$indice = Read-Host "`nElegí el número de la región"

if ($indice -notmatch '^\d+$' -or $indice -lt 1 -or $indice -gt $regionesConInstancias.Count) {
    Write-Host "Opción inválida. Saliendo."
    exit
}

$region = $regionesConInstancias[$indice - 1]

Write-Host "Región seleccionada: $region"
aws configure set region $region

# ------------------------------------------------------------
# Pedir ID de la instancia EC2
# ------------------------------------------------------------
Write-Host "`nBuscando instancias EC2 en la región seleccionada ($region)...`n"

# Obtener todas las instancias de la región seleccionada
$instancias = aws ec2 describe-instances `
    --region $region `
    --query "Reservations[].Instances[].{ID:InstanceId,Name:Tags[?Key=='Name']|[0].Value,State:State.Name,Type:InstanceType}" `
    --output json --no-cli-pager | ConvertFrom-Json

if (-not $instancias -or $instancias.Count -eq 0) {
    Write-Host "No se encontraron instancias EC2 en la región $region."
    exit
}

Write-Host "Instancias encontradas:`n"

# Mostrar lista numerada con ID + Nombre
for ($i = 0; $i -lt $instancias.Count; $i++) {
    $item = $instancias[$i]
    $nombre = if ($item.Name) { $item.Name } else { "(sin nombre)" }

    Write-Host "$($i+1)) ID: $($item.ID)  |  Nombre: $nombre  |  Estado: $($item.State)  |  Tipo: $($item.Type)"
}

# Elegir instancia por número
$indiceInstancia = Read-Host "`nElegí el número de la instancia EC2"

if ($indiceInstancia -notmatch '^\d+$' -or $indiceInstancia -lt 1 -or $indiceInstancia -gt $instancias.Count) {
    Write-Host "Opción inválida. Saliendo."
    exit
}

$ec2Id = $instancias[$indiceInstancia - 1].ID

Write-Host "`nInstancia seleccionada: $ec2Id"

# ------------------------------------------------------------
# Elegir protocolo y puertos
# ------------------------------------------------------------
Write-Host "Selecciona el protocolo:"
Write-Host "1) RDP (3389)"
Write-Host "2) SSH (22)"

$opcion = Read-Host "Elige 1 o 2"

switch ($opcion) {
    "1" {
        $puerto = 3389
        $puertoLocal = 33389
    }
    "2" {
        $puerto = 22
        $puertoLocal = 2222
    }
    default {
        Write-Host "Opciï¿½n invï¿½lida. Saliendo."
        exit
    }
}

Write-Host "Protocolo seleccionado. Puerto remoto: $puerto - Puerto local: $puertoLocal"

# ------------------------------------------------------------
# Ejecutar tï¿½nel SSM
# ------------------------------------------------------------
Write-Host "Iniciando tï¿½nel SSM hacia la instancia $ec2Id..."

aws ssm start-session `
    --target $ec2Id `
    --document-name AWS-StartPortForwardingSession `
    --parameters portNumber=$puerto,localPortNumber=$puertoLocal