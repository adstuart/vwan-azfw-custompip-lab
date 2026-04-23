# Results — captured live on 2026-04-23 (Sweden Central)

> All outputs below are real, captured during the lab run. Timings and IP addresses are specific to:
> - Azure Firewall **Standard** SKU, AZFW_Hub (secured vWAN hub)
> - Region `swedencentral`
> - Hub address prefix `10.100.0.0/23`, default autoscale
> - Routing intent: Private + Internet → AzFW
> - Test timestamp: 2026-04-23

---

## Phase 1 — vWAN + hub + AzFW + routing intent

Deployed:
- vWAN `vwan-swc` (Standard)
- Hub `hub-swc` in Sweden Central, address prefix `10.100.0.0/23`
- AzFW `azfw-hub-swc` (Standard, AZFW_Hub SKU) with 1 Azure-managed PIP
- Firewall Policy `fwpol-swc` with an Allow-Any-Any application rule (lab-only)
- Routing intent: `PrivateTraffic` and `InternetTraffic` both → `azfw-hub-swc`

```
$ az network vhub routing-intent show -g rg-vwan-azfw-custompip-lab --vhub hub-swc
provisioningState: Succeeded
routingPolicies:
  - name: InternetTraffic
    destinations: [Internet]
    nextHop: <azfw-hub-swc resource id>
  - name: PrivateTraffic
    destinations: [PrivateTraffic]
    nextHop: <azfw-hub-swc resource id>
```

## Phase 2 — spoke VNet + VM + hub connection

- `vnet-spoke1` `10.200.0.0/24`, subnet `snet-workload` `10.200.0.0/25`
- `vm-spoke1` Ubuntu 22.04 Standard_B2s, no Public IP (SSH via hub / Bastion path not required — all tests via `az vm run-command`)
- Hub connection `conn-spoke1` with `enableInternetSecurity=true`

## Phase 3 — baseline egress test

From `vm-spoke1`:
```
$ curl -s --max-time 10 https://api.ipify.org
4.223.66.239
$ curl -s --max-time 10 https://ifconfig.me
4.223.66.239
$ curl -s --max-time 10 https://icanhazip.com
4.223.66.239
```
The AzFW's Azure-managed PIP resolved to `4.223.66.239`. **Baseline confirmed: spoke traffic egresses through the hub firewall.** ✔

> Note: `ifconfig.co` now returns a Cloudflare bot-challenge HTML page to Azure egress IPs — any crude regex against that page will match junk (e.g. `1.2.1.1`). Scripts in this repo use ipify / ifconfig.me / icanhazip with explicit `KEY=IP` extraction and a ≥2-of-3 consensus check.

## Phase 4 — online parallel add (expected failure)

Created `pipprefix-fw` (`20.91.191.48/30`, Standard, static) and pre-allocated `pip-fw-prefix-1` (`20.91.191.48`) and `pip-fw-prefix-2` (`20.91.191.49`) from it. Attempted to add them to the running firewall via ARM PATCH:

```
$ az rest --method patch --uri "https://management.azure.com/.../azureFirewalls/azfw-hub-swc?api-version=2024-05-01" \
    --body @/tmp/patch-ipconfigs.json
ERROR: Bad Request({"error":{"code":"OnlyTagsSupportedForPatch",
  "message":"PATCH request content includes properties property. Only tags property is currently supported.",
  "details":[]}})
```

Repeated the same PATCH with 3 PIPs (2 prefix + 1 standalone) — same rejection:

```
ERROR: Bad Request({"error":{"code":"OnlyTagsSupportedForPatch", ...}})
```

**Online parallel add is impossible by design** — the block is on PATCH of `properties`, independent of PIP source.

## Phase 5 — Deallocate → Allocate swap (first swap, 2 PIPs)

Using the MS-Learn-documented PowerShell flow (`scripts/05-swap.ps1`):

