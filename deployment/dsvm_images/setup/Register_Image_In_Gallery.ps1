param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID (usually a string e.g enter 'testa' for Turing Development Safe Haven A)")]
    [string]$shmId,
    [Parameter(Mandatory = $true, HelpMessage = "Specify an existing VM image to add to the gallery.")]
    [string]$imageName,
    [Parameter(Mandatory = $false, HelpMessage = "Override the automatically determined version number. Use with caution.")]
    [string]$imageVersion = $null
)

Import-Module Az -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Configuration -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Deployments -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Logging -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Security -Force -ErrorAction Stop


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-ShmConfig $shmId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.dsvmImage.subscription -ErrorAction Stop


# Useful constants
# ----------------
$supportedImages = @("ComputeVM-Ubuntu1804Base", "ComputeVM-Ubuntu2004Base")
$majorVersion = $config.dsvmImage.gallery.imageMajorVersion
$minorVersion = $config.dsvmImage.gallery.imageMinorVersion


# Ensure that gallery resource group exists
# -----------------------------------------
$null = Deploy-ResourceGroup -Name $config.dsvmImage.gallery.rg -Location $config.dsvmImage.location


# Ensure that image gallery exists
# --------------------------------
$null = Get-AzGallery -Name $config.dsvmImage.gallery.sig -ResourceGroupName $config.dsvmImage.gallery.rg -ErrorVariable notExists -ErrorAction SilentlyContinue
if ($notExists) {
    Add-LogMessage -Level Info "Creating image gallery $($config.dsvmImage.gallery.sig)..."
    $null = New-AzGallery -GalleryName $config.dsvmImage.gallery.sig -ResourceGroupName $config.dsvmImage.gallery.rg -Location $config.dsvmImage.location
}


# Set up list of image definitions we want to support
# ---------------------------------------------------
foreach ($supportedImage in $supportedImages) {
    $null = Get-AzGalleryImageDefinition -GalleryName $config.dsvmImage.gallery.sig -ResourceGroupName $config.dsvmImage.gallery.rg -Name $supportedImage -ErrorVariable notExists -ErrorAction SilentlyContinue
    if ($notExists) {
        Add-LogMessage -Level Info "Creating image definition $supportedImage..."
        $offer = ($supportedImage -Split "-")[0]
        $sku = ($supportedImage -Split "-")[1]
        $null = New-AzGalleryImageDefinition -GalleryName $config.dsvmImage.gallery.sig -ResourceGroupName $config.dsvmImage.gallery.rg -Name $supportedImage -Publisher Turing -Offer $offer -Sku $sku -Location $config.dsvmImage.location -OsState generalized -OsType Linux
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
    @{Name = "Central US"; ReplicaCount = 1 },
    @{Name = "UK South"; ReplicaCount = 1 },
    @{Name = "UK West"; ReplicaCount = 1 },
    @{Name = "West Europe"; ReplicaCount = 1 }
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
foreach ($imageStatus in Get-AzGalleryImageVersion -ResourceGroupName $config.dsvmImage.gallery.rg -GalleryName $config.dsvmImage.gallery.sig -GalleryImageDefinitionName $imageDefinition -Name "$imageVersion") {
    Add-LogMessage -Level Info ($imageStatus | Out-String)
}



# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext -ErrorAction Stop
