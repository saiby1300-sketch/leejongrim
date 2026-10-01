# Fetch recent Instagram posts and their comments (read-only) and write comments.json
# Token comes from the IG_TOKEN environment variable (GitHub Secret). Nothing is posted.

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$base = "https://graph.instagram.com/v21.0"
$token = $env:IG_TOKEN
if (-not $token) { throw "IG_TOKEN is not set" }

function Invoke-IG($path, $params) {
    $params["access_token"] = $token
    $pairs = $params.GetEnumerator() | ForEach-Object { "$($_.Key)=$([uri]::EscapeDataString([string]$_.Value))" }
    return Invoke-RestMethod -Method Get -Uri "$base/$path`?$($pairs -join '&')"
}

$media = Invoke-IG "me/media" @{ fields = "id,caption,permalink,timestamp,comments_count"; limit = "10" }
$out = @()
foreach ($m in $media.data) {
    $cap = ""
    if ($m.caption) { $cap = ($m.caption -split "`n")[0] }
    $item = [ordered]@{ media_id = $m.id; permalink = $m.permalink; posted = $m.timestamp; title = $cap; comments_count = $m.comments_count; comments = @() }
    try {
        $c = Invoke-IG "$($m.id)/comments" @{ fields = "id,text,username,timestamp"; limit = "50" }
        if ($m.comments_count -gt 0 -and (-not $c.data -or $c.data.Count -eq 0)) {
            $item["raw_response"] = ($c | ConvertTo-Json -Depth 6 -Compress)
            try {
                $alt = Invoke-IG $m.id @{ fields = "comments{id,text,username,timestamp}" }
                $item["raw_expand"] = ($alt | ConvertTo-Json -Depth 8 -Compress)
                if ($alt.comments -and $alt.comments.data) { $c = $alt.comments }
            } catch {
                $item["raw_expand"] = "ERROR: " + $_.Exception.Message
            }
        }
        foreach ($x in $c.data) {
            $replies = @()
            if ($x.replies -and $x.replies.data) {
                foreach ($r in $x.replies.data) {
                    $replies += [ordered]@{ id = $r.id; username = $r.username; text = $r.text; timestamp = $r.timestamp }
                }
            }
            $item.comments += [ordered]@{ id = $x.id; username = $x.username; text = $x.text; timestamp = $x.timestamp; replies = $replies }
        }
    } catch {
        $item["error"] = $_.Exception.Message
    }
    $out += $item
}

$json = [ordered]@{ fetched_at = (Get-Date).ToUniversalTime().ToString("o"); posts = $out } | ConvertTo-Json -Depth 8
Set-Content -Path "comments.json" -Value $json -Encoding UTF8
$count = ($out | ForEach-Object { $_.comments.Count } | Measure-Object -Sum).Sum
Write-Host "Posts: $($out.Count)  Comments: $count"
