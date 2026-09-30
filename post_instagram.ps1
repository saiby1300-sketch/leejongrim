# Instagram carousel publisher (Instagram API with Instagram Login)
# Token is NOT stored in this file. Set it in your own terminal session:
#   $env:IG_TOKEN = "your token"
# or leave it unset and you will be asked to type it (hidden).
# -Yes skips the confirmation prompt (used by GitHub Actions).
param([switch]$Yes)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$base = "https://graph.instagram.com/v21.0"
$imgBase = "https://raw.githubusercontent.com/saiby1300-sketch/leejongrim/main/cards_jpg"
$count = 9

$token = $env:IG_TOKEN
if (-not $token) {
    $sec = Read-Host "Instagram access token" -AsSecureString
    $token = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
}

$caption = (Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot "caption.txt")).Trim()

function Invoke-IG($method, $path, $params) {
    $params["access_token"] = $token
    $pairs = $params.GetEnumerator() | ForEach-Object { "$($_.Key)=$([uri]::EscapeDataString([string]$_.Value))" }
    $qs = $pairs -join "&"
    if ($method -eq "GET") {
        return Invoke-RestMethod -Method Get -Uri "$base/$path`?$qs"
    }
    return Invoke-RestMethod -Method Post -Uri "$base/$path" -Body ([Text.Encoding]::UTF8.GetBytes($qs)) -ContentType "application/x-www-form-urlencoded; charset=utf-8"
}

function Wait-Container($id) {
    for ($i = 0; $i -lt 30; $i++) {
        $s = Invoke-IG "GET" $id @{ fields = "status_code" }
        if ($s.status_code -eq "FINISHED") { return }
        if ($s.status_code -eq "ERROR" -or $s.status_code -eq "EXPIRED") { throw "Container $id status: $($s.status_code)" }
        Start-Sleep -Seconds 2
    }
    throw "Timed out waiting for container $id"
}

$me = Invoke-IG "GET" "me" @{ fields = "user_id,username" }
Write-Host "Account : @$($me.username)"
Write-Host "Images  : $count (cards_jpg/card_1..$count.jpg)"
Write-Host "Caption :"
Write-Host $caption
Write-Host ""
if (-not $Yes) {
    $ans = Read-Host "Publish this carousel publicly now? (yes/no)"
    if ($ans -ne "yes") { Write-Host "Cancelled."; exit }
}

$children = @()
for ($n = 1; $n -le $count; $n++) {
    $r = Invoke-IG "POST" "me/media" @{ image_url = "$imgBase/card_$n.jpg"; is_carousel_item = "true" }
    $children += $r.id
    Write-Host "Item $n created: $($r.id)"
}
foreach ($c in $children) { Wait-Container $c }

$car = Invoke-IG "POST" "me/media" @{ media_type = "CAROUSEL"; children = ($children -join ","); caption = $caption }
Wait-Container $car.id

$pub = Invoke-IG "POST" "me/media_publish" @{ creation_id = $car.id }
Write-Host "Published. Media id: $($pub.id)"
$link = Invoke-IG "GET" $pub.id @{ fields = "permalink" }
Write-Host $link.permalink
