<#
.SYNOPSIS
    Lance TOUTE la pipeline de review automatisée (docs/REVIEW.md) en une
    seule commande et produit un rapport HTML unique (reports/review/<horodatage>/index.html)
    qu'une IA ou un humain peut ouvrir pour juger l'état du jeu.

.DESCRIPTION
    Orchestre, dans l'ordre : import du projet, tests unitaires gdUnit4,
    sonde de gameplay, fumée réseau (2 process), fumée de bots, captures de
    maps/UI/viewmodel-armes/personnages, masques de style (HUD/personnages/
    viewmodel), benchmark de performance, scan des logs, scoreur de la
    checklist de style (docs/STYLE_BIBLE.md §11, CHK-01 à CHK-47), puis
    génération du rapport. Chaque étape a son propre timeout, écrit son log
    dans <out>/logs/<étape>.log, et n'interrompt JAMAIS le reste de la
    pipeline si elle échoue, plante ou dépasse son délai — le but est un
    rapport qui reflète l'état réel, y compris les trous.

.PARAMETER Quick
    Ne lance que tests + sondes + fumées (import, unit_tests, gameplay_probe,
    net_smoke, bot_smoke) + log_scan + report. Saute tout ce qui demande une
    fenêtre (captures d'écran, benchmark) — boucle rapide pendant le dev.

.PARAMETER Only
    Liste d'étapes séparées par des virgules à exécuter, parmi : unit_tests,
    gameplay_probe, net_smoke, bot_smoke, map_shots, ui_shots,
    viewmodel_fp_shots, character_shots, style_masks, perf_bench. `import`,
    `log_scan`, `style_check` et `report` tournent TOUJOURS (bootstrap requis
    / scoreur de style et rapport toujours produits), même si absents de la
    liste. Prioritaire sur -Quick.

.PARAMETER Out
    Dossier de sortie. Par défaut reports/review/<yyyyMMdd-HHmmss> (chemin
    relatif résolu depuis la racine du dépôt). reports/ est gitignored.

.EXAMPLE
    powershell -File tools/review/run_review.ps1 -Quick
.EXAMPLE
    powershell -File tools/review/run_review.ps1
.EXAMPLE
    powershell -File tools/review/run_review.ps1 -Only unit_tests,map_shots
#>
param(
	[switch]$Quick,
	[string]$Only = "",
	[string]$Out = ""
)

$ErrorActionPreference = "Stop"

# =====================================================================
#  Résolution des chemins / outils
# =====================================================================

$RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)  # tools/review -> tools -> racine du dépôt

$GodotBin = if ($env:GODOT_BIN) { $env:GODOT_BIN } else { "C:\Users\srko\Desktop\Godot_v4.7-stable_win64.exe" }

function Get-PythonBin {
	foreach ($candidate in @('python', 'python3')) {
		$cmd = Get-Command $candidate -ErrorAction SilentlyContinue
		if ($cmd) { return $cmd.Source }
	}
	return $null
}
$PythonBin = Get-PythonBin

if (-not $Out) {
	$Out = Join-Path $RepoRoot ("reports\review\{0}" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
} elseif (-not [System.IO.Path]::IsPathRooted($Out)) {
	$Out = Join-Path $RepoRoot $Out
}
New-Item -ItemType Directory -Force -Path $Out | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $Out "logs") | Out-Null
$OutGodot = $Out -replace '\\', '/'   # convention forward-slash des outils tools/*.gd existants

Write-Host "=== REVIEW PIPELINE ===" -ForegroundColor Cyan
Write-Host "repo   : $RepoRoot"
Write-Host "godot  : $GodotBin$(if (-not (Test-Path $GodotBin)) { ' (INTROUVABLE)' })"
Write-Host "python : $(if ($PythonBin) { $PythonBin } else { 'INTROUVABLE — log_scan et report seront sautés' })"
Write-Host "out    : $Out"
Write-Host ""

# =====================================================================
#  Utilitaires process (timeout par étape, jamais bloquant pour le reste)
# =====================================================================

function Quote-Arg([string]$s) {
	if ($s -match '[\s"]') { return '"' + ($s -replace '"', '\"') + '"' }
	return $s
}
function Join-Args([string[]]$parts) {
	return ($parts | ForEach-Object { Quote-Arg $_ }) -join ' '
}

