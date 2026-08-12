import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../providers/pos_provider.dart';

class CategoriesSidebar extends StatelessWidget {
  const CategoriesSidebar({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<POSProvider>(
      builder: (context, provider, child) {
        final categories = provider.categories;
        final selectedId = provider.selectedCategoryId;

        // Build list with "All" as first item
        final allItems = [null, ...categories];

        return Container(
          color: Colors.white,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'الأقسام',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Colors.grey[800],
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 1.4,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: allItems.length,
                  itemBuilder: (context, index) {
                    final category = allItems[index];
                    final bool isAll = category == null;
                    final bool isSelected = isAll 
                        ? selectedId == null 
                        : selectedId == category.id;

                    return InkWell(
                      onTap: () => provider.selectCategory(isAll ? null : category.id),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.blue[50] : Colors.grey[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected ? Colors.blue : Colors.grey.shade200,
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              isAll ? Icons.dashboard_outlined : Icons.category_outlined,
                              color: isSelected ? Colors.blue : Colors.grey[600],
                              size: 24,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              isAll ? 'الكل' : category.name,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isSelected ? Colors.blue[900] : Colors.black87,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
