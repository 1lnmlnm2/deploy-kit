param(
    [Parameter(Mandatory = $true)][string]$Server,
    [string]$Package = "",
    [string]$Sha256 = "",
    [int]$SshPort = 22,
    [int]$AppPort = 8090
)

# preflight.ps1 —— Windows 侧发布前检查：包存在 + sha256 匹配、远端 22/8090 可达、本机 8090 未占用。
# 状态词与 bash 版一致；退出码 0=全 OK / 1=有 WARN / 2=有 FAIL。仅 PowerShell 7。

$script:rc = 0
function Report([string]$level, [string]$item, [string]$value) {
    '{0,-7} {1}: {2}' -f "[$level]", $item, $value
    if ($level -eq 'FAIL') { $script:rc = 2 }
    elseif ($level -eq 'WARN' -and $script:rc -lt 1) { $script:rc = 1 }
}
function Test-Tcp([string]$Target, [int]$Port) {
    $client = [System.Net.Sockets.TcpClient]::new()
    try {
        return $client.ConnectAsync($Target, $Port).Wait(3000)
    } catch {
        return $false
    } finally {
        $client.Dispose()
    }
}

if ([string]::IsNullOrWhiteSpace($Package)) {
    Report 'WARN' '交付包' '未提供 -Package，跳过存在性与校验'
} elseif (-not (Test-Path -LiteralPath $Package -PathType Leaf)) {
    Report 'FAIL' '交付包' "不存在: $Package"
} else {
    Report 'OK' '交付包' "存在: $Package"
    if ([string]::IsNullOrWhiteSpace($Sha256)) {
        Report 'WARN' 'sha256' '未提供 -Sha256，跳过比对'
    } else {
        $actual = (Get-FileHash -LiteralPath $Package -Algorithm SHA256).Hash.ToLower()
        if ($actual -eq $Sha256.ToLower()) {
            Report 'OK' 'sha256' '与给定值一致'
        } else {
            Report 'FAIL' 'sha256' "不一致: 实际 $actual"
        }
    }
}

if (Test-Tcp $Server $SshPort) {
    Report 'OK' "远端 $SshPort" '可达'
} else {
    Report 'FAIL' "远端 $SshPort" '不可达'
}

if (Test-Tcp $Server $AppPort) {
    Report 'OK' "远端 $AppPort" '可达'
} else {
    Report 'WARN' "远端 $AppPort" '不可达（首装前正常）'
}

$local = Get-NetTCPConnection -LocalPort $AppPort -State Listen -ErrorAction SilentlyContinue
if ($local) {
    Report 'FAIL' "本机 $AppPort" '已被占用'
} else {
    Report 'OK' "本机 $AppPort" '未占用'
}

exit $script:rc
