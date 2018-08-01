$aadSvcPrinAppDisplayName = 'APPLICATION NAME' # Name for AAD Enterprise application
$aadSvcPrinAppHomePage = 'http://NAME.domain.co.uk' # http://FakeURLBecauseItsNotReallyNeededForThisPurpose
$aadSvcPrinAppIdentifierUri = 'https://domain.co.uk/NAME' # URL service principal
$aadSvcPrinAppPassword = ConvertTo-SecureString 'PASSWORD' -asplaintext -force # AAD Enterprise Application secret

#Manual login into Azure
#Login-AzureRmAccount # Application MUST be in the AAD assoicated with the Subscription

#Select subscription
write-Host -ForegroundColor Cyan "Select the correct subscription..."
$subscription = (
    Get-AzureRmSubscription |
    Sort-Object -Property Name |
    Select-Object -Property Name,Id |
    Out-GridView -OutputMode Single -Title 'Select an subscription'
).name

Select-AzureRmSubscription -SubscriptionName $subscription
write-Host -ForegroundColor Green "Ok, lets go!"

Read-Host -Prompt "Check that the subscription has been selected above, press any key to continue or Ctrl+C to abort"

#Create Service Principal App to Use For Encryption of VMs
$aadSvcPrinApplication = New-AzureRmADApplication   -DisplayName $aadSvcPrinAppDisplayName `
                                                    -HomePage $aadSvcPrinAppHomePage `
                                                    -IdentifierUris $aadSvcPrinAppIdentifierUri `
                                                    -Password $aadSvcPrinAppPassword

New-AzureRmADServicePrincipal -ApplicationId $aadSvcPrinApplication.ApplicationId