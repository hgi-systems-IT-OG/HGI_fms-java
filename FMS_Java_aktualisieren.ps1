#Requires -RunAsAdministrator
# Java fuer FileMaker Server Web Publishing (WebDirect, Custom Web Publishing) auf Windows einrichten
# und aktualisieren. Fuer Erstinstallation und jedes spaetere Update dasselbe Skript.
#
# - erkennt die installierte FileMaker-Server-Version und deren Ordner
# - waehlt die Java-Hauptversion, die Claris fuer diese Version verlangt (Tabelle $javaFuerFms),
#   und davon die neueste Eclipse-Temurin-JDK (x64, MSI von adoptium.net, SHA256 geprueft)
# - ist sie schon installiert, aendert es nichts
# - stoppt auf Rueckfrage die Web Publishing Engine (mit fmsadmin, sonst von Hand in der Admin Console)
# - entfernt AdoptOpenJDK, alte Temurin-Installationen, den Ordner <FMS>\Web Publishing\java
#   und alte JAVA_HOME-/Path-Eintraege
# - installiert nach C:\Program Files\Eclipse Adoptium\jdk-<Hauptversion>\ mit JAVA_HOME und PATH
# - startet auf Rueckfrage die Web Publishing Engine wieder, sofern kein Neustart noetig ist
#
# Aufruf (PowerShell als Administrator):
#   powershell -ExecutionPolicy Bypass -File FMS_Java_aktualisieren.ps1
#   powershell -ExecutionPolicy Bypass -File FMS_Java_aktualisieren.ps1 -JavaMajor 21   # Tabelle uebersteuern
#
# Protokoll und Download liegen in C:\Zert\java.
#
# Secondary Machines (WebDirect auf eigener Maschine): dort fehlt eventuell fmsadmin oder es kann die
# Web Publishing Engine nicht steuern. Dann fragt das Skript, sie in der Admin Console zu stoppen
# bzw. zu starten, und macht sonst dasselbe. Auf jeder Maschine einzeln ausfuehren.

param(
    [int]$JavaMajor = 0
)

# Benoetigte Java-Hauptversion je FileMaker-Server-Hauptversion.
# Quelle: Claris-Artikel "Claris FileMaker Server and Java ... Installation Instructions".
# Bei einer neuen FileMaker-Server-Version hier eine Zeile ergaenzen.
$javaFuerFms = @{
    19 = 11    # FileMaker Server 19
    20 = 17    # FileMaker Server 2023
    21 = 17    # FileMaker Server 2024
    22 = 17    # FileMaker Server 2025
    26 = 21    # FileMaker Server 2026
}

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$arbeit       = 'C:\Zert\java'
$envKey       = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment'
$uninstallKey = @(
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)

New-Item -ItemType Directory -Force -Path $arbeit | Out-Null
Start-Transcript -Path (Join-Path $arbeit 'protokoll.txt') -Append | Out-Null

function Get-MachinePathRaw {
    # Roh aus der Registry, damit %VARIABLEN% nicht aufgeloest zurueckgeschrieben werden
    (Get-Item $envKey).GetValue('Path', '', 'DoNotExpandEnvironmentNames')
}

function Get-JavaHome {
    (Get-Item $envKey).GetValue('JAVA_HOME', '')
}

function Test-AltJava([string]$eintrag) {
    $eintrag -match 'AdoptOpenJDK|Eclipse Adoptium|Temurin' -or
    $eintrag -like "$fmsJava*" -or
    $eintrag -match '%JAVA_HOME%'
}

function Get-FmsWurzel($fmsEintrag) {
    # Ordner, in dem "Database Server\fmsadmin.exe" liegt, sonst "Web Publishing" (Secondary ohne fmsadmin)
    $kandidaten = @()
    if ($fmsEintrag.InstallLocation) { $kandidaten += $fmsEintrag.InstallLocation }
    $dienst = Get-CimInstance Win32_Service | Where-Object { $_.DisplayName -match 'FileMaker Server' } | Select-Object -First 1
    if ($dienst -and $dienst.PathName -match '^"?([^"]+\.exe)') { $kandidaten += Split-Path $Matches[1] }
    foreach ($merkmal in 'Database Server\fmsadmin.exe', 'Web Publishing') {
        foreach ($k in $kandidaten) {
            $ordner = $k.TrimEnd('\')
            while ($ordner) {
                if (Test-Path (Join-Path $ordner $merkmal)) { return $ordner }
                $ordner = Split-Path $ordner
            }
        }
    }
    throw 'FileMaker-Server-Ordner nicht gefunden (weder Database Server\fmsadmin.exe noch Web Publishing).'
}

function Get-JavaProzesse {
    @(Get-Process java, javaw -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -like "$fmsWurzel*" -or $_.Path -match 'AdoptOpenJDK|Eclipse Adoptium' })
}

