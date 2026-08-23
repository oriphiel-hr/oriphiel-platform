# Dohvat subjekta iz Sudskog registra po MBS -> PowerShell objekt / JSON
# Stabilni URL (bez cs= session tokena).
#
# Jedan MBS:
#   & C:\GIT_PROJEKTI\oriphiel-platform\scripts\sudreg\Get-SudregSubject.ps1 -Mbs 081617997 -AsJson
#
# Niz MBS-ova (iz druge skripte / pipeline):
#   $lista = @('081617997','040432754','010077259')
#   $lista | & C:\GIT_PROJEKTI\oriphiel-platform\scripts\sudreg\Get-SudregSubject.ps1 -AsJson
#   & C:\GIT_PROJEKTI\oriphiel-platform\scripts\sudreg\Get-SudregSubject.ps1 -Mbs $lista -AsJson
#
# Iz datoteke (jedan MBS po retku):
#   & C:\GIT_PROJEKTI\oriphiel-platform\scripts\sudreg\Get-SudregSubject.ps1 -MbsFile C:\GIT_PROJEKTI\oriphiel-platform\scripts\sudreg\mbs-sample.txt -AsJson
#   Get-Content C:\GIT_PROJEKTI\oriphiel-platform\scripts\sudreg\mbs-sample.txt | & C:\GIT_PROJEKTI\oriphiel-platform\scripts\sudreg\Get-SudregSubject.ps1 -AsJson
#
# Pauza izmedu zahtjeva: nasumicno 0.3-0.7 s (promjena: -MinDelaySec / -MaxDelaySec)

[CmdletBinding()]
param(
  [Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
  [string[]]$Mbs,

  [Parameter(Mandatory = $false)]
  [string]$MbsFile,

  [switch]$AsJson,

  [ValidateRange(0, 60)]
  [double]$MinDelaySec = 0.3,

  [ValidateRange(0, 60)]
  [double]$MaxDelaySec = 0.7
)

begin {
  $ErrorActionPreference = "Stop"
  if ($MinDelaySec -gt $MaxDelaySec) {
    throw "MinDelaySec ($MinDelaySec) ne smije biti veci od MaxDelaySec ($MaxDelaySec)"
  }

  $script:SudregQueue = New-Object System.Collections.Generic.List[string]
  $script:SudregFromPipeline = $false
  $script:SudregHeaders = @{
    'User-Agent'      = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) OriphielSudregBot/1.0'
    'Accept'          = 'text/html,application/xhtml+xml'
    'Accept-Language' = 'hr-HR,hr;q=0.9'
  }
  $script:SudregResults = New-Object System.Collections.Generic.List[object]

  $script:AddSudregMbs = {
    param([string]$raw)
    if ([string]::IsNullOrWhiteSpace($raw)) { return }
    foreach ($part in ($raw -split '[,\s;]+')) {
      $p = $part.Trim()
      if ($p) { [void]$script:SudregQueue.Add($p) }
    }
  }
}

process {
  if ($MyInvocation.ExpectingInput) {
    $script:SudregFromPipeline = $true
    foreach ($item in @($Mbs)) { & $script:AddSudregMbs $item }
  }
}

