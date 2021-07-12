#-------------------------------
# Local Declarations
#-------------------------------
locals {
  resource_group_name = element(coalescelist(data.azurerm_resource_group.rgrp.*.name, azurerm_resource_group.rg.*.name, [""]), 0)
  location            = element(coalescelist(data.azurerm_resource_group.rgrp.*.location, azurerm_resource_group.rg.*.location, [""]), 0)
  default_site_config = {
    default_documents = [
      "Default.htm",
      "Default.html",
      "Default.asp",
      "index.htm",
      "index.html",
      "iisstart.htm",
      "default.aspx",
      "hostingstart.html",
    ]
  }
}

data "azurerm_client_config" "current" {}

#---------------------------------------------------------
# Resource Group Creation or selection - Default is "true"
#---------------------------------------------------------
data "azurerm_resource_group" "rgrp" {
  count = var.create_resource_group == false ? 1 : 0
  name  = var.resource_group_name
}

resource "azurerm_resource_group" "rg" {
  #ts:skip=accurics.azure.NS.272 RSG lock should be skipped for now.
  count    = var.create_resource_group ? 1 : 0
  name     = lower(var.resource_group_name)
  location = var.location
  tags     = merge({ "ResourceName" = format("%s", var.resource_group_name) }, var.tags, )
}

#---------------------------------------------------------
# Application ClientID/Secret Creation or selection
#---------------------------------------------------------

resource "time_rotating" "main" {
  count            = var.auth_settings_enabled ? 1 : 0

  rotation_years = var.years

  triggers = {
    years = var.years
  }
}

resource "azuread_application" "main" {
  count            = var.auth_settings_enabled ? 1 : 0

  display_name     = format("%s-%s", var.prefix, lower(replace(var.name, "/[[:^alnum:]]/", "")))
  identifier_uris  = [format("api://%s-%s", var.prefix, lower(replace(var.name, "/[[:^alnum:]]/", "")))]
  sign_in_audience = "AzureADMyOrg"

  required_resource_access {
    resource_app_id = "00000003-0000-0000-c000-000000000000"

    resource_access {
      id   = "e1fe6dd8-ba31-4d61-89e7-88639da4683d"
      type = "Scope"
    }
  }

  web {
    homepage_url  = format("https://%s-%s.azurewebsites.net", var.prefix, lower(replace(var.name, "/[[:^alnum:]]/", "")))
    redirect_uris = [format("https://%s-%s.azurewebsites.net/.auth/login/aad/callback", var.prefix, lower(replace(var.name, "/[[:^alnum:]]/", "")))]
    implicit_grant {
      access_token_issuance_enabled = false
    }
  }
}

resource "azuread_service_principal" "main" {
  count                        = var.auth_settings_enabled ? 1 : 0

  application_id               = azuread_application.main[0].application_id
  app_role_assignment_required = true
}

resource "azuread_application_password" "main" {
  count                 = var.auth_settings_enabled ? 1 : 0

  display_name          = format("%s-%s", var.prefix, lower(replace(var.name, "/[[:^alnum:]]/", "")))
  application_object_id = azuread_application.main[0].object_id
  end_date              = time_rotating.main[0].rotation_rfc3339
}

#---------------------------------------------------------
# App Service Creation or selection
#---------------------------------------------------------

resource "azurerm_app_service" "main" {
  name                = format("%s-%s", var.prefix, lower(replace(var.name, "/[[:^alnum:]]/", "")))
  location            = local.location
  resource_group_name = local.resource_group_name
  app_service_plan_id = var.app_service_plan_id

  dynamic "site_config" {
    for_each = [merge(local.default_site_config, var.site_config)]

    content {
      always_on                 = lookup(site_config.value, "always_on", null)
      app_command_line          = lookup(site_config.value, "app_command_line", null)
      default_documents         = lookup(site_config.value, "default_documents", null)
      dotnet_framework_version  = lookup(site_config.value, "dotnet_framework_version", null)
      ftps_state                = lookup(site_config.value, "ftps_state", null)
      health_check_path         = lookup(site_config.value, "health_check_path", null)
      number_of_workers         = lookup(site_config.value, "number_of_workers", null)
      http2_enabled             = lookup(site_config.value, "http2_enabled", null)
      linux_fx_version          = lookup(site_config.value, "linux_fx_version", null)
      windows_fx_version        = lookup(site_config.value, "windows_fx_version", null)
      managed_pipeline_mode     = lookup(site_config.value, "managed_pipeline_mode", null)
      min_tls_version           = lookup(site_config.value, "min_tls_version", null)
      python_version            = lookup(site_config.value, "python_version", null)
      remote_debugging_enabled  = lookup(site_config.value, "remote_debugging_enabled", null)
      remote_debugging_version  = lookup(site_config.value, "remote_debugging_version", null)
      scm_type                  = lookup(site_config.value, "scm_type", null)
      use_32_bit_worker_process = lookup(site_config.value, "use_32_bit_worker_process", null)
      websockets_enabled        = lookup(site_config.value, "websockets_enabled", null)
    }
  }

  auth_settings {
    enabled                        = var.auth_settings_enabled
    issuer                         = format("https://sts.windows.net/%s/v2.0", data.azurerm_client_config.current.tenant_id)
    token_store_enabled            = false
    unauthenticated_client_action  = "RedirectToLoginPage"
    default_provider               = "AzureActiveDirectory"
    allowed_external_redirect_urls = []

    active_directory {
      client_id         = azuread_application.main[0].application_id
      allowed_audiences = [format("api://%s", azuread_application.main[0].application_id)]
    }
  }

  identity {
    type = "SystemAssigned"
  }

  tags = merge({ "ResourceName" = format("%s-%s", var.prefix, lower(replace(var.name, "/[[:^alnum:]]/", ""))) }, var.tags, )

}
