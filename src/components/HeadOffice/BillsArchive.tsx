import React, { useState, useMemo } from 'react';
import { 
  Search, 
  Filter, 
  Download, 
  Eye, 
  Printer, 
  FileText, 
  Calendar, 
  DollarSign, 
  CreditCard, 
  Building2, 
  Clock, 
  X,
  RefreshCw,
  AlertTriangle,
  CheckCircle,
  Trash2,
  FileX
} from 'lucide-react';

interface BillData {
  id: string;
  branch: string;
  dateTime: Date;
  cashier: string;
  customer?: string;
  itemsCount: number;
  discount: number;
  tax: number;
  total: number;
  paymentMethod: 'cash' | 'credit' | 'bank' | 'paylater';
  status: 'completed' | 'refunded' | 'cancelled';
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

interface FilterState {
  dateRange: string;
  customDateStart: string;
  customDateEnd: string;
  selectedBranches: string[];
  selectedCashiers: string[];
  billId: string;
  customer: string;
  paymentMethod: string;
  minAmount: string;
  maxAmount: string;
}

export const BillsArchive: React.FC = () => {
  const [filters, setFilters] = useState<FilterState>({
    dateRange: 'today',
    customDateStart: '',
    customDateEnd: '',
    selectedBranches: ['All'],
    selectedCashiers: ['All'],
    billId: '',
    customer: '',
    paymentMethod: 'all',
    minAmount: '',
    maxAmount: '',
  });

  const [selectedBills, setSelectedBills] = useState<string[]>([]);
  const [selectedBill, setSelectedBill] = useState<BillData | null>(null);
  const [showBillDetails, setShowBillDetails] = useState(false);
  const [showRefundModal, setShowRefundModal] = useState(false);
  const [refundReason, setRefundReason] = useState('');
  const [currentPage, setCurrentPage] = useState(1);
  const itemsPerPage = 50;

  // Mock data - in real app, this would come from API
  const branches = ['Downtown Branch', 'Mall Branch', 'Industrial Branch', 'Suburb Branch'];
  const cashiers = ['John Smith', 'Jane Doe', 'Mike Johnson', 'Sarah Wilson', 'David Chen', 'Lisa Anderson'];

  const mockBillsData: BillData[] = [
    {
      id: 'CB001',
      branch: 'Downtown Branch',
      dateTime: new Date('2024-01-15T14:30:00'),
      cashier: 'John Smith',
      customer: 'ABC Construction Ltd',
      itemsCount: 3,
      discount: 125.50,
      tax: 156.25,
      total: 2078.75,
      paymentMethod: 'cash',
      status: 'completed',
      lineItems: [
        { productName: 'Metal Roofing Sheets', category: 'roofing', quantity: 5, unitType: 'per sheet', unitPrice: 25.99, discount: 25.00, total: 104.95 },
        { productName: 'Portland Cement', category: 'cement', quantity: 10, unitType: 'per bag', unitPrice: 12.50, discount: 0, total: 125.00 },
        { productName: 'Steel Rebar', category: 'steel', quantity: 20, unitType: 'per piece', unitPrice: 45.00, discount: 100.50, total: 799.50 },
      ]
    },
    {
      id: 'CB002',
      branch: 'Mall Branch',
      dateTime: new Date('2024-01-15T15:45:00'),
      cashier: 'Jane Doe',
      itemsCount: 2,
      discount: 89.25,
      tax: 71.34,
      total: 980.59,
      paymentMethod: 'credit',
      status: 'completed',
      lineItems: [
        { productName: 'Exterior Wall Paint', category: 'paint', quantity: 8, unitType: 'per gallon', unitPrice: 34.99, discount: 35.00, total: 244.92 },
        { productName: 'Power Drill', category: 'tools', quantity: 3, unitType: 'per piece', unitPrice: 89.99, discount: 54.25, total: 215.72 },
      ]
    },
    {
      id: 'CB003',
      branch: 'Industrial Branch',
      dateTime: new Date('2024-01-15T16:20:00'),
      cashier: 'Mike Johnson',
      customer: 'BuildRight Co.',
      itemsCount: 4,
      discount: 234.75,
      tax: 187.62,
      total: 2578.87,
      paymentMethod: 'bank',
      status: 'completed',
      lineItems: [
        { productName: 'Steel I-Beam', category: 'steel', quantity: 2, unitType: 'per piece', unitPrice: 156.00, discount: 31.20, total: 280.80 },
        { productName: 'Ready Mix Concrete', category: 'cement', quantity: 5, unitType: 'per cubic meter', unitPrice: 125.00, discount: 62.50, total: 562.50 },
        { productName: 'Clay Roof Tiles', category: 'roofing', quantity: 100, unitType: 'per piece', unitPrice: 3.50, discount: 35.00, total: 315.00 },
        { productName: 'Hex Bolts', category: 'hardware', quantity: 500, unitType: 'per piece', unitPrice: 0.45, discount: 22.50, total: 202.50 },
      ]
    },
    {
      id: 'CB004',
      branch: 'Suburb Branch',
      dateTime: new Date('2024-01-15T17:10:00'),
      cashier: 'David Chen',
      customer: 'HomeBuilder Inc',
      itemsCount: 1,
      discount: 45.60,
      tax: 36.48,
      total: 501.88,
      paymentMethod: 'paylater',
      status: 'completed',
      lineItems: [
        { productName: 'Interior Paint', category: 'paint', quantity: 12, unitType: 'per gallon', unitPrice: 29.99, discount: 45.60, total: 314.28 },
      ]
    },
    {
      id: 'CB005',
      branch: 'Downtown Branch',
      dateTime: new Date('2024-01-14T18:00:00'),
      cashier: 'Sarah Wilson',
      itemsCount: 3,
      discount: 156.80,
      tax: 125.44,
      total: 1725.64,
      paymentMethod: 'cash',
      status: 'refunded',
      lineItems: [
        { productName: 'Circular Saw', category: 'tools', quantity: 2, unitType: 'per piece', unitPrice: 145.00, discount: 29.00, total: 261.00 },
        { productName: 'Wood Screws', category: 'hardware', quantity: 1000, unitType: 'per piece', unitPrice: 0.25, discount: 25.00, total: 225.00 },
        { productName: 'Roofing Membrane', category: 'roofing', quantity: 3, unitType: 'per roll', unitPrice: 89.99, discount: 26.97, total: 242.97 },
      ]
    },
  ];

  // Filter data based on current filters
  const filteredData = useMemo(() => {
    let filtered = mockBillsData;

    // Branch filter
    if (!filters.selectedBranches.includes('All')) {
      filtered = filtered.filter(bill => filters.selectedBranches.includes(bill.branch));
    }

    // Cashier filter
    if (!filters.selectedCashiers.includes('All')) {
      filtered = filtered.filter(bill => filters.selectedCashiers.includes(bill.cashier));
    }

    // Bill ID filter
    if (filters.billId) {
      filtered = filtered.filter(bill => bill.id.toLowerCase().includes(filters.billId.toLowerCase()));
    }

    // Customer filter
    if (filters.customer) {
      filtered = filtered.filter(bill => 
        bill.customer?.toLowerCase().includes(filters.customer.toLowerCase())
      );
    }

    // Payment method filter
    if (filters.paymentMethod !== 'all') {
      filtered = filtered.filter(bill => bill.paymentMethod === filters.paymentMethod);
    }

    // Amount range filter
    if (filters.minAmount) {
      filtered = filtered.filter(bill => bill.total >= parseFloat(filters.minAmount));
    }
    if (filters.maxAmount) {
      filtered = filtered.filter(bill => bill.total <= parseFloat(filters.maxAmount));
    }

    return filtered;
  }, [filters]);

  // Paginate data
  const paginatedData = useMemo(() => {
    const startIndex = (currentPage - 1) * itemsPerPage;
    return filteredData.slice(startIndex, startIndex + itemsPerPage);
  }, [filteredData, currentPage]);

  const totalPages = Math.ceil(filteredData.length / itemsPerPage);

  const handleFilterChange = (key: keyof FilterState, value: any) => {
    setFilters(prev => ({ ...prev, [key]: value }));
    setCurrentPage(1); // Reset to first page when filters change
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

  const handleSelectBill = (billId: string) => {
    setSelectedBills(prev => 
      prev.includes(billId) 
        ? prev.filter(id => id !== billId)
        : [...prev, billId]
    );
  };

  const handleSelectAll = () => {
    if (selectedBills.length === paginatedData.length) {
      setSelectedBills([]);
    } else {
      setSelectedBills(paginatedData.map(bill => bill.id));
    }
  };

  const handleBillClick = (bill: BillData) => {
    setSelectedBill(bill);
    setShowBillDetails(true);
  };

  const handleRefund = (bill: BillData) => {
    setSelectedBill(bill);
    setShowRefundModal(true);
  };

  const confirmRefund = () => {
    if (selectedBill && refundReason.trim()) {
      alert(`Refund processed for Bill #${selectedBill.id}. Reason: ${refundReason}`);
      setShowRefundModal(false);
      setRefundReason('');
      setSelectedBill(null);
    }
  };

  const handleExport = (format: 'csv' | 'pdf') => {
    if (selectedBills.length > 0) {
      alert(`Exporting ${selectedBills.length} selected bills as ${format.toUpperCase()}...`);
    } else {
      alert(`Exporting all ${filteredData.length} bills as ${format.toUpperCase()}...`);
    }
  };

  const handleBatchExport = () => {
    if (selectedBills.length === 0) {
      alert('Please select bills to export');
      return;
    }
    alert(`Batch exporting ${selectedBills.length} bills...`);
  };

  const handleDailyReport = () => {
    const today = new Date().toISOString().split('T')[0];
    alert(`Generating daily report for ${today}...`);
  };

  const formatCurrency = (amount: number) => `฿${amount.toLocaleString()}`;
  const formatDateTime = (date: Date) => `${date.toLocaleDateString()} ${date.toLocaleTimeString()}`;

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'completed': return 'bg-green-100 text-green-800';
      case 'refunded': return 'bg-orange-100 text-orange-800';
      case 'cancelled': return 'bg-red-100 text-red-800';
      default: return 'bg-gray-100 text-gray-800';
    }
  };

