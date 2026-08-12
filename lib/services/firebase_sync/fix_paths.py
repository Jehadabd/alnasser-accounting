import os, re
path = r'C:\Users\jihad\Desktop\shop\debt_book\lib\services\firebase_sync\firebase_sync_service.dart'
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

content = re.sub(r"\.collection\('sync_groups'\)\s*\.doc\(_groupId\)\s*\.collection", r".collection", content)

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)
print('Replaced sync_groups successfully')