## Démarre un process avec stdout+stderr redirigés en direct vers un fichier
## de log unique (ordre chronologique réel via les événements .NET, pas une
## simple concaténation après coup). Ne bloque pas — voir Wait-ProcHandle.
function Start-ProcHandle {
	param(
		[string]$FilePath,
		[string]$Arguments,
		[string]$LogPath,
		[string]$WorkingDirectory = $RepoRoot
	)
	$psi = New-Object System.Diagnostics.ProcessStartInfo
	$psi.FileName = $FilePath
	$psi.Arguments = $Arguments
	$psi.WorkingDirectory = $WorkingDirectory
	$psi.RedirectStandardOutput = $true
	$psi.RedirectStandardError = $true
	$psi.UseShellExecute = $false
	$psi.CreateNoWindow = $true

	$proc = New-Object System.Diagnostics.Process
	$proc.StartInfo = $psi
	$proc.EnableRaisingEvents = $true

	# UTF8Encoding($false) : PAS de BOM — [System.Text.Encoding]::UTF8 en écrirait un,
	# ce qui polluerait la toute première ligne de chaque log pour log_scan.py.
	$writer = New-Object System.IO.StreamWriter($LogPath, $false, (New-Object System.Text.UTF8Encoding($false)))
	$writer.AutoFlush = $true
	$syncWriter = [System.IO.TextWriter]::Synchronized($writer)

	$action = {
		if ($null -ne $EventArgs.Data) { $Event.MessageData.WriteLine($EventArgs.Data) }
	}
	$subOut = Register-ObjectEvent -InputObject $proc -EventName OutputDataReceived -Action $action -MessageData $syncWriter
	$subErr = Register-ObjectEvent -InputObject $proc -EventName ErrorDataReceived -Action $action -MessageData $syncWriter

	$sw = [System.Diagnostics.Stopwatch]::StartNew()
	try {
		[void]$proc.Start()
		$proc.BeginOutputReadLine()
		$proc.BeginErrorReadLine()
		$startError = $null
	} catch {
		$startError = $_.Exception.Message
	}

	return [PSCustomObject]@{
		Process    = $proc
		Writer     = $syncWriter
		Subs       = @($subOut, $subErr)
		Stopwatch  = $sw
		LogPath    = $LogPath
		StartError = $startError
	}
}

## Attend la fin d'un process démarré par Start-ProcHandle, jusqu'à
## $TimeoutSec ; au-delà, tue l'arbre de process (taskkill /T) — un timeout
## n'est jamais une exception qui casse la pipeline, juste un statut.
function Wait-ProcHandle {
	param($Handle, [int]$TimeoutSec)

	if ($Handle.StartError) {
		foreach ($s in $Handle.Subs) { Unregister-Event -SourceIdentifier $s.Name -ErrorAction SilentlyContinue }
		try { $Handle.Writer.WriteLine("[run_review] échec du démarrage du process : $($Handle.StartError)"); $Handle.Writer.Flush(); $Handle.Writer.Close() } catch {}
		return [PSCustomObject]@{ ExitCode = -1; TimedOut = $false; DurationSec = 0.0; StartError = $Handle.StartError }
	}

	$exited = $false
	try { $exited = $Handle.Process.WaitForExit($TimeoutSec * 1000) } catch {}
	$timedOut = -not $exited
	if ($timedOut) {
		try { & taskkill /PID $($Handle.Process.Id) /T /F 2>$null | Out-Null } catch {}
		try { $Handle.Process.WaitForExit(5000) | Out-Null } catch {}
	}
	$Handle.Stopwatch.Stop()
	Start-Sleep -Milliseconds 200  # laisse les derniers événements stdout/stderr s'écrire avant de fermer le fichier
	foreach ($s in $Handle.Subs) { Unregister-Event -SourceIdentifier $s.Name -ErrorAction SilentlyContinue }

	$exitCode = -1
	if (-not $timedOut) {
		try { $exitCode = $Handle.Process.ExitCode } catch { $exitCode = -1 }
	}
	try { $Handle.Writer.Flush(); $Handle.Writer.Close() } catch {}

	return [PSCustomObject]@{
		ExitCode    = $exitCode
		TimedOut    = $timedOut
		DurationSec = [math]::Round($Handle.Stopwatch.Elapsed.TotalSeconds, 2)
		StartError  = $null
	}
}

## Un process, du début à la fin, avec timeout — le cas courant (une seule
## commande godot/python par étape).
function Invoke-Simple {
	param([string]$FilePath, [string]$Arguments, [string]$LogPath, [int]$TimeoutSec, [string]$WorkingDirectory = $RepoRoot)
	$h = Start-ProcHandle -FilePath $FilePath -Arguments $Arguments -LogPath $LogPath -WorkingDirectory $WorkingDirectory
	return Wait-ProcHandle -Handle $h -TimeoutSec $TimeoutSec
}

function New-StepResult {
	param(
		[string]$Name, [string]$Status, $ExitCode = $null, [bool]$TimedOut = $false,
		[double]$DurationSec = 0.0, [string[]]$Logs = @(), [string]$Note = "", [string]$Artifact = ""
	)
	[PSCustomObject]@{
		name         = $Name
		status       = $Status        # ok | warn | fail | missing | error
		exit_code    = $ExitCode
		timed_out    = $TimedOut
		duration_sec = $DurationSec
		logs         = $Logs
		note         = $Note
		artifact     = $Artifact      # dossier relatif à $Out, si l'étape écrit ses propres artefacts
	}
}

