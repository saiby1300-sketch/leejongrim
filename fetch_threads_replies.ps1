# Collects replies to my recent Threads posts into replies_threads.json.
# Token comes from the THREADS_TOKEN environment variable.
# "pending" lists replies from other people that I have not answered yet.
param([int]$Posts = 10)

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

$me = Invoke-TH "me" @{ fields = "id,username" }
$mine = Invoke-TH "me/threads" @{ fields = "id,text,timestamp,permalink"; limit = $Posts }

$out = @()
$pending = @()
foreach ($p in $mine.data) {
    $conv = Invoke-TH "$($p.id)/conversation" @{ fields = "id,text,username,timestamp,reply_to_id,permalink"; reverse = "false" }
    $items = @($conv.data)
    foreach ($i in $items) {
        if ($i.username -ne $me.username) {
            # answered = I have a direct reply under this comment (reply_to_id is not always set in /conversation)
            $kids = Invoke-TH "$($i.id)/replies" @{ fields = "id,username" }
            if (@($kids.data | Where-Object { $_.username -eq $me.username }).Count -gt 0) { continue }
            $pending += [pscustomobject]@{
                reply_id = $i.id; username = $i.username; text = $i.text; timestamp = $i.timestamp
                reply_to_id = $i.reply_to_id; permalink = $i.permalink
                post_id = $p.id; post_text = $p.text
            }
        }
    }
    $out += [pscustomobject]@{ post_id = $p.id; text = $p.text; permalink = $p.permalink; reply_count = $items.Count }
}

$result = [pscustomobject]@{
    account = $me.username
    fetched_at = (Get-Date).ToUniversalTime().ToString("o")
    pending_count = $pending.Count
    pending = $pending
    posts = $out
}
$result | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 (Join-Path $PSScriptRoot "replies_threads.json")
Write-Host "Posts checked: $($out.Count), pending replies: $($pending.Count)"
