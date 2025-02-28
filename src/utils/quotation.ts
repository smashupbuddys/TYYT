import { format } from 'date-fns';
import type { QuotationItem } from '../types';

export const generateQuotationNumber = () => {
  return `Q${format(new Date(), 'yyyyMMdd')}${Math.floor(Math.random() * 1000).toString().padStart(3, '0')}`;
};

export const calculateTotals = (
  items: QuotationItem[],
  discount: number,
  gstRate: number = 18,
  includeGst: boolean = true
) => {
  const subtotal = items.reduce((sum, item) => {
    const price = Number(item.price) || 0;
    const quantity = Number(item.quantity) || 0;
    return sum + (price * quantity);
  }, 0);

  const discountAmount = (subtotal * discount) / 100;
  const total = subtotal - discountAmount;
  const gstAmount = includeGst ? (total * gstRate) / 100 : 0;
  const finalTotal = total + gstAmount;

  return {
    subtotal,
    discountAmount,
    total,
    gstAmount,
    finalTotal,
    gstRate
  };
};

export function numberToWords(num: number): string {
  const ones = ['', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine'];
  const tens = ['', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety'];
  const teens = ['Ten', 'Eleven', 'Twelve', 'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen', 'Seventeen', 'Eighteen', 'Nineteen'];

  function convert(n: number): string {
    if (n < 10) return ones[n];
    if (n < 20) return teens[n - 10];
    if (n < 100) return tens[Math.floor(n / 10)] + (n % 10 ? ' ' + ones[n % 10] : '');
    if (n < 1000) return ones[Math.floor(n / 100)] + ' Hundred' + (n % 100 ? ' ' + convert(n % 100) : '');
    if (n < 100000) return convert(Math.floor(n / 1000)) + ' Thousand' + (n % 1000 ? ' ' + convert(n % 1000) : '');
    if (n < 10000000) return convert(Math.floor(n / 100000)) + ' Lakh' + (n % 100000 ? ' ' + convert(n % 100000) : '');
    return convert(Math.floor(n / 10000000)) + ' Crore' + (n % 10000000 ? ' ' + convert(n % 10000000) : '');
  }

  const rupees = Math.floor(num);
  const paise = Math.round((num - rupees) * 100);
  
  let result = 'Rupees ' + convert(rupees);
  if (paise > 0) {
    result += ' and ' + convert(paise) + ' Paise';
  }
  
  return result;
}
export const formatCurrency = (amount: number) => {
  if (typeof amount !== 'number' || isNaN(amount)) {
    amount = 0;
  }
  return `₹${amount.toLocaleString('en-IN', {
    maximumFractionDigits: 2,
    minimumFractionDigits: 2
  })}`;
};

export const validateQuotation = (items: QuotationItem[]) => {
  if (items.length === 0) {
    return 'Please add items to the quotation';
  }

  for (const item of items) {
    if (item.quantity > item.product.stockLevel) {
      return `Insufficient stock for ${item.product.name}`;
    }
    if (item.quantity <= 0) {
      return `Invalid quantity for ${item.product.name}`;
    }
    if (item.price <= 0) {
      return `Invalid price for ${item.product.name}`;
    }
  }

  return null;
};

export const getDiscountLimits = (
  customerType: 'wholesaler' | 'retailer',
  isAdvancedDiscountEnabled: boolean
) => {
  if (isAdvancedDiscountEnabled) {
    return {
      max: 100,
      presets: [5, 10, 15, 20, 25, 30]
    };
  }

  return customerType === 'retailer'
    ? {
        max: 3,
        presets: [1, 2, 3]
      }
    : {
        max: 10,
        presets: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
      };
};