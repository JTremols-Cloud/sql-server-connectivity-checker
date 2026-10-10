<#
.SYNOPSIS
    Checks the most common reasons a client can't connect to a SQL Server instance.

.DESCRIPTION
    Runs on the SQL Server machine and checks, in order:
      1. Is the SQL Server service running?
      2. Is the SQL Browser service running? (needed for named instances)
      3. Is the TCP/IP protocol enabled, and which port is it using?
      4. Is SQL Server actually listening on that port?
      5. Is there an inbound Windows Firewall rule allowing that port?
      6. (Optional) Can we log in and run a query?

    Each check prints PASS, WARN, or FAIL with a short explanation of what to fix.

.PARAMETER InstanceName
    The SQL instance to check. Use MSSQLSERVER for the default instance,
    or the instance name (for example SQLEXPRESS) for a named instance.

.PARAMETER TestLogin
    Also try to log in with Windows authentication and run SELECT @@VERSION.

.EXAMPLE
    .\Test-SqlConnectivity.ps1 -InstanceName SQLEXPRESS

.EXAMPLE
    .\Test-SqlConnectivity.ps1 -InstanceName SQLEXPRESS -TestLogin
#>

param(
    [string]$InstanceName = 'MSSQLSERVER',
    [switch]$TestLogin
)

# Every check adds one row to this list. We print them all at the end.
$results = New-Object System.Collections.Generic.List[object]

function Add-Result {
    param([string]$Check, [string]$Status, [string]$Detail)
    $results.Add([pscustomobject]@{ Check = $Check; Status = $Status; Detail = $Detail })
}

$isDefault = $InstanceName -eq 'MSSQLSERVER'

# The Windows service name is different for default vs. named instances.
if ($isDefault) { $serviceName = 'MSSQLSERVER' } else { $serviceName = "MSSQL`$$InstanceName" }

# --- Check 1: SQL Server service -------------------------------------------
$sqlService = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if (-not $sqlService) {
    Add-Result 'SQL Server service' 'FAIL' "Service '$serviceName' not found. Check the instance name."
}
elseif ($sqlService.Status -eq 'Running') {
    Add-Result 'SQL Server service' 'PASS' "'$serviceName' is running."
}
else {
    Add-Result 'SQL Server service' 'FAIL' "'$serviceName' is $($sqlService.Status). Start it in services.msc or SQL Server Configuration Manager."
}

# --- Check 2: SQL Browser service ------------------------------------------
# Named instances use SQL Browser (UDP 1434) to tell clients which port to use.
$browser = Get-Service -Name 'SQLBrowser' -ErrorAction SilentlyContinue
if ($isDefault) {
    Add-Result 'SQL Browser service' 'PASS' 'Not required for the default instance.'
}
elseif ($browser -and $browser.Status -eq 'Running') {
    Add-Result 'SQL Browser service' 'PASS' 'SQLBrowser is running.'
}
else {
    Add-Result 'SQL Browser service' 'WARN' 'SQLBrowser is not running. Clients must connect with an explicit port (server,port).'
}

# --- Check 3: TCP/IP protocol and port (read from the registry) ------------
# SQL Server stores its network settings under an internal instance ID,
# for example MSSQL16.SQLEXPRESS. First look up that ID, then read the TCP settings.
$port = $null
$instanceId = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL' -ErrorAction SilentlyContinue).$InstanceName

