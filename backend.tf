# Remote state backend.
# UPDATE THE storage_account_name BELOW to match the storage account you
# already provisioned for the bkr multi-cloud lab. The key is unique per
# stack, so this state lives separately from the rest of your lab.
#
# If you'd rather use local state for this lab while you're learning,
# comment this entire block out — Terraform will fall back to terraform.tfstate
# in the working directory.

terraform {
  backend "azurerm" {
    resource_group_name  = "bkr-lab-az-rg-tfstate"        # <-- change if yours differs
    storage_account_name = "bkrlabazsttfstate"          # <-- CHANGE ME to your actual SA name
    container_name       = "tfstate"
    key                  = "avd/terraform.tfstate"
  }
}
