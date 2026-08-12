"""Fix corrupted visual feedback section in quick_product_creation_dialog.dart"""
import sys

f = r'c:\Users\jihad\Desktop\shop-maniger-MBmain\lib\widgets\quick_product_creation_dialog.dart'

with open(f, 'r', encoding='utf-8') as fh:
    content = fh.read()

# The correct visual feedback block (lines 1012-1058 need to be replaced)
correct_block = '''                    // Visual feedback for auto-calculation
                    if (_invoiceOriginalUnit != null && _invoiceOriginalCost > 0 && _hierarchyItems.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Builder(builder: (_) {
                        final factor = (_hierarchyItems.first['contains_qty'] as num?)?.toDouble() ?? 0;
                        if (factor <= 0) return const SizedBox.shrink();
                        final costPerBase = _invoiceOriginalCost / factor;
                        final sellPerBase = costPerBase * 1.10;
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.blue.withOpacity(0.3)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.calculate, color: Colors.blue, size: 20),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      '\u0633\u0639\u0631 \u0627\u0644$_invoiceOriginalUnit ${NumberFormat('#,##0').format(_invoiceOriginalCost)} \u00f7 ${factor.toInt()} ${_baseUnitNameController.text}',
                                      style: const TextStyle(fontSize: 12, color: Colors.blue),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  const SizedBox(width: 28),
                                  Expanded(
                                    child: Text(
                                      '= \u0633\u0639\u0631 \u0627\u0644\u062a\u0643\u0644\u0641\u0629: ${NumberFormat('#,##0').format(costPerBase)}  |  \u0633\u0639\u0631 \u0627\u0644\u0628\u064a\u0639: ${NumberFormat('#,##0').format(sellPerBase)} (+10%)',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.green),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
'''

# Find the corrupted block by its markers
start_marker = "// Visual feedback for auto-calculation"
end_marker_after_block = "                  ],\r\n                ),\r\n              ),"

# Find start of corrupted block
start_idx = content.find(start_marker)
if start_idx == -1:
    print("ERROR: Could not find start marker")
    sys.exit(1)

# Go back to beginning of line
line_start = content.rfind('\n', 0, start_idx) + 1

# Find the end after the block - look for the closing brackets pattern
# The block ends with "                    ],\r\r\n" followed by "                  ],\r\n"
# Find "                  ]," after the start
search_from = start_idx
# Find the pattern that closes the if-spread block: "                    ]," 
# then "                  ]," (closing the Column children)
# then "                )," (closing the Column)  
# then "              )," (closing _buildExpandableSection)

# Strategy: find all content from start_marker to the next "              )," after "                ),\r\n              ),"
# The pattern we need to find is the closing of the expandable section

# Let's find the end by looking for the line "              ),\r\n" that follows "                ),\r\n"
# after our block

# Simpler approach: find the old block content between start marker and end
# We know it ends before "              \r\n              const SizedBox(height: 24),"
end_pattern = "              \r\n              const SizedBox(height: 24),"
end_idx = content.find(end_pattern, start_idx)

if end_idx == -1:
    # Try without extra \r
    end_pattern = "              \n              const SizedBox(height: 24),"  
    end_idx = content.find(end_pattern, start_idx)

if end_idx == -1:
    # Try to find just the SizedBox after the block
    end_pattern = "const SizedBox(height: 24),"
    end_idx = content.find(end_pattern, start_idx)
    if end_idx == -1:
        print("ERROR: Could not find end marker")
        sys.exit(1)
    # Go back to include the whitespace before it
    # Find the last newline before end_idx
    last_nl = content.rfind('\n', start_idx, end_idx)
    end_idx = last_nl + 1  # Start of the line with SizedBox

# Now also need to find what comes BEFORE the visual feedback block
# It should be right after "                    )," (the TextButton closing)
# Let's find the "                    )," line that comes just before

# Everything from line_start to end_idx is the corrupted block + closing brackets
# We need to replace from line_start to end_idx with the correct block

# But we need to keep "                  ],\r\n                ),\r\n              ),"
# which are the closing brackets of the Column, child, and _buildExpandableSection

old_content = content[line_start:end_idx]
print(f"Found corrupted block ({len(old_content)} chars)")
print(f"First 80 chars: {repr(old_content[:80])}")
print(f"Last 80 chars: {repr(old_content[-80:])}")

# The correct replacement includes the visual feedback PLUS the closing brackets
correct_replacement = correct_block + "                  ],\r\n                ),\r\n              ),\r\n              \r\n"

new_content = content[:line_start] + correct_replacement + content[end_idx:]

with open(f, 'w', encoding='utf-8') as fh:
    fh.write(new_content)

print(f"SUCCESS: File fixed. Old block was {len(old_content)} chars, new block is {len(correct_replacement)} chars")