# =====================================================================
#  Étapes
# =====================================================================

function Step-Import {
	$log = Join-Path $Out "logs\import.log"
	$r = Invoke-Simple -FilePath $GodotBin -Arguments (Join-Args @('--headless', '--path', '.', '--import')) -LogPath $log -TimeoutSec 180
	$status = if ($r.StartError) { 'error' } elseif ($r.TimedOut) { 'fail' } elseif ($r.ExitCode -eq 0) { 'ok' } else { 'warn' }
	New-StepResult -Name 'import' -Status $status -ExitCode $r.ExitCode -TimedOut $r.TimedOut -DurationSec $r.DurationSec -Logs @('logs/import.log') -Note $(if ($r.StartError) { $r.StartError } else { '' })
}

function Step-UnitTests {
	$log = Join-Path $Out "logs\unit_tests.log"
	$args = Join-Args @('--headless', '--path', '.', '-s', '-d', '--remote-debug', 'tcp://127.0.0.1:1',
		'res://addons/gdUnit4/bin/GdUnitCmdTool.gd', '-a', 'res://tests', '-c', '--ignoreHeadlessMode')
	$before = @{}
	Get-ChildItem -Path (Join-Path $RepoRoot 'reports') -Directory -Filter 'report_*' -ErrorAction SilentlyContinue |
		ForEach-Object { $before[$_.Name] = $true }
	$r = Invoke-Simple -FilePath $GodotBin -Arguments $args -LogPath $log -TimeoutSec 300

	# gdUnit4 : 0 = tout passe, 100 = échecs, 101 = avertissements seuls.
	$status = if ($r.StartError) { 'error' }
		elseif ($r.TimedOut) { 'fail' }
		elseif ($r.ExitCode -eq 0) { 'ok' }
		elseif ($r.ExitCode -eq 101) { 'warn' }
		else { 'fail' }

	$note = ''
	$latest = Get-ChildItem -Path (Join-Path $RepoRoot 'reports') -Directory -Filter 'report_*' -ErrorAction SilentlyContinue |
		Where-Object { $_.Name -match '^report_(\d+)$' } |
		Sort-Object { [int]($_.Name -replace '^report_', '') } -Descending |
		Select-Object -First 1
	if ($latest) {
		$dest = Join-Path $Out 'unit_tests'
		New-Item -ItemType Directory -Force -Path $dest | Out-Null
		try {
			Copy-Item -Path (Join-Path $latest.FullName '*') -Destination $dest -Recurse -Force
			@{ report_dir = $latest.Name; source_path = $latest.FullName } | ConvertTo-Json | Set-Content -Path (Join-Path $dest 'meta.json') -Encoding UTF8
		} catch {
			$note = "copie du rapport gdUnit4 ($($latest.Name)) échouée : $($_.Exception.Message)"
		}
	} else {
		$note = 'aucun reports/report_<n> trouvé après exécution (gdUnit4 a-t-il bien tourné ?)'
	}
	New-StepResult -Name 'unit_tests' -Status $status -ExitCode $r.ExitCode -TimedOut $r.TimedOut -DurationSec $r.DurationSec -Logs @('logs/unit_tests.log') -Note $note -Artifact 'unit_tests'
}

## Étape du contrat parallèle : tools/review/gameplay_probe.gd (headless).
function Step-GameplayProbe {
	$scriptRel = 'tools/review/gameplay_probe.gd'
	if (-not (Test-Path (Join-Path $RepoRoot $scriptRel))) {
		return New-StepResult -Name 'gameplay_probe' -Status 'missing' -Note "$scriptRel absent (livré par l'agent parallèle) — étape sautée"
	}
	$log = Join-Path $Out "logs\gameplay_probe.log"
	$outDir = "$OutGodot/gameplay_probe"
	$args = Join-Args @('--headless', '--path', '.', '-s', $scriptRel, '--', "--out=$outDir")
	$r = Invoke-Simple -FilePath $GodotBin -Arguments $args -LogPath $log -TimeoutSec 90
	$status = if ($r.StartError) { 'error' } elseif ($r.TimedOut) { 'fail' } elseif ($r.ExitCode -eq 0) { 'ok' } else { 'fail' }
	New-StepResult -Name 'gameplay_probe' -Status $status -ExitCode $r.ExitCode -TimedOut $r.TimedOut -DurationSec $r.DurationSec -Logs @('logs/gameplay_probe.log') -Artifact 'gameplay_probe'
}

