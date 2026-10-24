# Return the first reachable, explicitly configured local HTTP proxy.
# Do not scan unrelated ports, resolve PAC scripts, or accept proxy credentials.
$settings = Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction SilentlyContinue
$candidates = @()
if ($settings.ProxyEnable -eq 1 -and $settings.ProxyServer) {
    foreach ($entry in ([string]$settings.ProxyServer -split ';')) {
        if ($entry.Trim() -match '^(?:(?:http|https)=)?(?<address>[^=]+)$') {
            $candidates += [pscustomobject]@{ Address = $Matches.address.Trim(); Source = 'Windows system proxy' }
        }
    }
}
foreach ($name in @('HTTPS_PROXY', 'HTTP_PROXY', 'ALL_PROXY')) {
    $value = [Environment]::GetEnvironmentVariable($name, 'Process')
    if ($value) { $candidates += [pscustomobject]@{ Address = $value.Trim(); Source = $name } }
}

foreach ($candidate in $candidates) {
    $address = $candidate.Address
    if ($address -notmatch '^[a-z][a-z0-9+.-]*://') { $address = 'http://' + $address }
    $uri = $null
    if (-not [Uri]::TryCreate($address, [UriKind]::Absolute, [ref]$uri)) { continue }
    if ($uri.Scheme -ne 'http' -or $uri.Host -notin @('127.0.0.1', 'localhost') -or
        $uri.Port -lt 1 -or $uri.Port -gt 65535 -or $uri.UserInfo -or $uri.Query -or
        $uri.Fragment -or $uri.AbsolutePath -ne '/') { continue }
    $client = New-Object Net.Sockets.TcpClient
    try {
        $connection = $client.ConnectAsync('127.0.0.1', $uri.Port)
        if ($connection.Wait(400) -and $client.Connected) {
            return [pscustomobject]@{ Port = $uri.Port; Source = $candidate.Source }
        }
    } catch {
        # Try the next explicitly configured source if this one is unreachable.
    } finally { $client.Dispose() }
}
