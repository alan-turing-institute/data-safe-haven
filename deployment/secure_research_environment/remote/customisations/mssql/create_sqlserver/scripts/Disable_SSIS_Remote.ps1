# MsDtsServer150 and SSISTelemetry150 are the names of the SSIS services for SQL 2019
$ssisServices = Get-Service | Where-Object {($_.Name -like 'MsDtsServer150') -or ($_.Name -like 'SSISTelemetry150')}

foreach($ssisService in $ssisServices) {
    if ($ssisService.Status -eq "Running") {     
        Stop-Service $ssisService                
    }
    
    Set-Service -StartupType Disabled $ssisService.Name       
}