## Test réseau à deux process (hôte + client) — tools/net_smoke.gd.
function Step-NetSmoke {
	$hostLog = Join-Path $Out "logs\net_smoke_host.log"
	$clientLog = Join-Path $Out "logs\net_smoke_client.log"
	$sw = [System.Diagnostics.Stopwatch]::StartNew()

	$hHost = Start-ProcHandle -FilePath $GodotBin -Arguments (Join-Args @('--headless', '--path', '.', '-s', 'res://tools/net_smoke.gd', '--', '--role=host')) -LogPath $hostLog
	Start-Sleep -Seconds 1
	$hClient = Start-ProcHandle -FilePath $GodotBin -Arguments (Join-Args @('--headless', '--path', '.', '-s', 'res://tools/net_smoke.gd', '--', '--role=client')) -LogPath $clientLog

	$rHost = Wait-ProcHandle -Handle $hHost -TimeoutSec 30
	$rClient = Wait-ProcHandle -Handle $hClient -TimeoutSec 30
	$sw.Stop()

	$hostText = if (Test-Path $hostLog) { Get-Content $hostLog -Raw -ErrorAction SilentlyContinue } else { '' }
	$m = [regex]::Match($hostText, 'NET_SMOKE_RESULT ok=(true|false) damage_taken=([\d.]+) rejected_shots=(\d+) agent_index=(-?\d+)')

	$result = [ordered]@{
		ok                = if ($m.Success) { $m.Groups[1].Value -eq 'true' } else { $false }
		damage_taken      = if ($m.Success) { [double]$m.Groups[2].Value } else { $null }
		rejected_shots    = if ($m.Success) { [int]$m.Groups[3].Value } else { $null }
		agent_index       = if ($m.Success) { [int]$m.Groups[4].Value } else { $null }
		host_exit_code    = $rHost.ExitCode
		client_exit_code  = $rClient.ExitCode
		host_timed_out    = $rHost.TimedOut
		client_timed_out  = $rClient.TimedOut
		result_line_found = $m.Success
	}
	$dest = Join-Path $Out 'net_smoke'
	New-Item -ItemType Directory -Force -Path $dest | Out-Null
	($result | ConvertTo-Json) | Set-Content -Path (Join-Path $dest 'result.json') -Encoding UTF8

	$status = if (-not $m.Success) { 'fail' } elseif ($result.ok -and $rHost.ExitCode -eq 0) { 'ok' } else { 'fail' }
	New-StepResult -Name 'net_smoke' -Status $status -ExitCode $rHost.ExitCode -TimedOut ($rHost.TimedOut -or $rClient.TimedOut) `
		-DurationSec ([math]::Round($sw.Elapsed.TotalSeconds, 2)) -Logs @('logs/net_smoke_host.log', 'logs/net_smoke_client.log') -Artifact 'net_smoke' `
		-Note $(if (-not $m.Success) { 'ligne NET_SMOKE_RESULT introuvable dans le log hôte' } else { '' })
}

