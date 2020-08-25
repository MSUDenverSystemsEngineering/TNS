<#
.SYNOPSIS
	This script performs the installation or uninstallation of an application(s).
	# LICENSE #
	PowerShell App Deployment Toolkit - Provides a set of functions to perform common application deployment tasks on Windows.
	Copyright (C) 2017 - Sean Lillis, Dan Cunningham, Muhammad Mashwani, Aman Motazedian.
	This program is free software: you can redistribute it and/or modify it under the terms of the GNU Lesser General Public License as published by the Free Software Foundation, either version 3 of the License, or any later version. This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
	You should have received a copy of the GNU Lesser General Public License along with this program. If not, see <http://www.gnu.org/licenses/>.
.DESCRIPTION
	The script is provided as a template to perform an install or uninstall of an application(s).
	The script either performs an "Install" deployment type or an "Uninstall" deployment type.
	The install deployment type is broken down into 3 main sections/phases: Pre-Install, Install, and Post-Install.
	The script dot-sources the AppDeployToolkitMain.ps1 script which contains the logic and functions required to install or uninstall an application.
.PARAMETER DeploymentType
	The type of deployment to perform. Default is: Install.
.PARAMETER DeployMode
	Specifies whether the installation should be run in Interactive, Silent, or NonInteractive mode. Default is: Interactive. Options: Interactive = Shows dialogs, Silent = No dialogs, NonInteractive = Very silent, i.e. no blocking apps. NonInteractive mode is automatically set if it is detected that the process is not user interactive.
.PARAMETER AllowRebootPassThru
	Allows the 3010 return code (requires restart) to be passed back to the parent process (e.g. SCCM) if detected from an installation. If 3010 is passed back to SCCM, a reboot prompt will be triggered.
.PARAMETER TerminalServerMode
	Changes to "user install mode" and back to "user execute mode" for installing/uninstalling applications for Remote Destkop Session Hosts/Citrix servers.
.PARAMETER DisableLogging
	Disables logging to file for the script. Default is: $false.
.EXAMPLE
    powershell.exe -Command "& { & '.\Deploy-Application.ps1' -DeployMode 'Silent'; Exit $LastExitCode }"
.EXAMPLE
    powershell.exe -Command "& { & '.\Deploy-Application.ps1' -AllowRebootPassThru; Exit $LastExitCode }"
.EXAMPLE
    powershell.exe -Command "& { & '.\Deploy-Application.ps1' -DeploymentType 'Uninstall'; Exit $LastExitCode }"
.EXAMPLE
    Deploy-Application.exe -DeploymentType "Install" -DeployMode "Silent"
.NOTES
	Toolkit Exit Code Ranges:
	60000 - 68999: Reserved for built-in exit codes in Deploy-Application.ps1, Deploy-Application.exe, and AppDeployToolkitMain.ps1
	69000 - 69999: Recommended for user customized exit codes in Deploy-Application.ps1
	70000 - 79999: Recommended for user customized exit codes in AppDeployToolkitExtensions.ps1
.LINK
	http://psappdeploytoolkit.com
#>
[CmdletBinding()]

## Suppress PSScriptAnalyzer errors for not using declared variables during AppVeyor build
[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "", Justification="Suppress AppVeyor errors on unused variables below")]

Param (
	[Parameter(Mandatory=$false)]
	[ValidateSet('Install','Uninstall','Repair')]
	[string]$DeploymentType = 'Install',
	[Parameter(Mandatory=$false)]
	[ValidateSet('Interactive','Silent','NonInteractive')]
	[string]$DeployMode = 'Interactive',
	[Parameter(Mandatory=$false)]
	[switch]$AllowRebootPassThru = $false,
	[Parameter(Mandatory=$false)]
	[switch]$TerminalServerMode = $false,
	[Parameter(Mandatory=$false)]
	[switch]$DisableLogging = $false
)

