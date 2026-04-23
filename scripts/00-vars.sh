#!/usr/bin/env bash
# Shared variables for all phases. Source this in each script.
set -euo pipefail

# Set your subscription ID before running. Example:
#   export SUB="00000000-0000-0000-0000-000000000000"
if [[ -z "${SUB:-}" ]]; then
  echo "ERROR: SUB environment variable not set. Export your Azure subscription GUID first." >&2
  exit 1
fi
export LOC="${LOC:-swedencentral}"
export RG="${RG:-rg-vwan-azfw-custompip-lab}"
export VWAN="vwan-swc"
export HUB="hub-swc"
export HUB_ADDR="10.100.0.0/23"
export FWPOL="fwpol-swc"
export FWNAME="azfw-hub-swc"
export SPOKE_VNET="vnet-spoke1"
export SPOKE_ADDR="10.200.0.0/24"
export SPOKE_SUBNET="snet-workload"
export SPOKE_SUBNET_ADDR="10.200.0.0/25"
export SPOKE_NSG="nsg-spoke1"
export VM_NAME="vm-spoke1"
export VM_IMAGE="Ubuntu2204"
export VM_SIZE="Standard_B2s"
export VM_USER="azureuser"
export PIP_PREFIX_NAME="pipprefix-fw"
export PIP_PREFIX_LEN=30
export REPORT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/docs/RESULTS.md"

az account set --subscription "$SUB"
echo "[vars] sub=$(az account show --query name -o tsv)  loc=$LOC  rg=$RG"
