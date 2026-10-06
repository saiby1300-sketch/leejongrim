# Threads text publisher (Threads API). Reads the post text from threads_text.txt.
# Token comes from the THREADS_TOKEN environment variable, or you are asked to type it (hidden).
# -Yes skips the confirmation prompt (used by GitHub Actions).
param([switch]$Yes)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$base = "https://graph.threads.net/v1.0"

$token = $env:THREADS_TOKEN
if (-not $token) {
    $sec = Read-Host "Threads access token" -AsSecureString
    $token = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
}

$text = (Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot "threads_text.txt")).Trim()
if (-not $text) { throw "threads_text.txt is empty." }
if ($text.Length -gt 500) { throw "Text is $($text.Length) chars; Threads allows at most 500." }

function Invoke-TH($method, $path, $params) {
    $params["access_token"] = $token
    $pairs = $params.GetEnumerator() | ForEach-Object { "$($_.Key)=$([uri]::EscapeDataString([string]$_.Value))" }
    $qs = $pairs -join "&"
    if ($method -eq "GET") {
        return Invoke-RestMethod -Method Get -Uri "$base/$path`?$qs"
    }
    return Invoke-RestMethod -Method Post -Uri "$base/$path" -Body ([Text.Encoding]::UTF8.GetBytes($qs)) -ContentType "application/x-www-form-urlencoded; charset=utf-8"
}

$me = Invoke-TH "GET" "me" @{ fields = "id,username" }
Write-Host "Account : @$($me.username)"
Write-Host "Length  : $($text.Length) chars"
Write-Host "Text    :"
Write-Host $text
Write-Host ""
if (-not $Yes) {
    $ans = Read-Host "Publish this post publicly now? (yes/no)"
    if ($ans -ne "yes") { Write-Host "Cancelled."; exit }
}

$c = Invoke-TH "POST" "me/threads" @{ media_type = "TEXT"; text = $text }
Start-Sleep -Seconds 3
$pub = Invoke-TH "POST" "me/threads_publish" @{ creation_id = $c.id }
Write-Host "Published. Post id: $($pub.id)"
$link = Invoke-TH "GET" $pub.id @{ fields = "permalink" }
Write-Host $link.permalink
