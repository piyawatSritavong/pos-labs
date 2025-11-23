import React from 'react';
import { X, Clock, Trash2, Play, FileText } from 'lucide-react';
import { ParkedBill } from '../types';

interface ParkedBillsDrawerProps {
  isOpen: boolean;
  onClose: () => void;
  parkedBills: ParkedBill[];
  onResumeBill: (bill: ParkedBill) => void;
  onDeleteBill: (billId: string) => void;
  onPrintProvisional: (bill: ParkedBill) => void;
}

export const ParkedBillsDrawer: React.FC<ParkedBillsDrawerProps> = ({
  isOpen,
  onClose,
  parkedBills,
  onResumeBill,
  onDeleteBill,
  onPrintProvisional,
}) => {
  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-end z-50">
      <div className="bg-white h-full w-full max-w-2xl shadow-xl flex flex-col">
        <div className="flex items-center justify-between p-6 border-b border-gray-200">
          <h3 className="text-lg font-semibold text-gray-900 flex items-center space-x-2">
            <Clock className="w-5 h-5" />
            <span>Parked Bills</span>
          </h3>
          <button
            onClick={onClose}
            className="text-gray-400 hover:text-gray-600 transition-colors"
          >
            <X className="w-5 h-5" />
          </button>
        </div>
        
        <div className="flex-1 overflow-y-auto p-6">
          {parkedBills.length === 0 ? (
            <div className="text-center py-12">
              <Clock className="w-12 h-12 text-gray-400 mx-auto mb-4" />
              <div className="text-gray-500 text-lg">No parked bills</div>
              <div className="text-gray-400 text-sm mt-2">
                Parked bills will appear here
              </div>
            </div>
          ) : (
            <div className="space-y-4">
              {parkedBills.map((bill) => (
                <div key={bill.id} className="bg-gray-50 rounded-lg p-4 border border-gray-200">
                  <div className="flex items-start justify-between mb-3">
                    <div>
                      <div className="font-semibold text-gray-900">Bill #{bill.id}</div>
                      <div className="text-sm text-gray-500">
                        {bill.timestamp.toLocaleDateString()} {bill.timestamp.toLocaleTimeString()}
                      </div>
                      <div className="text-sm text-gray-500">Cashier: {bill.cashier}</div>
                      {bill.customerNote && (
                        <div className="text-sm text-gray-600 mt-1">
                          Note: {bill.customerNote}
                        </div>
                      )}
                    </div>
                    <div className="text-right">
                      <div className="font-bold text-lg text-gray-900">
                        ฿{bill.total.toFixed(2)}
                      </div>
                      <div className="text-sm text-gray-500">
                        {bill.items.length} item{bill.items.length !== 1 ? 's' : ''}
                      </div>
                    </div>
                  </div>
                  
                  <div className="flex items-center space-x-2">
                    <button
                      onClick={() => onResumeBill(bill)}
                      className="flex items-center space-x-1 px-3 py-2 bg-blue-500 hover:bg-blue-600 text-white text-sm rounded-lg transition-colors"
                    >
                      <Play className="w-4 h-4" />
                      <span>Resume</span>
                    </button>
                    <button
                      onClick={() => onPrintProvisional(bill)}
                      className="flex items-center space-x-1 px-3 py-2 bg-gray-500 hover:bg-gray-600 text-white text-sm rounded-lg transition-colors"
                    >
                      <FileText className="w-4 h-4" />
                      <span>Print</span>
                    </button>
                    <button
                      onClick={() => onDeleteBill(bill.id)}
                      className="flex items-center space-x-1 px-3 py-2 bg-red-500 hover:bg-red-600 text-white text-sm rounded-lg transition-colors"
                    >
                      <Trash2 className="w-4 h-4" />
                      <span>Delete</span>
                    </button>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      </div>
    </div>
  );
};