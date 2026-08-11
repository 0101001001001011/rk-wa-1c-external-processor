# Сборка RKWhatsApp.epf из XML-исходников. Выполняется НА МАШИНЕ С 1С.
#
# Конфигуратор — GUI-приложение: по SSH мы попадаем в сессию без рабочего
# стола, и он там не отработает. Поэтому скрипт запускается задачей
# планировщика с LogonType Interactive — она исполняется в интерактивном
# сеансе пользователя.
#
# Кириллица в параметрах передаётся через base64: PowerShell 5.1 читает
# файлы без BOM как ANSI и портит строки.

$ErrorActionPreference = 'Continue'

# Рабочий каталог задаётся переменной окружения, чтобы скрипт не зависел
# от того, куда его положили. Значение по умолчанию — каталог стенда.
$Work   = if ($env:RKWA_WORK) { $env:RKWA_WORK } else { 'C:\Temp\rkwa' }
$Bin    = if ($env:RKWA_1CV8) { $env:RKWA_1CV8 } else { 'C:\Program Files\1cv8\8.3.23.2236\bin\1cv8.exe' }
$Report = Join-Path $Work 'build-epf.txt'
$Log    = Join-Path $Work 'designer.log'
$Src    = Join-Path $Work 'src\RKWhatsApp.xml'
$Out    = Join-Path $Work 'RKWhatsApp.epf'

$lines = New-Object System.Collections.Generic.List[string]
function W($s) { $script:lines.Add([string]$s) }

# Отчёт пишется всегда, даже если скрипт упал на середине. Молчание —
# худший результат: по нему невозможно понять, что произошло.
trap {
    W ("СБОЙ: " + $_.Exception.Message)
    W ("в строке: " + $_.InvocationInfo.ScriptLineNumber + " — " + $_.InvocationInfo.Line.Trim())
    $lines | Out-File -FilePath $Report -Encoding utf8
    exit 1
}

# Строка подключения лежит отдельным файлом: в ней пароль, и её нельзя
# ни коммитить, ни передавать аргументом (аргументы видны в списке
# процессов всем, кто на машине).
$conn = Get-Content (Join-Path $Work 'conn.txt') -Raw -Encoding UTF8
$conn = $conn.Trim()   # строка вида /S"localhost\umc_dev2" /N"..." /P"..."
W ("строка подключения прочитана, длина " + $conn.Length)

Remove-Item $Out, $Log -ErrorAction SilentlyContinue
W ("исходник на месте: " + (Test-Path $Src))

$argline = 'DESIGNER ' + $conn + ' /DisableStartupMessages /DisableStartupDialogs ' +
           '/LoadExternalDataProcessorOrReportFromFiles "' + $Src + '" "' + $Out + '" ' +
           '/Out "' + $Log + '"'

$p = Start-Process -FilePath $Bin -ArgumentList $argline -PassThru
$exited = $p.WaitForExit(300000)
W ("завершился вовремя: " + $exited + " код=" + $(if ($p.HasExited) { $p.ExitCode } else { 'таймаут' }))

$warnings = $false
if (Test-Path $Log) {
    $text = Get-Content $Log -Raw -Encoding Default
    W '--- лог конфигуратора ---'
    W $text
    # Конфигуратор может отбросить привязку события и всё равно вернуть 0:
    # форма соберётся, но сама ничего не запустит. Читаем лог, а не только
    # код возврата.
    if ($text -match 'не было обнаружено') {
        W 'ВНИМАНИЕ: привязка события отброшена — форма не запустит код сама'
        $warnings = $true
    }
}

W ("epf собран: " + (Test-Path $Out) + " размер=" + $(if (Test-Path $Out) { (Get-Item $Out).Length } else { 0 }))
W ("замечания в логе: " + $warnings)
$lines | Out-File -FilePath $Report -Encoding utf8
