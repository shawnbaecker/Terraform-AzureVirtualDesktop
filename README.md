# Terraform-AzureVirtualDesktop

End-to-end Azure Virtual Desktop deployment as code. Built and verified against a personal Azure subscription as a working portfolio piece.

## What this builds

A minimum viable AVD environment in commercial Azure, deployed entirely from Terraform:

- Resource group scoped to a single environment
- VNet + subnet with an NSG that allows only outbound traffic to the AVD control plane (reverse-connect — no inbound RDP/443 to session hosts)
- Pooled host pool (Windows 11 multi-session, BreadthFirst load balancing, max 4 sessions per host)
- Application group (Desktop) and workspace, wired together
- Entra-joined session host VM(s) with Trusted Launch (vTPM + Secure Boot)
- AVD agent installed and registered via the DSC extension using a rotating registration token
- RBAC role assignments granting designated Entra users `Desktop Virtualization User` (on the app group) and `Virtual Machine User Login` (on the resource group)

State is stored in a shared Azure Storage backend so this stack lives alongside other Terraform projects in the same multi-cloud lab without colliding.

This is *v1*. FSLogix, custom images via Compute Gallery, scaling plans, Log Analytics integration, and CI/CD are called out at the bottom as v2 enhancements.

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
│             └── Session Host (vm-bkr-sh1)    │
│                  ↑ Entra-joined, AVD agent   │
└──────────────────────────────────────────────┘
```

The architectural takeaway: the control plane is a managed service. What I deploy and manage is the data plane — session hosts, identity, networking, and storage.

## Module layout

```
Terraform-AzureVirtualDesktop/
├── main.tf, variables.tf, outputs.tf, providers.tf, backend.tf
├── terraform.tfvars.example       # template; terraform.tfvars is gitignored
└── modules/
    ├── network/         VNet, subnet, NSG, NSG association
    ├── avd/             Host pool, registration token, app group, workspace, RBAC
    └── session-hosts/   NICs, VMs, AAD-join + AVD DSC extensions, login RBAC
```

Modules are split by lifecycle. Session hosts can be rebuilt from a new gold image without touching host pool config. The network module changes rarely. The AVD control-plane objects sit between them.

## Naming convention

Resources follow Microsoft's [Cloud Adoption Framework abbreviations](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-best-practices/resource-abbreviations) combined with a `<type>-<prefix>-<workload>-<env>[-<region>]` pattern:

| Resource | Example name |
|---|---|
| Resource group | `rg-bkr-avd-lab-eastus` |
| Virtual network | `vnet-bkr-avd-lab-eastus` |
| Network security group | `nsg-bkr-avd-sh-lab` |
| Host pool | `hp-bkr-avd-lab` |
| Application group | `ag-bkr-avd-desktop-lab` |
| Workspace | `ws-bkr-avd-lab` |
| Session host (Azure resource) | `vm-bkr-sh1` |
| Session host (Windows hostname) | `bkr-sh1` (15-char NetBIOS limit) |

The `bkr` prefix is project-owner-specific. Environment lets one subscription host lab/dev/prod side by side without collisions.

## Prerequisites

1. **Azure subscription** with Owner (or Contributor + User Access Administrator). User Access Administrator is required because the deployment creates role assignments.
2. **A native Entra user for AVD authentication.** Personal Microsoft accounts (hotmail.com, outlook.com) own subscriptions fine but cannot fully authenticate to AVD. Create a regular Entra user (`<name>@<tenant>.onmicrosoft.com`) and use its object ID — see `terraform.tfvars.example`.
3. **AVD-eligible licensing** assigned to that Entra user. Win 11 multi-session AVD requires one of: M365 E3/E5, Win 10/11 Enterprise E3/E5, or Win VDA. The free **Microsoft 365 E5 trial** (25 licenses, 30 days, no credit card) works for lab use.
4. **vCPU quota** for whichever VM family you're using in your target region. Fresh subscriptions often start with zero quota on newer families like DSv5. Older families like DSv4 typically have default quota of 10 cores in most regions.
5. **Toolchain:** Terraform ≥ 1.5, Azure CLI, Git, VS Code.

## Deploy

```powershell
# 1. Authenticate to Azure
az login --tenant "<your-tenant-id>"
az account set --subscription "<your-subscription-id>"

