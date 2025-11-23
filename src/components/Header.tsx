import React from 'react';
import { Search, QrCode, Clock, History, Package, LogOut } from 'lucide-react';
import { ParkedBillsBadge } from './ParkedBillsBadge';
import { LowStockBadge } from './LowStockBadge';

interface HeaderProps {
  onSearch: (query: string) => void;
  searchQuery: string;
  onOpenQRGenerator: () => void;
  onOpenParkedBills: () => void;
  onOpenBillsHistory: () => void;
  parkedBillsCount: number;
  onOpenStock: () => void;
  onCloseShift: () => void;
  lowStockCount: number;
}

export const Header: React.FC<HeaderProps> = ({
  onSearch,
  searchQuery,
  onOpenQRGenerator,
  onOpenParkedBills,
  onOpenBillsHistory,
  parkedBillsCount,
  onOpenStock,
  onCloseShift,
  lowStockCount,
}) => {
  return (
    <header className="bg-white border-b border-gray-200 px-6 py-4">
      <div className="flex items-center justify-between">
        <div className="flex items-center space-x-6">
          <div className="flex items-center space-x-3">
            <div className="w-10 h-10 bg-blue-600 rounded-lg flex items-center justify-center">
              <span className="text-white font-bold text-lg">CM</span>
            </div>
            <div>
              <h1 className="text-xl font-bold text-gray-900">ConstructMart POS</h1>
              <p className="text-sm text-gray-500">Construction Materials Store</p>
            </div>
          </div>
          
          <nav className="flex items-center space-x-4">
            <button
              onClick={onOpenQRGenerator}
              className="flex items-center space-x-2 px-3 py-2 text-gray-600 hover:text-gray-900 hover:bg-gray-100 rounded-lg transition-colors"
            >
              <QrCode className="w-4 h-4" />
              <span className="text-sm font-medium">QR Code</span>
            </button>
            
            <div className="relative">
              <button
                onClick={onOpenParkedBills}
                className="flex items-center space-x-2 px-3 py-2 text-gray-600 hover:text-gray-900 hover:bg-gray-100 rounded-lg transition-colors"
              >
                <Clock className="w-4 h-4" />
                <span className="text-sm font-medium">Parked Bills</span>
              </button>
              <ParkedBillsBadge count={parkedBillsCount} />
            </div>
            
            <div className="relative">
            <button
              onClick={onOpenStock}
              className="flex items-center space-x-2 px-3 py-2 text-gray-600 hover:text-gray-900 hover:bg-gray-100 rounded-lg transition-colors"
            >
              <Package className="w-4 h-4" />
              <span className="text-sm font-medium">Stock</span>
            </button>
            <LowStockBadge count={lowStockCount} />
            </div>
            
            <button
              onClick={onOpenBillsHistory}
              className="flex items-center space-x-2 px-3 py-2 text-gray-600 hover:text-gray-900 hover:bg-gray-100 rounded-lg transition-colors"
            >
              <History className="w-4 h-4" />
              <span className="text-sm font-medium">Bills</span>
            </button>
          </nav>
        </div>
        
        <div className="flex items-center space-x-4">
          <div className="relative">
            <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 text-gray-400 w-4 h-4" />
            <input
              type="text"
              placeholder="Search products..."
              value={searchQuery}
              onChange={(e) => onSearch(e.target.value)}
              className="pl-10 pr-4 py-2 w-80 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
            />
          </div>
          
          <div className="flex items-center space-x-2">
            <button className="px-3 py-1 text-sm bg-gray-100 text-gray-700 rounded-md hover:bg-gray-200 transition-colors">
              EN
            </button>
            <button className="px-3 py-1 text-sm text-gray-500 rounded-md hover:bg-gray-100 transition-colors">
              TH
            </button>
          </div>
          
          <div className="flex items-center space-x-3 pl-4 border-l border-gray-200">
            <button
              onClick={onCloseShift}
              className="flex items-center space-x-2 px-3 py-2 text-red-600 hover:text-red-800 hover:bg-red-50 rounded-lg transition-colors"
            >
              <LogOut className="w-4 h-4" />
              <span className="text-sm font-medium">Close Shift</span>
            </button>
            
            <div className="w-8 h-8 bg-blue-100 rounded-full flex items-center justify-center">
              <span className="text-blue-600 font-semibold text-sm">JS</span>
            </div>
            <div>
              <p className="text-sm font-medium text-gray-900">John Smith</p>
              <p className="text-xs text-gray-500">Cashier</p>
            </div>
          </div>
        </div>
      </div>
    </header>
  );
};