  const getStatusIcon = (status: string) => {
    switch (status) {
      case 'completed': return <CheckCircle className="w-3 h-3" />;
      case 'refunded': return <RefreshCw className="w-3 h-3" />;
      case 'cancelled': return <FileX className="w-3 h-3" />;
      default: return <Clock className="w-3 h-3" />;
    }
  };

  const getPaymentIcon = (method: string) => {
    switch (method) {
      case 'cash': return <DollarSign className="w-4 h-4 text-green-600" />;
      case 'credit': return <CreditCard className="w-4 h-4 text-blue-600" />;
      case 'bank': return <Building2 className="w-4 h-4 text-purple-600" />;
      case 'paylater': return <Clock className="w-4 h-4 text-orange-600" />;
      default: return <DollarSign className="w-4 h-4 text-gray-600" />;
    }
  };

  return (
    <div className="p-6">
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-3xl font-bold text-gray-900">Bills Archive</h1>
          <p className="text-gray-600 mt-2">Centralized archive of all completed transactions</p>
        </div>
        <div className="flex items-center space-x-3">
          <button
            onClick={handleDailyReport}
            className="flex items-center space-x-2 px-4 py-2 bg-purple-500 hover:bg-purple-600 text-white rounded-lg transition-colors"
          >
            <Calendar className="w-4 h-4" />
            <span>Daily Report</span>
          </button>
          <button
            onClick={() => handleExport('csv')}
            className="flex items-center space-x-2 px-4 py-2 bg-green-500 hover:bg-green-600 text-white rounded-lg transition-colors"
          >
            <Download className="w-4 h-4" />
            <span>Export CSV</span>
          </button>
          <button
            onClick={() => handleExport('pdf')}
            className="flex items-center space-x-2 px-4 py-2 bg-red-500 hover:bg-red-600 text-white rounded-lg transition-colors"
          >
            <FileText className="w-4 h-4" />
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
            <label className="block text-sm font-medium text-gray-700 mb-2">Bill ID</label>
            <input
              type="text"
              placeholder="Search by Bill ID..."
              value={filters.billId}
              onChange={(e) => handleFilterChange('billId', e.target.value)}
              className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
            />
          </div>

          <div>
            <label className="block text-sm font-medium text-gray-700 mb-2">Customer</label>
            <input
              type="text"
              placeholder="Search by customer..."
              value={filters.customer}
              onChange={(e) => handleFilterChange('customer', e.target.value)}
              className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
            />
          </div>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 mb-4">
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

          <div>
            <label className="block text-sm font-medium text-gray-700 mb-2">Min Amount</label>
            <input
              type="number"
              placeholder="0.00"
              value={filters.minAmount}
              onChange={(e) => handleFilterChange('minAmount', e.target.value)}
              className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
            />
          </div>

          <div>
            <label className="block text-sm font-medium text-gray-700 mb-2">Max Amount</label>
            <input
              type="number"
              placeholder="999999.99"
              value={filters.maxAmount}
              onChange={(e) => handleFilterChange('maxAmount', e.target.value)}
              className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
            />
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

      {/* Bills Table */}
      <div className="bg-white rounded-lg border border-gray-200 overflow-hidden">
        {/* Bulk Actions Bar */}
        {selectedBills.length > 0 && (
          <div className="bg-blue-50 border-b border-blue-200 px-6 py-3">
            <div className="flex items-center justify-between">
              <span className="text-sm text-blue-700">
                {selectedBills.length} bill{selectedBills.length !== 1 ? 's' : ''} selected
              </span>
              <div className="flex items-center space-x-2">
                <button
                  onClick={handleBatchExport}
                  className="px-3 py-1 bg-blue-500 hover:bg-blue-600 text-white text-sm rounded transition-colors"
                >
                  Batch Export
                </button>
                <button
                  onClick={() => setSelectedBills([])}
                  className="px-3 py-1 bg-gray-500 hover:bg-gray-600 text-white text-sm rounded transition-colors"
                >
                  Clear Selection
                </button>
              </div>
            </div>
          </div>
        )}

        <div className="overflow-x-auto">
          <table className="w-full">
            <thead className="bg-gray-50 border-b border-gray-200">
              <tr>
                <th className="px-6 py-3 text-left">
                  <input
                    type="checkbox"
                    checked={selectedBills.length === paginatedData.length && paginatedData.length > 0}
                    onChange={handleSelectAll}
                    className="rounded border-gray-300 text-blue-600 focus:ring-blue-500"
                  />
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Bill ID</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Branch</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Date/Time</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Cashier</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Customer</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Items</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Discount</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Tax</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Total</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Payment</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Status</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Actions</th>
              </tr>
            </thead>
            <tbody className="bg-white divide-y divide-gray-200">
              {paginatedData.map((bill) => (
                <tr 
                  key={bill.id} 
                  className="hover:bg-gray-50 cursor-pointer"
                  onClick={() => handleBillClick(bill)}
                >
                  <td className="px-6 py-4 whitespace-nowrap">
                    <input
                      type="checkbox"
                      checked={selectedBills.includes(bill.id)}
                      onChange={(e) => {
                        e.stopPropagation();
                        handleSelectBill(bill.id);
                      }}
                      className="rounded border-gray-300 text-blue-600 focus:ring-blue-500"
                    />
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm font-medium text-blue-600 hover:text-blue-800">
                    #{bill.id}
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">{bill.branch}</td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                    {bill.dateTime.toLocaleDateString()}<br />
                    {bill.dateTime.toLocaleTimeString()}
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">{bill.cashier}</td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                    {bill.customer || '-'}
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">{bill.itemsCount}</td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-red-600">{formatCurrency(bill.discount)}</td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">{formatCurrency(bill.tax)}</td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">{formatCurrency(bill.total)}</td>
                  <td className="px-6 py-4 whitespace-nowrap">
                    <div className="flex items-center space-x-1">
                      {getPaymentIcon(bill.paymentMethod)}
                      <span className="text-sm text-gray-700 capitalize">{bill.paymentMethod}</span>
                    </div>
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap">
                    <span className={`inline-flex items-center space-x-1 px-2.5 py-0.5 rounded-full text-xs font-medium ${getStatusColor(bill.status)}`}>
                      {getStatusIcon(bill.status)}
                      <span className="capitalize">{bill.status}</span>
                    </span>
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                    <div className="flex items-center space-x-2">
                      <button
                        onClick={(e) => {
                          e.stopPropagation();
                          handleBillClick(bill);
                        }}
                        className="text-blue-600 hover:text-blue-800 transition-colors"
                        title="View Details"
                      >
                        <Eye className="w-4 h-4" />
                      </button>
                      <button
                        onClick={(e) => {
                          e.stopPropagation();
                          alert(`Reprinting Bill #${bill.id}`);
                        }}
                        className="text-gray-600 hover:text-gray-800 transition-colors"
                        title="Reprint"
                      >
                        <Printer className="w-4 h-4" />
                      </button>
                      <button
                        onClick={(e) => {
                          e.stopPropagation();
                          alert(`Exporting Bill #${bill.id} as PDF`);
                        }}
                        className="text-green-600 hover:text-green-800 transition-colors"
                        title="Export PDF"
                      >
                        <FileText className="w-4 h-4" />
                      </button>
                      {bill.status === 'completed' && (
                        <button
                          onClick={(e) => {
                            e.stopPropagation();
                            handleRefund(bill);
                          }}
                          className="text-red-600 hover:text-red-800 transition-colors"
                          title="Refund/Cancel"
                        >
                          <Trash2 className="w-4 h-4" />
                        </button>
                      )}
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>

        {/* Pagination */}
        <div className="bg-white px-4 py-3 flex items-center justify-between border-t border-gray-200 sm:px-6">
          <div className="flex-1 flex justify-between sm:hidden">
            <button
              onClick={() => setCurrentPage(prev => Math.max(prev - 1, 1))}
              disabled={currentPage === 1}
              className="relative inline-flex items-center px-4 py-2 border border-gray-300 text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50 disabled:opacity-50 disabled:cursor-not-allowed"
            >
              Previous
            </button>
            <button
              onClick={() => setCurrentPage(prev => Math.min(prev + 1, totalPages))}
              disabled={currentPage === totalPages}
              className="ml-3 relative inline-flex items-center px-4 py-2 border border-gray-300 text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50 disabled:opacity-50 disabled:cursor-not-allowed"
            >
              Next
            </button>
          </div>
          <div className="hidden sm:flex-1 sm:flex sm:items-center sm:justify-between">
            <div>
              <p className="text-sm text-gray-700">
                Showing <span className="font-medium">{(currentPage - 1) * itemsPerPage + 1}</span> to{' '}
                <span className="font-medium">
                  {Math.min(currentPage * itemsPerPage, filteredData.length)}
                </span>{' '}
                of <span className="font-medium">{filteredData.length}</span> results
              </p>
            </div>
            <div>
              <nav className="relative z-0 inline-flex rounded-md shadow-sm -space-x-px" aria-label="Pagination">
                <button
                  onClick={() => setCurrentPage(prev => Math.max(prev - 1, 1))}
                  disabled={currentPage === 1}
                  className="relative inline-flex items-center px-2 py-2 rounded-l-md border border-gray-300 bg-white text-sm font-medium text-gray-500 hover:bg-gray-50 disabled:opacity-50 disabled:cursor-not-allowed"
                >
                  Previous
                </button>
                {Array.from({ length: Math.min(totalPages, 5) }, (_, i) => {
                  const pageNum = i + 1;
                  return (
                    <button
                      key={pageNum}
                      onClick={() => setCurrentPage(pageNum)}
                      className={`relative inline-flex items-center px-4 py-2 border text-sm font-medium ${
                        currentPage === pageNum
                          ? 'z-10 bg-blue-50 border-blue-500 text-blue-600'
                          : 'bg-white border-gray-300 text-gray-500 hover:bg-gray-50'
                      }`}
                    >
                      {pageNum}
                    </button>
                  );
                })}
                <button
                  onClick={() => setCurrentPage(prev => Math.min(prev + 1, totalPages))}
                  disabled={currentPage === totalPages}
                  className="relative inline-flex items-center px-2 py-2 rounded-r-md border border-gray-300 bg-white text-sm font-medium text-gray-500 hover:bg-gray-50 disabled:opacity-50 disabled:cursor-not-allowed"
                >
                  Next
                </button>
              </nav>
            </div>
          </div>
        </div>

        {filteredData.length === 0 && (
          <div className="text-center py-12">
            <div className="text-gray-500 text-lg">No bills found</div>
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
              <h3 className="text-xl font-semibold text-gray-900">Bill Details - #{selectedBill.id}</h3>
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
                    <p className="font-medium">{formatDateTime(selectedBill.dateTime)}</p>
                  </div>
                  <div>
                    <span className="text-sm text-gray-500">Payment Method:</span>
                    <p className="font-medium capitalize">{selectedBill.paymentMethod}</p>
                  </div>
                  {selectedBill.customer && (
                    <div className="col-span-2">
                      <span className="text-sm text-gray-500">Customer:</span>
                      <p className="font-medium">{selectedBill.customer}</p>
                    </div>
                  )}
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

      {/* Refund Modal */}
      {showRefundModal && selectedBill && (
        <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
          <div className="bg-white rounded-lg shadow-xl max-w-md w-full mx-4">
            <div className="flex items-center justify-between p-6 border-b border-gray-200">
              <h3 className="text-lg font-semibold text-gray-900">Refund Bill</h3>
              <button
                onClick={() => setShowRefundModal(false)}
                className="text-gray-400 hover:text-gray-600 transition-colors"
              >
                <X className="w-5 h-5" />
              </button>
            </div>
            
            <div className="p-6">
              <div className="flex items-center space-x-3 p-4 rounded-lg border border-red-200 bg-red-50 mb-4">
                <AlertTriangle className="w-5 h-5 text-red-600 flex-shrink-0" />
                <div>
                  <p className="text-sm font-medium text-red-800">Refund Bill #{selectedBill.id}</p>
                  <p className="text-sm text-red-600">Total: {formatCurrency(selectedBill.total)}</p>
                </div>
              </div>
              
              <div className="mb-4">
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  Reason for Refund <span className="text-red-500">*</span>
                </label>
                <textarea
                  value={refundReason}
                  onChange={(e) => setRefundReason(e.target.value)}
                  rows={4}
                  className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                  placeholder="Please provide a detailed reason for the refund..."
                />
              </div>
            </div>
            
            <div className="flex items-center justify-end space-x-3 p-6 border-t border-gray-200">
              <button
                onClick={() => setShowRefundModal(false)}
                className="px-4 py-2 text-sm font-medium text-gray-700 bg-gray-100 hover:bg-gray-200 rounded-lg transition-colors"
              >
                Cancel
              </button>
              <button
                onClick={confirmRefund}
                disabled={!refundReason.trim()}
                className="px-4 py-2 text-sm font-medium text-white bg-red-500 hover:bg-red-600 disabled:bg-gray-300 disabled:cursor-not-allowed rounded-lg transition-colors"
              >
                Process Refund
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};