param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter DSG ID (usually a number e.g enter '9' for DSG9)")]
  [string]$dsgId
)

Import-Module Az
Import-Module $PSScriptRoot/../DsgConfig.psm1 -Force
Import-Module $PSScriptRoot/../GeneratePassword.psm1 -Force

# Get DSG config
$config = Get-DsgConfig($dsgId);

# Temporarily switch to DSG subscription
$prevContext = Get-AzContext
$_ = Set-AzContext -SubscriptionId $config.dsg.subscriptionName;

# Find VM with private IP address matching the provided last octect
## Turn provided last octect into full IP address in the data subnet
$vmIpAddress = $config.dsg.linux.hackmd.ip
Write-Host " - Finding VM with IP $vmIpAddress"
## Get all web app server VMs
$webAppVms = Get-AzVM -ResourceGroupName $config.dsg.linux.rg
## Get the NICs attached to all the compute VMs
$webAppVmNicIds = ($webAppVms | ForEach-Object{(Get-AzVM -ResourceGroupName $config.dsg.linux.rg -Name $_.Name).NetworkProfile.NetworkInterfaces.Id})
$webAppVmNics = ($webAppVmNicIds | ForEach-Object{Get-AzNetworkInterface -ResourceGroupName $config.dsg.linux.rg -Name $_.Split("/")[-1]})
## Filter the NICs to the one matching the desired IP address and get the name of the VM it is attached to
$vmName = ($webAppVmNics | Where-Object{$_.IpConfigurations.PrivateIpAddress -match $vmIpAddress})[0].VirtualMachine.Id.Split("/")[-1]

# Set HackMD config values
$hackmdLdapSearchFilter = "(&(objectClass=user)(memberOf=CN=" + $config.dsg.domain.securityGroups.researchUsers.name + "," + $config.shm.domain.securityOuPath + ")(userPrincipalName={{username}}))"
$hackmdLdapSearchBase = $config.shm.domain.userOuPath;
$hackmdBindCreds = (Get-AzKeyVaultSecret -vaultName $config.dsg.keyVault.name -name $config.dsg.users.ldap.hackmd.passwordSecretName).SecretValueText;
$hackmdLdapBindDn = "CN=" + $config.dsg.users.ldap.hackmd.name + "," + $config.shm.domain.serviceOuPath
$hackmdLdapUrl = "ldap://" + $config.shm.dc.fqdn
$hackmdLdapProviderName = $config.shm.domain.netbiosName

## Creare hackmd docker-compose.yaml config file
$hackmdConfig = @"
version: '2'
services:
database:
    # Don't upgrade PostgreSQL by simply changing the version number
    # You need to migrate the Database to the new PostgreSQL version
    image: postgres:9.6-alpine
    #mem_limit: 256mb         # version 2 only
    #memswap_limit: 512mb     # version 2 only
    #read_only: true          # not supported in swarm mode please enable along with tmpfs
    #tmpfs:
    #  - /run/postgresql:size=512K
    #  - /tmp:size=256K
    environment:
    - POSTGRES_USER=hackmd
    - POSTGRES_PASSWORD=hackmdpass
    - POSTGRES_DB=hackmd
    volumes:
    - database:/var/lib/postgresql/data
    networks:
    backend:
    restart: always

app:
    image: hackmdio/hackmd:1.2.0
    #mem_limit: 256mb         # version 2 only
    #memswap_limit: 512mb     # version 2 only
    #read_only: true          # not supported in swarm mode, enable along with tmpfs
    #tmpfs:
    #  - /tmp:size=512K
    #  - /hackmd/tmp:size=1M
    # Make sure you remove this when you use filesystem as upload type
    #  - /hackmd/public/uploads:size=10M
    volumes:
    - uploads:/hackmd/public/uploads
    environment:
    # DB_URL is formatted like: <databasetype>://<username>:<password>@<hostname>/<database>
    # Other examples are:
    # - mysql://hackmd:hackmdpass@database:3306/hackmd
    # - sqlite:///data/sqlite.db (NOT RECOMMENDED)
    # - For details see the official sequelize docs: http://docs.sequelizejs.com/en/v3/
    - HMD_DB_URL=postgres://hackmd:hackmdpass@database:5432/hackmd
    - HMD_ALLOW_ANONYMOUS=false
    - HMD_ALLOW_FREEURL=true
    - HMD_EMAIL=false
    - HMD_USECDN=false
    - HMD_LDAP_SEARCHFILTER=$hackmdLdapSearchFilter
    - HMD_LDAP_SEARCHBASE=$hackmdLdapSearchBase
    - HMD_LDAP_BINDCREDENTIALS=$hackmdBindCreds
    - HMD_LDAP_BINDDN=$hackmdLdapBindDn
    - HMD_LDAP_URL=$hackmdLdapUrl
    - HMD_LDAP_PROVIDERNAME=$hackmdLdapProviderName
    - HMD_IMAGE_UPLOAD_TYPE=filesystem
    ports:
    # Ports that are published to the outside.
    # The latter port is the port inside the container. It should always stay on 3000
    # If you only specify a port it'll published on all interfaces. If you want to use a
    # local reverse proxy, you may want to listen on 127.0.0.1.
    # Example:
    # - "127.0.0.1:3000:3000"
    - "3000:3000"
    networks:
    backend:
    restart: always
    depends_on:
    - database

# Define networks to allow best isolation
networks:
# Internal network for communication with PostgreSQL/MySQL
backend:
    
# Define named volumes so data stays in place
volumes:
# Volume for PostgreSQL/MySQL database
database:
uploads:
"@

# Run remote script
$scriptPath = Join-Path $PSScriptRoot "remote_scripts" "update_hackmd_config.sh"

$params = @{
    HACKMD_CONFIG = $hackmdConfig
};

$result = Invoke-AzVMRunCommand -ResourceGroupName $config.dsg.linux.rg -Name "$vmName" `
          -CommandId 'RunShellScript' -ScriptPath $scriptPath -Parameter $params
Write-Output $result.Value;

# Switch back to previous subscription
$_ = Set-AzContext -Context $prevContext;
