param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID (usually a string e.g enter 'testa' for Turing Development Safe Haven A).")]
    [string]$shmId,
    [Parameter(Mandatory = $true, HelpMessage = "Specify an existing VM image to add to the gallery.")]
    [string]$imageName,
    [Parameter(Mandatory = $false, HelpMessage = "Override the automatically determined version number. Use with caution.")]
    [string]$imageVersion = $null
)

Import-Module Az
Import-Module $PSScriptRoot/../../common/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../../common/Deployments.psm1 -Force
Import-Module $PSScriptRoot/../../common/Logging.psm1 -Force
Import-Module $PSScriptRoot/../../common/Security.psm1 -Force


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-ShmFullConfig($shmId)
$originalContext = Get-AzContext
$_ = Set-AzContext -SubscriptionId $config.dsvmImage.subscription

# Other constants
$supportedImages = @("ComputeVM-Ubuntu1804Base", "ComputeVM-UbuntuTorch1804Base", "DSVM-Ubuntu1804Base")
$majorVersion = 0
$minorVersion = 1


# Ensure that gallery resource group exists
# -----------------------------------------
$_ = Deploy-ResourceGroup -Name $config.dsvmImage.gallery.rg -Location $config.dsvmImage.location


# Ensure that image gallery exists
# --------------------------------
$gallery = Get-AzGallery -Name $config.dsvmImage.gallery.sig -ResourceGroupName $config.dsvmImage.gallery.rg -ErrorVariable notExists -ErrorAction SilentlyContinue
if ($notExists) {
    Add-LogMessage -Level Info "Creating image gallery $($config.dsvmImage.gallery.sig)..."
    $gallery = New-AzGallery -GalleryName $config.dsvmImage.gallery.sig -ResourceGroupName $config.dsvmImage.gallery.rg -Location $config.dsvmImage.location
}


# Set up list of image definitions we want to support
# ---------------------------------------------------
foreach ($supportedImage in $supportedImages) {
    $_ = Get-AzGalleryImageDefinition -GalleryName $config.dsvmImage.gallery.sig -ResourceGroupName $config.dsvmImage.gallery.rg -Name $supportedImage -ErrorVariable notExists -ErrorAction SilentlyContinue
    if ($notExists) {
        Add-LogMessage -Level Info "Creating image definition $supportedImage..."
        $offer = ($supportedImage -Split "-")[0]
        $sku = ($supportedImage -Split "-")[1]
        $_ = New-AzGalleryImageDefinition -GalleryName $config.dsvmImage.gallery.sig -ResourceGroupName $config.dsvmImage.gallery.rg -Name $supportedImage -Publisher Turing -Offer $offer -Sku $sku -Location $config.dsvmImage.location -OsState generalized -OsType Linux
    }
}


# Ensure that image exists in the image resource group
# ----------------------------------------------------
$image = Get-AzResource -ResourceType Microsoft.Compute/images -ResourceGroupName $config.dsvmImage.images.rg -Name $imageName
if (-Not $image) {
    Add-LogMessage -Level Error "Could not find an image called '$imageName' in resource group $($config.dsvmImage.images.rg)"
    Add-LogMessage -Level Info "Available images are:"
    foreach ($image in Get-AzResource -ResourceType Microsoft.Compute/images -ResourceGroupName $config.dsvmImage.images.rg) {
        Add-LogMessage -Level Info "  $($image.Name)"
    }
    throw "Could not find an image called '$imageName'!"
}


# Check which image definition to use
# -----------------------------------
Add-LogMessage -Level Info "Checking whether $($image.Name) is a supported image..."
$imageDefinition = $supportedImages | Where-Object { $image.Name -Like "*$_*" } | Select-Object -First 1
if (-Not $imageDefinition) {
    Add-LogMessage -Level Fatal "Could not identify $($image.Name) as a supported image"
}


# Determine the appropriate image version
# ---------------------------------------
Add-LogMessage -Level Info "[ ] Determining appropriate image version..."
if (-Not $imageVersion) {
    $baseImageVersion = "${majorVersion}.${minorVersion}.$(Get-Date -Format "yyyyMMdd")"
    $mostRecentImageVersion = Get-AzGalleryImageVersion -ResourceGroupName $config.dsvmImage.gallery.rg -GalleryName $config.dsvmImage.gallery.sig -GalleryImageDefinitionName $imageDefinition | Where-Object { $_.Name -Like "${baseImageVersion}*" } | ForEach-Object { $_.Name } | Sort-Object -Descending | Select-Object -First 1
    if ($mostRecentImageVersion) {
        $imageVersion = "${majorVersion}.${minorVersion}.$([int]($mostRecentImageVersion.Split('.')[2]) + 1)"
    } else {
        $imageVersion = "${baseImageVersion}00"
    }
}
Add-LogMessage -Level Success "Image version '$imageVersion' will be used"


# Create the image as a new version of the appropriate existing registered version
# --------------------------------------------------------------------------------
$targetRegions = @(
    @{Name="West Europe"; ReplicaCount=1},
    @{Name="UK South"; ReplicaCount=1},
    @{Name="UK West"; ReplicaCount=1}
)
Add-LogMessage -Level Info "[ ] Preparing to replicate $($image.Name) across $($targetRegions.Length) regions as version $imageVersion of $imageDefinition..."
Add-LogMessage -Level Info "Please note, this may take about 1 hour to complete"
$imageVersion = New-AzGalleryImageVersion -GalleryImageDefinitionName $imageDefinition `
                                          -GalleryImageVersionName "$imageVersion" `
                                          -GalleryName $config.dsvmImage.gallery.sig `
                                          -ResourceGroupName $config.dsvmImage.gallery.rg `
                                          -Location $config.dsvmImage.location `
                                          -TargetRegion $targetRegions  `
                                          -Source $image.Id.ToString() `
                                          -AsJob
$job = Get-Job -Command New-AzGalleryImageVersion | Sort-Object { $_.PSBeginTime } -Descending | Select-Object -First 1
while ($job.State -ne "Completed") {
    $progress = [math]::min(100, $progress + 1)
    Write-Progress -Activity "Replication status" -Status $job.State -PercentComplete $progress
    Start-Sleep 60
}


# Create the image as a new version of the appropriate existing registered version
# --------------------------------------------------------------------------------
Add-LogMessage -Level Info "Result of replication..."
Get-AzGalleryImageVersion -ResourceGroupName $config.dsvmImage.gallery.rg -GalleryName $config.dsvmImage.gallery.sig -GalleryImageDefinitionName $imageDefinition -Name "$imageVersion"


# Switch back to original subscription
# ------------------------------------
$_ = Set-AzContext -Context $originalContext
