#Requires -Modules Az.Accounts, Az.Resources
[cmdletbinding()]
param(
    [Parameter(Mandatory = $true, Position = 0, HelpMessage = "Path to the configuration file.")]
    [ValidateNotNull()]
    [string] $ConfigurationFilePath,
    [Parameter(Position = 1, HelpMessage = "The subscription id where the resources will be deployed.")]
    [string] $SubscriptionId
)

$InformationPreference = "Continue"
$ErrorActionPreference = "Stop"

function Install-Bicep {
    # Look into the windows $PATH environment variable to see if bicep is installed.
    # if it is not installed, download it from the GitHub release page, https://github.com/Azure/bicep/releases/latest/download/bicep-win-x64.exe and add it to the PATH
    if (-not (Get-Command bicep -ErrorAction SilentlyContinue)) {
        Write-Output "Bicep is not installed. Downloading and installing it..."
        if (!(Test-Path -Path "$env:TEMP/tools")) {
            New-Item -Path "$env:TEMP/tools" -ItemType Directory -Force | Out-Null
        }
        $bicepPath = Join-Path -Path $env:TEMP -ChildPath "tools/bicep.exe"
        Invoke-WebRequest -Uri "https://github.com/Azure/bicep/releases/latest/download/bicep-win-x64.exe" -OutFile $bicepPath
        $env:Path = $env:Path + ";" + ([System.IO.Path]::GetDirectoryName($bicepPath))
    }
}

$configFile = Get-Content -Path $ConfigurationFilePath -Raw | ConvertFrom-Json
$configSubscriptionId = $configFile.subscriptionId

$azContext = Get-AzContext
if ($null -eq $azContext) {
    Connect-AzAccount
}

$azContext = Get-AzContext
if (![string]::IsNullOrWhiteSpace($SubscriptionId)) {
    if (![string]::IsNullOrWhiteSpace($configSubscriptionId) -and $configSubscriptionId -ne $SubscriptionId) {
        $res = Read-Host "SubscriptionId parameter was supplied and is different than from the configuration file. The supplied value from the configuration file will be ignored. Do you want to continue? [y/n, default y]"

        if ([string]::Equals($res, "n", [StringComparison]::OrdinalIgnoreCase)) {
            exit 0
        }

        if ($SubscriptionId -ne $azContext.Subscription.Id) {
            $azContext = Set-AzContext -SubscriptionId $SubscriptionId
        }
    }
    else {
        if ($azContext.Subscription.Id -ne $SubscriptionId) {
            Write-Warning "SubscriptionId was supplied and is different than the context. Setting context subscription to $SubscriptionId"
            $azContext = Set-AzContext -SubscriptionId $SubscriptionId
        }
    }
}

Install-Bicep

$devCenterId = $configFile.devCenterId
$devCenterLocation = Get-AzResource -ResourceId $devCenterId | Select-Object -ExpandProperty Location

Write-Information "Deploying the Dev Center resources to subscription $($azContext.Subscription.Id) using configuration file $ConfigurationFilePath"

$deployment = New-AzDeployment `
                -Location $devCenterLocation `
                -Name "DevCenterDeployment-$((New-Guid).Guid)" `
                -TemplateFile $([System.IO.Path]::Join($PWD,"bicep/main.bicep")) `
                -TemplateParameterFile $ConfigurationFilePath `
                -ErrorVariable deploymentError `
                -ErrorAction SilentlyContinue

if ($deploymentError) {
    Write-Error "Deployment failed with error: $deploymentError"
    exit 1
}

$outputPath = [System.IO.Path]::Join($PWD,"$([System.IO.Path]::GetFileNameWithoutExtension($ConfigurationFilePath)).output.json")
$deployment.Outputs| ConvertTo-Json | Set-Content -Path $outputPath -Force
Write-Information "Deployment completed successfully. Output file: $outputPath"