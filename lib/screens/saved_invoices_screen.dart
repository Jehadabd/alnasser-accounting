import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../models/invoice.dart';
import 'create_invoice_screen.dart';

class SavedInvoicesScreen extends StatelessWidget {
  const SavedInvoicesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الفواتير المحفوظة'),
      ),
      body: Consumer<AppProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          return FutureBuilder<List<Invoice>>(
            future: provider.getAllInvoices(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return Center(
                  child: Text('حدث خطأ: ${snapshot.error}'),
                );
              }

              final invoices = snapshot.data ?? [];

              if (invoices.isEmpty) {
                return const Center(
                  child: Text('لا توجد فواتير محفوظة'),
                );
              }

              return ListView.builder(
                itemCount: invoices.length,
                itemBuilder: (context, index) {
                  final invoice = invoices[index];
                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: ListTile(
                      title: Text(
                        invoice.customerName,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('التاريخ: ${invoice.invoiceDate.toString().split(' ')[0]}'),
                          if (invoice.customerPhone != null && invoice.customerPhone!.isNotEmpty)
                            Text('الهاتف: ${invoice.customerPhone}'),
                        ],
                      ),
                      trailing: Text(
                        '${invoice.totalAmount.toStringAsFixed(2)} دينار',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => CreateInvoiceScreen(
                              existingInvoice: invoice,
                              isViewOnly: invoice.status == 'محفوظة',
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
} 