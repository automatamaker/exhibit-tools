# ============================================================================
#  enable_ssh.ps1 — 【各Windows機で一度だけ・管理者で実行】
#  Windows 10 22H2 を Raspberry Pi から遠隔セットアップできるようにする下ごしらえ。
#  やること:
#    1) OpenSSH Server を導入＋自動起動
#    2) 受信ファイアウォールを許可
#    3) SSH の既定シェルを PowerShell に（Pi から流すコマンド用）
#    4) Pi(展示セットアップ機) の公開鍵を信頼させる
#    5) この機体の接続情報（Computer/User/IP/Edition）を表示
#  実行後、表示された IP と User を Pi 側の担当（claude）に伝えれば、あとは遠隔で全自動。
#
#  実行方法（「管理者として実行」した PowerShell で、ラクなものを1つ。手打ちでOK）:
#    A) Piから取得（短い）:  irm http://<PiのIP>/e | iex
#    B) GitHubから取得:      irm https://raw.githubusercontent.com/automatamaker/exhibit-tools/master/win/enable_ssh.ps1 | iex
#    C) ファイルを置いて:    Set-ExecutionPolicy -Scope Process Bypass -Force; .\enable_ssh.ps1
#  ※ PowerShell への貼り付けは「右クリック」。まず必ず「管理者として実行」で開くこと。
# ============================================================================
$ErrorActionPreference = 'Stop'

# 管理者権限チェック（irm|iex でも動くよう #Requires は使わない）
$__admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
if (-not $__admin) {
    Write-Host '【要・管理者】PowerShell を「管理者として実行」で開き直してから、もう一度実行してください。' -ForegroundColor Red
    return
}

# ---- Pi(展示セットアップ機) の公開鍵。埋め込み済み。差し替え不要 ----
$PiPubKey = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDEGGdPA0u592Wpw1t8HPZ/OJUB7U2egpCAReV/IcbMf winfleet@gamedev'

Write-Host '== 1) OpenSSH Server を導入/有効化 ==' -ForegroundColor Cyan
$cap = Get-WindowsCapability -Online | Where-Object { $_.Name -like 'OpenSSH.Server*' }
if ($cap.State -ne 'Installed') {
    Write-Host '   OpenSSH.Server を追加中...'
    Add-WindowsCapability -Online -Name $cap.Name | Out-Null
} else {
    Write-Host '   既に導入済み'
}
Set-Service -Name sshd -StartupType Automatic
Start-Service sshd

Write-Host '== 2) ファイアウォール(受信 TCP/22) を許可 ==' -ForegroundColor Cyan
if (-not (Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' `
        -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null
    Write-Host '   受信ルールを作成'
} else {
    Write-Host '   受信ルールは既存'
}

Write-Host '== 3) SSH の既定シェルを PowerShell に ==' -ForegroundColor Cyan
if (-not (Test-Path 'HKLM:\SOFTWARE\OpenSSH')) { New-Item -Path 'HKLM:\SOFTWARE\OpenSSH' -Force | Out-Null }
New-ItemProperty -Path 'HKLM:\SOFTWARE\OpenSSH' -Name DefaultShell `
    -Value (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') `
    -PropertyType String -Force | Out-Null

Write-Host '== 4) Pi の公開鍵を信頼（administrators_authorized_keys） ==' -ForegroundColor Cyan
$akFile = Join-Path $env:ProgramData 'ssh\administrators_authorized_keys'
if (-not (Test-Path $akFile)) { New-Item -ItemType File -Path $akFile -Force | Out-Null }
$existing = @(Get-Content $akFile -ErrorAction SilentlyContinue)
if ($existing -notcontains $PiPubKey) { Add-Content -Path $akFile -Value $PiPubKey }
# 管理者用 authorized_keys は ACL が厳格でないと sshd が拒否する。
# well-known SID を使い日本語版でも確実に: S-1-5-32-544=Administrators, S-1-5-18=SYSTEM
icacls $akFile /inheritance:r | Out-Null
icacls $akFile /grant '*S-1-5-32-544:F' '*S-1-5-18:F' | Out-Null

Restart-Service sshd

# ---- 5) 接続情報を表示 ----
$ip = (Get-NetIPAddress -AddressFamily IPv4 |
        Where-Object { $_.IPAddress -notlike '169.254.*' -and $_.IPAddress -ne '127.0.0.1' } |
        Sort-Object -Property InterfaceMetric |
        Select-Object -First 1).IPAddress
Write-Host ''
Write-Host '================ この機体の接続情報（Piに伝えてください） ================' -ForegroundColor Green
Write-Host ("  Computer : {0}" -f $env:COMPUTERNAME)
Write-Host ("  User     : {0}" -f $env:USERNAME)
Write-Host ("  IP       : {0}" -f $ip)
Write-Host ("  Edition  : {0}" -f (Get-CimInstance Win32_OperatingSystem).Caption)
Write-Host '========================================================================' -ForegroundColor Green
Write-Host '  → この4行を Pi 側の担当に伝えてください。以降は Pi から遠隔で全自動です。'