## Match TDM avec bots, un seul process — tools/bot_smoke.gd. Le script
## n'expose aucun paramètre --seed (voir son code source) : "2 seeds si le
## script le permet" ne s'applique donc pas, une seule exécution suffit à
## honorer le contrat (120 s fixes ; en lancer 2 dépasserait le budget de
## 10 min pour un run complet — voir docs/REVIEW.md).
function Step-BotSmoke {
	$log = Join-Path $Out "logs\bot_smoke.log"
	$r = Invoke-Simple -FilePath $GodotBin -Arguments (Join-Args @('--headless', '--path', '.', '-s', 'res://tools/bot_smoke.gd')) -LogPath $log -TimeoutSec 150
	$text = if (Test-Path $log) { Get-Content $log -Raw -ErrorAction SilentlyContinue } else { '' }
	$m = [regex]::Match($text, 'BOT_SMOKE kills=(\d+) errors=(\d+) rejected_shots=(\d+)')
	$result = [ordered]@{
		kills             = if ($m.Success) { [int]$m.Groups[1].Value } else { $null }
		errors            = if ($m.Success) { [int]$m.Groups[2].Value } else { $null }
		rejected_shots    = if ($m.Success) { [int]$m.Groups[3].Value } else { $null }
		exit_code         = $r.ExitCode
		result_line_found = $m.Success
	}
	$dest = Join-Path $Out 'bot_smoke'
	New-Item -ItemType Directory -Force -Path $dest | Out-Null
	($result | ConvertTo-Json) | Set-Content -Path (Join-Path $dest 'result.json') -Encoding UTF8

	$status = if (-not $m.Success) { 'fail' } elseif ($result.kills -gt 0 -and $result.errors -eq 0 -and $r.ExitCode -eq 0) { 'ok' } else { 'fail' }
	New-StepResult -Name 'bot_smoke' -Status $status -ExitCode $r.ExitCode -TimedOut $r.TimedOut -DurationSec $r.DurationSec -Logs @('logs/bot_smoke.log') -Artifact 'bot_smoke' `
		-Note $(if (-not $m.Success) { 'ligne BOT_SMOKE introuvable dans le log' } else { '' })
}

## Captures fenêtrées de TOUTES les maps — tools/map_shots.gd (existant).
function Step-MapShots {
	$log = Join-Path $Out "logs\map_shots.log"
	$outDir = "$OutGodot/map_shots"
	$args = Join-Args @('--path', '.', '-s', 'res://tools/map_shots.gd', '--', "--out=$outDir")
	$r = Invoke-Simple -FilePath $GodotBin -Arguments $args -LogPath $log -TimeoutSec 180
	$text = if (Test-Path $log) { Get-Content $log -Raw -ErrorAction SilentlyContinue } else { '' }
	$shotCount = ([regex]::Matches($text, 'MAP_SHOT ')).Count
	$done = $text -match 'MAP_SHOTS_DONE'
	$failMatch = [regex]::Match($text, 'MAP_SHOTS_FAIL (.+)')
	$dest = Join-Path $Out 'map_shots'
	New-Item -ItemType Directory -Force -Path $dest | Out-Null
	(@{ done = [bool]$done; shot_count = $shotCount; fail_reason = if ($failMatch.Success) { $failMatch.Groups[1].Value.Trim() } else { $null } } | ConvertTo-Json) |
		Set-Content -Path (Join-Path $dest 'result.json') -Encoding UTF8
	$status = if ($r.StartError) { 'error' } elseif ($r.TimedOut) { 'fail' } elseif ($done -and $r.ExitCode -eq 0) { 'ok' } else { 'fail' }
	New-StepResult -Name 'map_shots' -Status $status -ExitCode $r.ExitCode -TimedOut $r.TimedOut -DurationSec $r.DurationSec -Logs @('logs/map_shots.log') -Artifact 'map_shots'
}

## Étape du contrat parallèle : tools/review/ui_shots.gd (fenêtré).
function Step-UiShots {
	$scriptRel = 'tools/review/ui_shots.gd'
	if (-not (Test-Path (Join-Path $RepoRoot $scriptRel))) {
		return New-StepResult -Name 'ui_shots' -Status 'missing' -Note "$scriptRel absent (livré par l'agent parallèle) — étape sautée"
	}
	$log = Join-Path $Out "logs\ui_shots.log"
	$outDir = "$OutGodot/ui_shots"
	$args = Join-Args @('--path', '.', '-s', $scriptRel, '--', "--out=$outDir")
	$r = Invoke-Simple -FilePath $GodotBin -Arguments $args -LogPath $log -TimeoutSec 120
	$jsonPath = Join-Path $Out 'ui_shots\ui_shots.json'
	$note = if ($r.ExitCode -eq 0 -and -not (Test-Path $jsonPath)) { 'exit 0 mais ui_shots.json absent' } else { '' }
	$status = if ($r.StartError) { 'error' } elseif ($r.TimedOut) { 'fail' } elseif ($r.ExitCode -eq 0 -and (Test-Path $jsonPath)) { 'ok' } else { 'fail' }
	New-StepResult -Name 'ui_shots' -Status $status -ExitCode $r.ExitCode -TimedOut $r.TimedOut -DurationSec $r.DurationSec -Logs @('logs/ui_shots.log') -Artifact 'ui_shots' -Note $note
}

## Captures ViewModel (bras+arme) fenêtrées — tools/blender/viewmodel_shots.gd
## + tools/fp_shots.gd (existants, angles complémentaires : armes brutes vs.
## poses sprint/ADS).
function Step-ViewmodelFpShots {
	$logVm = Join-Path $Out "logs\viewmodel_fp_shots.viewmodel.log"
	$logFp = Join-Path $Out "logs\viewmodel_fp_shots.fp.log"
	$sw = [System.Diagnostics.Stopwatch]::StartNew()

	$rVm = Invoke-Simple -FilePath $GodotBin -LogPath $logVm -TimeoutSec 90 -Arguments (Join-Args @(
			'--path', '.', '-s', 'res://tools/blender/viewmodel_shots.gd', '--', "--out=$OutGodot/viewmodel_fp/viewmodel"))
	$rFp = Invoke-Simple -FilePath $GodotBin -LogPath $logFp -TimeoutSec 90 -Arguments (Join-Args @(
			'--path', '.', '-s', 'res://tools/fp_shots.gd', '--', "--out=$OutGodot/viewmodel_fp/fp"))
	$sw.Stop()

	$vmText = if (Test-Path $logVm) { Get-Content $logVm -Raw -ErrorAction SilentlyContinue } else { '' }
	$fpText = if (Test-Path $logFp) { Get-Content $logFp -Raw -ErrorAction SilentlyContinue } else { '' }
	$vmDone = $vmText -match 'VIEWMODEL_SHOTS_DONE'
	$fpDone = $fpText -match 'FP_SHOTS_DONE'
	$result = [ordered]@{
		viewmodel = @{ done = [bool]$vmDone; shots = ([regex]::Matches($vmText, 'VIEWMODEL_SHOT ')).Count; exit_code = $rVm.ExitCode }
		fp        = @{ done = [bool]$fpDone; shots = ([regex]::Matches($fpText, 'FP_SHOT ')).Count; exit_code = $rFp.ExitCode }
	}
	$dest = Join-Path $Out 'viewmodel_fp'
	New-Item -ItemType Directory -Force -Path $dest | Out-Null
	($result | ConvertTo-Json -Depth 4) | Set-Content -Path (Join-Path $dest 'result.json') -Encoding UTF8

	$status = if ($vmDone -and $fpDone -and $rVm.ExitCode -eq 0 -and $rFp.ExitCode -eq 0) { 'ok' } else { 'fail' }
	New-StepResult -Name 'viewmodel_fp_shots' -Status $status -ExitCode $rVm.ExitCode -TimedOut ($rVm.TimedOut -or $rFp.TimedOut) `
		-DurationSec ([math]::Round($sw.Elapsed.TotalSeconds, 2)) -Logs @('logs/viewmodel_fp_shots.viewmodel.log', 'logs/viewmodel_fp_shots.fp.log') -Artifact 'viewmodel_fp'
}

