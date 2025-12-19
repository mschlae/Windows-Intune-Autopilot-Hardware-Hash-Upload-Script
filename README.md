# Windows Autopilot Hardware Hash Upload Script

This PowerShell script automates the collection and upload of Windows device information (hardware hashes) to Microsoft Intune for Autopilot enrollment. It is specifically designed for IT administrators and MDM managers who want to efficiently integrate devices into Autopilot.  

This enables quick enrollment without additional effort such as logging in or manually uploading CSV files.

## Features
- Automatically installs required PowerShell modules (`Microsoft.Graph.Authentication`, `Microsoft.Graph.DeviceManagement.Enrollment`) and the `Get-WindowsAutopilotInfo` script.
- Collects device information including Serial Number, Manufacturer, Model, and Hardware Hash.
- Uploads hardware information directly to Intune via Microsoft Graph API.
- Optional fallback using the `Microsoft.Graph.DeviceManagement` PowerShell module if the direct REST API call fails.
- Temporary adjustment of PowerShell Execution Policy to ensure smooth execution.
- Cleans up temporary CSV files after successful upload.

## Prerequisites
- PowerShell 7 or higher recommended (PowerShell 5.1 also supported).
- Administrator privileges on the device being enrolled.
- Azure AD App Registration with the required Microsoft Graph permissions:
  - `DeviceManagementServiceConfig.ReadWrite.All` **or**
  - `DeviceManagementManagedDevices.ReadWrite.All`

## Usage
1. Download or clone the repository.
2. Fill in the following variables in the script:
   ```powershell
   $ClientId = "<Your Azure AD App Client ID>"
   $ClientSecret = "<Your Azure AD App Client Secret>"
   $TenantId = "<Your Azure AD Tenant ID>"
3. Put the Script on a USB-Stick and Run it on your devices.