end {
  if (-not $script:SudregFromPipeline) {
    foreach ($item in @($Mbs)) { & $script:AddSudregMbs $item }
  }

  if ($MbsFile) {
    if (-not (Test-Path -LiteralPath $MbsFile)) {
      throw "MbsFile ne postoji: $MbsFile"
    }
    Get-Content -LiteralPath $MbsFile | ForEach-Object { & $script:AddSudregMbs $_ }
  }

function Normalize-Mbs([string]$value) {
  $digits = ($value -replace '\D', '')
  if ([string]::IsNullOrWhiteSpace($digits)) { throw "MBS nije ispravan: $value" }
  return $digits.PadLeft(9, '0')
}

function Html-Decode([string]$s) {
  if ($null -eq $s) { return $null }
  return [System.Net.WebUtility]::HtmlDecode(($s -replace '&nbsp;', ' ')).Trim()
}

function Strip-Tags([string]$html) {
  if ([string]::IsNullOrWhiteSpace($html)) { return '' }
  $t = $html -replace '(?is)<script.*?</script>', ' '
  $t = $t -replace '(?is)<style.*?</style>', ' '
  $t = $t -replace '(?is)<br\s*/?>', "`n"
  $t = $t -replace '(?is)</p>', "`n"
  $t = $t -replace '(?is)<[^>]+>', ' '
  $t = Html-Decode $t
  $t = $t -replace '[ \t]+', ' '
  $t = $t -replace '(\r?\n\s*)+', "`n"
  return $t.Trim()
}

function Get-SectionMap([string]$html) {
  $map = @{}
  $rx = [regex]::Matches(
    $html,
    '(?is)<h2 class="srn-kat-title">\s*(?<title>.*?)\s*</h2>(?<body>.*?)(?=<h2 class="srn-kat-title"|$)'
  )
  foreach ($m in $rx) {
    $title = Html-Decode ($m.Groups['title'].Value -replace '\s+', ' ')
    if ($title) { $map[$title] = $m.Groups['body'].Value }
  }
  return $map
}

function Find-Section([hashtable]$map, [string[]]$needles) {
  foreach ($key in $map.Keys) {
    foreach ($n in $needles) {
      if ($key -like "*$n*") { return $map[$key] }
    }
  }
  return $null
}

function As-StringArray {
  param($Value)
  $tmp = New-Object System.Collections.Generic.List[string]
  if ($null -eq $Value) { return ,([string[]]@()) }
  if ($Value -is [string]) {
    [void]$tmp.Add($Value)
    return ,([string[]]$tmp.ToArray())
  }
  foreach ($item in @($Value)) {
    if ($null -eq $item) { continue }
    if ($item -is [string]) { [void]$tmp.Add($item); continue }
    foreach ($x in @($item)) {
      if ($null -ne $x -and "$x" -ne '') { [void]$tmp.Add([string]$x) }
    }
  }
  return ,([string[]]$tmp.ToArray())
}

function Get-TableTexts([string]$sectionHtml) {
  $list = New-Object System.Collections.Generic.List[string]
  if ([string]::IsNullOrWhiteSpace($sectionHtml)) { return ,([string[]]@()) }
  foreach ($m in [regex]::Matches($sectionHtml, '(?is)<td[^>]*>(?<td>.*?)</td>')) {
    $txt = Strip-Tags $m.Groups['td'].Value
    if ($txt) { [void]$list.Add($txt) }
  }
  return ,([string[]]$list.ToArray())
}

function Get-FirstText([string]$sectionHtml) {
  if ([string]::IsNullOrWhiteSpace($sectionHtml)) { return $null }
  $m = [regex]::Match($sectionHtml, '(?is)<td[^>]*>(?<td>.*?)</td>')
  if (-not $m.Success) { return $null }
  $txt = Strip-Tags $m.Groups['td'].Value
  if ($txt) { return $txt }
  return $null
}

function Parse-People([string]$sectionHtml) {
  $people = New-Object System.Collections.Generic.List[object]
  if ([string]::IsNullOrWhiteSpace($sectionHtml)) { return @() }

  $evaluator = {
    param($match)
    $roleTxt = Strip-Tags $match.Groups[1].Value
    $roleTxt = ($roleTxt -replace '^-\s*', '').Trim()
    if ($roleTxt) { return " [[ROLE:$roleTxt]] " }
    return ' '
  }
  $flatSection = [regex]::Replace(
    $sectionHtml,
    '(?is)<table class="srn-l2-table">(.*?)</table>',
    $evaluator
  )

  foreach ($table in [regex]::Matches($flatSection, '(?is)<table class="srn-l1-table">(.*?)</table>')) {
    $inner = $table.Groups[1].Value
    foreach ($tr in [regex]::Matches($inner, '(?is)<tr>\s*<td[^>]*>(.*?)</td>\s*</tr>')) {
      $cell = $tr.Groups[1].Value
      $roles = New-Object System.Collections.Generic.List[string]
      foreach ($rm in [regex]::Matches($cell, '\[\[ROLE:(.*?)\]\]')) {
        $r = $rm.Groups[1].Value.Trim()
        if ($r) { [void]$roles.Add($r) }
      }

      $cellNoRole = [regex]::Replace($cell, '\[\[ROLE:.*?\]\]', ' ')
      $cellNoLink = [regex]::Replace($cellNoRole, '(?is)<a[^>]*>.*?</a>', ' ')
      $text = Strip-Tags $cellNoLink
      if (-not $text) { continue }
      if ($text -match '^\s*-\s*') { continue }

      $oib = $null
      $om = [regex]::Match($text, 'OIB:\s*(\d{11})')
      if ($om.Success) { $oib = $om.Groups[1].Value }

      if ($roles.Count -eq 0) {
        foreach ($line in ($text -split '\r?\n')) {
          if ($line -match '^\s*-\s*(.+)$') { [void]$roles.Add($Matches[1].Trim()) }
        }
      }

      $textClean = [regex]::Replace($text, '(?m)^\s*-\s*.*$', '').Trim()
      $textClean = ($textClean -replace '\n+', "`n").Trim()
      if (-not $textClean) { continue }

      [void]$people.Add([pscustomobject]@{
          ime   = (($textClean -split ', OIB:')[0].Trim())
          oib   = $oib
          tekst = $textClean
          uloge = [string[]]$roles.ToArray()
        })
    }
  }
  return @($people.ToArray())
}

function Get-SudregSubjectObject {
  param([string]$MbsValue)

  $mbsNorm = Normalize-Mbs $MbsValue
  $url = "https://sudreg.pravosudje.hr/ords/r/esudreg/public/podaci-o-poslovnom-subjektu?p28_sbt_mbs=$mbsNorm"

  $resp = Invoke-WebRequest -Uri $url -Headers $script:SudregHeaders -UseBasicParsing -TimeoutSec 60
  $html = $resp.Content
  if ($html -match 'Neispravna url adresa') { throw "Sudreg: neispravna adresa za MBS $mbsNorm" }

  $sections = Get-SectionMap $html

  $secSud = Find-Section $sections @('Nadle')
  $secMbs = Find-Section $sections @('MBS')
  $secOib = Find-Section $sections @('OIB')
  $secEuid = Find-Section $sections @('EUID')
  $secStatus = Find-Section $sections @('Status')
  $secTvrtka = Find-Section $sections @('Tvrtka')
  $secAdresa = Find-Section $sections @('Sjedi')
  $secEmail = Find-Section $sections @('elektroni')
  $secKapital = Find-Section $sections @('kapital')
  $secOblik = Find-Section $sections @('Pravni oblik')
  $secPretezita = Find-Section $sections @('Prete')
  $secDjelatnosti = Find-Section $sections @('Evidencijske', 'Predmet poslovanja')
  $secClanovi = Find-Section $sections @('Osniva')
  $secZastupnici = Find-Section $sections @('zastupanje')
  $secPravni = Find-Section $sections @('Pravni odnosi')
  $secFin = Find-Section $sections @('Financijska')

  foreach ($k in @($sections.Keys)) {
    if ($k -eq 'MBS') { $secMbs = $sections[$k] }
    elseif ($k -eq 'OIB') { $secOib = $sections[$k] }
    elseif ($k -eq 'EUID') { $secEuid = $sections[$k] }
    elseif ($k -eq 'Status') { $secStatus = $sections[$k] }
    elseif ($k -eq 'Tvrtka') { $secTvrtka = $sections[$k] }
  }

  $tvrtkaLines = [string[]](As-StringArray (Get-TableTexts $secTvrtka))
  $naziv = $null
  $nazivKraci = $null
  if ($tvrtkaLines.Length -gt 0) { $naziv = $tvrtkaLines[0] }
  if ($tvrtkaLines.Length -gt 1) {
    $nazivKraci = $tvrtkaLines[1]
  } else {
    foreach ($line in $tvrtkaLines) {
      if ($line -match '\bd\.o\.o\.|\bd\.d\.|\bj\.d\.o\.o\.|\bLLC\b') { $nazivKraci = $line; break }
    }
  }

  $djelatnosti = [string[]](As-StringArray (
    (As-StringArray (Get-TableTexts $secDjelatnosti)) |
      ForEach-Object { $_ -replace '^\*\s*', '' } |
      Where-Object { $_ }
  ))

  $fullText = Strip-Tags $html
  $deleted = $false
  $deletedNote = $null
  if ($fullText -match '(?is)brisao je ovaj subjekt.{0,500}') {
    $deleted = $true
    $deletedNote = $Matches[0].Trim()
  }

  $oibVal = Get-FirstText $secOib

  return [pscustomobject]@{
    sourceUrl           = $url
    fetchedAt           = (Get-Date).ToString('o')
    mbs                 = $mbsNorm
    oib                 = if ($oibVal -match '(\d{11})') { $Matches[1] } elseif ($oibVal) { ($oibVal -replace '\D', '') } else { $null }
    euid                = Get-FirstText $secEuid
    status              = Get-FirstText $secStatus
    deleted             = $deleted
    deletedNote         = $deletedNote
    nadlezniSud         = Get-FirstText $secSud
    naziv               = $naziv
    nazivKraci          = $nazivKraci
    adresa              = (([string[]](As-StringArray (Get-TableTexts $secAdresa))) -join ', ')
    email               = Get-FirstText $secEmail
    temeljniKapital     = Get-FirstText $secKapital
    pravniOblik         = Get-FirstText $secOblik
    pretezitaDjelatnost = Get-FirstText $secPretezita
    djelatnosti         = $djelatnosti
    clanovi             = @(Parse-People $secClanovi)
    zastupnici          = @(Parse-People $secZastupnici)
    pravniOdnosi        = [string[]](As-StringArray (Get-TableTexts $secPravni))
    financijskaIzvjesca = [string[]](As-StringArray (Get-TableTexts $secFin))
    ok                  = $true
    error               = $null
  }
}

function Wait-SudregDelay {
  if ($MaxDelaySec -le $MinDelaySec) {
    Start-Sleep -Seconds $MinDelaySec
    return
  }
  $rnd = New-Object System.Random
  $delay = $MinDelaySec + ($rnd.NextDouble() * ($MaxDelaySec - $MinDelaySec))
  Start-Sleep -Seconds ([Math]::Round($delay, 3))
}

  $total = $script:SudregQueue.Count
  if ($total -eq 0) {
    throw "Nije predan nijedan MBS. Koristi -Mbs, -MbsFile ili pipeline (npr. Get-Content .\mbs.txt | ...)."
  }

  for ($i = 0; $i -lt $total; $i++) {
    $one = $script:SudregQueue[$i]
    try {
      $obj = Get-SudregSubjectObject -MbsValue $one
    } catch {
      $obj = [pscustomobject]@{
        sourceUrl           = $null
        fetchedAt           = (Get-Date).ToString('o')
        mbs                 = ($one -replace '\D', '').PadLeft(9, '0')
        oib                 = $null
        euid                = $null
        status              = $null
        deleted             = $null
        deletedNote         = $null
        nadlezniSud         = $null
        naziv               = $null
        nazivKraci          = $null
        adresa              = $null
        email               = $null
        temeljniKapital     = $null
        pravniOblik         = $null
        pretezitaDjelatnost = $null
        djelatnosti         = @()
        clanovi             = @()
        zastupnici          = @()
        pravniOdnosi        = @()
        financijskaIzvjesca = @()
        ok                  = $false
        error               = $_.Exception.Message
      }
    }

    [void]$script:SudregResults.Add($obj)

    if (-not $AsJson) {
      Write-Output $obj
    }

    if ($i -lt ($total - 1)) {
      Wait-SudregDelay
    }
  }

  if ($AsJson) {
    if ($script:SudregResults.Count -eq 1) {
      $script:SudregResults[0] | ConvertTo-Json -Depth 8
    } else {
      @($script:SudregResults.ToArray()) | ConvertTo-Json -Depth 8
    }
  }
}
