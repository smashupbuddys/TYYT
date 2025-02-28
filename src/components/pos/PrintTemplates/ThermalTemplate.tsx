import React from 'react';
import { format } from 'date-fns';
import { QRCodeSVG } from 'qrcode.react';
import { getCompanySettings, getPrintSettings } from '../../../utils/settings';
import type { PrintTemplatesProps } from './types';
import { calculateTotals, numberToWords } from '../../../utils/quotation';

const ThermalTemplate: React.FC<PrintTemplatesProps> = ({
  items,
  customerType,
  total,
  customer,
  discount,
  quotationNumber,
  gstRate,
  includeGst = true
}) => {
  const companySettings = getCompanySettings();
  const printSettings = getPrintSettings();
  const totals = calculateTotals(items, discount, gstRate, includeGst);

  // Calculate category totals with memoization
  const categoryTotals = React.useMemo(() => {
    const totals = items.reduce((acc, item) => {
      const category = item.product.category;
      if (!acc[category]) {
        acc[category] = { quantity: 0 };
      }
      acc[category].quantity += item.quantity;
      return acc;
    }, {} as Record<string, { quantity: number }>);

    // Calculate grand total
    const grandTotal = Object.values(totals).reduce(
      (sum, cat) => ({
        quantity: sum.quantity + cat.quantity
      }),
      { quantity: 0 }
    );

    return { categories: totals, grandTotal };
  }, [items]);

  const Header = () => (
    <div className="text-center border-b pb-2 mb-2">
      <div className="font-bold text-lg">{companySettings.name}</div>
      <div className="text-sm">{companySettings.address}</div>
      <div className="text-sm">GSTIN: {companySettings.gst_number}</div>
      <div className="text-sm">Ph: {companySettings.phone}</div>
    </div>
  );

  const BillInfo = () => (
    <div className="mb-3 text-sm">
      <div className="flex justify-between">
        <span className="font-medium">Bill No: {quotationNumber}</span>
        <span>{format(new Date(), 'dd/MM/yy HH:mm')}</span>
      </div>
      <div className="flex justify-between mt-1">
        <span>Customer: {customer?.name || 'Counter Sale'}</span>
        {customer?.phone && <span>Ph: {customer.phone}</span>}
      </div>
    </div>
  );

  const ItemsTable = () => (
    <table className="w-full text-sm mb-3">
      <thead className="border-y">
        <tr>
          <th className="text-left py-1">Item</th>
          <th className="text-right w-16">Qty</th>
          <th className="text-right w-20">Rate</th>
          <th className="text-right w-20">Amt</th>
        </tr>
      </thead>
      <tbody className="divide-y">
        {items.map((item, index) => (
          <tr key={index} className="py-1">
            <td>
              <div>{item.product.category}</div>
              <div className="text-xs text-gray-600">{item.product.sku}</div>
            </td>
            <td className="text-right">{item.quantity}</td>
            <td className="text-right">{item.price.toFixed(2)}</td>
            <td className="text-right">{(item.quantity * item.price).toFixed(2)}</td>
          </tr>
        ))}
      </tbody>
    </table>
  );

  const CategorySummary = () => (
    <div className="mb-3 border-t pt-2">
      <div className="font-medium mb-2">Items Summary:</div>
      <div className="space-y-1">
          {Object.entries(categoryTotals.categories).map(([category, data]) => (
            <div key={category} className="flex justify-between text-sm">
              <span>{category}:</span>
              <span className="mono">{data.quantity} pcs</span>
            </div>
          ))}
          <div className="flex justify-between font-medium text-sm pt-1 border-t border-dotted">
            <span>Total Items:</span>
            <span className="mono">{categoryTotals.grandTotal.quantity} pcs</span>
          </div>
      </div>
    </div>
  );

  const TotalSection = () => (
    <div className="border-t pt-2 mb-3">
      <div className="flex justify-between text-sm">
        <span>Subtotal:</span>
        <span>{totals.subtotal.toFixed(2)}</span>
      </div>
      {discount > 0 && (
        <div className="flex justify-between text-sm text-green-600">
          <span>Discount ({discount}%):</span>
          <span>-{totals.discountAmount.toFixed(2)}</span>
        </div>
      )}
      {includeGst && (
        <div className="flex justify-between text-sm">
          <span>GST ({gstRate}%):</span>
          <span>{totals.gstAmount.toFixed(2)}</span>
        </div>
      )}
      <div className="flex justify-between font-bold mt-1 pt-1 border-t">
        <span>Net Amount:</span>
        <span>{totals.finalTotal.toFixed(2)}</span>
      </div>
    </div>
  );

  const Footer = () => (
    <div className="text-center text-sm space-y-2">
      <div className="border-t pt-2">
        <div className="font-medium">Amount in Words:</div>
        <div className="text-xs">{numberToWords(totals.finalTotal)} Only</div>
      </div>
      {printSettings.footerText && (
        <div className="border-t pt-2">{printSettings.footerText}</div>
      )}
      {printSettings.termsText && (
        <div className="border-t pt-2 text-left">
          <div className="font-medium">Terms & Conditions:</div>
          <div className="text-xs whitespace-pre-line">{printSettings.termsText}</div>
        </div>
      )}
      <div className="border-t pt-2">
        <div>Thank You for Your Business!</div>
        <div className="flex justify-center mt-2">
          <QRCodeSVG 
            value={JSON.stringify({
              quotationNumber,
              total: totals.finalTotal,
              date: format(new Date(), 'yyyy-MM-dd'),
              customer: customer?.name || 'Counter Sale'
            })}
            size={80}
            level="M"
            includeMargin={true}
          />
        </div>
        <div className="text-xs mt-1">{quotationNumber}</div>
      </div>
    </div>
  );

  return (
    <div className="p-4 max-w-sm mx-auto bg-white">
      <Header />
      <BillInfo />
      <ItemsTable />
      <CategorySummary />
      <TotalSection />
      <Footer />
    </div>
  );
};

export default ThermalTemplate;