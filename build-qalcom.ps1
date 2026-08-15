<#
    build-qalcom.ps1
    ---------------------------------------------------------------------------
    Compiles a smaller, install-ready copy of Qalcom OS into a "dist" folder.

    Your full, commented source in this folder is never touched. This script
    reads it, strips everything the Lua runtime does not need (comments, blank
    lines, indentation, CRLF line endings, redundant spaces), and writes the
    shrunk copy to  dist\  . Copy the CONTENTS of dist\ onto the CC:T computer
    (dist\startup.lua -> /startup.lua, dist\qalcom -> /qalcom).

    The minifier is "safe" level: it only removes whitespace and comments. It
    never renames variables and never joins lines, so behavior is identical.
    Strings and long-bracket literals/comments are preserved byte-for-byte.

    USAGE
      Right-click -> Run with PowerShell, or from a terminal:
        powershell -ExecutionPolicy Bypass -File .\build-qalcom.ps1
      Optional:
        -SourceRoot <path>   folder holding startup.lua + qalcom  (default: script folder)
        -OutRoot    <path>   output folder                        (default: <SourceRoot>\dist)
#>

param(
    [string]$SourceRoot = $PSScriptRoot,
    [string]$OutRoot    = $null
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($SourceRoot)) { $SourceRoot = (Get-Location).Path }
if ([string]::IsNullOrWhiteSpace($OutRoot))    { $OutRoot = Join-Path $SourceRoot 'dist' }

# Character constants (avoids char/string comparison ambiguity).
$NL   = [char]10   # \n
$CR   = [char]13   # \r
$TAB  = [char]9
$SP   = [char]32
$DASH = [char]'-'
$LBR  = [char]'['
$RBR  = [char]']'
$EQ   = [char]'='
$SQ   = [char]39   # '
$DQ   = [char]34   # "
$BSL  = [char]92   # backslash

