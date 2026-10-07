# Looks at the latest posts of people who commented on my Threads posts (profile discovery API).
# Writes visit_candidates.json. Token comes from THREADS_TOKEN. Usernames already in .visited_threads are skipped.
param([int]$Max = 3, [int]$PostsEach = 3)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$base = "https://graph.threads.net/v1.0"
$token = $env:THREADS_TOKEN
if (-not $token) { throw "THREADS_TOKEN is not set." }

function Invoke-TH($path, $params) {
    $params["access_token"] = $token
    $pairs = $params.GetEnumerator() | ForEach-Object { "$($_.Key)=$([uri]::EscapeDataString([string]$_.Value))" }
    return Invoke-RestMethod -Method Get -Uri "$base/$path`?$($pairs -join '&')"
}

# Diagnostic: if probe_user.txt exists, test profile_posts for that one username and exit.
$pf = Join-Path $PSScriptRoot "probe_user.txt"
if (Test-Path $pf) {
    $pu = (Get-Content $pf -Raw).Trim()
    try {
        $t = Invoke-TH "profile_posts" @{ username = $pu; fields = "id,timestamp"; limit = 1 }
        $res = "OK ($(@($t.data).Count) posts)"
    } catch {
        $m = if ($_.ErrorDetails.Message) { $_.ErrorDetails.Message } else { $_.Exception.Message }
        $res = "FAIL " + ($m -replace '\s+',' ')
    }
    exit 0
}
$visited = @()
$vf = Join-Path $PSScriptRoot ".visited_threads"
if (Test-Path $vf) { $visited = @(Get-Content $vf) }

$me = Invoke-TH "me" @{ fields = "id,username" }
$mine = Invoke-TH "me/threads" @{ fields = "id"; limit = 10 }

$names = [ordered]@{}
foreach ($p in $mine.data) {
    $conv = Invoke-TH "$($p.id)/conversation" @{ fields = "id,username,text" }
    foreach ($i in @($conv.data)) {
        if ($i.username -and $i.username -ne $me.username -and -not $names.Contains($i.username)) {
            $names[$i.username] = $i.text
        }
    }
}

$cands = @()
$errors = @()
foreach ($u in $names.Keys) {
    if ($visited -contains $u) { continue }
    if ($cands.Count -ge $Max) { break }
    try {
        $posts = Invoke-TH "profile_posts" @{ username = $u; fields = "id,text,timestamp,permalink,media_type,is_reply"; limit = $PostsEach }
        $cands += [pscustomobject]@{ username = $u; their_comment = $names[$u]; posts = @($posts.data) }
    } catch {
        $msg = if ($_.ErrorDetails.Message) { $_.ErrorDetails.Message } else { $_.Exception.Message }
        $errors += [pscustomobject]@{ username = $u; error = $msg }
        break
    }
}

[pscustomobject]@{
    fetched_at = (Get-Date).ToUniversalTime().ToString("o")
    commenters_total = $names.Count
    candidates = $cands
    errors = $errors
} | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 (Join-Path $PSScriptRoot "visit_candidates.json")
Write-Host "Commenters: $($names.Count), candidates: $($cands.Count), errors: $($errors.Count)"