import React from 'react';
import { CreditCard, DollarSign, Clock, Building2 } from 'lucide-react';

interface PaymentMethod {
  id: string;
  label: string;
  icon: React.ComponentType<{ className?: string }>;
  color: string;
}

interface PaymentMethodSelectorProps {
  selectedMethod: string | null;
  onMethodSelect: (methodId: string) => void;
  onParkBill: () => void;
}

export const PaymentMethodSelector: React.FC<PaymentMethodSelectorProps> = ({
  selectedMethod,
  onMethodSelect,
  onParkBill,
}) => {
  const paymentMethods: PaymentMethod[] = [
    { id: 'credit', label: 'Credit Card', icon: CreditCard, color: 'bg-blue-500' },
    { id: 'cash', label: 'Cash', icon: DollarSign, color: 'bg-green-500' },
    { id: 'bank', label: 'Bank Transfer', icon: Building2, color: 'bg-purple-500' },
  ];

  const handleMethodClick = (methodId: string) => {
    onMethodSelect(methodId);
  };

  return (
    <div className="mb-6">
      <h3 className="font-semibold text-gray-900 mb-3">Payment Method</h3>
      <div className="grid grid-cols-2 gap-2 mb-3">
        {paymentMethods.map((method) => (
          <button
            key={method.id}
            onClick={() => handleMethodClick(method.id)}
            className={`flex flex-col items-center p-3 border rounded-lg transition-all group ${
              selectedMethod === method.id
                ? 'border-blue-500 bg-blue-50 ring-2 ring-blue-200'
                : 'border-gray-200 hover:bg-gray-50 hover:border-gray-300'
            }`}
          >
            <div className={`w-8 h-8 ${method.color} rounded-lg flex items-center justify-center mb-2 group-hover:scale-110 transition-transform`}>
              <method.icon className="w-4 h-4 text-white" />
            </div>
            <span className="text-sm font-medium text-gray-700">{method.label}</span>
          </button>
        ))}
      </div>
      
      <button
        onClick={onParkBill}
        className="w-full flex items-center justify-center space-x-2 p-3 border border-orange-200 rounded-lg hover:bg-orange-50 hover:border-orange-300 transition-colors group"
      >
        <div className="w-8 h-8 bg-orange-500 rounded-lg flex items-center justify-center group-hover:scale-110 transition-transform">
          <Clock className="w-4 h-4 text-white" />
        </div>
        <span className="text-sm font-medium text-gray-700">Park Bill</span>
      </button>
    </div>
  );
};