# 2. Set the admin password for the local VM admin account.
#    DO NOT put this in terraform.tfvars — set it as an env var instead.
$env:TF_VAR_admin_password = "Your-Strong-P@ssw0rd-Here!"

# 3. Create your tfvars from the template
Copy-Item terraform.tfvars.example terraform.tfvars
#    Edit terraform.tfvars and set:
#      - avd_user_object_ids (your native Entra user's object ID)
#      - session_host_vm_size (a SKU you have quota and capacity for)
#      - session_host_count (1 for lab demo, 2+ for distributed pooled scenario)

# 4. Update backend.tf with your shared state storage account name
#    (or comment the backend block out to use local state for testing)

# 5. Initialize, plan, apply
terraform init
terraform plan
terraform apply
```

Apply takes about 7-15 minutes depending on session host count. The slow part is the DSC extension downloading the AVD agent and registering each VM with the host pool.

## Verify the deployment

After apply:

1. **Portal → AVD → Host pools → `hp-bkr-avd-lab` → Session hosts.** Each VM should show **Status: Available**.
2. **Open the Windows App** (download from <https://aka.ms/avdwindows>) or the web client at <https://client.wvd.microsoft.com/arm/webclient/>.
3. Sign in with the Entra user whose object ID is in tfvars. The **Baecker AVD Lab** workspace should appear with the **Baecker AVD Desktop** resource inside it.
4. Click the desktop tile and connect. You'll authenticate twice — once to the AVD control plane, once to the VM itself, both with the same Entra credentials.

## Cost

| Resource | Approx monthly (24/7) |
|---|---|
| 1× session host (Standard_D2s_v4) | ~$70 |
| 1× Premium SSD OS disk (128 GB) | ~$20 |
| VNet / NSG / no public IPs | ~$0 |
| AVD control plane | $0 (Microsoft-managed) |
| State storage (shared) | < $1 |
| **Lab cost when running 24/7** | **~$90/mo** |

The lab is designed to be created and destroyed on demand:

```powershell
terraform destroy   # tears everything down in ~5-7 min
```

Running for 1-2 hours per session and destroying afterward keeps actual cost to a few dollars per month. State stays in the storage backend, so re-applying brings everything back in ~10 minutes.

## Real-world issues encountered (and how they were resolved)

These are documented because they're the operational realities that distinguish "ran a tutorial" from "deployed this for real." Each one is interview-worthy.

**Default vCPU quota of zero on the DSv5 family.** Fresh personal subscriptions start with zero cores allocated to newer VM families as a fraud-prevention measure. Resolved by switching to D2s_v4 (which had default quota of 10 cores). In production, the answer would be a quota increase request through the portal — auto-approves in ~10 minutes for reasonable amounts.

**SkuNotAvailable capacity restrictions in popular regions.** B-series VMs in East US and East US 2 returned `SkuNotAvailable` at deploy time despite having quota — this is real-time capacity exhaustion, not a quota issue. Microsoft doesn't expose true real-time capacity ahead of deploy. Resolved by switching to D2s_v4 in East US, where the enterprise-tier D family has reliable capacity. The lesson: quota and capacity are separate failure modes that look similar in error output but require different responses.

**Personal Microsoft accounts can't fully authenticate to AVD.** A `Baecker-Cloud@hotmail.com` account owns the Azure subscription and signs into the portal fine, but Windows App rejected it with `AADSTS500200`: *"Personal Microsoft accounts are not supported for this application."* Resolved by creating a native Entra user (`shawnbaecker@<tenant>.onmicrosoft.com`) inside the tenant, assigning it Global Administrator and an M365 E5 trial license, and using its object ID in tfvars. This actually mirrors the principle of separation of concerns in DoD/enterprise environments: distinct identities for billing-owner and end-user roles.

**Terraform data source resolution at plan time vs. apply time.** Initial design used `data "azurerm_resource_group"` in the session-hosts module to look up the RG ID for RBAC scope. This failed at plan time because the RG didn't exist yet — data sources resolve when plan runs, not when apply runs. Fixed by constructing the resource ID directly from the subscription ID (via `data "azurerm_subscription"`) and the RG name variable. The lesson: data sources are for things that already exist outside the current plan; for in-plan references, use exported attributes or constructed strings.

**State lock not releasing after Ctrl+C.** Cancelling a plan mid-flight (during a password prompt) left the state blob lease held. Resolved with `terraform force-unlock <lock-id>` — safe because the lock was clearly mine and stale.

**MFA enforcement on first Azure CLI auth.** `terraform init` failed against the storage backend with `AADSTS50076` — Conditional Access required interactive MFA reauth. Resolved by `az logout` followed by `az login --tenant "<tenant-id>"` to force a fresh interactive flow.

## Configuration choices worth explaining

**Pooled host pool with one session host (lab) or many (production).** A Pooled host pool is just a logical container — the user-to-VM relationship model, not the count. One host or many, the architecture is identical. Lab uses one host to minimize cost; scaling up is a `session_host_count` change.

**`custom_rdp_properties` includes `targetisaadjoined:i:1` and `enablerdsaadauth:i:1`.** Without these, Entra-joined session hosts prompt for credentials twice. This is the #1 stumbling block on cloud-native AVD deployments.

**`time_rotating` resource for the registration token.** Tokens expire after a maximum of 30 days. Hardcoding an expiration would silently break new session host registrations after a month. The `time_rotating` resource regenerates the token every 29 days automatically.

**DSC extension `depends_on` AAD-join extension.** If the AVD agent registers before the VM is Entra-joined, the host registers as a non-Entra-joined host and SSO permanently breaks for that VM. Order matters.

**Two role assignments per user.** `Desktop Virtualization User` on the app group lets users see and click into the workspace. `Virtual Machine User Login` on the resource group lets them actually authenticate to the Windows OS. Miss either and users hit a wall.

**NSG outbound rules use service tags.** `WindowsVirtualDesktop` and `AzureCloud` are Microsoft-maintained tag groups that auto-update when endpoints change. IP-based rules for Azure services break the moment Microsoft shifts an endpoint.

## Secret handling

- `terraform.tfvars` is gitignored. The example file shows the structure; real values live only on the operator's machine.
- The local VM admin password is set via `$env:TF_VAR_admin_password`, never in tfvars.
- Sensitive variables and outputs are marked `sensitive = true` so they don't leak to console output or logs.
- State contains secrets in plaintext (this is a Terraform reality, not a bug); state lives in an Azure Storage backend with platform-managed encryption at rest, RBAC-scoped access, and TLS in transit.
- For production, the upgrade path is to source secrets from Azure Key Vault via the `azurerm_key_vault_secret` data source, and to enable customer-managed encryption keys on the state storage account.

## v2 enhancements (the things that turn "lab" into "production")

1. **FSLogix profile containers** on Premium Azure Files with Entra Kerberos authentication. Required for usable Pooled deployments with multiple users.
2. **Azure Compute Gallery + custom image.** Replace the marketplace image reference with a versioned, STIG-baselined gold image. The single biggest "this person knows what they're doing" addition.
3. **Scaling plan** (`azurerm_virtual_desktop_scaling_plan`). Schedule-based ramp-up/ramp-down so VMs don't run idle overnight.
4. **Diagnostics to Log Analytics** with an `azurerm_log_analytics_workspace` and diagnostic settings on the host pool, app group, and workspace. Enables the AVD Insights dashboard.
5. **Private networking.** Replace public outbound connectivity with Private Link / Private Endpoints for backend services. Pair with Azure Firewall + UDRs for egress filtering — this is the topology you'd see in IL4.
6. **CI/CD pipeline.** GitHub Actions running `terraform fmt`, `validate`, `tflint`, and `plan` on PR, and `apply` on merge to main with manual approval.
7. **Group-based access** instead of individual user object IDs. Replace `avd_user_object_ids` entries with an Entra security group's object ID, then manage AVD access by group membership rather than by re-running Terraform.

## Talking points

- *"I deploy AVD with Terraform, split into network, control-plane, and session-host modules so lifecycles are independent."*
- *"Reverse-connect means no inbound 443 or 3389 on session hosts — the NSG only permits outbound to the WindowsVirtualDesktop and AzureCloud service tags."*
- *"Pooled with one session host or many — the architecture is the same. Scaling up is a count change."*
- *"For production I'd add FSLogix on Azure Files Premium with Entra Kerberos, a versioned custom image in Compute Gallery, a scaling plan, and AVD Insights through Log Analytics."*
- *"Personal Microsoft accounts can own subscriptions but can't fully authenticate to AVD — production deployments always use native Entra identities, but personal labs hit this constantly."*
- *"Two failure modes I learned to distinguish: vCPU quota (fixable with a quota request) versus SkuNotAvailable (real-time capacity, requires SKU or region change)."*
