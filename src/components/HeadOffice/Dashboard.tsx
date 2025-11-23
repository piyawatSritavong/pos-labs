import React, { useState, useMemo } from 'react';
import { 
  TrendingUp, 
  Users, 
  ShoppingCart, 
  AlertTriangle, 
  DollarSign, 
  Building2,
  Calendar,
  Download,
  Filter,
  Clock,
  Receipt,
  Percent,
  Calculator
} from 'lucide-react';

interface DashboardProps {}

interface BillData {
  id: string;
  branch: string;
  cashier: string;
  total: number;
  timestamp: Date;
  paymentMethod: 'cash' | 'credit' | 'bank' | 'paylater';
}

interface BranchData {
  name: string;
  revenue: number;
  bills: number;
  status: 'online' | 'offline';
}

interface LowStockItem {
  name: string;
  branch: string;
  currentStock: number;
  threshold: number;
  category: string;
}

interface MissingShift {
  branch: string;
  shift: 'Morning' | 'Afternoon' | 'Evening';
  dueTime: Date;
  cashier: string;
}

export const Dashboard: React.FC<DashboardProps> = () => {
  const [dateRange, setDateRange] = useState('7D');
  const [selectedBranches, setSelectedBranches] = useState<string[]>(['All']);
  const [customDateStart, setCustomDateStart] = useState('');
  const [customDateEnd, setCustomDateEnd] = useState('');

  // Mock data - in real app, this would come from API
  const branches = ['Downtown Branch', 'Mall Branch', 'Industrial Branch', 'Suburb Branch'];
  
  const mockBillsData: BillData[] = [
    { id: 'CB001', branch: 'Downtown Branch', cashier: 'John Smith', total: 1250.75, timestamp: new Date(Date.now() - 1000 * 60 * 15), paymentMethod: 'cash' },
    { id: 'CB002', branch: 'Mall Branch', cashier: 'Jane Doe', total: 890.50, timestamp: new Date(Date.now() - 1000 * 60 * 25), paymentMethod: 'credit' },
    { id: 'CB003', branch: 'Industrial Branch', cashier: 'Mike Johnson', total: 2340.25, timestamp: new Date(Date.now() - 1000 * 60 * 35), paymentMethod: 'bank' },
    { id: 'CB004', branch: 'Downtown Branch', cashier: 'Sarah Wilson', total: 567.80, timestamp: new Date(Date.now() - 1000 * 60 * 45), paymentMethod: 'paylater' },
    { id: 'CB005', branch: 'Suburb Branch', cashier: 'David Chen', total: 1890.00, timestamp: new Date(Date.now() - 1000 * 60 * 55), paymentMethod: 'cash' },
    { id: 'CB006', branch: 'Mall Branch', cashier: 'Lisa Anderson', total: 445.30, timestamp: new Date(Date.now() - 1000 * 60 * 65), paymentMethod: 'credit' },
    { id: 'CB007', branch: 'Industrial Branch', cashier: 'Tom Brown', total: 3250.90, timestamp: new Date(Date.now() - 1000 * 60 * 75), paymentMethod: 'bank' },
    { id: 'CB008', branch: 'Downtown Branch', cashier: 'John Smith', total: 789.45, timestamp: new Date(Date.now() - 1000 * 60 * 85), paymentMethod: 'cash' },
    { id: 'CB009', branch: 'Suburb Branch', cashier: 'Emma Davis', total: 1456.70, timestamp: new Date(Date.now() - 1000 * 60 * 95), paymentMethod: 'paylater' },
    { id: 'CB010', branch: 'Mall Branch', cashier: 'Jane Doe', total: 678.25, timestamp: new Date(Date.now() - 1000 * 60 * 105), paymentMethod: 'credit' },
  ];

  const branchData: BranchData[] = [
    { name: 'Downtown Branch', revenue: 45230.50, bills: 342, status: 'online' },
    { name: 'Mall Branch', revenue: 38920.75, bills: 298, status: 'online' },
    { name: 'Industrial Branch', revenue: 52150.25, bills: 245, status: 'online' },
    { name: 'Suburb Branch', revenue: 29129.00, bills: 362, status: 'offline' },
  ];

  const lowStockItems: LowStockItem[] = [
    { name: 'Clay Roof Tiles', branch: 'Downtown Branch', currentStock: 8, threshold: 10, category: 'roofing' },
    { name: 'Mortar Mix', branch: 'Mall Branch', currentStock: 6, threshold: 10, category: 'cement' },
    { name: 'Paint Primer', branch: 'Industrial Branch', currentStock: 7, threshold: 10, category: 'paint' },
    { name: 'Wood Screws', branch: 'Suburb Branch', currentStock: 85, threshold: 100, category: 'hardware' },
    { name: 'Steel Wire Mesh', branch: 'Downtown Branch', currentStock: 9, threshold: 10, category: 'steel' },
    { name: 'Exterior Paint', branch: 'Mall Branch', currentStock: 8, threshold: 15, category: 'paint' },
    { name: 'Cement Bags', branch: 'Industrial Branch', currentStock: 18, threshold: 20, category: 'cement' },
    { name: 'Roofing Nails', branch: 'Suburb Branch', currentStock: 45, threshold: 50, category: 'hardware' },
    { name: 'Insulation Foam', branch: 'Downtown Branch', currentStock: 5, threshold: 8, category: 'insulation' },
    { name: 'PVC Pipes', branch: 'Mall Branch', currentStock: 12, threshold: 15, category: 'plumbing' },
  ];

  const missingShifts: MissingShift[] = [
    { branch: 'Suburb Branch', shift: 'Evening', dueTime: new Date(Date.now() - 1000 * 60 * 60 * 2), cashier: 'David Chen' },
    { branch: 'Industrial Branch', shift: 'Morning', dueTime: new Date(Date.now() - 1000 * 60 * 60 * 1), cashier: 'Mike Johnson' },
    { branch: 'Mall Branch', shift: 'Afternoon', dueTime: new Date(Date.now() - 1000 * 60 * 30), cashier: 'Jane Doe' },
  ];

  // Filter data based on selected branches
  const filteredData = useMemo(() => {
    const isAllBranches = selectedBranches.includes('All');
    const filteredBills = isAllBranches ? mockBillsData : mockBillsData.filter(bill => selectedBranches.includes(bill.branch));
    const filteredBranchData = isAllBranches ? branchData : branchData.filter(branch => selectedBranches.includes(branch.name));
    
    return { bills: filteredBills, branches: filteredBranchData };
  }, [selectedBranches]);

  // Calculate KPIs
  const kpis = useMemo(() => {
    const totalRevenue = filteredData.bills.reduce((sum, bill) => sum + bill.total, 0);
    const totalBills = filteredData.bills.length;
    const avgBillValue = totalBills > 0 ? totalRevenue / totalBills : 0;
    const discounts = totalRevenue * 0.05; // Mock 5% average discount
    const tax = totalRevenue * 0.08; // 8% tax
    const netSales = totalRevenue - discounts;

    return { totalRevenue, totalBills, avgBillValue, discounts, tax, netSales };
  }, [filteredData.bills]);

  // Payment method breakdown
  const paymentBreakdown = useMemo(() => {
    const breakdown = filteredData.bills.reduce((acc, bill) => {
      acc[bill.paymentMethod] = (acc[bill.paymentMethod] || 0) + bill.total;
      return acc;
    }, {} as Record<string, number>);

    return [
      { name: 'Cash', value: breakdown.cash || 0, color: '#10B981' },
      { name: 'Credit Card', value: breakdown.credit || 0, color: '#3B82F6' },
      { name: 'Bank Transfer', value: breakdown.bank || 0, color: '#8B5CF6' },
      { name: 'PayLater', value: breakdown.paylater || 0, color: '#F59E0B' },
    ];
  }, [filteredData.bills]);

  const handleBranchSelect = (branch: string) => {
    if (branch === 'All') {
      setSelectedBranches(['All']);
    } else {
      setSelectedBranches(prev => {
        const filtered = prev.filter(b => b !== 'All');
        if (filtered.includes(branch)) {
          const newSelection = filtered.filter(b => b !== branch);
          return newSelection.length === 0 ? ['All'] : newSelection;
        } else {
          return [...filtered, branch];
        }
      });
    }
  };

  const handleExportPDF = () => {
    alert('Exporting dashboard snapshot to PDF...');
  };

  const formatTime = (date: Date) => {
    const now = new Date();
    const diffMs = now.getTime() - date.getTime();
    const diffMins = Math.floor(diffMs / (1000 * 60));
    
    if (diffMins < 1) return 'Just now';
    if (diffMins < 60) return `${diffMins}m ago`;
    const diffHours = Math.floor(diffMins / 60);
    if (diffHours < 24) return `${diffHours}h ago`;
    const diffDays = Math.floor(diffHours / 24);
    return `${diffDays}d ago`;
  };

  return (
    <div className="p-6 bg-gray-50 min-h-screen">
      {/* Header */}
      <div className="mb-8">
        <div className="flex items-center justify-between mb-6">
          <div>
            <h1 className="text-3xl font-bold text-gray-900">Head Office — Dashboard</h1>
            <p className="text-gray-600 mt-2">Real-time overview of all branch operations</p>
          </div>
          <button
            onClick={handleExportPDF}
            className="flex items-center space-x-2 px-4 py-2 bg-blue-500 hover:bg-blue-600 text-white rounded-lg transition-colors"
          >
            <Download className="w-4 h-4" />
            <span>Export PDF</span>
          </button>
        </div>

        {/* Filters */}
        <div className="bg-white rounded-lg border border-gray-200 p-4">
          <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-2">Date Range</label>
              <select
                value={dateRange}
                onChange={(e) => setDateRange(e.target.value)}
                className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
              >
                <option value="Today">Today</option>
                <option value="7D">Last 7 Days</option>
                <option value="30D">Last 30 Days</option>
                <option value="Custom">Custom Range</option>
              </select>
            </div>

            {dateRange === 'Custom' && (
              <>
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">Start Date</label>
                  <input
                    type="date"
                    value={customDateStart}
                    onChange={(e) => setCustomDateStart(e.target.value)}
                    className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                  />
                </div>
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">End Date</label>
                  <input
                    type="date"
                    value={customDateEnd}
                    onChange={(e) => setCustomDateEnd(e.target.value)}
                    className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                  />
                </div>
              </>
            )}

            <div>
              <label className="block text-sm font-medium text-gray-700 mb-2">Branches</label>
              <div className="relative">
                <select
                  multiple
                  value={selectedBranches}
                  onChange={(e) => {
                    const values = Array.from(e.target.selectedOptions, option => option.value);
                    setSelectedBranches(values.length === 0 ? ['All'] : values);
                  }}
                  className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                >
                  <option value="All">All Branches</option>
                  {branches.map(branch => (
                    <option key={branch} value={branch}>{branch}</option>
                  ))}
                </select>
              </div>
            </div>
          </div>

          <div className="mt-4 flex flex-wrap gap-2">
            {['All', ...branches].map(branch => (
              <button
                key={branch}
                onClick={() => handleBranchSelect(branch)}
                className={`px-3 py-1 rounded-full text-sm font-medium transition-colors ${
                  selectedBranches.includes(branch)
                    ? 'bg-blue-500 text-white'
                    : 'bg-gray-100 text-gray-700 hover:bg-gray-200'
                }`}
              >
                {branch}
              </button>
            ))}
          </div>
        </div>
      </div>

      {/* KPI Cards */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-6 gap-6 mb-8">
        <div className="bg-white rounded-lg border border-gray-200 p-6">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-gray-600">Total Revenue</p>
              <p className="text-2xl font-bold text-gray-900">฿{kpis.totalRevenue.toLocaleString()}</p>
            </div>
            <DollarSign className="w-8 h-8 text-green-600" />
          </div>
        </div>

        <div className="bg-white rounded-lg border border-gray-200 p-6">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-gray-600">Total Bills</p>
              <p className="text-2xl font-bold text-gray-900">{kpis.totalBills.toLocaleString()}</p>
            </div>
            <Receipt className="w-8 h-8 text-blue-600" />
          </div>
        </div>

        <div className="bg-white rounded-lg border border-gray-200 p-6">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-gray-600">Avg. Bill Value</p>
              <p className="text-2xl font-bold text-gray-900">฿{kpis.avgBillValue.toLocaleString()}</p>
            </div>
            <Calculator className="w-8 h-8 text-purple-600" />
          </div>
        </div>

        <div className="bg-white rounded-lg border border-gray-200 p-6">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-gray-600">Discounts</p>
              <p className="text-2xl font-bold text-red-600">฿{kpis.discounts.toLocaleString()}</p>
            </div>
            <Percent className="w-8 h-8 text-red-600" />
          </div>
        </div>

        <div className="bg-white rounded-lg border border-gray-200 p-6">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-gray-600">Tax</p>
              <p className="text-2xl font-bold text-gray-900">฿{kpis.tax.toLocaleString()}</p>
            </div>
            <Building2 className="w-8 h-8 text-orange-600" />
          </div>
        </div>

        <div className="bg-white rounded-lg border border-gray-200 p-6">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-gray-600">Net Sales</p>
              <p className="text-2xl font-bold text-green-600">฿{kpis.netSales.toLocaleString()}</p>
            </div>
            <TrendingUp className="w-8 h-8 text-green-600" />
          </div>
        </div>
      </div>

      {/* Charts Row */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6 mb-8">
        {/* Sales Trend Chart */}
        <div className="lg:col-span-2 bg-white rounded-lg border border-gray-200 p-6">
          <h3 className="text-lg font-semibold text-gray-900 mb-4">Sales Trend</h3>
          <div className="h-64 flex items-center justify-center bg-gray-50 rounded-lg">
            <div className="text-center">
              <TrendingUp className="w-12 h-12 text-gray-400 mx-auto mb-2" />
              <p className="text-gray-500">Sales trend chart would be rendered here</p>
              <p className="text-sm text-gray-400">Line chart showing daily sales over selected period</p>
            </div>
          </div>
        </div>

        {/* Payment Breakdown */}
        <div className="bg-white rounded-lg border border-gray-200 p-6">
          <h3 className="text-lg font-semibold text-gray-900 mb-4">Payment Breakdown</h3>
          <div className="space-y-4">
            {paymentBreakdown.map((method, index) => (
              <div key={index} className="flex items-center justify-between">
                <div className="flex items-center space-x-3">
                  <div 
                    className="w-4 h-4 rounded-full"
                    style={{ backgroundColor: method.color }}
                  ></div>
                  <span className="text-sm text-gray-700">{method.name}</span>
                </div>
                <span className="text-sm font-medium text-gray-900">
                  ฿{method.value.toLocaleString()}
                </span>
              </div>
            ))}
          </div>
        </div>
      </div>

      {/* Branch Comparison Chart */}
      <div className="bg-white rounded-lg border border-gray-200 p-6 mb-8">
        <h3 className="text-lg font-semibold text-gray-900 mb-4">Branch Comparison</h3>
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
          {filteredData.branches.map((branch, index) => (
            <div key={index} className="p-4 bg-gray-50 rounded-lg">
              <div className="flex items-center justify-between mb-2">
                <h4 className="font-medium text-gray-900">{branch.name}</h4>
                <div className={`w-3 h-3 rounded-full ${branch.status === 'online' ? 'bg-green-500' : 'bg-red-500'}`}></div>
              </div>
              <p className="text-2xl font-bold text-gray-900">฿{branch.revenue.toLocaleString()}</p>
              <p className="text-sm text-gray-500">{branch.bills} bills</p>
            </div>
          ))}
        </div>
      </div>

      {/* Alerts & Recent Activity */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Alerts & Tasks */}
        <div className="space-y-6">
          {/* Low Stock Alerts */}
          <div className="bg-white rounded-lg border border-gray-200 p-6">
            <div className="flex items-center space-x-2 mb-4">
              <AlertTriangle className="w-5 h-5 text-orange-600" />
              <h3 className="text-lg font-semibold text-gray-900">Low Stock Alerts</h3>
            </div>
            <div className="space-y-3">
              {lowStockItems.slice(0, 5).map((item, index) => (
                <div key={index} className="flex items-center justify-between p-3 bg-orange-50 rounded-lg">
                  <div>
                    <p className="font-medium text-gray-900">{item.name}</p>
                    <p className="text-sm text-gray-500">{item.branch} • {item.category}</p>
                  </div>
                  <div className="text-right">
                    <p className="text-sm font-medium text-orange-600">{item.currentStock} left</p>
                    <p className="text-xs text-gray-500">Min: {item.threshold}</p>
                  </div>
                </div>
              ))}
            </div>
          </div>

          {/* Missing Shift Reports */}
          <div className="bg-white rounded-lg border border-gray-200 p-6">
            <div className="flex items-center space-x-2 mb-4">
              <Clock className="w-5 h-5 text-red-600" />
              <h3 className="text-lg font-semibold text-gray-900">Missing Shift Reports</h3>
            </div>
            <div className="space-y-3">
              {missingShifts.map((shift, index) => (
                <div key={index} className="flex items-center justify-between p-3 bg-red-50 rounded-lg">
                  <div>
                    <p className="font-medium text-gray-900">{shift.branch}</p>
                    <p className="text-sm text-gray-500">{shift.shift} Shift • {shift.cashier}</p>
                  </div>
                  <div className="text-right">
                    <p className="text-sm font-medium text-red-600">Overdue</p>
                    <p className="text-xs text-gray-500">{formatTime(shift.dueTime)}</p>
                  </div>
                </div>
              ))}
            </div>
          </div>
        </div>

        {/* Recent Activity */}
        <div className="bg-white rounded-lg border border-gray-200 p-6">
          <h3 className="text-lg font-semibold text-gray-900 mb-4">Recent Activity</h3>
          <div className="space-y-3">
            {filteredData.bills.slice(0, 10).map((bill, index) => (
              <div key={index} className="flex items-center justify-between p-3 bg-gray-50 rounded-lg">
                <div>
                  <p className="font-medium text-gray-900">#{bill.id}</p>
                  <p className="text-sm text-gray-500">{bill.branch} • {bill.cashier}</p>
                </div>
                <div className="text-right">
                  <p className="font-medium text-gray-900">฿{bill.total.toLocaleString()}</p>
                  <p className="text-xs text-gray-500">{formatTime(bill.timestamp)}</p>
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
};