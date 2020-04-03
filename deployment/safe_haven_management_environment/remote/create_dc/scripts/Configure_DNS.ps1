# Use Microsoft Azure DNS server for resolving external addresses
# https://docs.microsoft.com/en-us/azure/virtual-network/what-is-ip-address-168-63-129-16
Write-Host "Forward external DNS requests to Microsoft Azure DNS server..."
Add-DnsServerForwarder -IPAddress 168.63.129.16 -PassThru
if ($?) {
    Write-Host " [o] Successfully created/updated DNS forwarding"
} else {
    Write-Host " [x] Failed to create/update DNS forwarding!"
}
