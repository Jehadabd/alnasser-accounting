@echo off
chcp 65001 >nul
setlocal EnableDelayedExpansion
cd /d "%~dp0"
rem ==========================================================================
rem  claude_money_coverage.bat  = خريطة مسارات المال: أيها مرّ به اختبار وأيها لم يمر
rem  يشغّل كل اختبارات المال (السريعة) مع قياس التغطية، ثم يكتب التقرير:
rem    test_results\money_coverage\report.txt
rem  شغّله وحده، بعد أن تنجح الاختبارات كل منها على حدة (يأخذ وقتها كلها مجتمعة).
rem ==========================================================================
if not exist test_results\money_coverage mkdir test_results\money_coverage
set OUT=test_results\money_coverage\tests_output.txt
echo [1/2] تشغيل اختبارات المال مع قياس التغطية (طويل) — السجل في %OUT%
call flutter test --coverage --concurrency=1 --dart-define=COVERAGE=true --dart-define=QUICK=true --dart-define=FAST_DISK=true ^
  test\services\iqd_whole_dinar_test.dart ^
  test\sync_harness\invoice_math_test.dart ^
  test\sync_harness\full_accounting_scenarios_test.dart ^
  test\sync_harness\supplier_flows_test.dart ^
  test\sync_harness\extreme_scenarios_test.dart ^
  test\sync_harness\ledger_extras_test.dart ^
  test\sync_harness\rest_torture_test.dart ^
  test\sync_harness\accounting_torture_test.dart ^
  test\sync_harness\features_torture_test.dart ^
  test\sync_harness\invoice_scenarios_test.dart ^
  test\sync_harness\rare_sync_branches_test.dart ^
  test\sync_harness\armored_approval_test.dart ^
  test\sync_harness\compound_receipt_test.dart ^
  test\sync_harness\comprehensive_test.dart > %OUT% 2>&1
if errorlevel 1 echo ⚠️ بعض الاختبارات فشلت — التغطية تُقاس رغم ذلك، وانظر %OUT%
echo [2/2] الخريطة
call dart run tool\money_coverage.dart
pause
