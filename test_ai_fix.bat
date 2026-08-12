@echo off
echo ========================================
echo Testing AI API Fixes
echo ========================================
echo.
echo Cleaning build...
flutter clean
echo.
echo Getting dependencies...
flutter pub get
echo.
echo Running app...
echo Watch for these messages in the logs:
echo   - Groq model: llama-3.2-90b-vision-preview
echo   - Success messages from Groq or Gemini
echo.
flutter run
