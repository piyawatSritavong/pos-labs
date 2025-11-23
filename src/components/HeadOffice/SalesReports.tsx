import React, { useState, useMemo } from 'react';
import { Download, Filter, Calendar, TrendingUp, DollarSign, Receipt, Percent, Calculator, Eye, BarChart3, X, FileText, Mail } from 'lucide-react';

interface SalesData {
  billId: string;
  branch: string;
  dateTime: Date;
  cashier: string;
  items: number;
  discount: number;
  tax: number;
  total: number;
  paymentMethod: 'cash' | 'credit' | 'bank' | 'paylater';
  lineItems: LineItem[];
}

interface LineItem {
  productName: string;
  category: string;
  quantity: number;
  unitType: string;
  unitPrice: number;
  discount: number;
  total: number;
}

interface ProductSummary {
  productName: string;
  category: string;
  unitsSold: number;
  avgPrice: number;
  revenue: number;
  margin: number;
}

interface FilterState {
  dateRange: string;
  customDateStart: string;
  customDateEnd: string;
  selectedBranches: string[];
  selectedCashiers: string[];
  productCategory: string;
  paymentMethod: string;
  minAmount: string;
  maxAmount: string;
  includeDiscounts: boolean;
}

export const SalesReports: React.FC = () => {
  const [filters, setFilters] = useState<FilterState>({
    dateRange: 'today',
    customDateStart: '',
    customDateEnd: '',
    selectedBranches: ['All'],
    selectedCashiers: ['All'],
    productCategory: 'all',
    paymentMethod: 'all',
    minAmount: '',
    maxAmount: '',
    includeDiscounts: true,
  });

  const [activeTab, setActiveTab] = useState<'bills' | 'products'>('bills');
  const [selectedBill, setSelectedBill] = useState<SalesData | null>(null);
  const [selectedProduct, setSelectedProduct] = useState<string | null>(null);
  const [showBillDetails, setShowBillDetails] = useState(false);
  const [showProductChart, setShowProductChart] = useState(false);
  const [showScheduleModal, setShowScheduleModal] = useState(false);

  // Mock data - in real app, this would come from API
  const branches = ['Downtown Branch', 'Mall Branch', 'Industrial Branch', 'Suburb Branch'];
  const cashiers = ['John Smith', 'Jane Doe', 'Mike Johnson', 'Sarah Wilson', 'David Chen', 'Lisa Anderson'];
  const categories = ['roofing', 'cement', 'steel', 'paint', 'tools', 'hardware'];

  const mockSalesData: SalesData[] = [
    {
      billId: 'CB001',
      branch: 'Downtown Branch',
      dateTime: new Date('2024-01-15T14:30:00'),
      cashier: 'John Smith',
      items: 3,
      discount: 125.50,
      tax: 156.25,
      total: 2078.75,
      paymentMethod: 'cash',
      lineItems: [
        { productName: 'Metal Roofing Sheets', category: 'roofing', quantity: 5, unitType: 'per sheet', unitPrice: 25.99, discount: 25.00, total: 104.95 },
        { productName: 'Portland Cement', category: 'cement', quantity: 10, unitType: 'per bag', unitPrice: 12.50, discount: 0, total: 125.00 },
        { productName: 'Steel Rebar', category: 'steel', quantity: 20, unitType: 'per piece', unitPrice: 45.00, discount: 100.50, total: 799.50 },
      ]
    },
    {
      billId: 'CB002',
      branch: 'Mall Branch',
      dateTime: new Date('2024-01-15T15:45:00'),
      cashier: 'Jane Doe',
      items: 2,
      discount: 89.25,
      tax: 71.34,
      total: 980.59,
      paymentMethod: 'credit',
      lineItems: [
        { productName: 'Exterior Wall Paint', category: 'paint', quantity: 8, unitType: 'per gallon', unitPrice: 34.99, discount: 35.00, total: 244.92 },
        { productName: 'Power Drill', category: 'tools', quantity: 3, unitType: 'per piece', unitPrice: 89.99, discount: 54.25, total: 215.72 },
      ]
    },
    {
      billId: 'CB003',
      branch: 'Industrial Branch',
      dateTime: new Date('2024-01-15T16:20:00'),
      cashier: 'Mike Johnson',
      items: 4,
      discount: 234.75,
      tax: 187.62,
      total: 2578.87,
      paymentMethod: 'bank',
      lineItems: [
        { productName: 'Steel I-Beam', category: 'steel', quantity: 2, unitType: 'per piece', unitPrice: 156.00, discount: 31.20, total: 280.80 },
        { productName: 'Ready Mix Concrete', category: 'cement', quantity: 5, unitType: 'per cubic meter', unitPrice: 125.00, discount: 62.50, total: 562.50 },
        { productName: 'Clay Roof Tiles', category: 'roofing', quantity: 100, unitType: 'per piece', unitPrice: 3.50, discount: 35.00, total: 315.00 },
        { productName: 'Hex Bolts', category: 'hardware', quantity: 500, unitType: 'per piece', unitPrice: 0.45, discount: 22.50, total: 202.50 },
      ]
    },
    {
      billId: 'CB004',
      branch: 'Suburb Branch',
      dateTime: new Date('2024-01-15T17:10:00'),
      cashier: 'David Chen',
      items: 1,
      discount: 45.60,
      tax: 36.48,
      total: 501.88,
      paymentMethod: 'paylater',
      lineItems: [
        { productName: 'Interior Paint', category: 'paint', quantity: 12, unitType: 'per gallon', unitPrice: 29.99, discount: 45.60, total: 314.28 },
      ]
    },
    {
      billId: 'CB005',
      branch: 'Downtown Branch',
      dateTime: new Date('2024-01-15T18:00:00'),
      cashier: 'Sarah Wilson',
      items: 3,
      discount: 156.80,
      tax: 125.44,
      total: 1725.64,
      paymentMethod: 'cash',
      lineItems: [
        { productName: 'Circular Saw', category: 'tools', quantity: 2, unitType: 'per piece', unitPrice: 145.00, discount: 29.00, total: 261.00 },
        { productName: 'Wood Screws', category: 'hardware', quantity: 1000, unitType: 'per piece', unitPrice: 0.25, discount: 25.00, total: 225.00 },
        { productName: 'Roofing Membrane', category: 'roofing', quantity: 3, unitType: 'per roll', unitPrice: 89.99, discount: 26.97, total: 242.97 },
      ]
    },
  ];

  // Filter data based on current filters
  const filteredData = useMemo(() => {
    let filtered = mockSalesData;

    // Branch filter
    if (!filters.selectedBranches.includes('All')) {
      filtered = filtered.filter(item => filters.selectedBranches.includes(item.branch));
    }

    // Cashier filter
    if (!filters.selectedCashiers.includes('All')) {
      filtered = filtered.filter(item => filters.selectedCashiers.includes(item.cashier));
    }

    // Payment method filter
    if (filters.paymentMethod !== 'all') {
      filtered = filtered.filter(item => item.paymentMethod === filters.paymentMethod);
    }

    // Amount range filter
    if (filters.minAmount) {
      filtered = filtered.filter(item => item.total >= parseFloat(filters.minAmount));
    }
    if (filters.maxAmount) {
      filtered = filtered.filter(item => item.total <= parseFloat(filters.maxAmount));
    }

    return filtered;
  }, [filters]);

  // Calculate summary metrics
  const summaryMetrics = useMemo(() => {
    const grossSales = filteredData.reduce((sum, item) => sum + item.total, 0);
    const totalDiscounts = filteredData.reduce((sum, item) => sum + item.discount, 0);
    const totalTax = filteredData.reduce((sum, item) => sum + item.tax, 0);
    const netSales = filters.includeDiscounts ? grossSales : grossSales - totalDiscounts;
    const billsCount = filteredData.length;

    return { grossSales, totalDiscounts, totalTax, netSales, billsCount };
  }, [filteredData, filters.includeDiscounts]);

  // Calculate product summary
  const productSummary = useMemo(() => {
    const productMap = new Map<string, ProductSummary>();

    filteredData.forEach(bill => {
      bill.lineItems.forEach(item => {
        const key = item.productName;
        if (productMap.has(key)) {
          const existing = productMap.get(key)!;
          existing.unitsSold += item.quantity;
          existing.revenue += item.total;
          existing.avgPrice = existing.revenue / existing.unitsSold;
        } else {
          productMap.set(key, {
            productName: item.productName,
            category: item.category,
            unitsSold: item.quantity,
            avgPrice: item.unitPrice,
            revenue: item.total,
            margin: 0.25, // Mock 25% margin
          });
        }
      });
    });

    return Array.from(productMap.values()).sort((a, b) => b.revenue - a.revenue);
  }, [filteredData]);

  const handleFilterChange = (key: keyof FilterState, value: any) => {
    setFilters(prev => ({ ...prev, [key]: value }));
  };

  const handleMultiSelectChange = (key: 'selectedBranches' | 'selectedCashiers', value: string) => {
    setFilters(prev => {
      const currentValues = prev[key];
      if (value === 'All') {
        return { ...prev, [key]: ['All'] };
      } else {
        const filtered = currentValues.filter(v => v !== 'All');
        if (filtered.includes(value)) {
          const newValues = filtered.filter(v => v !== value);
          return { ...prev, [key]: newValues.length === 0 ? ['All'] : newValues };
        } else {
          return { ...prev, [key]: [...filtered, value] };
        }
      }
    });
  };

  const handleBillClick = (bill: SalesData) => {
    setSelectedBill(bill);
    setShowBillDetails(true);
  };

  const handleProductClick = (productName: string) => {
    setSelectedProduct(productName);
    setShowProductChart(true);
  };

  const handleExport = (format: 'csv' | 'excel' | 'pdf') => {
    alert(`Exporting ${activeTab} data as ${format.toUpperCase()}...`);
  };

  const formatCurrency = (amount: number) => `฿${amount.toLocaleString()}`;

  return (
    <div className="p-6">
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-3xl font-bold text-gray-900">Sales Reports</h1>
          <p className="text-gray-600 mt-2">Comprehensive sales analytics across all branches</p>
        </div>
        <div className="flex items-center space-x-3">
          <button
            onClick={() => setShowScheduleModal(true)}
            className="flex items-center space-x-2 px-4 py-2 bg-purple-500 hover:bg-purple-600 text-white rounded-lg transition-colors"
          >
            <Mail className="w-4 h-4" />
            <span>Schedule Export</span>
          </button>
          <button
            onClick={() => handleExport('csv')}
            className="flex items-center space-x-2 px-4 py-2 bg-green-500 hover:bg-green-600 text-white rounded-lg transition-colors"
          >
            <Download className="w-4 h-4" />
            <span>Export CSV</span>
          </button>
          <button
            onClick={() => handleExport('excel')}
            className="flex items-center space-x-2 px-4 py-2 bg-blue-500 hover:bg-blue-600 text-white rounded-lg transition-colors"
          >
            <FileText className="w-4 h-4" />
            <span>Export Excel</span>
          </button>
          <button
            onClick={() => handleExport('pdf')}
            className="flex items-center space-x-2 px-4 py-2 bg-red-500 hover:bg-red-600 text-white rounded-lg transition-colors"
          >
            <Download className="w-4 h-4" />
            <span>Export PDF</span>
          </button>
        </div>
      </div>

      {/* Sticky Filter Bar */}
      <div className="sticky top-0 z-10 bg-white rounded-lg border border-gray-200 p-4 mb-6 shadow-sm">
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 mb-4">
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-2">Date Range</label>
            <select
              value={filters.dateRange}
              onChange={(e) => handleFilterChange('dateRange', e.target.value)}
              className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
            >
              <option value="today">Today</option>
              <option value="yesterday">Yesterday</option>
              <option value="week">This Week</option>
              <option value="month">This Month</option>
              <option value="custom">Custom Range</option>
            </select>
          </div>

          {filters.dateRange === 'custom' && (
            <>
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">Start Date</label>
                <input
                  type="date"
                  value={filters.customDateStart}
                  onChange={(e) => handleFilterChange('customDateStart', e.target.value)}
                  className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                />
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">End Date</label>
                <input
                  type="date"
                  value={filters.customDateEnd}
                  onChange={(e) => handleFilterChange('customDateEnd', e.target.value)}
                  className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                />
              </div>
            </>
          )}

          <div>
            <label className="block text-sm font-medium text-gray-700 mb-2">Product Category</label>
            <select
              value={filters.productCategory}
              onChange={(e) => handleFilterChange('productCategory', e.target.value)}
              className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
            >
              <option value="all">All Categories</option>
              {categories.map(category => (
                <option key={category} value={category}>{category}</option>
              ))}
            </select>
          </div>

          <div>
            <label className="block text-sm font-medium text-gray-700 mb-2">Payment Method</label>
            <select
              value={filters.paymentMethod}
              onChange={(e) => handleFilterChange('paymentMethod', e.target.value)}
              className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
            >
              <option value="all">All Methods</option>
              <option value="cash">Cash</option>
              <option value="credit">Credit Card</option>
              <option value="bank">Bank Transfer</option>
              <option value="paylater">PayLater</option>
            </select>
          </div>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 mb-4">
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-2">Min Amount</label>
            <input
              type="number"
              value={filters.minAmount}
              onChange={(e) => handleFilterChange('minAmount', e.target.value)}
              placeholder="0.00"
              className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
            />
          </div>

          <div>
            <label className="block text-sm font-medium text-gray-700 mb-2">Max Amount</label>
            <input
              type="number"
              value={filters.maxAmount}
              onChange={(e) => handleFilterChange('maxAmount', e.target.value)}
              placeholder="999999.99"
              className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
            />
          </div>

          <div className="flex items-end">
            <label className="flex items-center space-x-2">
              <input
                type="checkbox"
                checked={filters.includeDiscounts}
                onChange={(e) => handleFilterChange('includeDiscounts', e.target.checked)}
                className="rounded border-gray-300 text-blue-600 focus:ring-blue-500"
              />
              <span className="text-sm text-gray-700">Include Discounts</span>
            </label>
          </div>
        </div>

        {/* Multi-select filters */}
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-2">Branches</label>
            <div className="flex flex-wrap gap-2">
              {['All', ...branches].map(branch => (
                <button
                  key={branch}
                  onClick={() => handleMultiSelectChange('selectedBranches', branch)}
                  className={`px-3 py-1 rounded-full text-sm font-medium transition-colors ${
                    filters.selectedBranches.includes(branch)
                      ? 'bg-blue-500 text-white'
                      : 'bg-gray-100 text-gray-700 hover:bg-gray-200'
                  }`}
                >
                  {branch}
                </button>
              ))}
            </div>
          </div>

          <div>
            <label className="block text-sm font-medium text-gray-700 mb-2">Cashiers</label>
            <div className="flex flex-wrap gap-2">
              {['All', ...cashiers].map(cashier => (
                <button
                  key={cashier}
                  onClick={() => handleMultiSelectChange('selectedCashiers', cashier)}
                  className={`px-3 py-1 rounded-full text-sm font-medium transition-colors ${
                    filters.selectedCashiers.includes(cashier)
                      ? 'bg-blue-500 text-white'
                      : 'bg-gray-100 text-gray-700 hover:bg-gray-200'
                  }`}
                >
                  {cashier}
                </button>
              ))}
            </div>
          </div>
        </div>
      </div>

      {/* Summary Cards */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-5 gap-6 mb-8">
        <div className="bg-white rounded-lg border border-gray-200 p-6">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-gray-600">Gross Sales</p>
              <p className="text-2xl font-bold text-gray-900">{formatCurrency(summaryMetrics.grossSales)}</p>
            </div>
            <DollarSign className="w-8 h-8 text-green-600" />
          </div>
        </div>

        <div className="bg-white rounded-lg border border-gray-200 p-6">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-gray-600">Discounts</p>
              <p className="text-2xl font-bold text-red-600">{formatCurrency(summaryMetrics.totalDiscounts)}</p>
            </div>
            <Percent className="w-8 h-8 text-red-600" />
          </div>
        </div>

        <div className="bg-white rounded-lg border border-gray-200 p-6">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-gray-600">Tax</p>
              <p className="text-2xl font-bold text-blue-600">{formatCurrency(summaryMetrics.totalTax)}</p>
            </div>
            <Calculator className="w-8 h-8 text-blue-600" />
          </div>
        </div>

        <div className="bg-white rounded-lg border border-gray-200 p-6">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-gray-600">Net Sales</p>
              <p className="text-2xl font-bold text-green-600">{formatCurrency(summaryMetrics.netSales)}</p>
            </div>
            <TrendingUp className="w-8 h-8 text-green-600" />
          </div>
        </div>

        <div className="bg-white rounded-lg border border-gray-200 p-6">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-gray-600">Bills Count</p>
              <p className="text-2xl font-bold text-gray-900">{summaryMetrics.billsCount.toLocaleString()}</p>
            </div>
            <Receipt className="w-8 h-8 text-purple-600" />
          </div>
        </div>
      </div>

      {/* Tab Navigation */}
      <div className="bg-white rounded-lg border border-gray-200 overflow-hidden mb-6">
        <div className="border-b border-gray-200">
          <nav className="flex space-x-8 px-6">
            <button
              onClick={() => setActiveTab('bills')}
              className={`py-4 px-1 border-b-2 font-medium text-sm ${
                activeTab === 'bills'
                  ? 'border-blue-500 text-blue-600'
                  : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'
              }`}
            >
              Bill-Level Analysis
            </button>
            <button
              onClick={() => setActiveTab('products')}
              className={`py-4 px-1 border-b-2 font-medium text-sm ${
                activeTab === 'products'
                  ? 'border-blue-500 text-blue-600'
                  : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'
              }`}
            >
              Product-Level Analysis
            </button>
          </nav>
        </div>

        {/* Bills Table */}
        {activeTab === 'bills' && (
          <div className="overflow-x-auto">
            <table className="w-full">
              <thead className="bg-gray-50 border-b border-gray-200">
                <tr>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Bill ID</th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Branch</th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Date/Time</th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Cashier</th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Items</th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Discount</th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Tax</th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Total</th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Payment</th>
                </tr>
              </thead>
              <tbody className="bg-white divide-y divide-gray-200">
                {filteredData.map((bill) => (
                  <tr 
                    key={bill.billId} 
                    className="hover:bg-gray-50 cursor-pointer"
                    onClick={() => handleBillClick(bill)}
                  >
                    <td className="px-6 py-4 whitespace-nowrap text-sm font-medium text-blue-600 hover:text-blue-800">
                      #{bill.billId}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">{bill.branch}</td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                      {bill.dateTime.toLocaleDateString()}<br />
                      {bill.dateTime.toLocaleTimeString()}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">{bill.cashier}</td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">{bill.items}</td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-red-600">{formatCurrency(bill.discount)}</td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">{formatCurrency(bill.tax)}</td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">{formatCurrency(bill.total)}</td>
                    <td className="px-6 py-4 whitespace-nowrap">
                      <span className={`inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium ${
                        bill.paymentMethod === 'cash' ? 'bg-green-100 text-green-800' :
                        bill.paymentMethod === 'credit' ? 'bg-blue-100 text-blue-800' :
                        bill.paymentMethod === 'bank' ? 'bg-purple-100 text-purple-800' :
                        'bg-orange-100 text-orange-800'
                      }`}>
                        {bill.paymentMethod}
                      </span>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}

        {/* Products Table */}
        {activeTab === 'products' && (
          <div className="overflow-x-auto">
            <table className="w-full">
              <thead className="bg-gray-50 border-b border-gray-200">
                <tr>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Product</th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Category</th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Units Sold</th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Avg. Price</th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Revenue</th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Margin</th>
                </tr>
              </thead>
              <tbody className="bg-white divide-y divide-gray-200">
                {productSummary.map((product, index) => (
                  <tr 
                    key={index} 
                    className="hover:bg-gray-50 cursor-pointer"
                    onClick={() => handleProductClick(product.productName)}
                  >
                    <td className="px-6 py-4 whitespace-nowrap text-sm font-medium text-blue-600 hover:text-blue-800">
                      {product.productName}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">{product.category}</td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">{product.unitsSold.toLocaleString()}</td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">{formatCurrency(product.avgPrice)}</td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">{formatCurrency(product.revenue)}</td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-green-600">{(product.margin * 100).toFixed(1)}%</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}

        {filteredData.length === 0 && (
          <div className="text-center py-12">
            <div className="text-gray-500 text-lg">No data found</div>
            <div className="text-gray-400 text-sm mt-2">
              Try adjusting your filters
            </div>
          </div>
        )}
      </div>

      {/* Bill Details Drawer */}
      {showBillDetails && selectedBill && (
        <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-end z-50">
          <div className="bg-white h-full w-full max-w-2xl shadow-xl flex flex-col">
            <div className="flex items-center justify-between p-6 border-b border-gray-200">
              <h3 className="text-xl font-semibold text-gray-900">Bill Details - #{selectedBill.billId}</h3>
              <button
                onClick={() => setShowBillDetails(false)}
                className="text-gray-400 hover:text-gray-600 transition-colors"
              >
                <X className="w-6 h-6" />
              </button>
            </div>
            
            <div className="flex-1 overflow-y-auto p-6">
              <div className="mb-6">
                <div className="grid grid-cols-2 gap-4 mb-4">
                  <div>
                    <span className="text-sm text-gray-500">Branch:</span>
                    <p className="font-medium">{selectedBill.branch}</p>
                  </div>
                  <div>
                    <span className="text-sm text-gray-500">Cashier:</span>
                    <p className="font-medium">{selectedBill.cashier}</p>
                  </div>
                  <div>
                    <span className="text-sm text-gray-500">Date & Time:</span>
                    <p className="font-medium">
                      {selectedBill.dateTime.toLocaleDateString()} {selectedBill.dateTime.toLocaleTimeString()}
                    </p>
                  </div>
                  <div>
                    <span className="text-sm text-gray-500">Payment Method:</span>
                    <p className="font-medium capitalize">{selectedBill.paymentMethod}</p>
                  </div>
                </div>
              </div>

              <div className="mb-6">
                <h4 className="text-lg font-semibold text-gray-900 mb-4">Line Items</h4>
                <div className="space-y-3">
                  {selectedBill.lineItems.map((item, index) => (
                    <div key={index} className="bg-gray-50 rounded-lg p-4">
                      <div className="flex justify-between items-start mb-2">
                        <div>
                          <h5 className="font-medium text-gray-900">{item.productName}</h5>
                          <p className="text-sm text-gray-500">{item.category}</p>
                        </div>
                        <div className="text-right">
                          <p className="font-medium text-gray-900">{formatCurrency(item.total)}</p>
                        </div>
                      </div>
                      <div className="grid grid-cols-3 gap-4 text-sm">
                        <div>
                          <span className="text-gray-500">Quantity:</span>
                          <p className="font-medium">{item.quantity} {item.unitType}</p>
                        </div>
                        <div>
                          <span className="text-gray-500">Unit Price:</span>
                          <p className="font-medium">{formatCurrency(item.unitPrice)}</p>
                        </div>
                        <div>
                          <span className="text-gray-500">Discount:</span>
                          <p className="font-medium text-red-600">{formatCurrency(item.discount)}</p>
                        </div>
                      </div>
                    </div>
                  ))}
                </div>
              </div>

              <div className="bg-gray-50 rounded-lg p-4">
                <h4 className="text-lg font-semibold text-gray-900 mb-3">Bill Summary</h4>
                <div className="space-y-2">
                  <div className="flex justify-between">
                    <span className="text-gray-600">Subtotal:</span>
                    <span className="font-medium">{formatCurrency(selectedBill.total - selectedBill.tax + selectedBill.discount)}</span>
                  </div>
                  <div className="flex justify-between text-red-600">
                    <span>Discount:</span>
                    <span className="font-medium">-{formatCurrency(selectedBill.discount)}</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-gray-600">Tax (8%):</span>
                    <span className="font-medium">{formatCurrency(selectedBill.tax)}</span>
                  </div>
                  <div className="border-t border-gray-200 pt-2 flex justify-between font-semibold text-lg">
                    <span>Total:</span>
                    <span>{formatCurrency(selectedBill.total)}</span>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Product Chart Modal */}
      {showProductChart && selectedProduct && (
        <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
          <div className="bg-white rounded-lg shadow-xl max-w-4xl w-full mx-4 max-h-[80vh] overflow-y-auto">
            <div className="flex items-center justify-between p-6 border-b border-gray-200">
              <h3 className="text-xl font-semibold text-gray-900">Sales by Branch - {selectedProduct}</h3>
              <button
                onClick={() => setShowProductChart(false)}
                className="text-gray-400 hover:text-gray-600 transition-colors"
              >
                <X className="w-6 h-6" />
              </button>
            </div>
            
            <div className="p-6">
              <div className="h-64 flex items-center justify-center bg-gray-50 rounded-lg">
                <div className="text-center">
                  <BarChart3 className="w-12 h-12 text-gray-400 mx-auto mb-2" />
                  <p className="text-gray-500">Product sales by branch chart would be rendered here</p>
                  <p className="text-sm text-gray-400">Showing {selectedProduct} sales across all branches</p>
                </div>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Schedule Export Modal */}
      {showScheduleModal && (
        <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
          <div className="bg-white rounded-lg shadow-xl max-w-md w-full mx-4">
            <div className="flex items-center justify-between p-6 border-b border-gray-200">
              <h3 className="text-lg font-semibold text-gray-900">Schedule Daily Export</h3>
              <button
                onClick={() => setShowScheduleModal(false)}
                className="text-gray-400 hover:text-gray-600 transition-colors"
              >
                <X className="w-5 h-5" />
              </button>
            </div>
            
            <div className="p-6">
              <div className="space-y-4">
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">Email Address</label>
                  <input
                    type="email"
                    className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                    placeholder="admin@constructmart.com"
                  />
                </div>
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">Export Format</label>
                  <select className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent">
                    <option value="csv">CSV</option>
                    <option value="excel">Excel</option>
                    <option value="pdf">PDF</option>
                  </select>
                </div>
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">Send Time</label>
                  <input
                    type="time"
                    defaultValue="08:00"
                    className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                  />
                </div>
              </div>
            </div>
            
            <div className="flex items-center justify-end space-x-3 p-6 border-t border-gray-200">
              <button
                onClick={() => setShowScheduleModal(false)}
                className="px-4 py-2 text-sm font-medium text-gray-700 bg-gray-100 hover:bg-gray-200 rounded-lg transition-colors"
              >
                Cancel
              </button>
              <button
                onClick={() => {
                  alert('Daily export scheduled successfully!');
                  setShowScheduleModal(false);
                }}
                className="px-4 py-2 text-sm font-medium text-white bg-blue-500 hover:bg-blue-600 rounded-lg transition-colors"
              >
                Schedule Export
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};