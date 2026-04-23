param(
  [string]$SubscriptionId = $env:AZURE_SUBSCRIPTION_ID,
  [string]$ResourceGroup  = "rg-vwan-azfw-custompip-lab",
  [string]$FirewallName   = "azfw-hub-swc",
  [string]$VirtualHubName = "hub-swc",
  [string[]]$PublicIpNames = @("pip-fw-prefix-1","pip-fw-prefix-2","pip-fw-standalone")
)

$ErrorActionPreference = "Stop"
function Stamp { (Get-Date).ToString("o") }

Write-Host "[$(Stamp)] Connect-AzAccount -Identity"
Connect-AzAccount -Identity -Subscription $SubscriptionId | Out-Null

Write-Host "[$(Stamp)] Get-AzFirewall"
$azfw = Get-AzFirewall -ResourceGroupName $ResourceGroup -Name $FirewallName

Write-Host "[$(Stamp)] (FW already in IpConfig mode; skipping count=0 step — only applies when on hubIPAddresses)"

Write-Host "[$(Stamp)] DEALLOCATE_START"
$azfw.Deallocate()
Set-AzFirewall -AzureFirewall $azfw | Out-Null
Write-Host "[$(Stamp)] DEALLOCATE_DONE"

Write-Host "[$(Stamp)] Fetch PIPs + vhub"
$pips = foreach ($n in $PublicIpNames) { Get-AzPublicIpAddress -ResourceGroupName $ResourceGroup -Name $n }
$vhub = Get-AzVirtualHub -ResourceGroupName $ResourceGroup -Name $VirtualHubName

Write-Host "[$(Stamp)] ALLOCATE_START with $($pips.Count) PIPs: $($pips.IpAddress -join ', ')"
$azfw.Allocate($vhub.Id, $pips)
Set-AzFirewall -AzureFirewall $azfw | Out-Null
Write-Host "[$(Stamp)] ALLOCATE_DONE"

$final = Get-AzFirewall -ResourceGroupName $ResourceGroup -Name $FirewallName
Write-Host "[$(Stamp)] ipConfigurations:"
$final.IpConfigurations | Select-Object Name, @{N="PipId";E={$_.PublicIPAddress.Id}} | Format-Table -Auto
