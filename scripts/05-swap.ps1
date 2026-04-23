#!/usr/bin/env pwsh
param(
  [string]$RG = 'rg-vwan-azfw-custompip-lab',
  [string]$FWNAME = 'azfw-hub-swc',
  [string]$HUB = 'hub-swc',
  [string]$SUB = $env:AZURE_SUBSCRIPTION_ID,
  [string]$PIP1 = 'pip-fw-prefix-1',
  [string]$PIP2 = 'pip-fw-prefix-2'
)
$ErrorActionPreference = 'Stop'
Import-Module Az.Accounts, Az.Network

Connect-AzAccount -Identity -Subscription $SUB | Out-Null

Write-Host '== [05] Retrieving FW =='
$fw = Get-AzFirewall -ResourceGroupName $RG -Name $FWNAME
Write-Host "    Current PIPs: $($fw.HubIPAddresses.PublicIPs.Addresses.Address -join ', ')"

Write-Host '== [05] Setting PIP count to 0 =='
$hubIp = New-AzFirewallHubPublicIpAddress -Count 0
$fw.HubIPAddresses = New-AzFirewallHubIpAddress -PublicIP $hubIp
$fw | Set-AzFirewall | Out-Null

Write-Host '== [05] Deallocating FW =='
$fw = Get-AzFirewall -ResourceGroupName $RG -Name $FWNAME
$fw.Deallocate()
$fw | Set-AzFirewall | Out-Null

Write-Host '== [05] Allocating with prefix PIPs =='
$fw = Get-AzFirewall -ResourceGroupName $RG -Name $FWNAME
$p1 = Get-AzPublicIpAddress -ResourceGroupName $RG -Name $PIP1
$p2 = Get-AzPublicIpAddress -ResourceGroupName $RG -Name $PIP2
$vhub = Get-AzVirtualHub -ResourceGroupName $RG -Name $HUB
$fw.Allocate($vhub.Id, @($p1, $p2))
$fw | Set-AzFirewall | Out-Null

Write-Host '== [05] Current hub IPs: =='
(Get-AzFirewall -ResourceGroupName $RG -Name $FWNAME).HubIPAddresses.PublicIPs.Addresses |
  Format-Table Address