if (-not $instanceId) {
    Add-Result 'TCP/IP protocol' 'FAIL' "No registry entry for instance '$InstanceName'."
}
else {
    $tcpKey = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$instanceId\MSSQLServer\SuperSocketNetLib\Tcp"
    $tcpEnabled = (Get-ItemProperty $tcpKey -ErrorAction SilentlyContinue).Enabled
    $ipAll = Get-ItemProperty "$tcpKey\IPAll" -ErrorAction SilentlyContinue

    # A static port wins; otherwise SQL Server picks a dynamic port at startup.
    if ($ipAll.TcpPort) { $port = [int](($ipAll.TcpPort -split ',')[0]) }
    elseif ($ipAll.TcpDynamicPorts) { $port = [int](($ipAll.TcpDynamicPorts -split ',')[0]) }

    if ($tcpEnabled -ne 1) {
        Add-Result 'TCP/IP protocol' 'FAIL' 'TCP/IP is disabled. Enable it in SQL Server Configuration Manager, then restart the service.'
    }
    elseif ($ipAll.TcpPort) {
        Add-Result 'TCP/IP protocol' 'PASS' "Enabled on static port $port."
    }
    elseif ($port) {
        Add-Result 'TCP/IP protocol' 'WARN' "Enabled on dynamic port $port. This can change on restart; set a static port for reliable firewall rules."
    }
    else {
        Add-Result 'TCP/IP protocol' 'WARN' 'Enabled, but no port is assigned yet. Restart the SQL Server service.'
    }
}

# --- Check 4: Is SQL Server listening on the port? -------------------------
if ($port) {
    $listening = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
    if ($listening) {
        Add-Result 'Port listening' 'PASS' "Something is listening on TCP $port."
    }
    else {
        Add-Result 'Port listening' 'FAIL' "Nothing is listening on TCP $port. The service may be stopped or need a restart."
    }
}
else {
    Add-Result 'Port listening' 'WARN' 'Skipped: no port found in check 3.'
}

# --- Check 5: Windows Firewall inbound rule --------------------------------
if ($port) {
    $rules = Get-NetFirewallPortFilter -Protocol TCP -ErrorAction SilentlyContinue |
        Where-Object { $_.LocalPort -eq "$port" } |
        Get-NetFirewallRule -ErrorAction SilentlyContinue |
        Where-Object { $_.Enabled -eq 'True' -and $_.Direction -eq 'Inbound' -and $_.Action -eq 'Allow' }

    if ($rules) {
        Add-Result 'Firewall rule' 'PASS' "Inbound allow rule found: $(($rules.DisplayName) -join ', ')."
    }
    else {
        Add-Result 'Firewall rule' 'WARN' "No enabled inbound rule for TCP $port. Remote clients will likely be blocked (local connections still work)."
    }
}
else {
    Add-Result 'Firewall rule' 'WARN' 'Skipped: no port found in check 3.'
}

# --- Check 6 (optional): log in and run a query ----------------------------
if ($TestLogin) {
    if ($isDefault) { $server = 'localhost' } else { $server = "localhost\$InstanceName" }
    $conn = New-Object System.Data.SqlClient.SqlConnection "Server=$server;Integrated Security=True;Connect Timeout=5"
    try {
        $conn.Open()
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = 'SELECT @@VERSION'
        $version = ($cmd.ExecuteScalar() -split "`n")[0].Trim()
        Add-Result 'Login test' 'PASS' "Connected to $server. $version"
    }
    catch {
        Add-Result 'Login test' 'FAIL' "Could not log in to ${server}: $($_.Exception.Message)"
    }
    finally {
        $conn.Dispose()
    }
}

# --- Report ----------------------------------------------------------------
Write-Host ''
Write-Host "SQL Server connectivity check: $env:COMPUTERNAME\$InstanceName" -ForegroundColor Cyan
Write-Host ('-' * 60)

foreach ($r in $results) {
    switch ($r.Status) {
        'PASS' { $color = 'Green' }
        'WARN' { $color = 'Yellow' }
        default { $color = 'Red' }
    }
    Write-Host ('[{0}] ' -f $r.Status) -ForegroundColor $color -NoNewline
    Write-Host ('{0}: {1}' -f $r.Check, $r.Detail)
}

$fails = @($results | Where-Object Status -eq 'FAIL').Count
$warns = @($results | Where-Object Status -eq 'WARN').Count
Write-Host ('-' * 60)
if ($fails -eq 0 -and $warns -eq 0) { $summaryColor = 'Green' } elseif ($fails -eq 0) { $summaryColor = 'Yellow' } else { $summaryColor = 'Red' }
Write-Host "Result: $fails failed, $warns warnings" -ForegroundColor $summaryColor
Write-Host ''
