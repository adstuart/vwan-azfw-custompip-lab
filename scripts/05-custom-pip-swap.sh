#!/usr/bin/env bash
# Phase 5: Official swap path via Az PowerShell (CLI does not expose Deallocate/Allocate for hub AzFW).
source "$(dirname "$0")/00-vars.sh"

if ! command -v pwsh >/dev/null; then
  echo "pwsh not installed; installing..."
  sudo snap install powershell --classic
fi

pwsh -NoProfile -Command "
  if (-not (Get-Module -ListAvailable Az.Network)) {
    Install-Module Az.Network -Scope CurrentUser -Force -AllowClobber
  }
  Import-Module Az.Network
  try { Get-AzContext -ErrorAction Stop | Out-Null } catch { Connect-AzAccount -UseDeviceAuthentication }
  Set-AzContext -Subscription '$SUB' | Out-Null

  Write-Host '== [05] Retrieving FW =='
  \$fw = Get-AzFirewall -ResourceGroupName '$RG' -Name '$FWNAME'

  Write-Host '== [05] Setting PIP count to 0 =='
  \$hubIp = New-AzFirewallHubPublicIpAddress -Count 0
  \$fw.HubIPAddresses = New-AzFirewallHubIpAddress -PublicIP \$hubIp
  Set-AzFirewall -AzureFirewall \$fw

  Write-Host '== [05] Deallocating FW =='
  \$fw.Deallocate()
  Set-AzFirewall -AzureFirewall \$fw

  Write-Host '== [05] Allocating with prefix PIPs =='
  \$p1 = Get-AzPublicIpAddress -ResourceGroupName '$RG' -Name 'pip-fw-prefix-1'
  \$p2 = Get-AzPublicIpAddress -ResourceGroupName '$RG' -Name 'pip-fw-prefix-2'
  \$vhub = Get-AzVirtualHub -ResourceGroupName '$RG' -Name '$HUB'
  \$fw.Allocate(\$vhub.Id, @(\$p1,\$p2))
  Set-AzFirewall -AzureFirewall \$fw

  Write-Host '== [05] Current hub IPs: =='
  (Get-AzFirewall -ResourceGroupName '$RG' -Name '$FWNAME').HubIPAddresses.PublicIPs.Addresses
"

echo "== [05] Verify via CLI =="
az network firewall show -g "$RG" -n "$FWNAME" \
  --query "{state:provisioningState, pips:hubIPAddresses.publicIPs.addresses[].address}" -o json | tee /tmp/fw-pips-after.txt

{
  echo
  echo "## Swap to prefix PIPs — $(date -Iseconds)"
  echo
  echo '```json'; cat /tmp/fw-pips-after.txt; echo '```'
} >> "$REPORT"
