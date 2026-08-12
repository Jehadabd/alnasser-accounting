# Test Windows OCR availability
Write-Host "Testing Windows OCR..." -ForegroundColor Cyan

try {
    Add-Type -AssemblyName System.Runtime.WindowsRuntime
    Write-Host "✓ System.Runtime.WindowsRuntime loaded" -ForegroundColor Green
    
    $null = [Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime]
    Write-Host "✓ Windows.Media.Ocr.OcrEngine loaded" -ForegroundColor Green
    
    $langs = [Windows.Media.Ocr.OcrEngine]::AvailableRecognizerLanguages
    Write-Host "`nAvailable OCR Languages:" -ForegroundColor Yellow
    foreach ($lang in $langs) {
        Write-Host "  - $($lang.LanguageTag)" -ForegroundColor White
    }
    
    if ($langs.Count -eq 0) {
        Write-Host "`n⚠ No OCR languages installed!" -ForegroundColor Red
        Write-Host "To install Arabic OCR, run as Administrator:" -ForegroundColor Yellow
        Write-Host "  Add-WindowsCapability -Online -Name 'Language.OCR~~~ar-SA~0.0.1.0'" -ForegroundColor Cyan
    }
    
} catch {
    Write-Host "✗ Error: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`nPress any key to exit..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
