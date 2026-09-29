@echo off
chcp 65001 >nul
cd /d "%~dp0"
if not exist test_results mkdir test_results
del /q test_results\*.txt 2>nul
echo [1/7] flutter pub get
call flutter pub get > test_results\1_pubget.txt 2>&1
echo [2/7] flutter analyze
call flutter analyze --no-fatal-infos --no-fatal-warnings > test_results\2_analyze.txt 2>&1
echo [3/7] full accounting scenarios (10 invoices, returns, sync, lock)
call flutter test test\sync_harness\full_accounting_scenarios_test.dart > test_results\3_full_scenarios.txt 2>&1
echo [4/7] invoice math
call flutter test test\sync_harness\invoice_math_test.dart > test_results\4_invoice_math.txt 2>&1
echo [5/7] accounting + lan + money
call flutter test test\accounting test\lan test\money_calculator_test.dart > test_results\5_accounting_lan.txt 2>&1
echo [6/7] sync harness: smoke, residual risks, products, stock migration
call flutter test test\sync_harness\smoke_test.dart test\sync_harness\residual_risks_test.dart test\sync_harness\product_merge_test.dart test\sync_harness\stock_migration_test.dart > test_results\6_sync.txt 2>&1
echo [7/7] sync chaos
call flutter test test\sync_harness\chaos_test.dart > test_results\7_chaos.txt 2>&1
echo DONE > test_results\done.txt
echo.
echo ===== انتهى — أخبر Claude =====
pause