function Test-FmsadminWpe([string]$befehl) {
    # Ob "fmsadmin <befehl> WPE" in dieser Version existiert; "help" braucht keine Anmeldung.
    # Ohne fmsadmin (Secondary) immer nein.
    if (-not $fmsadmin) { return $false }
    $hilfe = & $fmsadmin help $befehl 2>$null | Out-String
    $hilfe -match '\bWPE\b'
}

function Set-Wpe([string]$befehl) {
    # Web Publishing Engine starten/stoppen: mit fmsadmin, sonst oder bei Fehler von Hand.
    # Liefert $true, wenn es erledigt ist.
    $text = @{ stop = 'stoppen'; start = 'starten' }[$befehl]
    if (Test-FmsadminWpe $befehl) {
        try {
            Invoke-Fmsadmin @($befehl, 'wpe', '-y')
            return $true
        } catch {
            Write-Host "  $($_.Exception.Message)" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  fmsadmin kann die Web Publishing Engine hier nicht $text." -ForegroundColor Yellow
    }
    $antwort = Read-Host "  Bitte in der Admin Console > Connectors > Web Publishing $text, dann Enter (n = spaeter)"
    $antwort -ne 'n'
}

function Invoke-Fmsadmin([string[]]$argumente) {
    # fmsadmin fragt Benutzername und Passwort der Admin Console selbst ab
    & $fmsadmin @argumente
    if ($LASTEXITCODE -ne 0) { throw "fmsadmin $($argumente -join ' ') meldet Fehler $LASTEXITCODE" }
}

try {
    # ---------------------------------------------------------------- FileMaker Server erkennen
    Write-Host ''
    Write-Host '== FileMaker Server' -ForegroundColor Cyan

    $fms = Get-ItemProperty $uninstallKey -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -match 'FileMaker Server' -and $_.DisplayVersion } |
        Sort-Object { [version]($_.DisplayVersion -replace '[^0-9.]', '') } -Descending |
        Select-Object -First 1
    if (-not $fms) { throw 'Kein FileMaker Server installiert.' }

    $fmsMajor  = [int]($fms.DisplayVersion -split '\.')[0]
    $fmsWurzel = Get-FmsWurzel $fms
    $fmsadmin  = Join-Path $fmsWurzel 'Database Server\fmsadmin.exe'
    if (-not (Test-Path $fmsadmin)) { $fmsadmin = $null }
    $fmsJava   = Join-Path $fmsWurzel 'Web Publishing\java'
    Write-Host "  Version:          $($fms.DisplayName) $($fms.DisplayVersion)"
    Write-Host "  Ordner:           $fmsWurzel"
    if (-not $fmsadmin) { Write-Host '  fmsadmin:         fehlt (Secondary?), Web Publishing Engine von Hand' -ForegroundColor Yellow }

    if ($JavaMajor -eq 0) {
        if (-not $javaFuerFms.ContainsKey($fmsMajor)) {
            throw ("FileMaker Server $fmsMajor steht noch nicht in der Tabelle. Benoetigte Java-Version im Claris-Artikel " +
                   "'FileMaker Server and Java' nachsehen und oben in `$javaFuerFms ergaenzen oder -JavaMajor angeben.")
        }
        $JavaMajor = $javaFuerFms[$fmsMajor]
    }
    $installDir = "C:\Program Files\Eclipse Adoptium\jdk-$JavaMajor\"
    Write-Host "  braucht Java:     $JavaMajor"

    # ---------------------------------------------------------------- Bestand
    Write-Host ''
    Write-Host '== Bestand' -ForegroundColor Cyan

    $api = Invoke-RestMethod "https://api.adoptium.net/v3/assets/latest/$JavaMajor/hotspot?architecture=x64&image_type=jdk&os=windows&vendor=eclipse"
    $msi = $api[0].binary.installer
    $neu = $api[0].release_name -replace '^jdk-?', ''    # z.B. 21.0.12.1+1, so steht es auch im Anzeigenamen

    $altInstall = @(Get-ItemProperty $uninstallKey -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -match 'AdoptOpenJDK|Eclipse Temurin' })
    $javaHomeAlt = Get-JavaHome
    $pathAlt     = Get-MachinePathRaw

    $aktuell = $altInstall.Count -eq 1 -and $altInstall[0].DisplayName -like "*$neu*" -and
               "$javaHomeAlt".TrimEnd('\') -eq $installDir.TrimEnd('\') -and -not (Test-Path $fmsJava)
    if ($aktuell) {
        Write-Host "  Schon aktuell:    $($altInstall[0].DisplayName)" -ForegroundColor Green
        Write-Host '  Nichts zu tun.'
        return
    }

    foreach ($e in $altInstall) { Write-Host "  Deinstallieren:   $($e.DisplayName)" }
    if (Test-Path $fmsJava) { Write-Host "  Ordner loeschen:  $fmsJava" }
    Write-Host "  JAVA_HOME jetzt:  $javaHomeAlt"
    $pathAlt -split ';' | Where-Object { $_ -and (Test-AltJava $_) } | ForEach-Object { Write-Host "  Aus Path weg:     $_" }
    $pathAlt -split ';' | Where-Object { $_ -match 'java|jdk|jre' -and -not (Test-AltJava $_) } |
        ForEach-Object { Write-Host "  Bleibt im Path (fremdes Java?): $_" -ForegroundColor Yellow }
    Write-Host "  Installieren:     $($api[0].release_name) -> $installDir"

    Write-Host ''
    if ((Read-Host 'So durchfuehren? (j/n)') -ne 'j') { throw 'Abgebrochen, nichts geaendert.' }

    # ---------------------------------------------------------------- 1. Web Publishing Engine stoppen
    Write-Host ''
    Write-Host '== 1. Web Publishing Engine' -ForegroundColor Cyan
    $wpeGestoppt = $false
    if ((Get-JavaProzesse).Count -gt 0) {
        Write-Host '  Die Web Publishing Engine laeuft. Beim Stoppen werden alle WebDirect-Benutzer getrennt.' -ForegroundColor Yellow
        if ((Read-Host '  Web Publishing Engine jetzt stoppen? (j/n)') -ne 'j') { throw 'Abgebrochen, nichts geaendert.' }
        if (-not (Set-Wpe 'stop')) { throw 'Abgebrochen, nichts geaendert.' }
        $wpeGestoppt = $true
        for ($i = 0; $i -lt 60 -and (Get-JavaProzesse).Count -gt 0; $i++) { Start-Sleep -Seconds 1 }
        if ((Get-JavaProzesse).Count -gt 0) { throw 'Java laeuft nach 60 Sekunden noch. Web Publishing Engine in der Admin Console pruefen.' }
        Write-Host '  gestoppt'
    } else {
        Write-Host '  laeuft nicht'
    }

    # ---------------------------------------------------------------- 2. Bisheriges Java deinstallieren
    Write-Host ''
    Write-Host '== 2. Bisheriges Java deinstallieren' -ForegroundColor Cyan
    foreach ($e in $altInstall) {
        $code = $e.PSChildName
        if ($code -notmatch '^\{[0-9A-Fa-f-]+\}$') {
            Write-Host "  Kein MSI-Eintrag, bitte von Hand ueber appwiz.cpl entfernen: $($e.DisplayName)" -ForegroundColor Yellow
            continue
        }
        $p = Start-Process msiexec.exe -ArgumentList "/x $code /qn /norestart" -Wait -PassThru
        if ($p.ExitCode -notin 0, 3010) { throw "Deinstallation von $($e.DisplayName) fehlgeschlagen, msiexec $($p.ExitCode)" }
        Write-Host "  entfernt: $($e.DisplayName)"
    }
    if ($altInstall.Count -eq 0) { Write-Host '  nichts installiert' }

    # ---------------------------------------------------------------- 3. FileMaker-Java-Ordner loeschen
    Write-Host ''
    Write-Host '== 3. FileMaker-Java-Ordner loeschen' -ForegroundColor Cyan
    if (Test-Path $fmsJava) {
        Remove-Item $fmsJava -Recurse -Force
        Write-Host "  geloescht: $fmsJava"
    } else {
        Write-Host '  nicht vorhanden'
    }

    # ---------------------------------------------------------------- 4. JAVA_HOME und Path bereinigen
    Write-Host ''
    Write-Host '== 4. Umgebungsvariablen bereinigen' -ForegroundColor Cyan
    Add-Content -Path (Join-Path $arbeit 'Path_vorher.txt') -Value "$(Get-Date -Format s)`r`nJAVA_HOME=$javaHomeAlt`r`nPath=$pathAlt`r`n"

    # eine Temurin-Deinstallation nimmt JAVA_HOME schon selbst mit
    if (Get-JavaHome) {
        Remove-ItemProperty -Path $envKey -Name 'JAVA_HOME'
        Write-Host '  JAVA_HOME entfernt'
    }
    $pathJetzt = Get-MachinePathRaw    # die Deinstallation kann Path schon geaendert haben
    $pathNeu   = (@($pathJetzt -split ';' | Where-Object { $_ -and -not (Test-AltJava $_) })) -join ';'
    if ($pathNeu -ne $pathJetzt) {
        Set-ItemProperty -Path $envKey -Name 'Path' -Value $pathNeu -Type ExpandString
        Write-Host '  Path bereinigt (Sicherung: Path_vorher.txt)'
    } else {
        Write-Host '  Path war schon sauber'
    }

    # ---------------------------------------------------------------- 5. Temurin laden und pruefen
    Write-Host ''
    Write-Host "== 5. $($msi.name) laden" -ForegroundColor Cyan
    $msiDatei = Join-Path $arbeit $msi.name
    Invoke-WebRequest -Uri $msi.link -OutFile $msiDatei -UseBasicParsing
    $hash = (Get-FileHash $msiDatei -Algorithm SHA256).Hash
    if ($hash -ne $msi.checksum) { throw "SHA256 stimmt nicht: erwartet $($msi.checksum), erhalten $hash" }
    Write-Host '  SHA256 stimmt'

    # ---------------------------------------------------------------- 6. Installieren
    Write-Host ''
    Write-Host '== 6. Installieren' -ForegroundColor Cyan
    $msiArgs = @(
        '/i', "`"$msiDatei`"",
        'ADDLOCAL=FeatureMain,FeatureEnvironment,FeatureJavaHome',
        "INSTALLDIR=`"$installDir`"",
        '/qn', '/norestart',
        '/l*v', "`"$(Join-Path $arbeit 'msi_install.log')`""
    )
    $p = Start-Process msiexec.exe -ArgumentList $msiArgs -Wait -PassThru
    if ($p.ExitCode -notin 0, 3010) { throw "Installation fehlgeschlagen, msiexec $($p.ExitCode). Siehe msi_install.log" }
    Write-Host '  installiert'

    # ---------------------------------------------------------------- 7. Pruefen
    Write-Host ''
    Write-Host '== 7. Pruefen' -ForegroundColor Cyan
    $javaHome = Get-JavaHome
    Write-Host "  JAVA_HOME:  $javaHome"
    $javaExe = Join-Path $javaHome 'bin\java.exe'
    if (-not (Test-Path $javaExe)) { throw "java.exe fehlt unter $javaExe" }

    $versionDatei = Join-Path $arbeit 'version.txt'
    Start-Process $javaExe -ArgumentList '-version' -NoNewWindow -Wait -RedirectStandardError $versionDatei
    Get-Content $versionDatei | ForEach-Object { Write-Host "  $_" }

    Write-Host '  Java-Eintraege im Path:'
    (Get-MachinePathRaw) -split ';' | Where-Object { $_ -match 'java|jdk|jre|Adoptium' } | ForEach-Object { Write-Host "    $_" }

    # ---------------------------------------------------------------- 8. Abschluss
    Write-Host ''
    if ("$javaHomeAlt".TrimEnd('\') -eq "$javaHome".TrimEnd('\')) {
        Write-Host 'Fertig. JAVA_HOME ist gleich geblieben, kein Neustart noetig.' -ForegroundColor Green
        if ((Read-Host 'Web Publishing Engine jetzt starten? (j/n)') -eq 'j' -and (Set-Wpe 'start')) {
            Write-Host '  gestartet. In der Admin Console die JDK-Version pruefen und WebDirect testen.'
        } else {
            Write-Host '  Web Publishing Engine spaeter in der Admin Console starten.'
        }
    } else {
        Write-Host 'Fertig. JAVA_HOME hat sich geaendert: jetzt den Server NEU STARTEN.' -ForegroundColor Green
        Write-Host 'Danach Admin Console > Connectors > Web Publishing: JDK-Version pruefen, Web Publishing Engine starten, WebDirect aktivieren.'
    }
}
catch {
    Write-Host ''
    Write-Host "FEHLER: $($_.Exception.Message)" -ForegroundColor Red
    if ($wpeGestoppt) { Write-Host 'Die Web Publishing Engine wurde gestoppt und laeuft noch nicht wieder.' -ForegroundColor Yellow }
}
finally {
    Stop-Transcript | Out-Null
}
