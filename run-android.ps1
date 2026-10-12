param([string]$Device = '')
Set-Location -LiteralPath $PSScriptRoot
$flutterArgs = @('run', '--dart-define-from-file=config/supabase.local.json')
if ($Device) { $flutterArgs += @('-d', $Device) }
& flutter @flutterArgs
