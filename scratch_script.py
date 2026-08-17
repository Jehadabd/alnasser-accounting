import re

file_path = r'c:\Users\jihad\Desktop\shop-maniger-MBmain\lib\services\reports_service.dart'
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# Pattern for 'i.status = 'محفوظة''
def replacer_i(match):
    return match.group(1) + ' ${_deviceFilterFor("i.")}'

# Pattern for 'status = 'محفوظة'' (without i.)
def replacer_no_i(match):
    return match.group(1) + ' $_deviceFilter'

# Pattern for 'i.is_deleted'
def replacer_transactions_i(match):
    return match.group(1) + ' ${_deviceFilterFor("t.")}'

def replacer_transactions_no_i(match):
    return match.group(1) + ' $_deviceFilter'

content = re.sub(r"(AND\s+i\.status\s*=\s*'محفوظة')", replacer_i, content)
content = re.sub(r"(AND\s+status\s*=\s*'محفوظة')", replacer_no_i, content)

# For transactions:
content = re.sub(r"(WHERE\s+customer_id\s*=\s*\?[^']*?(?:AND\s+\(is_deleted\s+IS\s+NULL\s+OR\s+is_deleted\s*=\s*0\)))", replacer_transactions_no_i, content)
content = re.sub(r"(WHERE\s+t\.customer_id\s*=\s*\?[^']*?(?:AND\s+\(t\.is_deleted\s+IS\s+NULL\s+OR\s+t\.is_deleted\s*=\s*0\)))", replacer_transactions_i, content)


with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)
print("Done modifying queries.")
