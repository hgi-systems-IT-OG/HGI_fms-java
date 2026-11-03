<#
  Installieren.ps1  (hgi systems)

  Einstieg mit einem Befehl, in einer PowerShell als Administrator:

    [Net.ServicePointManager]::SecurityProtocol='Tls12'; irm https://github.com/hgi-systems-IT-OG/HGI_fms-java/releases/latest/download/Installieren.ps1 | iex

  Laedt FMS_Java_aktualisieren.ps1 aus demselben Release, prueft die Pruefsumme und startet es.
  Eine bestimmte Version statt der neuesten: in der URL "latest/download" durch "download/<tag>"
  ersetzen.

  Kein "exit" in diesem Skript: Ueber "irm | iex" wuerde das die ganze PowerShell schliessen.
#>

function Install-HgiFmsJava {
    $repo   = 'hgi-systems-IT-OG/HGI_fms-java'
    $basis  = "https://github.com/$repo/releases/latest/download"
    $skript = 'FMS_Java_aktualisieren.ps1'

    $ErrorActionPreference = 'Stop'
    $ProgressPreference    = 'SilentlyContinue'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    $admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $admin) {
        Write-Host 'Bitte PowerShell als Administrator starten.' -ForegroundColor Red
        return
    }

    $tmp = Join-Path $env:TEMP "hgi-fms-java-$([guid]::NewGuid())"
    New-Item -ItemType Directory -Force $tmp | Out-Null
    try {
        Write-Host "`nLade $basis/$skript ..."
        Invoke-WebRequest -Uri "$basis/$skript"        -OutFile "$tmp\$skript"        -UseBasicParsing
        Invoke-WebRequest -Uri "$basis/$skript.sha256" -OutFile "$tmp\$skript.sha256" -UseBasicParsing

        $soll = ((Get-Content "$tmp\$skript.sha256" -Raw).Trim() -split '\s+')[0]
        $ist  = (Get-FileHash "$tmp\$skript" -Algorithm SHA256).Hash
        if ($ist -ne $soll) {
            Write-Host "Pruefsumme stimmt nicht ($ist statt $soll). Abgebrochen." -ForegroundColor Red
            return
        }

        # Gilt nur fuer diesen Prozess: Das heruntergeladene Skript ist nicht signiert.
        Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
        & "$tmp\$skript"
    } finally {
        Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
    }
}

Install-HgiFmsJava
