# af_qa_engine/forensic_audit.py
import sqlite3
import shutil
import os
import sys
from tabulate import tabulate # type: ignore

def audit_customer(db_path, customer_name):
    """
    Performs a forensic audit of a customer's data in the database.
    1. Safely copies the DB to avoiding locking.
    2. Queries Invoices, Items, and Transactions.
    3. Prints a detailed report.
    """
    print(f"\n🔍 بدء التحقيق الجنائي للعميل: {customer_name}")
    print(f"   📂 مسار قاعدة البيانات: {db_path}")

    if not os.path.exists(db_path):
        print("   ❌ ملف قاعدة البيانات غير موجود!")
        return

    # 1. Safe Copy
    temp_db = "temp_audit.db"
    try:
        shutil.copy2(db_path, temp_db)
    except Exception as e:
        print(f"   ❌ فشل نسخ قاعدة البيانات: {e}")
        return

    conn = sqlite3.connect(temp_db)
    cursor = conn.cursor()

    try:
        # 2. Find Customer
        # Note: Adjusting table names based on typical Odoo/Flutter schemas. 
        # Will fail gracefully if tables differ, allowing us to debug schema.
        cursor.execute("SELECT id, name, phone, address FROM clients WHERE name = ?", (customer_name,))
        client = cursor.fetchone()
        
        if not client:
            print(f"   ⚠️ العميل '{customer_name}' غير موجود في جدول Clients.")
            # Try 'customers' table just in case
            try:
                cursor.execute("SELECT id, name FROM customers WHERE name = ?", (customer_name,))
                client = cursor.fetchone()
            except:
                pass
        
        if not client:
             print("   ❌ العميل غير موجود نهائياً.")
             return

        client_id = client[0]
        print(f"   👤 تم التعرف على العميل: ID={client_id} | Name={client[1]}")

        # 3. Get Invoices (Orders)
        print("\n   🧾 [الفواتير - Invoices]")
        # Assuming table 'invoices' or 'orders'
        table_name = "invoices"
        try:
            cursor.execute(f"SELECT id, created_at, total, discount, final_total, is_paid, payment_type FROM {table_name} WHERE client_id = ?", (client_id,))
        except:
             # Fallback usually
             table_name = "bills"
             cursor.execute(f"SELECT id, date, total, discount, total_after_discount, is_cash, payment_type FROM {table_name} WHERE customer_id = ?", (client_id,))

        invoices = cursor.fetchall()
        
        inv_data = []
        for inv in invoices:
            inv_id = inv[0]
            # Fetch Items for this invoice
            # Assuming 'invoice_items' or 'bill_items'
            item_table = "invoice_items" if table_name == "invoices" else "bill_items"
            fk_col = "invoice_id" if table_name == "invoices" else "bill_id"
            
            cursor.execute(f"SELECT product_name, quantity, price, total FROM {item_table} WHERE {fk_col} = ?", (inv_id,))
            items = cursor.fetchall()
            item_str = ", ".join([f"{i[0]}({i[1]}x{i[2]})" for i in items])
            
            inv_data.append([inv[0], inv[1], inv[4], inv[6], item_str])

        print(tabulate(inv_data, headers=["ID", "Date", "Net Total", "Type", "Items"], tablefmt="grid"))

        # 4. Get Debt Log (Transactions)
        print("\n   📒 [سجل الديون - Transactions]")
        # Assuming 'client_accounts' or 'transactions'
        try:
             cursor.execute("SELECT id, created_at, amount, type, description FROM client_accounts WHERE client_id = ?", (client_id,))
             trans = cursor.fetchall()
             print(tabulate(trans, headers=["ID", "Date", "Amount", "Type", "Desc"], tablefmt="grid"))
             
             # Calculate Balance
             total_credit = sum([t[2] for t in trans if t[3] == 'credit']) # Or logic based on type
             total_debit = sum([t[2] for t in trans if t[3] == 'debit'])
             print(f"   💰 الرصيد المحسوب: {total_credit - total_debit}")

        except Exception as e:
            print(f"   ⚠️ لم يتم العثور على سجل معاملات: {e}")

    except Exception as e:
        print(f"   ❌ خطأ أثناء الاستعلام: {e}")
        # Schema Dump for debugging
        print("   🔍 جداول قاعدة البيانات:")
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table';")
        print(cursor.fetchall())
    
    finally:
        conn.close()
        try:
            os.remove(temp_db)
        except:
            pass

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python forensic_audit.py <db_path> <customer_name>")
    else:
        audit_customer(sys.argv[1], sys.argv[2])