```
Connect-AzAccount -Identity
$azfw = Get-AzFirewall -ResourceGroupName rg-vwan-azfw-custompip-lab -Name azfw-hub-swc
$hubIp = New-AzFirewallHubPublicIpAddress -Count 0
$azfw.HubIPAddresses = New-AzFirewallHubIpAddress -PublicIP $hubIp
Set-AzFirewall -AzureFirewall $azfw
$azfw.Deallocate()
Set-AzFirewall -AzureFirewall $azfw
$pips = @( Get-AzPublicIpAddress -Name pip-fw-prefix-1 -ResourceGroupName rg-vwan-azfw-custompip-lab
           Get-AzPublicIpAddress -Name pip-fw-prefix-2 -ResourceGroupName rg-vwan-azfw-custompip-lab )
$vhub = Get-AzVirtualHub -Name hub-swc -ResourceGroupName rg-vwan-azfw-custompip-lab
$azfw.Allocate($vhub.Id, $pips)
Set-AzFirewall -AzureFirewall $azfw
```
Completed cleanly. Post-swap egress from `vm-spoke1`:
```
$ curl -s https://api.ipify.org
20.91.191.48
```
✔ Egress IP `20.91.191.48` is inside prefix `20.91.191.48/30`.

## Phase 6 — verify via ipConfigurations[] (post-swap shape)

Important: `hubIPAddresses` is now `null`; PIPs live in `ipConfigurations[]`:

```
$ az network firewall show -g rg-vwan-azfw-custompip-lab -n azfw-hub-swc \
    --query "{hub:hubIPAddresses, ipCfg:ipConfigurations[].{name:name, pipId:publicIPAddress.id}}" -o jsonc
{
  "hub": null,
  "ipCfg": [
    { "name": "AzureFirewallIpConfiguration0", "pipId": ".../publicIPAddresses/pip-fw-prefix-1" },
    { "name": "AzureFirewallIpConfiguration1", "pipId": ".../publicIPAddresses/pip-fw-prefix-2" }
  ]
}
```

## Phase 7 — second swap + downtime measurement (3 multi-source PIPs)

Added `pip-fw-standalone` (`4.223.83.37`) — a **standalone** Standard/static PIP not allocated from the prefix — to test whether multi-source customer PIPs can coexist. Ran a 2 Hz curl loop from `vm-spoke1` before/during/after the swap.

### Control plane timing

```
19:58:55Z  Connect-AzAccount -Identity
19:58:58Z  DEALLOCATE_START
20:08:41Z  DEALLOCATE_DONE       (9m 43s)
20:08:43Z  ALLOCATE_START (3 PIPs: 20.91.191.48, 20.91.191.49, 4.223.83.37)
20:16:47Z  ALLOCATE_DONE         (8m 04s)
                                 -----------
Total swap:                       17m 47s
```

### Data plane timing (curl loop, 2 Hz from `vm-spoke1`)

| Metric | Value |
|---|---|
| Pre-swap egress IP (stable) | `20.91.191.48` |
| First failed curl after Deallocate start | **+6.9 s** |
| Longest contiguous outage observed | **≥ 6 min 23 s** (383 s) |
| Curl success rate during swap | ~10 % |
| Stable egress restored | ~immediately after Allocate completed |
| Post-swap egress IPs observed | `20.91.191.48`, `20.91.191.49` (traffic distributed across prefix PIPs) |

### Final firewall state

```
ipConfigurations:
  AzureFirewallIpConfiguration0  ->  pip-fw-prefix-1    (20.91.191.48, from prefix)
  AzureFirewallIpConfiguration1  ->  pip-fw-prefix-2    (20.91.191.49, from prefix)
  AzureFirewallIpConfiguration2  ->  pip-fw-standalone  (4.223.83.37,  standalone static)
hubIPAddresses: null
```

**Multi-source customer PIPs coexist fine** — you can mix prefix PIPs with standalone PIPs on a single firewall. You still can't mix **customer-provided** with **Azure-managed** PIPs (those are separate ARM shapes), and each addition still requires a full Deallocate/Allocate cycle.

### Maintenance window sizing

Given observed timings in this environment (Standard SKU, Sweden Central, default sizing), **plan ≥20 minutes of downtime per firewall** for each swap. The data-plane outage is not a brief blip — it persists for most of the swap window. If you operate multiple hubs, you can do them sequentially and/or leverage geographic failover upstream.

## Phase 8 — teardown

```
$ az group delete -g rg-vwan-azfw-custompip-lab --yes --no-wait
```

Then confirm the resource group is gone:

```
$ az group exists -n rg-vwan-azfw-custompip-lab
false
```