function Convert-LuaMinify {
    param([string]$src)

    $n  = $src.Length
    $sb = New-Object System.Text.StringBuilder $n
    $i  = 0
    $atLineStart   = $true    # suppress leading indentation
    $pendingSpace  = $false   # collapse runs of interior whitespace to one space
    $lastWasNewline = $true    # suppress blank lines / leading newlines

    while ($i -lt $n) {
        $c = $src[$i]

        # --- carriage return: drop (CRLF -> LF) ---
        if ($c -eq $CR) { $i++; continue }

        # --- newline ---
        if ($c -eq $NL) {
            if (-not $lastWasNewline) {
                [void]$sb.Append($NL)
                $lastWasNewline = $true
            }
            $atLineStart  = $true
            $pendingSpace = $false
            $i++
            continue
        }

        # --- horizontal whitespace ---
        if ($c -eq $SP -or $c -eq $TAB) {
            if (-not $atLineStart) { $pendingSpace = $true }
            $i++
            continue
        }

        # --- comment ( -- ...) or long comment ( --[[ ... ]] ) ---
        if ($c -eq $DASH -and ($i + 1) -lt $n -and $src[$i + 1] -eq $DASH) {
            $j = $i + 2
            if ($j -lt $n -and $src[$j] -eq $LBR) {
                $k = $j + 1
                $eq = 0
                while ($k -lt $n -and $src[$k] -eq $EQ) { $eq++; $k++ }
                if ($k -lt $n -and $src[$k] -eq $LBR) {
                    # long comment of level $eq -> skip through matching close
                    $close = [string]$RBR + ([string]$EQ * $eq) + [string]$RBR
                    $idx = $src.IndexOf($close, $k + 1)
                    if ($idx -lt 0) { $i = $n } else { $i = $idx + $close.Length }
                    continue
                }
            }
            # short comment -> skip to end of line (leave the newline for next loop)
            $j = $i + 2
            while ($j -lt $n -and $src[$j] -ne $NL) { $j++ }
            $i = $j
            continue
        }

        # --- long-bracket string literal ( [[ ... ]] , [=[ ... ]=] ) : emit verbatim ---
        if ($c -eq $LBR) {
            $k = $i + 1
            $eq = 0
            while ($k -lt $n -and $src[$k] -eq $EQ) { $eq++; $k++ }
            if ($k -lt $n -and $src[$k] -eq $LBR) {
                $close = [string]$RBR + ([string]$EQ * $eq) + [string]$RBR
                $idx = $src.IndexOf($close, $k + 1)
                if ($idx -lt 0) { $end = $n } else { $end = $idx + $close.Length }
                if ($pendingSpace -and -not $atLineStart) { [void]$sb.Append($SP) }
                [void]$sb.Append($src.Substring($i, $end - $i))
                $pendingSpace   = $false
                $atLineStart    = $false
                $lastWasNewline = $false
                $i = $end
                continue
            }
            # otherwise a normal '[' -> fall through to code-char handling below
        }

        # --- short string ( "..." or '...' ) : emit verbatim, honor escapes ---
        if ($c -eq $DQ -or $c -eq $SQ) {
            if ($pendingSpace -and -not $atLineStart) { [void]$sb.Append($SP) }
            $quote = $c
            [void]$sb.Append($c)
            $i++
            while ($i -lt $n) {
                $ch = $src[$i]
                if ($ch -eq $BSL) {
                    [void]$sb.Append($ch)
                    if (($i + 1) -lt $n) { [void]$sb.Append($src[$i + 1]) }
                    $i += 2
                    continue
                }
                [void]$sb.Append($ch)
                $i++
                if ($ch -eq $quote) { break }
            }
            $pendingSpace   = $false
            $atLineStart    = $false
            $lastWasNewline = $false
            continue
        }

        # --- ordinary code character ---
        if ($pendingSpace -and -not $atLineStart) { [void]$sb.Append($SP) }
        [void]$sb.Append($c)
        $pendingSpace   = $false
        $atLineStart    = $false
        $lastWasNewline = $false
        $i++
    }

    return $sb.ToString().TrimEnd()
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

$startupSrc = Join-Path $SourceRoot 'startup.lua'
$qalcomSrc  = Join-Path $SourceRoot 'qalcom'
if (-not (Test-Path $startupSrc) -or -not (Test-Path $qalcomSrc)) {
    Write-Host "ERROR: could not find 'startup.lua' and 'qalcom\' in:" -ForegroundColor Red
    Write-Host "       $SourceRoot" -ForegroundColor Red
    Write-Host "Run this script from the Qalcom OS folder, or pass -SourceRoot." -ForegroundColor Yellow
    exit 1
}

Write-Host ""
Write-Host "Qalcom OS build" -ForegroundColor Cyan
Write-Host "  source: $SourceRoot"
Write-Host "  output: $OutRoot"
Write-Host ""

# Fresh output tree.
if (Test-Path $OutRoot) { Remove-Item -Recurse -Force $OutRoot }
New-Item -ItemType Directory -Force -Path $OutRoot | Out-Null

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$totalIn = 0L
$totalOut = 0L
$luaCount = 0
$copyCount = 0

# Collect the files that ship: startup.lua at root + everything under qalcom\.
$files = @( Get-Item $startupSrc )
$files += Get-ChildItem -Path $qalcomSrc -Recurse -File

foreach ($f in $files) {
    # Relative path from the source root, so the tree is mirrored under dist\.
    $rel = $f.FullName.Substring($SourceRoot.Length).TrimStart('\', '/')
    $dest = Join-Path $OutRoot $rel
    $destDir = Split-Path $dest -Parent
    if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Force -Path $destDir | Out-Null }

    $inBytes = $f.Length
    $totalIn += $inBytes

    if ($f.Extension -ieq '.lua') {
        $src = [System.IO.File]::ReadAllText($f.FullName)
        $min = Convert-LuaMinify $src
        [System.IO.File]::WriteAllText($dest, $min, $utf8NoBom)
        $outBytes = (Get-Item $dest).Length
        $luaCount++
    }
    else {
        # Non-Lua asset (none today, but future-proof): copy verbatim.
        Copy-Item -Path $f.FullName -Destination $dest -Force
        $outBytes = (Get-Item $dest).Length
        $copyCount++
    }
    $totalOut += $outBytes

    $pct = if ($inBytes -gt 0) { [math]::Round(100.0 * ($inBytes - $outBytes) / $inBytes) } else { 0 }
    "{0,7:N0} -> {1,7:N0}  (-{2,2}%)  {3}" -f $inBytes, $outBytes, $pct, $rel | Write-Host
}

$saved = $totalIn - $totalOut
$pctAll = if ($totalIn -gt 0) { [math]::Round(100.0 * $saved / $totalIn, 1) } else { 0 }

Write-Host ""
Write-Host ("Minified {0} Lua files, copied {1} other files." -f $luaCount, $copyCount)
Write-Host ("Total:  {0:N0} bytes  ->  {1:N0} bytes" -f $totalIn, $totalOut) -ForegroundColor Green
Write-Host ("Saved:  {0:N0} bytes  ({1}% smaller)" -f $saved, $pctAll) -ForegroundColor Green
Write-Host ""
Write-Host "Done. Install the contents of:" -ForegroundColor Cyan
Write-Host "  $OutRoot"
Write-Host "onto the computer  (dist\startup.lua -> /startup.lua,  dist\qalcom -> /qalcom)."
Write-Host ""
