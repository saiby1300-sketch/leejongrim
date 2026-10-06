# Posts a public reply to one Threads reply.
# Token comes from THREADS_TOKEN; the text comes from -Text or the REPLY_TEXT environment variable.
param([Parameter(Mandatory = $true)][string]$ReplyTo, [string]$Text = $env:REPLY_TEXT)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$base = "https://graph.threads.net/v1.0"
$token = $env:THREADS_TOKEN
if (-not $token) { throw "THREADS_TOKEN is not set." }
$Text = "$Text".Trim()
if (-not $Text) { throw "Reply text is empty." }
if ($Text.Length -gt 500) { throw "Reply is $($Text.Length) chars; Threads allows at most 500." }

function Invoke-TH($method, $path, $params) {
    $params["access_token"] = $token
    $pairs = $params.GetEnumerator() | ForEach-Object { "$($_.Key)=$([uri]::EscapeDataString([string]$_.Value))" }
    $qs = $pairs -join "&"
    if ($method -eq "GET") { return Invoke-RestMethod -Method Get -Uri "$base/$path`?$qs" }
    return Invoke-RestMethod -Method Post -Uri "$base/$path" -Body ([Text.Encoding]::UTF8.GetBytes($qs)) -ContentType "application/x-www-form-urlencoded; charset=utf-8"
}

$c = Invoke-TH "POST" "me/threads" @{ media_type = "TEXT"; text = $Text; reply_to_id = $ReplyTo }
Start-Sleep -Seconds 3
$pub = Invoke-TH "POST" "me/threads_publish" @{ creation_id = $c.id }
Write-Host "Replied. Post id: $($pub.id)"
$link = Invoke-TH "GET" $pub.id @{ fields = "permalink" }
Write-Host $link.permalink
