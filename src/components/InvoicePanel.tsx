import React from 'react';
import { CartItem } from '../types';
import { CartItem as CartItemComponent } from './CartItem';
import { DiscountPanel } from './DiscountPanel';
import { PaymentMethodSelector } from './PaymentMethodSelector';
import { Discount } from '../types';

interface InvoicePanelProps {
  cartItems: CartItem[];
  discount: Discount;
  onDiscountChange: (discount: Discount) => void;
  onQuantityChange: (id: string, unit: string, quantity: number) => void;
  onRemoveItem: (id: string, unit: string) => void;
  onPlaceOrder: () => void;
  onCancelBill: () => void;
  onParkBill: () => void;
  selectedPaymentMethod: string | null;
  onPaymentMethodSelect: (methodId: string) => void;
}

export const InvoicePanel: React.FC<InvoicePanelProps> = ({ 
  cartItems, 
  discount,
  onDiscountChange,
  onQuantityChange,
  onRemoveItem,
  onPlaceOrder, 
  onCancelBill,
  onParkBill,
  selectedPaymentMethod,
  onPaymentMethodSelect
}) => {
  const subtotal = cartItems.reduce((sum, item) => sum + (item.price * item.quantity), 0);
  const discountedSubtotal = subtotal - discount.amount;
  const tax = discountedSubtotal * 0.08; // 8% tax
  const total = discountedSubtotal + tax;

  const isOrderDisabled = cartItems.length === 0 || !selectedPaymentMethod;

  return (
    <div className="w-96 bg-white border-l border-gray-200 flex flex-col h-full">
      <div className="p-6 border-b border-gray-200">
        <h2 className="text-xl font-bold text-gray-900">Invoice</h2>
      </div>
      
      <div className="flex-1 overflow-y-auto p-6">
        <div className="space-y-4 mb-6">
          {cartItems.map((item) => (
            <CartItemComponent
              key={`${item.id}-${item.selectedUnit}`}
              item={item}
              onQuantityChange={onQuantityChange}
              onRemove={onRemoveItem}
            />
          ))}
        </div>
        
        <div className="bg-gray-50 rounded-lg p-4 mb-6">
          <h3 className="font-semibold text-gray-900 mb-3">Payment Summary</h3>
          <div className="space-y-2">
            <div className="flex justify-between text-sm">
              <span className="text-gray-600">Subtotal</span>
              <span className="font-medium">฿{subtotal.toFixed(2)}</span>
            </div>
            {discount.amount > 0 && (
              <div className="flex justify-between text-sm text-green-600">
                <span>Discount ({discount.type === 'percentage' ? `${discount.value}%` : 'Custom'})</span>
                <span>-฿{discount.amount.toFixed(2)}</span>
              </div>
            )}
            <div className="flex justify-between text-sm">
              <span className="text-gray-600">Tax (8%)</span>
              <span className="font-medium">฿{tax.toFixed(2)}</span>
            </div>
            <div className="border-t border-gray-200 pt-2 flex justify-between font-semibold">
              <span>Total</span>
              <span>฿{total.toFixed(2)}</span>
            </div>
          </div>
        </div>
        
        <DiscountPanel
          discount={discount}
          subtotal={subtotal}
          onDiscountChange={onDiscountChange}
        />
        
        <PaymentMethodSelector
          selectedMethod={selectedPaymentMethod}
          onMethodSelect={onPaymentMethodSelect}
          onParkBill={onParkBill}
        />
      </div>
      
      <div className="p-6 border-t border-gray-200 space-y-2">
        {!selectedPaymentMethod && cartItems.length > 0 && (
          <p className="text-sm text-gray-500 text-center mb-2">
            Select a payment method to continue
          </p>
        )}
        <button
          onClick={onCancelBill}
          disabled={cartItems.length === 0}
          className="w-full bg-red-500 hover:bg-red-600 disabled:bg-gray-300 disabled:cursor-not-allowed text-white font-semibold py-3 px-4 rounded-lg transition-colors"
        >
          Cancel Bill
        </button>
        <button
          onClick={onPlaceOrder}
          disabled={isOrderDisabled}
          className="w-full bg-blue-500 hover:bg-blue-600 disabled:bg-gray-300 disabled:cursor-not-allowed text-white font-semibold py-3 px-4 rounded-lg transition-colors"
        >
          Place Order
        </button>
      </div>
    </div>
  );
};