param(
 [ValidateSet('en','zh-CN','all')][string]$Language='all',
 [string]$Fengari='fengari', [string]$Ffmpeg='ffmpeg', [string]$Node='node',
 [switch]$SamplesOnly
)
$ErrorActionPreference='Stop'
$root=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).ProviderPath
$work=Join-Path $PSScriptRoot 'work'
New-Item -ItemType Directory -Force -Path $work | Out-Null
$catalog=@(Get-Content -LiteralPath (Join-Path $PSScriptRoot 'catalog.json') -Raw | ConvertFrom-Json)
$catalogLua='return {'+(($catalog | ForEach-Object {'"'+$_.id+'"'}) -join ',')+'}'
[IO.File]::WriteAllText((Join-Path $work 'catalog.lua'),$catalogLua)
$log=Join-Path $work 'capture.log'
& $Fengari (Join-Path $PSScriptRoot 'capture.lua') $root (Join-Path $work 'catalog.lua') (Join-Path $PSScriptRoot 'preview-config.lua') *> $log
if(-not (Select-String -LiteralPath $log -Pattern '^CAPTURE OK' -Quiet)){Get-Content -LiteralPath $log -Tail 8;throw 'Lua capture failed'}
& $Node (Join-Path $PSScriptRoot 'prepare.cjs') $work
if($LASTEXITCODE -ne 0){throw 'Frame preparation failed'}
Add-Type -AssemblyName System.Drawing
Add-Type -Path (Join-Path $PSScriptRoot 'Renderer.cs') -ReferencedAssemblies @('System.Drawing.Common','System.Drawing.Primitives','System.Diagnostics.Process','System.ComponentModel.Primitives','System.Private.Windows.GdiPlus','System.Private.Windows.Core','System.Collections')
$languages=if($Language -eq 'all'){@('en','zh-CN')}else{@($Language)}
$groups=@{A='A-auto';B='B-throttle';C='C-sticks'}
foreach($lang in $languages){
 $names=@($catalog | ForEach-Object {$_.PSObject.Properties[$lang].Value.name})
 $notes=@($catalog | ForEach-Object {$_.PSObject.Properties[$lang].Value.note})
 $renderer=[V15Preview]::new((Join-Path $work 'frames.bin'),[string[]]$catalog.id,[string[]]$names,[string[]]$notes,($lang -eq 'en'))
 $out=Join-Path $root ('HelloRadio-V15\previews\'+$lang)
 New-Item -ItemType Directory -Force -Path $out | Out-Null
 try{
  $renderer.Sample((Join-Path $work ('overview-'+$lang+'.png')),-1,100)
  $renderer.Sample((Join-Path $work ('combo-'+$lang+'.png')),31,50)
  $renderer.PaletteSample((Join-Path $work 'palette-source.png'))
  if($SamplesOnly){Write-Output ('Samples rendered: '+$lang);continue}
  $palette=Join-Path $work 'palette.png'
  & $Ffmpeg -hide_banner -loglevel error -i (Join-Path $work 'palette-source.png') -vf 'palettegen=max_colors=256:reserve_transparent=0' -frames:v 1 -y $palette
  if($LASTEXITCODE -ne 0){throw 'Palette encoding failed'}
  for($i=0;$i -lt $catalog.Count;$i++){
   $item=$catalog[$i];$folder=Join-Path $out $groups[$item.id.Substring(0,1)]
   $renderer.Encode($Ffmpeg,$palette,(Join-Path $folder ($item.id+'.gif')),$i)
   Write-Output ($lang+' '+($i+1)+'/32 '+$item.id)
  }
  $renderer.Encode($Ffmpeg,$palette,(Join-Path $out 'overview.gif'),-1)
  Write-Output ('RENDER COMPLETE: '+$lang)
 }finally{$renderer.Dispose()}
}
