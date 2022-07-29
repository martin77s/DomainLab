# DomainLab

The PowerShell script (deploy.ps1) initiates the deployment of the ARM templates (azuredeploy.json, and nested/vnet.json) to create an environment with 2 domain controllers and 2+ member servers.
It first determines the clients' public IP (by calling https://api.ipify.org/) to allow only that IP address in the NSG attached to the subnet. If it fails to determine the public IP, it will allow 0.0.0.0/32.

The AD domain creation, adding the member servers to the domain, and the creation a few test users is handeled by the DSC component (/dsc/dsc.ps1, "compiled" as /dsc/dsc.zip).

The resources created by the script and templates are:
- Public IP address
- Network security group with one rule (allow inbound RDP)
- Virtual Network with one subnet
- Availability set (for the two domain controllers)
- 2 virtual machines for the domain controllers (default names: dc1, dc2)
- 2+ virtual machines for the member servers (default names: srv1, srv2)

