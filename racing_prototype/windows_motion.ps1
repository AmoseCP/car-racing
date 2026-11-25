$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::ASCII

try {
    $parent = [Diagnostics.Process]::GetProcessById($gameProcessId)
    $accelerometer = [Windows.Devices.Sensors.Accelerometer, Windows.Devices.Sensors, ContentType=WindowsRuntime]
    $sensor = $null
    try {
        $readingType = [Windows.Devices.Sensors.AccelerometerReadingType, Windows.Devices.Sensors, ContentType=WindowsRuntime]
        $sensor = $accelerometer::GetDefault($readingType::Gravity)
    } catch {
        # Some drivers only expose their standard accelerometer.
    }
    if ($null -eq $sensor) {
        $sensor = $accelerometer::GetDefault()
    }
    if ($null -eq $sensor) {
        exit 0
    }

    $interval = [Math]::Max(16, [int]$sensor.MinimumReportInterval)
    try {
        $sensor.ReportInterval = [uint32]$interval
    } catch {
        # Keep polling at the sensor's reported minimum if its interval is fixed.
    }
    $culture = [Globalization.CultureInfo]::InvariantCulture
    $lastTicks = -1
    while (-not $parent.HasExited) {
        $reading = $sensor.GetCurrentReading()
        if ($null -ne $reading -and $reading.Timestamp.Ticks -ne $lastTicks) {
            $lastTicks = $reading.Timestamp.Ticks
            $values = [object[]]@($reading.AccelerationX, $reading.AccelerationY, $reading.AccelerationZ)
            [Console]::WriteLine([string]::Format($culture, '{0:R} {1:R} {2:R}', $values))
        }
        Start-Sleep -Milliseconds $interval
    }
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
