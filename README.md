# HGI_fms-java

Richtet Java für FileMaker Server Web Publishing (WebDirect) unter Windows ein und hält es aktuell. Erstinstallation und jedes Update laufen über dasselbe Skript.

## Starten

In einer PowerShell **als Administrator** auf dem FileMaker Server:

```powershell
[Net.ServicePointManager]::SecurityProtocol='Tls12'; irm https://github.com/hgi-systems-IT-OG/HGI_fms-java/releases/latest/download/Installieren.ps1 | iex
```

`Installieren.ps1` lädt `FMS_Java_aktualisieren.ps1` aus demselben Release, prüft die SHA256-Prüfsumme und startet es. Auf den Server muss nichts kopiert werden.

## Was es macht

1. Erkennt FileMaker-Server-Version und Installationsordner.
2. Wählt die Java-Version, die Claris dafür verlangt (nicht die neueste LTS):
   FMS 19 → Java 11 · FMS 2023/2024/2025 → Java 17 · FMS 2026 → Java 21
3. Ist die neueste Ausgabe davon schon installiert: „Schon aktuell“, nichts passiert.
4. Sonst zeigt es, was es tun wird, und fragt (j/n).
5. Stoppt nach Rückfrage die Web Publishing Engine (WebDirect-Benutzer werden getrennt). fmsadmin fragt dabei nach Benutzer und Passwort der Admin Console.
6. Entfernt altes Java: AdoptOpenJDK, alte Temurin, `<FMS>\Web Publishing\java`, alte `JAVA_HOME`- und Path-Einträge.
7. Lädt Eclipse Temurin JDK (x64, MSI) von adoptium.net, prüft SHA256 und installiert nach `C:\Program Files\Eclipse Adoptium\jdk-<Version>\` mit `JAVA_HOME` und PATH.
8. Gleiche Java-Hauptversion wie vorher: kein Neustart nötig, startet nach Rückfrage die Web Publishing Engine wieder. Neue Hauptversion: Server neu starten, danach die WPE in der Admin Console starten.

## Wann ausführen

Nach jedem Java-Quartalsupdate (Mitte Jänner, April, Juli, Oktober) und nach einem FileMaker-Server-Upgrade auf eine neue Hauptversion.

## Gut zu wissen

- Java **nicht** über die Admin Console hochladen und keine MSI von Hand drüberinstallieren.
- Eine neue FileMaker-Server-Version, die nicht in der Tabelle steht, lässt das Skript abbrechen. Die benötigte Java-Version steht im Claris-Artikel „FileMaker Server and Java“. In `FMS_Java_aktualisieren.ps1` unter `$javaFuerFms` eine Zeile ergänzen und ein neues Release machen.
- Mehrere WebDirect-Maschinen: auf jeder Maschine einzeln ausführen, Primary und Secondary mit derselben Java-Version. Fehlt auf einer Secondary fmsadmin oder kann es die Web Publishing Engine nicht steuern, fragt das Skript, sie in der Admin Console zu stoppen bzw. zu starten.
- Braucht Internetzugang zu github.com und api.adoptium.net.
- Protokoll, Download und Sicherung der alten Path-Werte: `C:\Zert\java`.

## Releases

Änderungen nur hier im Repo machen. Danach einen Tag `v<version>` setzen, z. B. `v1.0.1`. Die GitHub-Action legt das Release mit `Installieren.ps1`, `FMS_Java_aktualisieren.ps1` und `FMS_Java_aktualisieren.ps1.sha256` an, und der Befehl oben holt es über `releases/latest`.

hgi systems – Thomas Hasler
