import { supabase } from '../lib/supabase';
import type { QuotationItem, Customer } from '../types';

interface CompleteSaleParams {
  sale_type: 'counter' | 'video_call';
  customer_id: string | null;
  video_call_id: string | null;
  quotation_data: {
    items: Array<{
      product_id: string;
      quantity: number;
      price: number;
      product: {
        name: string;
        sku: string;
        description: string;
        manufacturer: string;
        category: string;
      };
    }>;
    total_amount: number;
    quotation_number: string;
    delivery_method: string;
  };
  payment_details: {
    total_amount: number;
    paid_amount: number;
    pending_amount: number;
    payment_status: string;
    payments: Array<{
      amount: number;
      date: string;
      type: string;
      method: string;
    }>;
  };
}

export const completeSale = async (params: CompleteSaleParams) => {
  try {
    // Validate payment details structure
    if (!params.payment_details ||
        typeof params.payment_details.total_amount !== 'number' ||
        typeof params.payment_details.paid_amount !== 'number' ||
        typeof params.payment_details.pending_amount !== 'number' ||
        !params.payment_details.payment_status ||
        !Array.isArray(params.payment_details.payments)) {
      throw new Error('Invalid payment details structure');
    }

    // Add initial payment record if paid amount > 0
    if (params.payment_details.paid_amount > 0) {
      params.payment_details.payments.push({
        amount: params.payment_details.paid_amount,
        date: new Date().toISOString(),
        type: params.payment_details.paid_amount === params.payment_details.total_amount ? 'full' : 'partial',
        method: 'cash'
      });
    }

    // Calculate totals first to avoid nested aggregates
    const totalItems = params.quotation_data.items.reduce((sum, item) => sum + item.quantity, 0);
    const totalAmount = params.quotation_data.total_amount;

    // Create quotation
    const { data: quotation, error: quotationError } = await supabase
      .from('quotations')
      .insert([{
        customer_id: params.customer_id,
        video_call_id: params.video_call_id,
        items: params.quotation_data.items,
        total_amount: totalAmount,
        status: 'accepted',
        payment_details: params.payment_details,
        workflow_status: {
          qc: params.quotation_data.delivery_method === 'hand_carry' ? 'completed' : 'pending',
          packaging: params.quotation_data.delivery_method === 'hand_carry' ? 'completed' : 'pending',
          dispatch: params.quotation_data.delivery_method === 'hand_carry' ? 'completed' : 'pending'
        },
        quotation_number: params.quotation_data.quotation_number,
        valid_until: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString(),
        bill_status: params.payment_details.payment_status === 'completed' ? 'paid' : 'pending',
        bill_generated_at: new Date().toISOString(),
        bill_paid_at: params.payment_details.payment_status === 'completed' ? new Date().toISOString() : null
      }])
      .select()
      .single();

    if (quotationError) throw quotationError;

    // Update video call if applicable
    if (params.video_call_id) {
      const { error: videoCallError } = await supabase
        .from('video_calls')
        .update({
          quotation_id: quotation.id,
          quotation_required: true,
          workflow_status: {
            video_call: 'completed',
            quotation: 'completed',
            profiling: 'pending',
            payment: params.payment_details.payment_status === 'completed' ? 'completed' : 'pending',
            qc: params.quotation_data.delivery_method === 'hand_carry' ? 'completed' : 'pending',
            packaging: params.quotation_data.delivery_method === 'hand_carry' ? 'completed' : 'pending',
            dispatch: params.quotation_data.delivery_method === 'hand_carry' ? 'completed' : 'pending'
          },
          bill_status: params.payment_details.payment_status === 'completed' ? 'paid' : 'pending',
          bill_amount: totalAmount,
          bill_generated_at: new Date().toISOString(),
          bill_paid_at: params.payment_details.payment_status === 'completed' ? new Date().toISOString() : null
        })
        .eq('id', params.video_call_id);

      if (videoCallError) throw videoCallError;
    }

    // Update customer purchase history if applicable
    if (params.customer_id) {
      const { error: customerError } = await supabase
        .from('customers')
        .update({
          total_purchases: supabase.sql`total_purchases + ${totalAmount}`,
          last_purchase_date: new Date().toISOString()
        })
        .eq('id', params.customer_id);

      if (customerError) throw customerError;
    }

    // Update stock levels one by one to avoid nested aggregates
    for (const item of params.quotation_data.items) {
      const { error: stockError } = await supabase
        .from('products')
        .update({
          stock_level: supabase.sql`stock_level - ${item.quantity}`,
          last_sold_at: new Date().toISOString()
        })
        .eq('id', item.product_id);

      if (stockError) throw stockError;
    }

    // Create sale record
    const { error: saleError } = await supabase
      .from('sales')
      .insert([{
        sale_type: params.sale_type,
        customer_id: params.customer_id,
        video_call_id: params.video_call_id,
        quotation_id: quotation.id,
        sale_number: params.quotation_data.quotation_number,
        total_amount: totalAmount,
        payment_status: params.payment_details.payment_status === 'completed' ? 'paid' : 'pending',
        payment_details: params.payment_details
      }]);

    if (saleError) throw saleError;

    return { success: true, quotationId: quotation.id };
  } catch (error) {
    console.error('Error completing sale:', error);
    throw error;
  }
};