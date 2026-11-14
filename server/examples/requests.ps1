param([string]$BaseUrl = 'http://127.0.0.1:8080', [switch]$Explain)
$ErrorActionPreference = 'Stop'
# Synthetic data only. Reuse this exact payload/UUID on retry.
$profile = Invoke-RestMethod -Method Post -Uri "$BaseUrl/api/v1/profiles" -ContentType 'application/json' -Body '{"display_name":"Demo crew member"}'
$payload = @{
    client_session_id = [guid]::NewGuid().ToString()
    performed_at = [DateTime]::UtcNow.ToString('o')
    protocol_version = 'reaction-memory-v1'
    source = 'synthetic'
    survey = @{sleep_hours = 8; fatigue = 0; stress = 2; mood = 7}
    reaction = @{trials = @(@{outcome = 'valid'; reaction_ms = 200}, @{outcome = 'valid'; reaction_ms = 300}, @{outcome = 'missed'})}
    memory = @{correct = 3; total = 4}
} | ConvertTo-Json -Depth 10
$session = Invoke-RestMethod -Method Post -Uri "$BaseUrl/api/v1/profiles/$($profile.id)/sessions" -ContentType 'application/json' -Body $payload
$replay = Invoke-RestMethod -Method Post -Uri "$BaseUrl/api/v1/profiles/$($profile.id)/sessions" -ContentType 'application/json' -Body $payload
if ($session.id -ne $replay.id) { throw 'Retry created a duplicate session' }
$history = Invoke-RestMethod -Uri "$BaseUrl/api/v1/profiles/$($profile.id)/sessions?limit=20&offset=0"
$report = Invoke-RestMethod -Uri "$BaseUrl/api/v1/sessions/$($session.id)/report"
if ($Explain) {
    $outcome = Invoke-RestMethod -Method Post -Uri "$BaseUrl/api/v1/sessions/$($session.id)/explanation" -TimeoutSec 140
    $outcome | ConvertTo-Json -Depth 12
}
[pscustomobject]@{profile_id = $profile.id; session_id = $session.id; history_total = $history.total; median_ms = $report.reaction.median_ms; memory_percent = $report.memory_percent; html_report = "$BaseUrl/api/v1/sessions/$($session.id)/report.html"}