Try {
	## Set the script execution policy for this process
	Try { Set-ExecutionPolicy -ExecutionPolicy 'ByPass' -Scope 'Process' -Force -ErrorAction 'Stop' } Catch { Write-Error "Failed to set the execution policy to Bypass for this process." }

	##*===============================================
	##* VARIABLE DECLARATION
	##*===============================================
	## Variables: Application
	[string]$appVendor = 'TNS name fix'
	[string]$appName = ''
	[string]$appVersion = ''
	[string]$appArch = 'n/a'
	[string]$appLang = 'EN'
	[string]$appRevision = '01'
	[string]$appScriptVersion = '1.0.0'
	[string]$appScriptDate = '28/03/2020'
	[string]$appScriptAuthor = '<David Torres>'
	##*===============================================
	## Variables: Install Titles (Only set here to override defaults set by the toolkit)
	[string]$installName = ''
	[string]$installTitle = ''

	##* Do not modify section below
	#region DoNotModify

	## Variables: Exit Code
	[int32]$mainExitCode = 0

	## Variables: Script
	[string]$deployAppScriptFriendlyName = 'Deploy Application'
	[version]$deployAppScriptVersion = [version]'3.8.1'
	[string]$deployAppScriptDate = '28/03/2020'
	[hashtable]$deployAppScriptParameters = $psBoundParameters

	## Variables: Environment
	If (Test-Path -LiteralPath 'variable:HostInvocation') { $InvocationInfo = $HostInvocation } Else { $InvocationInfo = $MyInvocation }
	[string]$scriptDirectory = Split-Path -Path $InvocationInfo.MyCommand.Definition -Parent

	## Dot source the required App Deploy Toolkit Functions
	Try {
		[string]$moduleAppDeployToolkitMain = "$scriptDirectory\AppDeployToolkit\AppDeployToolkitMain.ps1"
		If (-not (Test-Path -LiteralPath $moduleAppDeployToolkitMain -PathType 'Leaf')) { Throw "Module does not exist at the specified location [$moduleAppDeployToolkitMain]." }
		If ($DisableLogging) { . $moduleAppDeployToolkitMain -DisableLogging } Else { . $moduleAppDeployToolkitMain }
	}
	Catch {
		If ($mainExitCode -eq 0){ [int32]$mainExitCode = 60008 }
		Write-Error -Message "Module [$moduleAppDeployToolkitMain] failed to load: `n$($_.Exception.Message)`n `n$($_.InvocationInfo.PositionMessage)" -ErrorAction 'Continue'
		## Exit the script, returning the exit code to SCCM
		If (Test-Path -LiteralPath 'variable:HostInvocation') { $script:ExitCode = $mainExitCode; Exit } Else { Exit $mainExitCode }
	}

	#endregion
	##* Do not modify section above
	##*===============================================
	##* END VARIABLE DECLARATION
	##*===============================================

	If ($deploymentType -ine 'Uninstall' -and $deploymentType -ine 'Repair') {
		##*===============================================
		##* PRE-INSTALLATION
		##*===============================================
		[string]$installPhase = 'Pre-Installation'

		## Show Welcome Message, close Internet Explorer if needed, verify there is enough disk space to complete the install, and persist the prompt
		Show-InstallationWelcome -CloseApps 'iexplore' -CheckDiskSpace -PersistPrompt

		## Show Progress Message (with the default message)
		Show-InstallationProgress

		## <Perform Pre-Installation tasks here>


		##*===============================================
		##* INSTALLATION
		##*===============================================
		[string]$installPhase = 'Installation'

		## Handle Zero-Config MSI Installations
		If ($useDefaultMsi) {
			[hashtable]$ExecuteDefaultMSISplat =  @{ Action = 'Install'; Path = $defaultMsiFile }; If ($defaultMstFile) { $ExecuteDefaultMSISplat.Add('Transform', $defaultMstFile) }
			Execute-MSI @ExecuteDefaultMSISplat; If ($defaultMspFiles) { $defaultMspFiles | ForEach-Object { Execute-MSI -Action 'Patch' -Path $_ } }
		}

		## <Perform Installation tasks here>
        Remove-Item -Path "C:\ORACLE11G\product\11.2.0\client_1\Network\Admin\tnsnames.ora"
        Copy-Item -Path "$dirSupportFiles\Admin\tnsnames.ora" -Destination "$envSystemDrive\ORACLE11G\product\11.2.0\client_1\Network\Admin" -Recurse
       

		##*===============================================
		##* POST-INSTALLATION
		##*===============================================
		[string]$installPhase = 'Post-Installation'

		## <Perform Post-Installation tasks here>

		## Display a message at the end of the install
		If (-not $useDefaultMsi) {

		}
	}
	ElseIf ($deploymentType -ieq 'Uninstall')
	{
		##*===============================================
		##* PRE-UNINSTALLATION
		##*===============================================
		[string]$installPhase = 'Pre-Uninstallation'

		## Show Welcome Message, close Internet Explorer with a 60 second countdown before automatically closing
		Show-InstallationWelcome -CloseApps 'iexplore' -CloseAppsCountdown 60

		## Show Progress Message (with the default message)
		Show-InstallationProgress

		## <Perform Pre-Uninstallation tasks here>


		##*===============================================
		##* UNINSTALLATION
		##*===============================================
		[string]$installPhase = 'Uninstallation'

		## Handle Zero-Config MSI Uninstallations
		If ($useDefaultMsi) {
			[hashtable]$ExecuteDefaultMSISplat =  @{ Action = 'Uninstall'; Path = $defaultMsiFile }; If ($defaultMstFile) { $ExecuteDefaultMSISplat.Add('Transform', $defaultMstFile) }
			Execute-MSI @ExecuteDefaultMSISplat
		}

		# <Perform Uninstallation tasks here>


		##*===============================================
		##* POST-UNINSTALLATION
		##*===============================================
		[string]$installPhase = 'Post-Uninstallation'

		## <Perform Post-Uninstallation tasks here>


	}
	ElseIf ($deploymentType -ieq 'Repair')
	{
		##*===============================================
		##* PRE-REPAIR
		##*===============================================
		[string]$installPhase = 'Pre-Repair'

		## Show Progress Message (with the default message)
		Show-InstallationProgress

		## <Perform Pre-Repair tasks here>

		##*===============================================
		##* REPAIR
		##*===============================================
		[string]$installPhase = 'Repair'

		## Handle Zero-Config MSI Repairs
		If ($useDefaultMsi) {
			[hashtable]$ExecuteDefaultMSISplat =  @{ Action = 'Repair'; Path = $defaultMsiFile; }; If ($defaultMstFile) { $ExecuteDefaultMSISplat.Add('Transform', $defaultMstFile) }
			Execute-MSI @ExecuteDefaultMSISplat
		}
		# <Perform Repair tasks here>

		##*===============================================
		##* POST-REPAIR
		##*===============================================
		[string]$installPhase = 'Post-Repair'

		## <Perform Post-Repair tasks here>


    }
	##*===============================================
	##* END SCRIPT BODY
	##*===============================================

	## Call the Exit-Script function to perform final cleanup operations
	Exit-Script -ExitCode $mainExitCode
}
Catch {
	[int32]$mainExitCode = 60001
	[string]$mainErrorMessage = "$(Resolve-Error)"
	Write-Log -Message $mainErrorMessage -Severity 3 -Source $deployAppScriptFriendlyName
	Show-DialogBox -Text $mainErrorMessage -Icon 'Stop'
	Exit-Script -ExitCode $mainExitCode
}
# SIG # Begin signature block
# MIIf1wYJKoZIhvcNAQcCoIIfyDCCH8QCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCOYseAlzV8a+At
# fUbBUer+rl/ThF0/AcjhC80Xq5/FraCCGZswggWuMIIElqADAgECAhAHA3HRD3la
# QHGZK5QHYpviMA0GCSqGSIb3DQEBCwUAMHwxCzAJBgNVBAYTAlVTMQswCQYDVQQI
# EwJNSTESMBAGA1UEBxMJQW5uIEFyYm9yMRIwEAYDVQQKEwlJbnRlcm5ldDIxETAP
# BgNVBAsTCEluQ29tbW9uMSUwIwYDVQQDExxJbkNvbW1vbiBSU0EgQ29kZSBTaWdu
# aW5nIENBMB4XDTE4MDYyMTAwMDAwMFoXDTIxMDYyMDIzNTk1OVowgbkxCzAJBgNV
# BAYTAlVTMQ4wDAYDVQQRDAU4MDIwNDELMAkGA1UECAwCQ08xDzANBgNVBAcMBkRl
# bnZlcjEYMBYGA1UECQwPMTIwMSA1dGggU3RyZWV0MTAwLgYDVQQKDCdNZXRyb3Bv
# bGl0YW4gU3RhdGUgVW5pdmVyc2l0eSBvZiBEZW52ZXIxMDAuBgNVBAMMJ01ldHJv
# cG9saXRhbiBTdGF0ZSBVbml2ZXJzaXR5IG9mIERlbnZlcjCCASIwDQYJKoZIhvcN
# AQEBBQADggEPADCCAQoCggEBAMtXiSjEDjYNBIYXsPnFGHwZqvS5lgRNSaQjsyxg
# LsGI6yLLDCpaYy3CBwN1on4QnYzEQpsHV+TJ/3K61ZvqAxhR6Anw8TjVjaB3kPdt
# KJjEUlgiXNK0nDRyMVasZyeXALR5STSf1SxoMt8HIDd0KTB8yhME6ezFdFzwB5He
# 2/jyOswfYsN+n4k2Q9UcaVtWgCzWua39anwNva7M4GugPO5ZkF6XkrGzRHpXctV/
# Fk6LmqPY6sRm45nScnC1KQ3NN/t6ZBHzmAtgbZa41o5+AvNdkv9TVF6S3ODGpf3q
# KW8kjFt82LLYdZi0V07ln+S/BtAlGUPOvqem4EkbMtZ5M3MCAwEAAaOCAewwggHo
# MB8GA1UdIwQYMBaAFK41Ixf//wY9nFDgjCRlMx5wEIiiMB0GA1UdDgQWBBSl6Yhu
# vPlIpfXzOIq+Y/mkDGObDzAOBgNVHQ8BAf8EBAMCB4AwDAYDVR0TAQH/BAIwADAT
# BgNVHSUEDDAKBggrBgEFBQcDAzARBglghkgBhvhCAQEEBAMCBBAwZgYDVR0gBF8w
# XTBbBgwrBgEEAa4jAQQDAgEwSzBJBggrBgEFBQcCARY9aHR0cHM6Ly93d3cuaW5j
# b21tb24ub3JnL2NlcnQvcmVwb3NpdG9yeS9jcHNfY29kZV9zaWduaW5nLnBkZjBJ
# BgNVHR8EQjBAMD6gPKA6hjhodHRwOi8vY3JsLmluY29tbW9uLXJzYS5vcmcvSW5D
# b21tb25SU0FDb2RlU2lnbmluZ0NBLmNybDB+BggrBgEFBQcBAQRyMHAwRAYIKwYB
# BQUHMAKGOGh0dHA6Ly9jcnQuaW5jb21tb24tcnNhLm9yZy9JbkNvbW1vblJTQUNv
# ZGVTaWduaW5nQ0EuY3J0MCgGCCsGAQUFBzABhhxodHRwOi8vb2NzcC5pbmNvbW1v
# bi1yc2Eub3JnMC0GA1UdEQQmMCSBIml0c3N5c3RlbWVuZ2luZWVyaW5nQG1zdWRl
# bnZlci5lZHUwDQYJKoZIhvcNAQELBQADggEBAIc2PVq7BamWAujyCQPHsGCDbM3i
# 1OY5nruA/fOtbJ6mJvT9UJY4+61grcHLzV7op1y0nRhV459TrKfHKO42uRyZpdnH
# aOoC080cfg/0EwFJRy3bYB0vkVP8TeUkvUhbtcPVofI1P/wh9ZT2iYVCerOOAqiv
# xWqh8Dt+8oSbjSGhPFWyu04b8UczbK/97uXdgK0zNcXDJUjMKr6CbevfLQLfQiFP
# izaej+2fvR/jZHAvxO9W2rhd6Nw6gFs2q3P4CFK0+yAkFCLk+9wsp+RsRvRkvdWJ
# p+anNvAKOyVfCj6sz5dQPAIYIyLhy9ze3taVKm99DQQZV/wN/ATPDftLGm0wggXr
# MIID06ADAgECAhBl4eLj1d5QRYXzJiSABeLUMA0GCSqGSIb3DQEBDQUAMIGIMQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKTmV3IEplcnNleTEUMBIGA1UEBxMLSmVyc2V5
# IENpdHkxHjAcBgNVBAoTFVRoZSBVU0VSVFJVU1QgTmV0d29yazEuMCwGA1UEAxMl
# VVNFUlRydXN0IFJTQSBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTAeFw0xNDA5MTkw
# MDAwMDBaFw0yNDA5MTgyMzU5NTlaMHwxCzAJBgNVBAYTAlVTMQswCQYDVQQIEwJN
# STESMBAGA1UEBxMJQW5uIEFyYm9yMRIwEAYDVQQKEwlJbnRlcm5ldDIxETAPBgNV
# BAsTCEluQ29tbW9uMSUwIwYDVQQDExxJbkNvbW1vbiBSU0EgQ29kZSBTaWduaW5n
# IENBMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAwKAvix56u2p1rPg+
# 3KO6OSLK86N25L99MCfmutOYMlYjXAaGlw2A6O2igTXrC/Zefqk+aHP9ndRnec6q
# 6mi3GdscdjpZh11emcehsriphHMMzKuHRhxqx+85Jb6n3dosNXA2HSIuIDvd4xwO
# PzSf5X3+VYBbBnyCV4RV8zj78gw2qblessWBRyN9EoGgwAEoPgP5OJejrQLyAmj9
# 1QGr9dVRTVDTFyJG5XMY4DrkN3dRyJ59UopPgNwmucBMyvxR+hAJEXpXKnPE4CEq
# bMJUvRw+g/hbqSzx+tt4z9mJmm2j/w2nP35MViPWCb7hpR2LB8W/499Yqu+kr4LL
# BfgKCQIDAQABo4IBWjCCAVYwHwYDVR0jBBgwFoAUU3m/WqorSs9UgOHYm8Cd8rID
# ZsswHQYDVR0OBBYEFK41Ixf//wY9nFDgjCRlMx5wEIiiMA4GA1UdDwEB/wQEAwIB
# hjASBgNVHRMBAf8ECDAGAQH/AgEAMBMGA1UdJQQMMAoGCCsGAQUFBwMDMBEGA1Ud
# IAQKMAgwBgYEVR0gADBQBgNVHR8ESTBHMEWgQ6BBhj9odHRwOi8vY3JsLnVzZXJ0
# cnVzdC5jb20vVVNFUlRydXN0UlNBQ2VydGlmaWNhdGlvbkF1dGhvcml0eS5jcmww
# dgYIKwYBBQUHAQEEajBoMD8GCCsGAQUFBzAChjNodHRwOi8vY3J0LnVzZXJ0cnVz
# dC5jb20vVVNFUlRydXN0UlNBQWRkVHJ1c3RDQS5jcnQwJQYIKwYBBQUHMAGGGWh0
# dHA6Ly9vY3NwLnVzZXJ0cnVzdC5jb20wDQYJKoZIhvcNAQENBQADggIBAEYstn9q
# TiVmvZxqpqrQnr0Prk41/PA4J8HHnQTJgjTbhuET98GWjTBEE9I17Xn3V1yTphJX
# bat5l8EmZN/JXMvDNqJtkyOh26owAmvquMCF1pKiQWyuDDllxR9MECp6xF4wnH1M
# cs4WeLOrQPy+C5kWE5gg/7K6c9G1VNwLkl/po9ORPljxKKeFhPg9+Ti3JzHIxW7L
# dyljffccWiuNFR51/BJHAZIqUDw3LsrdYWzgg4x06tgMvOEf0nITelpFTxqVvMtJ
# hnOfZbpdXZQ5o1TspxfTEVOQAsp05HUNCXyhznlVLr0JaNkM7edgk59zmdTbSGdM
# q8Ztuu6VyrivOlMSPWmay5MjvwTzuNorbwBv0DL+7cyZBp7NYZou+DoGd1lFZN0j
# U5IsQKgm3+00pnnJ67crdFwfz/8bq3MhTiKOWEb04FT3OZVp+jzvaChHWLQ8gbCO
# RgClaZq1H3aqI7JeRkWEEEp6Tv4WAVsr/i7LoXU72gOb8CAzPFqwI4Excdrxp0I4
# OXbECHlDqU4sTInqwlMwofmxeO4u94196qIqJQl+8Sykl06VktqMux84Iw3ZQLH0
# 8J8LaJ+WDUycc4OjY61I7FGxCDkbSQf3npXeRFm0IBn8GiW+TRDk6J2XJFLWEtVZ
# mhboFlBLoUlqHUCKu0QOhU/+AEOqnY98j2zRMIIG7DCCBNSgAwIBAgIQMA9vrN1m
# mHR8qUY2p3gtuTANBgkqhkiG9w0BAQwFADCBiDELMAkGA1UEBhMCVVMxEzARBgNV
# BAgTCk5ldyBKZXJzZXkxFDASBgNVBAcTC0plcnNleSBDaXR5MR4wHAYDVQQKExVU
# aGUgVVNFUlRSVVNUIE5ldHdvcmsxLjAsBgNVBAMTJVVTRVJUcnVzdCBSU0EgQ2Vy
# dGlmaWNhdGlvbiBBdXRob3JpdHkwHhcNMTkwNTAyMDAwMDAwWhcNMzgwMTE4MjM1
# OTU5WjB9MQswCQYDVQQGEwJHQjEbMBkGA1UECBMSR3JlYXRlciBNYW5jaGVzdGVy
# MRAwDgYDVQQHEwdTYWxmb3JkMRgwFgYDVQQKEw9TZWN0aWdvIExpbWl0ZWQxJTAj
# BgNVBAMTHFNlY3RpZ28gUlNBIFRpbWUgU3RhbXBpbmcgQ0EwggIiMA0GCSqGSIb3
# DQEBAQUAA4ICDwAwggIKAoICAQDIGwGv2Sx+iJl9AZg/IJC9nIAhVJO5z6A+U++z
# WsB21hoEpc5Hg7XrxMxJNMvzRWW5+adkFiYJ+9UyUnkuyWPCE5u2hj8BBZJmbyGr
# 1XEQeYf0RirNxFrJ29ddSU1yVg/cyeNTmDoqHvzOWEnTv/M5u7mkI0Ks0BXDf56i
# XNc48RaycNOjxN+zxXKsLgp3/A2UUrf8H5VzJD0BKLwPDU+zkQGObp0ndVXRFzs0
# IXuXAZSvf4DP0REKV4TJf1bgvUacgr6Unb+0ILBgfrhN9Q0/29DqhYyKVnHRLZRM
# yIw80xSinL0m/9NTIMdgaZtYClT0Bef9Maz5yIUXx7gpGaQpL0bj3duRX58/Nj4O
# MGcrRrc1r5a+2kxgzKi7nw0U1BjEMJh0giHPYla1IXMSHv2qyghYh3ekFesZVf/Q
# OVQtJu5FGjpvzdeE8NfwKMVPZIMC1Pvi3vG8Aij0bdonigbSlofe6GsO8Ft96XZp
# kyAcSpcsdxkrk5WYnJee647BeFbGRCXfBhKaBi2fA179g6JTZ8qx+o2hZMmIklnL
# qEbAyfKm/31X2xJ2+opBJNQb/HKlFKLUrUMcpEmLQTkUAx4p+hulIq6lw02C0I3a
# a7fb9xhAV3PwcaP7Sn1FNsH3jYL6uckNU4B9+rY5WDLvbxhQiddPnTO9GrWdod6V
# QXqngwIDAQABo4IBWjCCAVYwHwYDVR0jBBgwFoAUU3m/WqorSs9UgOHYm8Cd8rID
# ZsswHQYDVR0OBBYEFBqh+GEZIA/DQXdFKI7RNV8GEgRVMA4GA1UdDwEB/wQEAwIB
# hjASBgNVHRMBAf8ECDAGAQH/AgEAMBMGA1UdJQQMMAoGCCsGAQUFBwMIMBEGA1Ud
# IAQKMAgwBgYEVR0gADBQBgNVHR8ESTBHMEWgQ6BBhj9odHRwOi8vY3JsLnVzZXJ0
# cnVzdC5jb20vVVNFUlRydXN0UlNBQ2VydGlmaWNhdGlvbkF1dGhvcml0eS5jcmww
# dgYIKwYBBQUHAQEEajBoMD8GCCsGAQUFBzAChjNodHRwOi8vY3J0LnVzZXJ0cnVz
# dC5jb20vVVNFUlRydXN0UlNBQWRkVHJ1c3RDQS5jcnQwJQYIKwYBBQUHMAGGGWh0
# dHA6Ly9vY3NwLnVzZXJ0cnVzdC5jb20wDQYJKoZIhvcNAQEMBQADggIBAG1UgaUz
# XRbhtVOBkXXfA3oyCy0lhBGysNsqfSoF9bw7J/RaoLlJWZApbGHLtVDb4n35nwDv
# QMOt0+LkVvlYQc/xQuUQff+wdB+PxlwJ+TNe6qAcJlhc87QRD9XVw+K81Vh4v0h2
# 4URnbY+wQxAPjeT5OGK/EwHFhaNMxcyyUzCVpNb0llYIuM1cfwGWvnJSajtCN3wW
# eDmTk5SbsdyybUFtZ83Jb5A9f0VywRsj1sJVhGbks8VmBvbz1kteraMrQoohkv6o
# b1olcGKBc2NeoLvY3NdK0z2vgwY4Eh0khy3k/ALWPncEvAQ2ted3y5wujSMYuaPC
# Rx3wXdahc1cFaJqnyTdlHb7qvNhCg0MFpYumCf/RoZSmTqo9CfUFbLfSZFrYKiLC
# S53xOV5M3kg9mzSWmglfjv33sVKRzj+J9hyhtal1H3G/W0NdZT1QgW6r8NDT/LKz
# H7aZlib0PHmLXGTMze4nmuWgwAxyh8FuTVrTHurwROYybxzrF06Uw3hlIDsPQaof
# 6aFBnf6xuKBlKjTg3qj5PObBMLvAoGMs/FwWAKjQxH/qEZ0eBsambTJdtDgJK0kH
# qv3sMNrxpy/Pt/360KOE2See+wFmd7lWEOEgbsausfm2usg1XTN2jvF8IAwqd661
# ogKGuinutFoAsYyr4/kKyVRd1LlqdJ69SK6YMIIHBjCCBO6gAwIBAgIQPRo1cjAV
# gmMw0BNxfoJBCDANBgkqhkiG9w0BAQwFADB9MQswCQYDVQQGEwJHQjEbMBkGA1UE
# CBMSR3JlYXRlciBNYW5jaGVzdGVyMRAwDgYDVQQHEwdTYWxmb3JkMRgwFgYDVQQK
# Ew9TZWN0aWdvIExpbWl0ZWQxJTAjBgNVBAMTHFNlY3RpZ28gUlNBIFRpbWUgU3Rh
# bXBpbmcgQ0EwHhcNMTkwNTAyMDAwMDAwWhcNMzAwODAxMjM1OTU5WjCBhDELMAkG
# A1UEBhMCR0IxGzAZBgNVBAgMEkdyZWF0ZXIgTWFuY2hlc3RlcjEQMA4GA1UEBwwH
# U2FsZm9yZDEYMBYGA1UECgwPU2VjdGlnbyBMaW1pdGVkMSwwKgYDVQQDDCNTZWN0
# aWdvIFJTQSBUaW1lIFN0YW1waW5nIFNpZ25lciAjMTCCAiIwDQYJKoZIhvcNAQEB
# BQADggIPADCCAgoCggIBAMtRUP9W/vx4Y3ABk1qeGPQ7U/YHryFs9aIPfR1wLYR0
# SIucipUFPVmE+ZGAeVEs2Yq3wQuaugqKzWZPA4sBuzDKq73bwE8SXvwKzOJFsAE4
# irtN59QcVJjtOVjPW8IvRZgxCvk1OLgxLm20Hjly4bgqvp+MjBqlRq4LK0yZ/ixL
# /Ci5IjpmF9CqVoohwPOWJLTQhSZruvBvZJh5pq29XNhTaysK1nKKhUbjDRgG2sZ7
# QVY2mxU+8WoRoPdm9RjQgFVjh2hm6w55VYJco+1JuHGGnpM3sGuj6mJso66W6Ln9
# i6vG9llbADxXIBgtcAOnnO+S63mhx13sfLSPS9/rXfyjIN2SOOVqUTprhZxMoJgI
# aVsG5yoZ0JWTiztrigUJKdjW2tvjcvpcSi97FVaGMr9/BQmdLSrPUOHmYSDbxwaA
# XE4URr6uV3Giqmwwkxx+d8sG6VfNkfXVM3Ic4drKbuvzD+x5W7snnuge/i/yu3/p
# 5dBn67gNfKQrWQOLle0iKM36LDvHFhGv49axUGdpxY71edCt/4fM+H+q+aLtYfjI
# jWnasfRRketnV9FkEetkywO9SVU6RUMYLCVs0S8MLW/1QTUkoPJjWRZf2aTpLE7b
# uzESxm34W24D3MsVjxuNcuzbDxWQ1hJO7uIAMSWTNW9qW6USY0ABirlpiDqIuA8Z
# AgMBAAGjggF4MIIBdDAfBgNVHSMEGDAWgBQaofhhGSAPw0F3RSiO0TVfBhIEVTAd
# BgNVHQ4EFgQUb02GB9gyJ54sKdLQEwOAgd0FgykwDgYDVR0PAQH/BAQDAgbAMAwG
# A1UdEwEB/wQCMAAwFgYDVR0lAQH/BAwwCgYIKwYBBQUHAwgwQAYDVR0gBDkwNzA1
# BgwrBgEEAbIxAQIBAwgwJTAjBggrBgEFBQcCARYXaHR0cHM6Ly9zZWN0aWdvLmNv
# bS9DUFMwRAYDVR0fBD0wOzA5oDegNYYzaHR0cDovL2NybC5zZWN0aWdvLmNvbS9T
# ZWN0aWdvUlNBVGltZVN0YW1waW5nQ0EuY3JsMHQGCCsGAQUFBwEBBGgwZjA/Bggr
# BgEFBQcwAoYzaHR0cDovL2NydC5zZWN0aWdvLmNvbS9TZWN0aWdvUlNBVGltZVN0
# YW1waW5nQ0EuY3J0MCMGCCsGAQUFBzABhhdodHRwOi8vb2NzcC5zZWN0aWdvLmNv
# bTANBgkqhkiG9w0BAQwFAAOCAgEAwGjts9jUUJvv03XLDzv3JNN6N0WNLO8W+1Gp
# LB+1JbWKn10LwhsgdI1mDzbLqvY2DQ9+j0tKdENlrA0q9grta23FCTjtABv45dym
# CkAFR++Eygm8Q2aDv5/t24490UFksXACLQNXWxhvHCzLHrIA6LoJL1uBBDW5qWNt
# jgjFGNHhIaz5EgoUwBLbfiWdrB0QwFqlg9IfGmZV/Jsq4uw3V47l35Yw+MCTC0MY
# +QJvqVGvuFcK8xwHaTmPN5xt15GupS5J6Ures9CMvzmQDcCBzvAqBzoMpi1R0nLz
# U8b5ve/vDGlJd58sVsTpoQg9B67FHtaEIse8fUMbWDhiTtEFJYTFQvgfL/bb+quM
# VOxFimwSTTBaUuWkFwki5u9v9V+GQ9+hLb1KRpKggZYsYZd/QG/YP4w1WqvRxqA7
# hWZUgO8fGvXxm7ChJ32y5wvP9i2cWBOUqYb8RVKiKG1/dA9SkUl66RL4qTuwkv19
# kRTpW21IlPLIlu4FOLPF7DA/4QcgBLHYi7z9sz5v8gJTBvSg7cmacqOXXwD7y2PQ
# 6M10/XXJ1DZFunsSWXLt5/J6UAB4+EOaRtjfv1TUXrHH0bwbg/Qr5wvoR8hTnswa
# rPb6inVTbCCFqdW4arokjoorCJGfNwQc9m+i3TSqkf/GFS4eQhoJKU/0xs3ikaLT
# QAyOeOMxggWSMIIFjgIBATCBkDB8MQswCQYDVQQGEwJVUzELMAkGA1UECBMCTUkx
# EjAQBgNVBAcTCUFubiBBcmJvcjESMBAGA1UEChMJSW50ZXJuZXQyMREwDwYDVQQL
# EwhJbkNvbW1vbjElMCMGA1UEAxMcSW5Db21tb24gUlNBIENvZGUgU2lnbmluZyBD
# QQIQBwNx0Q95WkBxmSuUB2Kb4jANBglghkgBZQMEAgEFAKCBhDAYBgorBgEEAYI3
# AgEMMQowCKACgAChAoAAMBkGCSqGSIb3DQEJAzEMBgorBgEEAYI3AgEEMBwGCisG
# AQQBgjcCAQsxDjAMBgorBgEEAYI3AgEVMC8GCSqGSIb3DQEJBDEiBCCbRy/U8di7
# 0NlksMuC8Sz27NNoiKyJDSSrA2/O+Lg0HjANBgkqhkiG9w0BAQEFAASCAQCoUEfB
# x7MQPDLGfEY1dKezwAvhOMMzXg+eX6n2vTnuxOEABE9iXLz8UZ3WtyfNA+tytK/B
# a2B1D8f+RBGmxdSPdExR/vCu4neRv9fl6DL+wafzDF3Kfho4endOwdNUsZQHngHq
# +wyJd/ED6Ak2ZQxK9rU+nC07L+X4t/k8VsayJ8K/PlGuvjVivNTGKU+MmMdBwIqk
# jtcBn85YHWKtJbmXYWY3UyM8EMApW8y5MnDuPJEoccGzMLrNhdvEbsOmi8FUeiEQ
# /Bt8Mu8wcQ7Z3nh4MMNLMHoGvS2AcOkS0Y5eXWxvzFXxi7jbwV0q7ENY2SUH2d/4
# DwvudRMWSVkXs2hwoYIDSzCCA0cGCSqGSIb3DQEJBjGCAzgwggM0AgEBMIGRMH0x
# CzAJBgNVBAYTAkdCMRswGQYDVQQIExJHcmVhdGVyIE1hbmNoZXN0ZXIxEDAOBgNV
# BAcTB1NhbGZvcmQxGDAWBgNVBAoTD1NlY3RpZ28gTGltaXRlZDElMCMGA1UEAxMc
# U2VjdGlnbyBSU0EgVGltZSBTdGFtcGluZyBDQQIQPRo1cjAVgmMw0BNxfoJBCDAN
# BglghkgBZQMEAgIFAKB5MBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZI
# hvcNAQkFMQ8XDTIwMDgyNTAwMDYwMlowPwYJKoZIhvcNAQkEMTIEMCdtq6pi9NjN
# Ed9WQYpa0Hy8dyXeIK64ezadj1oTg70Bqu1ER3jJ7QCrwt3A5jxELzANBgkqhkiG
# 9w0BAQEFAASCAgCVI1+hCnsVkjtokr402gr0XXndEl2qBDH2jpmGOdcXxVzKTwqS
# gnaMZHCQPao3bFFv81qku/FZWYuRDvHzM7xxjXFp6gxdpq8v7H+ATBGjqdAFNAeM
# OwJnOSAboT8QhMMAS6+u1deDDbEm/j5D+lsbABd1hRIFiV5YaA3vbczW4GEGueJi
# m7gB5NJ1/z+MVjWk6+PxnV3NKBg1y5Mmy6e8KYEyEviOQoabsu0jbdwyKzkGsWM3
# r7Pk+44u4V+DnqtKlKRF3Jsr8y0qkqw6YsgEFI8wRgOG7hgt33FiHcgIOY2K03JP
# MmcIQ86yPNR66F+o+kF8NB6r2TYpFHHTYmycqBTp84tgC6Z7jcy9UYGdGkZvOU5U
# gKWLC1dpgunKECGKRBFEeYb1l3n1D2tcu1sWRDTWiPDm9sVGJ9YiueVnZ3ZGBBRc
# /Rk+3TFMf10ALDuaQSwyChS6BRJBX/LycmpdFxLL12ApNjWPHIngTI7rkTTD2u4s
# x2Qm6uhm3X3Be0lcdKpoQovfy8YdCCwrs4LSdjK80ue0jkee85HMrywJWNCtVavf
# kGqXj071zowecNqIeaXmj/kl2WP/QuxaAMHw3MiIzOnxOVZjd+QRJzYOcfmp8OE5
# mRHAV9JcAZGLd5bButQdUuejL0YWH+yfsfyQvyONRBVLydk5bI00N5cUQA==
# SIG # End signature block
