param(
    [Parameter(Position = 0, HelpMessage = "Type of synchronisation ('Initial' or 'Delta')")]
    [ValidateSet("Initial", "Delta")]
    [String]
    $sync = "Delta"
)

Import-Module -Name "C:\Program Files\Microsoft Azure AD Sync\Bin\ADSync" -ErrorAction Stop
Start-ADSyncSyncCycle -PolicyType $sync
