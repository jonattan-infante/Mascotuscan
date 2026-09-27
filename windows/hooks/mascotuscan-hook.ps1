# Hook de Claude Code para mascotuscan en Windows.
#
# Claude Code invoca este script en cada evento (PreToolUse, PostToolUse,
# Notification, Stop, ...) y le pasa el payload JSON por stdin. El script traduce
# ese payload a una linea compacta y la agrega a %USERPROFILE%\.mascotuscan\shell.jsonl,
# que es de donde la mascota lee. Es el analogo Windows de shell/pet.zsh: en macOS
# la fuente es cmux; aqui, es Claude Code.
#
# Reglas de oro (heredadas del proyecto):
# - El hook NUNCA debe fallar ni bloquear: corre en el camino de Claude Code.
#   Todo va envuelto y siempre sale con codigo 0.
# - Un append a un archivo plano nunca bloquea a quien escribe.
#
# Uso (lo configura install-hooks.ps1, no hace falta llamarlo a mano):
#   powershell -NoProfile -ExecutionPolicy Bypass -File mascotuscan-hook.ps1

[CmdletBinding()]
param(
    [string]$Event = ""
)

$ErrorActionPreference = "SilentlyContinue"

try {
    $home_ = [Environment]::GetFolderPath("UserProfile")
    $dir = Join-Path $home_ ".mascotuscan"
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $log = Join-Path $dir "shell.jsonl"

    # Claude Code entrega el payload por stdin.
    $raw = [Console]::In.ReadToEnd()
    $payload = $null
    if ($raw) { try { $payload = $raw | ConvertFrom-Json } catch { $payload = $null } }

    $evName = $Event
    if ($payload -and $payload.hook_event_name) { $evName = $payload.hook_event_name }
    if (-not $evName) { exit 0 }

    # Solo los eventos que la mascota entiende. Cualquier otro se ignora.
    $known = @("SessionStart","SessionEnd","UserPromptSubmit","PreToolUse",
               "PostToolUse","Notification","Stop","SubagentStop")
    if ($known -notcontains $evName) { exit 0 }

    $rec = [ordered]@{
        ts      = [int64][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        event   = $evName
        session = if ($payload.session_id) { "$($payload.session_id)" } else { "?" }
        cwd     = if ($payload.cwd) { "$($payload.cwd)" } else { "$PWD" }
        tool    = if ($payload.tool_name) { "$($payload.tool_name)" } else { "" }
    }

    # A diferencia de cmux, Claude Code SI entrega tool_input: podemos mostrar el
    # comando real en el aviso de error. Se recorta para no volcar payloads enormes.
    if ($payload.tool_input -and $payload.tool_input.command) {
        $cmd = "$($payload.tool_input.command)"
        if ($cmd.Length -gt 80) { $cmd = $cmd.Substring(0, 80) }
        $rec.cmd = $cmd
    }
    if ($payload.message) { $rec.message = "$($payload.message)" }

    # Mejor esfuerzo para marcar error en un PostToolUse.
    if ($evName -eq "PostToolUse" -and $payload.tool_response) {
        $tr = $payload.tool_response
        if ($tr.is_error -or $tr.interrupted) { $rec.ok = $false }
    }

    $line = ($rec | ConvertTo-Json -Compress -Depth 4)
    Add-Content -Path $log -Value $line -Encoding utf8

    # Autoarranque: al empezar una sesion, levanta la mascota si no corre. Es el
    # equivalente al autostart de pet.zsh. Fire-and-forget, sin ventana.
    if ($evName -eq "SessionStart") {
        try {
            $petScript = Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) "pet.py"
            $pidFile = Join-Path $dir "pet.pid"
            $alive = $false
            if (Test-Path $pidFile) {
                $oldPid = (Get-Content $pidFile -Raw).Trim()
                if ($oldPid -and (Get-Process -Id $oldPid -ErrorAction SilentlyContinue)) { $alive = $true }
            }
            if ((-not $alive) -and (Test-Path $petScript)) {
                $py = (Get-Command pythonw.exe -ErrorAction SilentlyContinue)
                if (-not $py) { $py = (Get-Command python.exe -ErrorAction SilentlyContinue) }
                if ($py -and (-not $env:MASCOTUSCAN_NO_AUTOSTART)) {
                    Start-Process -FilePath $py.Source -ArgumentList "`"$petScript`"" -WindowStyle Hidden | Out-Null
                }
            }
        } catch { }
    }
}
catch { }

exit 0
