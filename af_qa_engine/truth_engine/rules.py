# af_qa_engine/truth_engine/rules.py
from typing import List, Tuple
from .models import Invoice, Transaction, Customer

class FinancialRules:
    """
    مكتبة القواعد المالية المستخرجة من كود التطبيق (InvoiceController.dart + TransactionDao.dart)
    هذه القواعد تمثل 'الحقيقة' التي يجب أن يلتزم بها التطبيق.
    """

    @staticmethod
    def calculate_expected_debt_change(
        old_invoice: Invoice, 
        new_invoice: Invoice,
        is_new_record: bool = False
    ) -> float:
        """
        تحسب الفرق المتوقع في رصيد العميل بناءً على التعديل في الفاتورة.
        مطابقة للمنطق في InvoiceController.dart -> validateDebtChange...
        """
        
        # 1. حالة فاتورة جديدة تماماً
        if is_new_record:
            if new_invoice.paymentType != 'دين':
                return 0.0
            return new_invoice.net_total - new_invoice.paid_amount

        # 2. حالة تعديل فاتورة موجودة
        # حساب الدين القديم (الذي كان مسجلاً)
        old_remaining = 0.0
        if old_invoice.paymentType == 'دين':
            old_remaining = old_invoice.net_total - old_invoice.paid_amount

        # حساب الدين الجديد
        new_remaining = 0.0
        if new_invoice.paymentType == 'دين':
            new_remaining = new_invoice.net_total - new_invoice.paid_amount

        # التحقق من تغيير العميل (Customer Change Logic)
        # إذا تغير العميل، فالدين القديم يُلغى من العميل القديم، والدين الجديد يضاف للعميل الجديد.
        # هذه الدالة تحسب التأثير على العميل *الحالي* (أو القديم إذا كنا نتحقق منه).
        # للتبسيط هنا نفترض نفس العميل، أو أننا نحسب delta للعميل الأصلي.
        
        if old_invoice.customer_name != new_invoice.customer_name:
             # إذا تغير العميل، العميل القديم يجب أن يُخصم منه كل الدين القديم
             return -old_remaining

        # إذا لم يتغير العميل
        return new_remaining - old_remaining

    @staticmethod
    def verify_transaction_sequence(transactions: List[Transaction]) -> List[str]:
        """
        تتحقق من تسلسل المعاملات في 'سجل الديون'.
        يجب أن يكون الرصيد التراكمي متصلاً: الرصيد بعد (للمعاملة السابقة) == الرصيد قبل (للمعاملة الحالية).
        مطابقة للمنطق في TransactionDao.dart.
        """
        errors = []
        if not transactions:
            return errors

        # ترتيب المعاملات زمنياً
        sorted_txs = sorted(transactions, key=lambda x: (x.date, x.id))

        # التحقق من أول معاملة (إذا كان لها منطق خاص، مثلاً رصيد افتتاحي)
        # هنا نفترض أننا نتحقق من التسلسل الداخلي فقط
        
        for i in range(1, len(sorted_txs)):
            prev = sorted_txs[i-1]
            curr = sorted_txs[i]

            # تحقق 1: هل الرصيد 'قبل' لهذه المعاملة يساوي الرصيد 'بعد' للتي قبلها؟
            # هامش خطأ بسيط جداً للأرقام العائمة
            if abs(curr.balance_before - prev.balance_after) > 0.01:
                errors.append(
                    f"كسر في التسلسل عند المعاملة رقم {curr.id}. "
                    f"الرصيد المتوقع قبل: {prev.balance_after}، الموجود: {curr.balance_before}"
                )

            # تحقق 2: هل العملية الحسابية داخل المعاملة صحيحة؟
            calculated_after = curr.balance_before + curr.amount_changed
            if abs(calculated_after - curr.balance_after) > 0.01:
                errors.append(
                    f"خطأ حسابي في المعاملة {curr.id}. "
                    f"قبل ({curr.balance_before}) + التغيير ({curr.amount_changed}) != بعد ({curr.balance_after})"
                )

        return errors

    @staticmethod
    def verify_daily_report_totals(invoices: List[Invoice]) -> dict:
        """
        تجميع أرقام الفواتير للتحقق من تقرير اليوم.
        مطابقة للمنطق في ReportsService.getDailySalesInPeriod
        """
        total_sales = 0.0
        net_profit = 0.0 # يحتاج تكلفة، سنستخدم قيمة تقريبية أو نمرر التكلفة
        cash_sales = 0.0
        credit_sales = 0.0

        for inv in invoices:
            if inv.status != 'محفوظة':
                continue
                
            total_sales += inv.total_amount # أو net_total حسب منطق التطبيق (عادة net_total بعد الخصم)
            
            # ملاحظة: في كود ReportsService يستخدم total_amount كـ "Sales"
            # وفي مكان آخر يستخدم (Total - Discount)
            # حسب الكود: getMonthlySalesSummary يستخدم total_amount
            
            if inv.payment_type == 'نقد':
                cash_sales += inv.total_amount
            elif inv.payment_type == 'دين':
                credit_sales += inv.total_amount

        return {
            'total_sales': total_sales,
            'cash_sales': cash_sales,
            'credit_sales': credit_sales
        }
