import React, { useState } from 'react';
import { Percent, DollarSign } from 'lucide-react';
import { Discount } from '../types';

interface DiscountPanelProps {
  discount: Discount;
  subtotal: number;
  onDiscountChange: (discount: Discount) => void;
}

export const DiscountPanel: React.FC<DiscountPanelProps> = ({
  discount,
  subtotal,
  onDiscountChange,
}) => {
  const [showCustom, setShowCustom] = useState(false);
  const [customValue, setCustomValue] = useState('');
  const [customType, setCustomType] = useState<'percentage' | 'absolute'>('percentage');

  const quickDiscounts = [0, 5, 10, 15, 20];

  const handleQuickDiscount = (percentage: number) => {
    const amount = (subtotal * percentage) / 100;
    onDiscountChange({
      type: 'percentage',
      value: percentage,
      amount,
    });
    setShowCustom(false);
  };

  const handleCustomDiscount = () => {
    const value = parseFloat(customValue) || 0;
    let amount = 0;
    
    if (customType === 'percentage') {
      amount = (subtotal * value) / 100;
    } else {
      amount = value;
    }
    
    onDiscountChange({
      type: customType,
      value,
      amount: Math.min(amount, subtotal), // Don't exceed subtotal
    });
    setShowCustom(false);
    setCustomValue('');
  };

  return (
    <div className="mb-4">
      <h3 className="font-semibold text-gray-900 mb-3">Quick Discounts</h3>
      
      <div className="grid grid-cols-3 gap-2 mb-3">
        {quickDiscounts.map((percentage) => (
          <button
            key={percentage}
            onClick={() => handleQuickDiscount(percentage)}
            className={`px-3 py-2 text-sm rounded-lg border transition-colors ${
              discount.type === 'percentage' && discount.value === percentage
                ? 'bg-blue-500 text-white border-blue-500'
                : 'bg-white text-gray-700 border-gray-300 hover:bg-gray-50'
            }`}
          >
            {percentage}%
          </button>
        ))}
      </div>
      
      <button
        onClick={() => setShowCustom(!showCustom)}
        className={`w-full px-3 py-2 text-sm rounded-lg border transition-colors ${
          showCustom
            ? 'bg-blue-500 text-white border-blue-500'
            : 'bg-white text-gray-700 border-gray-300 hover:bg-gray-50'
        }`}
      >
        Custom
      </button>
      
      {showCustom && (
        <div className="mt-3 p-3 bg-gray-50 rounded-lg">
          <div className="flex items-center space-x-2 mb-2">
            <input
              type="number"
              value={customValue}
              onChange={(e) => setCustomValue(e.target.value)}
              placeholder="Enter value"
              className="flex-1 px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent text-sm"
            />
            <div className="flex bg-white rounded-lg border border-gray-300 overflow-hidden">
              <button
                onClick={() => setCustomType('percentage')}
                className={`px-3 py-2 text-sm flex items-center space-x-1 ${
                  customType === 'percentage'
                    ? 'bg-blue-500 text-white'
                    : 'text-gray-700 hover:bg-gray-50'
                }`}
              >
                <Percent className="w-3 h-3" />
                <span>%</span>
              </button>
              <button
                onClick={() => setCustomType('absolute')}
                className={`px-3 py-2 text-sm flex items-center space-x-1 ${
                  customType === 'absolute'
                    ? 'bg-blue-500 text-white'
                    : 'text-gray-700 hover:bg-gray-50'
                }`}
              >
                <DollarSign className="w-3 h-3" />
                <span>THB</span>
              </button>
            </div>
          </div>
          <button
            onClick={handleCustomDiscount}
            className="w-full bg-blue-500 hover:bg-blue-600 text-white text-sm font-medium py-2 px-3 rounded-lg transition-colors"
          >
            Apply Discount
          </button>
        </div>
      )}
      
      {discount.amount > 0 && (
        <div className="mt-3 p-2 bg-green-50 border border-green-200 rounded-lg">
          <div className="text-sm text-green-800">
            <span className="font-medium">Discount Applied: </span>
            {discount.type === 'percentage' 
              ? `${discount.value}% (฿${discount.amount.toFixed(2)})`
              : `฿${discount.amount.toFixed(2)}`
            }
          </div>
        </div>
      )}
    </div>
  );
};