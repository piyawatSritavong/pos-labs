import React from 'react';
import { Clock, DollarSign, CreditCard, Building2, FileText, Users } from 'lucide-react';
import { ShiftSummary } from '../types';

interface ShiftClosingProps {
  isOpen: boolean;
  onClose: () => void;
  shiftSummary: ShiftSummary;
  onConfirmClose: () => void;
}

export const ShiftClosing: React.FC<ShiftClosingProps> = ({
  isOpen,
  onClose,
  shiftSummary,
  onConfirmClose,
}) => {
  if (!isOpen) return null;

  const totalPayments = shiftSummary.paymentBreakdown.cash + 
                       shiftSummary.paymentBreakdown.credit + 
                       shiftSummary.paymentBreakdown.bank;

  return (
    <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
      <div className="bg-white rounded-lg shadow-xl max-w-2xl w-full mx-4 max-h-[90vh] overflow-y-auto">
        <div className="flex items-center justify-between p-6 border-b border-gray-200">
          <h3 className="text-xl font-semibold text-gray-900 flex items-center space-x-2">
            <Clock className="w-6 h-6 text-blue-600" />
            <span>Close Shift</span>
          </h3>
          <button
            onClick={onClose}
            className="text-gray-400 hover:text-gray-600 transition-colors text-xl"
          >
            ×
          </button>
        </div>
        
        <div className="p-6">
          {/* Shift Info */}
          <div className="bg-blue-50 border border-blue-200 rounded-lg p-4 mb-6">
            <div className="grid grid-cols-2 gap-4">
              <div>
                <div className="text-sm text-blue-600 font-medium">Cashier</div>
                <div className="text-lg font-semibold text-blue-900">{shiftSummary.cashier}</div>
              </div>
              <div>
                <div className="text-sm text-blue-600 font-medium">Shift Type</div>
                <div className="text-lg font-semibold text-blue-900">{shiftSummary.shiftType}</div>
              </div>
              <div>
                <div className="text-sm text-blue-600 font-medium">Start Time</div>
                <div className="text-sm text-blue-900">
                  {shiftSummary.startTime.toLocaleDateString()} {shiftSummary.startTime.toLocaleTimeString()}
                </div>
              </div>
              <div>
                <div className="text-sm text-blue-600 font-medium">End Time</div>
                <div className="text-sm text-blue-900">
                  {shiftSummary.endTime.toLocaleDateString()} {shiftSummary.endTime.toLocaleTimeString()}
                </div>
              </div>
            </div>
          </div>

          {/* Sales Summary */}
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6 mb-6">
            <div className="bg-green-50 border border-green-200 rounded-lg p-4">
              <div className="flex items-center space-x-3 mb-2">
                <DollarSign className="w-5 h-5 text-green-600" />
                <div className="text-green-600 text-sm font-medium">Total Sales</div>
              </div>
              <div className="text-2xl font-bold text-green-900">฿{shiftSummary.totalSales.toFixed(2)}</div>
            </div>
            
            <div className="bg-orange-50 border border-orange-200 rounded-lg p-4">
              <div className="flex items-center space-x-3 mb-2">
                <FileText className="w-5 h-5 text-orange-600" />
                <div className="text-orange-600 text-sm font-medium">Bills Processed</div>
              </div>
              <div className="text-2xl font-bold text-orange-900">{shiftSummary.billsProcessed}</div>
            </div>
            
            <div className="bg-red-50 border border-red-200 rounded-lg p-4">
              <div className="flex items-center space-x-3 mb-2">
                <div className="w-5 h-5 bg-red-600 rounded-full flex items-center justify-center">
                  <span className="text-white text-xs font-bold">%</span>
                </div>
                <div className="text-red-600 text-sm font-medium">Total Discounts</div>
              </div>
              <div className="text-2xl font-bold text-red-900">฿{shiftSummary.totalDiscounts.toFixed(2)}</div>
            </div>
            
            <div className="bg-purple-50 border border-purple-200 rounded-lg p-4">
              <div className="flex items-center space-x-3 mb-2">
                <Users className="w-5 h-5 text-purple-600" />
                <div className="text-purple-600 text-sm font-medium">Parked Bills</div>
              </div>
              <div className="text-2xl font-bold text-purple-900">{shiftSummary.parkedBillsCount}</div>
            </div>
          </div>

          {/* Payment Methods Breakdown */}
          <div className="bg-gray-50 border border-gray-200 rounded-lg p-4 mb-6">
            <h4 className="font-semibold text-gray-900 mb-4">Payment Methods Breakdown</h4>
            <div className="space-y-3">
              <div className="flex items-center justify-between">
                <div className="flex items-center space-x-2">
                  <DollarSign className="w-4 h-4 text-green-600" />
                  <span className="text-sm text-gray-700">Cash</span>
                </div>
                <span className="font-medium text-gray-900">฿{shiftSummary.paymentBreakdown.cash.toFixed(2)}</span>
              </div>
              <div className="flex items-center justify-between">
                <div className="flex items-center space-x-2">
                  <CreditCard className="w-4 h-4 text-blue-600" />
                  <span className="text-sm text-gray-700">Credit Card</span>
                </div>
                <span className="font-medium text-gray-900">฿{shiftSummary.paymentBreakdown.credit.toFixed(2)}</span>
              </div>
              <div className="flex items-center justify-between">
                <div className="flex items-center space-x-2">
                  <Building2 className="w-4 h-4 text-purple-600" />
                  <span className="text-sm text-gray-700">Bank Transfer</span>
                </div>
                <span className="font-medium text-gray-900">฿{shiftSummary.paymentBreakdown.bank.toFixed(2)}</span>
              </div>
              <div className="border-t border-gray-300 pt-2 flex items-center justify-between font-semibold">
                <span className="text-gray-900">Total Payments</span>
                <span className="text-gray-900">฿{totalPayments.toFixed(2)}</span>
              </div>
            </div>
          </div>

          {/* Warning */}
          <div className="bg-yellow-50 border border-yellow-200 rounded-lg p-4 mb-6">
            <div className="flex items-start space-x-2">
              <div className="w-5 h-5 bg-yellow-500 rounded-full flex items-center justify-center flex-shrink-0 mt-0.5">
                <span className="text-white text-xs font-bold">!</span>
              </div>
              <div>
                <div className="font-medium text-yellow-800 mb-1">Important Notice</div>
                <div className="text-sm text-yellow-700">
                  Closing this shift will lock your session. Make sure all transactions are complete 
                  and all cash has been counted and secured before proceeding.
                </div>
              </div>
            </div>
          </div>
        </div>
        
        <div className="flex items-center justify-end space-x-3 p-6 border-t border-gray-200">
          <button
            onClick={onClose}
            className="px-6 py-2 text-sm font-medium text-gray-700 bg-gray-100 hover:bg-gray-200 rounded-lg transition-colors"
          >
            Cancel
          </button>
          <button
            onClick={onConfirmClose}
            className="px-6 py-2 text-sm font-medium text-white bg-red-500 hover:bg-red-600 rounded-lg transition-colors"
          >
            Close Shift
          </button>
        </div>
      </div>
    </div>
  );
};