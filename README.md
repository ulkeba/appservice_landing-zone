# Overview

The Bicep templates in this repository deploy following components:
- Azure App Serivces, protected from public internet access using a private endpoint and access restrictions.
- Azure Application Gateway, exposing the App Service via https and a self-signed certificate.
- Azure Key Vault, containing the self-signed certificate
- Azure Web Application Firewall Policiy, attached to the Application Gatewaz, enabling OWASP policies and a custom rule (detecting / blocking requests from NL or IE for test purposes)
- Azure Log Analtyics Workspace collecting diagnostic metrics and logs from the Application Gateway.
- Azure Virtual Machine running Windows 11 as Admin-Host.
- Azure Bastion Host for secure access to the VM.

# Deployment
- Create your own copy of `demo.parameters.json`
- Invoke deployment with `az deployment sub create` (see `deploy.sh`)