param (
    [string]$FilePath
)

if (-not (Test-Path $FilePath)) {
    Write-Error "File not found: $FilePath"
    exit
}

$content = Get-Content $FilePath -Raw

# Replace multiple blank lines with a single blank line
$content = $content -replace "(\r?\n){3,}", "`r`n`r`n"

# Remove Pandoc header/footer lines that are often inserted
$content = $content -replace "^---.*$", ""
$content = $content -replace "^\+\+\+.*$", ""

# Remove trailing whitespace
$content = $content -replace "[ \t]+$", ""

# Write back
Set-Content -Path $FilePath -Value $content -Encoding UTF8

Write-Host "Cleanup complete for $FilePath"



























# <#
# .SYNOPSIS
#     Cleans up an AsciiDoc file using several regex transformations
#     equivalent to your Python cleanup logic.

# .PARAMETER FilePath
#     The AsciiDoc file to clean.

# .EXAMPLE
#     .\cleanup-adoc.ps1 -FilePath "sample.adoc"
# #>

# param(
#     [Parameter(Mandatory = $true)]
#     [string]$FilePath
# )

# function Log {
#     param([string]$Message)
#     Write-Host $Message
# }

# function Cleanup-AdocFile {
#     param(
#         [string]$Path
#     )

#     Log "    Applying cleanup logic to '$([System.IO.Path]::GetFileName($Path))'..."

#     try {
#         $content = Get-Content -Path $Path -Raw -Encoding UTF8

#         # FIX 1: Remove trailing '+' at end of a line
#         $content = [regex]::Replace($content, "(.+?)\s*\+\s*$", '$1', 'Multiline')

#         # FIX 2: Replace standalone "{plus}" with "+"
#         $content = [regex]::Replace($content, "^\s*\{plus\}\s*$", '+', 'Multiline')

#         # FIX 3: Remove blank lines inside fault blocks (`--`)
#         $content = [regex]::Replace($content, "(--\n)\s+", '$1')
#         $content = [regex]::Replace($content, "\s+(\n--)", '$1')

#         # FIX 4: Join multiline attribute blocks `[ ... ]`
#         $lines = $content -split "`n"
#         $rebuilt = @()
#         $inBlock = $false

#         foreach ($line in $lines) {
#             $trim = $line.Trim()

#             if ($trim.StartsWith("[") -and -not $trim.EndsWith("]")) {
#                 $inBlock = $true
#                 $rebuilt += $line.TrimEnd()
#             }
#             elseif ($inBlock) {
#                 $rebuilt[-1] += " " + ($trim -replace "`", "")
#                 if ($trim.EndsWith("]")) { $inBlock = $false }
#             }
#             else {
#                 $rebuilt += $line
#             }
#         }

#         $content = ($rebuilt -join "`n")

#         # FIX 5: Normalize thematic breaks (---)
#         $content = [regex]::Replace(
#             $content,
#             "\s*^\s*-{3,}\s*$\s*",
#             "`n`n---`n`n",
#             'Multiline'
#         )

#         # FIX 6: Join wrapped list items
#         $lines = $content -split "`n"
#         $rebuilt = @()

#         foreach ($line in $lines) {

#             $isListStart = $line -match "^\s*(\*+|\.+)\s+"
#             $isSpecial = $line -match "^\s*(\[.+|--|\+|=)"

#             if (
#                 $rebuilt.Count -gt 0 -and
#                 ($rebuilt[-1] -match "^\s*(\*+|\.+)\s+") -and
#                 -not $isListStart -and
#                 $line.Trim() -ne "" -and
#                 -not $isSpecial
#             ) {
#                 $rebuilt[-1] += " " + $line.Trim()
#             }
#             else {
#                 $rebuilt += $line
#             }
#         }

#         $content = ($rebuilt -join "`n")

#         # FIX 7: Add blank line between "--" and a block anchor [[...]]
#         $content = [regex]::Replace(
#             $content,
#             "(--\s*\n)(\[\[.+?\]\])",
#             "`$1`n`$2",
#             'Multiline'
#         )

#         # Write back
#         Set-Content -Path $Path -Value $content -Encoding UTF8
#     }
#     catch {
#         Log "    ERROR: Failed to apply cleanup logic to '$([System.IO.Path]::GetFileName($Path))'"
#         Log "      Details: $_"
#     }
# }

# Cleanup-AdocFile -Path $FilePath