## Captures personnages fenêtrées — tools/character_shots.gd (poses statiques)
## + tools/char_ingame_shots.gd (en match, 3e + 1re personne).
function Step-CharacterShots {
	$logStatic = Join-Path $Out "logs\character_shots.static.log"
	$logIngame = Join-Path $Out "logs\character_shots.ingame.log"
	$sw = [System.Diagnostics.Stopwatch]::StartNew()

	$rStatic = Invoke-Simple -FilePath $GodotBin -LogPath $logStatic -TimeoutSec 90 -Arguments (Join-Args @(
			'--path', '.', '-s', 'tools/character_shots.gd', '--', "--out=$OutGodot/character_shots/static"))
	$rIngame = Invoke-Simple -FilePath $GodotBin -LogPath $logIngame -TimeoutSec 90 -Arguments (Join-Args @(
			'--path', '.', '-s', 'res://tools/char_ingame_shots.gd', '--', "--out=$OutGodot/character_shots/ingame"))
	$sw.Stop()

	$staticText = if (Test-Path $logStatic) { Get-Content $logStatic -Raw -ErrorAction SilentlyContinue } else { '' }
	$ingameText = if (Test-Path $logIngame) { Get-Content $logIngame -Raw -ErrorAction SilentlyContinue } else { '' }
	$staticDone = $staticText -match 'CHAR_SHOTS_DONE'
	$ingameDone = $ingameText -match 'CHAR_INGAME_SHOTS_DONE'
	$result = [ordered]@{
		static = @{ done = [bool]$staticDone; shots = ([regex]::Matches($staticText, 'CHAR_SHOT ')).Count; exit_code = $rStatic.ExitCode }
		ingame = @{ done = [bool]$ingameDone; shots = ([regex]::Matches($ingameText, 'CHAR_SHOT ')).Count; exit_code = $rIngame.ExitCode }
	}
	$dest = Join-Path $Out 'character_shots'
	New-Item -ItemType Directory -Force -Path $dest | Out-Null
	($result | ConvertTo-Json -Depth 4) | Set-Content -Path (Join-Path $dest 'result.json') -Encoding UTF8

	$status = if ($staticDone -and $ingameDone -and $rStatic.ExitCode -eq 0 -and $rIngame.ExitCode -eq 0) { 'ok' } else { 'fail' }
	New-StepResult -Name 'character_shots' -Status $status -ExitCode $rStatic.ExitCode -TimedOut ($rStatic.TimedOut -or $rIngame.TimedOut) `
		-DurationSec ([math]::Round($sw.Elapsed.TotalSeconds, 2)) -Logs @('logs/character_shots.static.log', 'logs/character_shots.ingame.log') -Artifact 'character_shots'
}

## Benchmark de perf fenêtré — tools/review/perf_bench.gd (mon script).
function Step-PerfBench {
	$log = Join-Path $Out "logs\perf_bench.log"
	$outDir = "$OutGodot/perf_bench"
	$args = Join-Args @('--path', '.', '-s', 'res://tools/review/perf_bench.gd', '--', "--out=$outDir")
	$r = Invoke-Simple -FilePath $GodotBin -Arguments $args -LogPath $log -TimeoutSec 240
	$jsonPath = Join-Path $Out 'perf_bench\perf.json'
	$status = if ($r.StartError) { 'error' } elseif ($r.TimedOut -or -not (Test-Path $jsonPath)) { 'fail' } elseif ($r.ExitCode -eq 0) { 'ok' } else { 'fail' }
	New-StepResult -Name 'perf_bench' -Status $status -ExitCode $r.ExitCode -TimedOut $r.TimedOut -DurationSec $r.DurationSec -Logs @('logs/perf_bench.log') -Artifact 'perf_bench'
}

## Masques HUD/personnages/viewmodel fenêtrés — tools/review/style_masks.gd
## (ART-03), consommés par Step-StyleCheck (CHK-02/04/05/06/18/20/21/22...).
function Step-StyleMasks {
	$scriptRel = 'tools/review/style_masks.gd'
	if (-not (Test-Path (Join-Path $RepoRoot $scriptRel))) {
		return New-StepResult -Name 'style_masks' -Status 'missing' -Note "$scriptRel absent — étape sautée"
	}
	$log = Join-Path $Out "logs\style_masks.log"
	$outDir = "$OutGodot/style_masks"
	$args = Join-Args @('--path', '.', '-s', $scriptRel, '--', "--out=$outDir")
	$r = Invoke-Simple -FilePath $GodotBin -Arguments $args -LogPath $log -TimeoutSec 150
	$text = if (Test-Path $log) { Get-Content $log -Raw -ErrorAction SilentlyContinue } else { '' }
	$done = $text -match 'STYLE_MASKS_DONE'
	$failMatch = [regex]::Match($text, 'STYLE_MASKS_FAIL (.+)')
	$status = if ($r.StartError) { 'error' } elseif ($r.TimedOut) { 'fail' } elseif ($done -and $r.ExitCode -eq 0) { 'ok' } else { 'fail' }
	New-StepResult -Name 'style_masks' -Status $status -ExitCode $r.ExitCode -TimedOut $r.TimedOut -DurationSec $r.DurationSec -Logs @('logs/style_masks.log') -Artifact 'style_masks' `
		-Note $(if ($failMatch.Success) { $failMatch.Groups[1].Value.Trim() } else { '' })
}

