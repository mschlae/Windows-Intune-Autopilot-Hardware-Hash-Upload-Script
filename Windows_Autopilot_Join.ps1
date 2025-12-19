#AD Tenant ID
$TenantId     = ""

#Registert Application
$ClientId     = ""
$ClientSecret = ""


Write-Host "Installier benötigte PowerShell-module..." -ForegroundColor Cyan
# Kompletter Reset
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Set-ExecutionPolicy Bypass -Force



# Module
#Install-Module Microsoft.Graph -Force 
Install-Module Microsoft.Graph.Authentication -Force 
Install-Module Microsoft.Graph.DeviceManagement.Enrollment -Force 

# Script
Install-Script Get-WindowsAutopilotInfo -Force
# Execution Policy (temporär)
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force







# ===============================================
# TOKEN ANFORDERN
# =============================================
Write-Host "Fordere Token an..." -ForegroundColor Cyan
$TokenBody = @{
    grant_type    = "client_credentials"
    client_id     = $ClientId
    client_secret = $ClientSecret
    scope         = "https://graph.microsoft.com/.default"
}

try {
    $Token = Invoke-RestMethod `
        -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" `
        -Method Post `
        -Body $TokenBody `
        -ContentType "application/x-www-form-urlencoded"
    
    Write-Host "Token erfolgreich erhalten" -ForegroundColor Green
}
catch {
    Write-Host "Fehler: Token konnte nicht abgerufen werden." -ForegroundColor Red
    Write-Host "Fehlermeldung: $($_.Exception.Message)"
    Write-Host "Response: $($_.ErrorDetails.Message)"
    exit 1
}

$AccessToken = $Token.access_token

# ===============================================
# MICROSOFT GRAPH CONNECTION
# ===============================================
Write-Host "verbinde mit Microsoft Graph..." -ForegroundColor Cyan

try {
    # Disconnect first if already connected
    if (Get-Command Disconnect-MgGraph -ErrorAction SilentlyContinue) {
        Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
    }
    
    # Import required modules
    Import-Module Microsoft.Graph.Authentication -Force
    Import-Module Microsoft.Graph.DeviceManagement.Enrollment -Force
    
    # Connect with AccessToken
    $SecureAccessToken = ConvertTo-SecureString $AccessToken -AsPlainText -Force
    Connect-MgGraph -AccessToken $SecureAccessToken -NoWelcome | Out-Null
    
    Write-Host "Erfolgreich mit Microsoft Graph verbunden" -ForegroundColor Green
}
catch {
    Write-Host "Fehler: Graph Connection schlug fehl." -ForegroundColor Red
    Write-Host "Fehlermeldung: $($_.Exception.Message)"
    exit 2
}

# ===============================================
# HARDWARE HASH SAMMELN (CSV)
# ===============================================
Write-Host "Sammle Hardware-Informationen..." -ForegroundColor Cyan
$TempCsv = "$env:TEMP\autopilot_hw.csv"

try {
    # Run as admin or with proper permissions
    Get-WindowsAutopilotInfo -OutputFile $TempCsv
}
catch {
    Write-Host "Fehler: Autopilot Hardware Hash konnte nicht gesammelt werden." -ForegroundColor Red
    Write-Host "Tipp: Führen Sie PowerShell als Administrator aus" -ForegroundColor Yellow
    exit 3
}

# CSV-Datei lesen
try {
    $csvData = Import-Csv $TempCsv
    $deviceInfo = $csvData[0]
    
    $apinfo = @{
        serialNumber = $deviceInfo.'Device Serial Number'.Trim()
        hardwareHash = $deviceInfo.'Hardware Hash'.Trim()
    }
    
    # Hersteller und Modell von WMI holen
    $computerSystem = Get-WmiObject -Class Win32_ComputerSystem
    $apinfo.manufacturer = $computerSystem.Manufacturer.Trim()
    $apinfo.model = $computerSystem.Model.Trim()
    
    Write-Host "`nAutopilot-Informationen:" -ForegroundColor Green
    Write-Host "Serial Number: $($apinfo.serialNumber)"
    Write-Host "Manufacturer: $($apinfo.manufacturer)"
    Write-Host "Model: $($apinfo.model)"
    Write-Host "Hardware Hash (erste 20 Zeichen): $($apinfo.hardwareHash.Substring(0, [Math]::Min(20, $apinfo.hardwareHash.Length)))..."
}
catch {
    Write-Host "Fehler bei CSV-Verarbeitung: $($_.Exception.Message)" -ForegroundColor Red
    exit 3
}

