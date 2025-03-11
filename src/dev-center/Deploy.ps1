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

$windows365PrincipalId = (Get-AzADServicePrincipal -ApplicationId "0af06dc6-e4b5-4f28-818e-e78e62d137a5").Id
$configLocation = $configFile.location

Write-Information "Deploying the Dev Center resources to subscription $($azContext.Subscription.Id) using configuration file $ConfigurationFilePath"

$deployment = New-AzDeployment `
                -Location $configLocation `
                -Name "DevCenterDeployment-$((New-Guid).Guid)" `
                -TemplateFile $([System.IO.Path]::Join($PWD,"bicep/main.bicep")) `
                -TemplateParameterFile $ConfigurationFilePath `
                -windows365PrincipalId $windows365PrincipalId `
                -ErrorVariable deploymentError `
                -ErrorAction SilentlyContinue

if ($deploymentError) {
    Write-Error "Deployment failed with error: $deploymentError"
    exit 1
}

$outputPath = [System.IO.Path]::Join($PWD,"$([System.IO.Path]::GetFileNameWithoutExtension($ConfigurationFilePath)).output.json")
$deployment.Outputs| ConvertTo-Json | Set-Content -Path $outputPath -Force
Write-Information "Deployment completed successfully. Output file: $outputPath"