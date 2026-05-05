# Terraform-AzureVirtualDesktop

A working, end-to-end Azure Virtual Desktop lab deployed entirely with Terraform. Part of the `bkr` multi-cloud lab.

## What this builds

A minimum viable AVD environment in commercial Azure:

- Resource group, VNet, subnet, NSG (outbound-only via service tags — reverse-connect, no inbound)
- Windows 11 multi-session host pool (Pooled, BreadthFirst load balancing)
- Desktop application group + workspace, wired together
- Two Entra-joined session host VMs registered with the host pool
- RBAC assignments so designated Entra users can subscribe to the workspace and log into the session hosts

This is intentionally *v1*. FSLogix profile containers, scaling plans, Azure Compute Gallery images, and Log Analytics integration are all called out as v2 enhancements at the bottom of this README.

## Architecture (logical)

```
┌──────────────────────────────────────────────┐
│  AVD Control Plane (Microsoft-managed)       │
│  Gateway · Broker · Diagnostics · Web client │
└────────────────────┬─────────────────────────┘
                     │ reverse connect (outbound 443)
┌────────────────────┴─────────────────────────┐
│  Workspace (ws-bkr-avd-lab)                  │
│   └── Application Group (Desktop)            │
│        └── Host Pool (hp-bkr-avd-lab)        │
│             ├── Session Host 1 (vm-bkr-sh1)  │
│             └── Session Host 2 (vm-bkr-sh2)  │
│                  ↑ Entra-joined, AVD agent   │
└──────────────────────────────────────────────┘
```

## Prerequisites

1. **Azure subscription** with Owner or Contributor + User Access Administrator on the subscription (you need to create role assignments).
2. **Eligible Windows licensing.** Win 11 multi-session AVD images require one of: M365 E3/E5, Win 10/11 Enterprise E3/E5, Win VDA E3/E5. If your personal tenant doesn't have this, spin up a free **Microsoft 365 E5 trial** — it gives you 25 licenses for 30 days, which is plenty for the lab. Without eligible licensing, the VMs deploy fine but you'll see a license activation error at logon.
3. **Toolchain** (you already have these from the bkr lab setup): Terraform ≥ 1.5, Azure CLI, Git, VS Code.
4. **Your Entra user object ID.** Get it from Entra ID → Users → click your account → copy "Object ID."

## Deploy

```powershell
# 1. Authenticate to Azure (commercial cloud)
az cloud set --name AzureCloud
az login
az account set --subscription "<your-subscription-id>"

# 2. Set the admin password as an env var (don't commit it)
$env:TF_VAR_admin_password = "Your-Strong-P@ssw0rd-Here!"

# 3. Copy the example tfvars and fill in your user object ID
Copy-Item terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — at minimum set avd_user_object_ids

# 4. Update backend.tf with your existing bkr state storage account name

# 5. Initialize, plan, apply
terraform init
terraform plan -out=avd.tfplan
terraform apply avd.tfplan
```

Apply takes ~12-15 minutes. The slow part is the DSC extension installing the AVD agent and registering each session host with the host pool.

## Verify

1. **Azure portal** → AVD → Host pools → `hp-bkr-avd-lab` → Session hosts. Both VMs should show **Status: Available**.
2. **Open the Remote Desktop client.** Either:
   - Web client: <https://client.wvd.microsoft.com/arm/webclient/>
   - Windows app: download from <https://aka.ms/avdwindows>
3. Sign in with the Entra user whose object ID you put in tfvars. You should see the **Baecker AVD Lab** workspace with the **Baecker AVD Desktop** resource. Click to connect.

## Destroy (do this when not testing — VMs run ~$70/mo each)

```powershell
terraform destroy
```

The whole stack tears down cleanly. The remote state is preserved.

## What this costs running 24/7

| Resource | Approx monthly |
|---|---|
| 2× Standard_D2s_v5 VMs | ~$140 |
| 2× Premium SSD OS disks (128 GB) | ~$40 |
| VNet / NSG / public IPs | ~$0 (no public IPs in this build) |
| AVD control plane | $0 (Microsoft-managed) |
| **Total if left running** | **~$180/mo** |

For lab use, `terraform destroy` between sessions keeps actual cost to a couple of dollars. Or change `session_host_vm_size` to `Standard_B2ms` to halve the VM cost.

## Module layout

```
Terraform-AzureVirtualDesktop/
├── main.tf, variables.tf, outputs.tf, providers.tf, backend.tf
├── terraform.tfvars.example
└── modules/
    ├── network/         VNet, subnet, NSG, NSG association
    ├── avd/             Host pool, registration token, app group, workspace
    └── session-hosts/   NICs, VMs, Entra join + AVD agent extensions, RBAC
```

## v2 enhancements (the things to add next)

These are the talking points that turn this from "I built a lab" into "I architected a real solution":

1. **FSLogix profile containers.** Add an `azurerm_storage_account` (Premium FileStorage) + `azurerm_storage_share` for profiles. Configure Entra Kerberos auth on the storage account, install the FSLogix agent in the gold image, and apply registry settings via a custom script extension or DSC.
2. **Azure Compute Gallery + custom image.** Replace the marketplace image reference with a versioned custom image so you can roll patched, STIG-baselined images out as immutable infrastructure. This is the single biggest "you sound senior" addition.
3. **Scaling plan** (`azurerm_virtual_desktop_scaling_plan`). Schedule-based ramp-up/ramp-down so VMs don't run idle overnight.
4. **Diagnostics → Log Analytics** with an `azurerm_log_analytics_workspace` and diagnostic settings on the host pool, app group, and workspace. Enable AVD Insights for the dashboard.
5. **Private networking.** Replace the outbound public connectivity with Private Link / Private Endpoints for the storage account and any backend services. Pair with Azure Firewall + UDRs for egress filtering — this is the topology you'd see in IL4.
6. **CI/CD pipeline.** A GitHub Actions workflow that runs `terraform fmt`, `validate`, `tflint`, and `plan` on PR, and `apply` on merge to main with manual approval. This closes the "implementing AVD in CI/CD pipelines" line in the job description.

## Interview talking points this lab gives you

- "I deploy AVD with Terraform, organized into network / control-plane / session-host modules so lifecycles are independent."
- "Session hosts are Entra-joined with the AAD login extension; the AVD agent is installed and registered via the DSC extension using a rotating registration token."
- "Reverse-connect means no inbound 443 or 3389 on the session hosts — the NSG only permits outbound to the WindowsVirtualDesktop and AzureCloud service tags."
- "The registration token rotates every 29 days via the time_rotating resource so we don't carry a stale token in state."
- "For production I'd add FSLogix on Azure Files Premium with Entra Kerberos, a versioned custom image in Compute Gallery, a scaling plan, and AVD Insights through Log Analytics."