# ===============================================
# HARDWARE HASH IN INTUNE/AUTOPILOT HOCHLADEN
# ===============================================
Write-Host "`nLade hardware Hash in Intune Autopilot hoch..." -ForegroundColor Cyan

try {
    # Hardware Hash bereinigen und konvertieren
    $cleanHash = $apinfo.hardwareHash -replace '[^A-Za-z0-9+/=]', ''
    
    # DEBUG: Show hash info
    Write-Host "Hardware Hash Länge: $($cleanHash.Length)" -ForegroundColor Yellow
    Write-Host "Hash (erste 50 Zeichen): $($cleanHash.Substring(0, [Math]::Min(50, $cleanHash.Length)))..." -ForegroundColor Yellow
    
    # Convert from Base64 to byte array
    try {
        $hardwareIdentifier = [System.Convert]::FromBase64String($cleanHash)
        Write-Host "Base64 Konvertierung erfolgreich" -ForegroundColor Green
    }
    catch [System.FormatException] {
        Write-Host "Fehler: Hardware Hash ist nicht im korrekten Base64-Format" -ForegroundColor Red
        Write-Host "Hash muss Base64-kodiert sein (nur A-Z, a-z, 0-9, +, /, =)" -ForegroundColor Yellow
        exit 4
    }
    
    # Erstelle Autopilot Device Eintrag mit der richtigen Methode
    Write-Host "Erstelle Autopilot Device Eintrag..." -ForegroundColor Yellow
    
    # Option 1: Direkter Aufruf der Graph API (empfohlen)
    $headers = @{
        "Authorization" = "Bearer $AccessToken"
        "Content-Type" = "application/json"
    }
    
    $body = @{
        serialNumber = $apinfo.serialNumber
        hardwareIdentifier = $cleanHash
        manufacturer = $apinfo.manufacturer
        model = $apinfo.model
    } | ConvertTo-Json
    
    Write-Host "Sende Request an Graph API..." -ForegroundColor Yellow
    
    $response = Invoke-RestMethod `
        -Uri "https://graph.microsoft.com/beta/deviceManagement/importedWindowsAutopilotDeviceIdentities" `
        -Method Post `
        -Headers $headers `
        -Body $body `
        -ErrorAction Stop
    
    Write-Host "Hardware Hash erfolgreich in Intune hochgeladen" -ForegroundColor Green
    Write-Host "Importierte Device ID: $($response.id)" -ForegroundColor Green
    Write-Host "Status: $($response.state)" -ForegroundColor Green
    Write-Host "Device Serial: $($response.serialNumber)" -ForegroundColor Green
    
}
catch {
    Write-Host "Fehler beim Hochladen in Intune Autopilot:" -ForegroundColor Red
    Write-Host "Fehlermeldung: $($_.Exception.Message)" -ForegroundColor Red
    
    # Versuche alternative Methode
    if ($_.Exception.Response) {
        $errorResponse = $_.Exception.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($errorResponse)
        $reader.BaseStream.Position = 0
        $reader.DiscardBufferedData()
        $responseBody = $reader.ReadToEnd()
        Write-Host "Response Body: $responseBody" -ForegroundColor Red
    }
    
    # Alternative: Verwende New-MgDeviceManagementImportedWindowsAutopilotDeviceIdentity
    Write-Host "`nVersuche alternative Methode..." -ForegroundColor Yellow
    
    try {
        $params = @{
            serialNumber = $apinfo.serialNumber
            hardwareIdentifier = [System.Convert]::FromBase64String($cleanHash)
            manufacturer = $apinfo.manufacturer
            model = $apinfo.model
        }
        
        $result = New-MgDeviceManagementImportedWindowsAutopilotDeviceIdentity @params
        Write-Host "Alternative Methode erfolgreich!" -ForegroundColor Green
        Write-Host "Device ID: $($result.Id)" -ForegroundColor Green
    }
    catch {
        Write-Host "Auch alternative Methode fehlgeschlagen: $($_.Exception.Message)" -ForegroundColor Red
        exit 4
    }
}

# ===============================================
# AUFRÄUMEN
# ===============================================
try {
    if (Test-Path $TempCsv) {
        Remove-Item $TempCsv -Force
    }
}
catch {
    # Ignoriere Fehler beim Löschen
}

Write-Host "`nFertig" -ForegroundColor Green