## Scoreur de la checklist de style (docs/STYLE_BIBLE.md §11, ART-03) —
## tools/review/style_check.py note CHK-01 à CHK-47 sur les captures/masques/
## jetons de CE run et écrit "<Out>/style_check.json" (score PASS/total dans
## ce fichier ET dans steps.json via la note de cette étape, tous deux sous
## $Out — donc "dans le rapport de revue" au sens de reports/review/<ts>/).
## Tourne TOUJOURS, comme log_scan/report (voir $pipeline plus bas) : un
## contrôle sans capture disponible retombe en WARN "non mesuré", jamais un
## FAIL, et les lints statiques (CHK-07/19/26/27/39/41) restent mesurables
## même en -Quick ou -Only restreint, sans aucune fenêtre.
function Step-StyleCheck {
	if (-not $PythonBin) {
		return New-StepResult -Name 'style_check' -Status 'missing' -Note 'python introuvable'
	}
	$log = Join-Path $Out "logs\style_check.log"
	$args = Join-Args @('tools/review/style_check.py', $Out)
	$r = Invoke-Simple -FilePath $PythonBin -Arguments $args -LogPath $log -TimeoutSec 120
	$jsonPath = Join-Path $Out 'style_check.json'
	$scoreText = ''
	$gate = ''
	if (Test-Path $jsonPath) {
		try {
			$data = Get-Content $jsonPath -Raw | ConvertFrom-Json
			$scoreText = $data.score.text
			$gate = $data.gate
		} catch {}
	}
	$status = if ($r.StartError) { 'error' } elseif (-not (Test-Path $jsonPath)) { 'fail' } elseif ($gate -eq 'FAIL') { 'fail' } elseif ($gate -eq 'WARN') { 'warn' } else { 'ok' }
	$note = if ($scoreText) { "score style $scoreText (gate=$gate)" } else { 'style_check.json non produit' }
	New-StepResult -Name 'style_check' -Status $status -ExitCode $r.ExitCode -TimedOut $r.TimedOut -DurationSec $r.DurationSec -Logs @('logs/style_check.log') -Artifact '.' -Note $note
}

function Step-LogScan {
	if (-not $PythonBin) {
		return New-StepResult -Name 'log_scan' -Status 'missing' -Note 'python introuvable'
	}
	$log = Join-Path $Out "logs\log_scan.log"
	$args = Join-Args @('tools/review/log_scan.py', $Out)
	$r = Invoke-Simple -FilePath $PythonBin -Arguments $args -LogPath $log -TimeoutSec 60
	$status = if ($r.StartError) { 'error' } elseif ($r.ExitCode -eq 0) { 'ok' } else { 'fail' }
	New-StepResult -Name 'log_scan' -Status $status -ExitCode $r.ExitCode -TimedOut $r.TimedOut -DurationSec $r.DurationSec -Logs @('logs/log_scan.log') -Artifact '.'
}

function Step-Report {
	if (-not $PythonBin) {
		return New-StepResult -Name 'report' -Status 'missing' -Note 'python introuvable'
	}
	$log = Join-Path $Out "logs\report.log"
	$args = Join-Args @('tools/review/report.py', $Out)
	$r = Invoke-Simple -FilePath $PythonBin -Arguments $args -LogPath $log -TimeoutSec 90
	$status = if ($r.StartError) { 'error' } elseif ($r.ExitCode -eq 0) { 'ok' } else { 'fail' }
	New-StepResult -Name 'report' -Status $status -ExitCode $r.ExitCode -TimedOut $r.TimedOut -DurationSec $r.DurationSec -Logs @('logs/report.log') -Artifact '.'
}

# =====================================================================
#  Sélection des étapes à exécuter
# =====================================================================

$CoreSteps = @('unit_tests', 'gameplay_probe', 'net_smoke', 'bot_smoke', 'map_shots', 'ui_shots', 'viewmodel_fp_shots', 'character_shots', 'style_masks', 'perf_bench')
$QuickSteps = @('unit_tests', 'gameplay_probe', 'net_smoke', 'bot_smoke')
$AllStepNames = @('import') + $CoreSteps + @('log_scan', 'style_check', 'report')

if ($Only) {
	$requested = $Only -split ',' | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ -ne '' }
	$unknown = $requested | Where-Object { $AllStepNames -notcontains $_ }
	if ($unknown) { Write-Warning "Noms d'étape inconnus dans -Only (ignorés) : $($unknown -join ', ')" }
	$selected = $CoreSteps | Where-Object { $requested -contains $_.ToLower() }
} elseif ($Quick) {
	$selected = $QuickSteps
} else {
	$selected = $CoreSteps
}

# import -> [étapes sélectionnées] -> log_scan -> style_check -> report,
# TOUJOURS forcés aux extrémités : import est un bootstrap requis,
# log_scan+style_check+report garantissent qu'une commande produit toujours
# SON rapport (et son score de style), même avec -Only restreint.
$pipeline = @('import') + $selected + @('log_scan', 'style_check', 'report')

$StepDispatch = @{
	'import'              = { Step-Import }
	'unit_tests'          = { Step-UnitTests }
	'gameplay_probe'      = { Step-GameplayProbe }
	'net_smoke'           = { Step-NetSmoke }
	'bot_smoke'           = { Step-BotSmoke }
	'map_shots'           = { Step-MapShots }
	'ui_shots'            = { Step-UiShots }
	'viewmodel_fp_shots'  = { Step-ViewmodelFpShots }
	'character_shots'     = { Step-CharacterShots }
	'style_masks'         = { Step-StyleMasks }
	'perf_bench'          = { Step-PerfBench }
	'log_scan'            = { Step-LogScan }
	'style_check'         = { Step-StyleCheck }
	'report'              = { Step-Report }
}

# =====================================================================
#  Exécution — jamais interrompue par l'échec d'une étape
# =====================================================================

$StepResults = New-Object System.Collections.Generic.List[object]
$runSw = [System.Diagnostics.Stopwatch]::StartNew()

foreach ($stepName in $pipeline) {
	Write-Host ">>> $stepName" -ForegroundColor Yellow
	$t0 = Get-Date
	try {
		$result = & $StepDispatch[$stepName]
	} catch {
		$result = New-StepResult -Name $stepName -Status 'error' -DurationSec ([math]::Round(((Get-Date) - $t0).TotalSeconds, 2)) -Note "exception PowerShell : $($_.Exception.Message)"
	}
	$StepResults.Add($result)
	$colorMap = @{ ok = 'Green'; warn = 'DarkYellow'; fail = 'Red'; missing = 'DarkGray'; error = 'Red' }
	Write-Host ("    {0,-8} exit={1} {2}s {3}" -f $result.status, $result.exit_code, $result.duration_sec, $result.note) -ForegroundColor $colorMap[$result.status]
	# Écrit steps.json après CHAQUE étape : un run interrompu (Ctrl+C, crash)
	# laisse quand même un état exploitable pour le rapport.
	$StepResults | ConvertTo-Json -Depth 8 | Set-Content -Path (Join-Path $Out 'steps.json') -Encoding UTF8
}
$runSw.Stop()

Write-Host ""
Write-Host "=== terminé en $([math]::Round($runSw.Elapsed.TotalMinutes, 1)) min ===" -ForegroundColor Cyan

$summaryPath = Join-Path $Out 'summary.json'
if (Test-Path $summaryPath) {
	try {
		$summary = Get-Content $summaryPath -Raw | ConvertFrom-Json
		Write-Host "gate global : $($summary.overall_status)" -ForegroundColor $(if ($summary.overall_status -eq 'PASS') { 'Green' } elseif ($summary.overall_status -eq 'WARN') { 'DarkYellow' } else { 'Red' })
	} catch {}
}
Write-Host "rapport : $Out\index.html"
