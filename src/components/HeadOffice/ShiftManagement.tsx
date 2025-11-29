import React, { useState, useMemo } from 'react';
import { 
  Clock, 
  Users, 
  DollarSign, 
  CreditCard, 
  Building2, 
  AlertTriangle, 
  Download, 
  FileText, 
  Search, 
  Calendar, 
  Eye, 
  X,
  CheckCircle,
  XCircle,
  TrendingUp,
  Calculator,
  Percent
} from 'lucide-react';

interface ShiftData {
  id: string;
  branch: string;
  cashier: string;
  shiftType: 'Morning' | 'Afternoon' | 'Evening' | 'Custom';
  startTime: Date;
  endTime: Date;
  billsCount: number;
  grossSales: number;
  discounts: number;
  tax: number;
  netSales: number;
  paymentBreakdown: {
    cash: number;
    credit: number;
    bank: number;
    paylater: number;
  };
  cashReconciliation?: {
    expected: number;
    counted: number;
    variance: number;
  };
  events: ShiftEvent[];
}

interface ShiftEvent {
  id: string;
  timestamp: Date;
  type: 'open' | 'close' | 'anomaly' | 'break' | 'override';
  description: string;
  severity: 'info' | 'warning' | 'error';
}

interface MissingShift {
  branch: string;
  shiftType: 'Morning' | 'Afternoon' | 'Evening';
  expectedCloseTime: Date;
  assignedCashier: string;
  status: 'overdue' | 'critical';
}

interface FilterState {
  dateRange: string;
  customDateStart: string;
  customDateEnd: string;
  selectedBranches: string[];
  selectedCashiers: string[];
  shiftType: string;
}

export const ShiftManagement: React.FC = () => {
  const [filters, setFilters] = useState<FilterState>({
    dateRange: 'today',
    customDateStart: '',
    customDateEnd: '',
    selectedBranches: ['All'],
    selectedCashiers: ['All'],
    shiftType: 'all',
  });

  const [selectedShift, setSelectedShift] = useState<ShiftData | null>(null);
  const [showShiftDetails, setShowShiftDetails] = useState(false);

  // Mock data
  const branches = ['Downtown Branch', 'Mall Branch', 'Industrial Branch', 'Suburb Branch'];
  const cashiers = ['John Smith', 'Jane Doe', 'Mike Johnson', 'Sarah Wilson', 'David Chen', 'Lisa Anderson'];

  const mockShiftData: ShiftData[] = [
    {
      id: 'SH001',
      branch: 'Downtown Branch',
      cashier: 'John Smith',
      shiftType: 'Morning',
      startTime: new Date('2024-01-15T08:00:00'),
      endTime: new Date('2024-01-15T16:00:00'),
      billsCount: 45,
      grossSales: 12450.75,
      discounts: 625.50,
      tax: 942.42,
      netSales: 11825.25,
      paymentBreakdown: {
        cash: 4500.00,
        credit: 3200.50,
        bank: 2800.75,
        paylater: 1324.00,
      },
      cashReconciliation: {
        expected: 4500.00,
        counted: 4485.00,
        variance: -15.00,
      },
      events: [
        {
          id: 'evt1',
          timestamp: new Date('2024-01-15T08:00:00'),
          type: 'open',
          description: 'Shift opened - Morning shift started',
          severity: 'info',
        },
        {
          id: 'evt2',
          timestamp: new Date('2024-01-15T12:30:00'),
          type: 'break',
          description: 'Lunch break - 30 minutes',
          severity: 'info',
        },
        {
          id: 'evt3',
          timestamp: new Date('2024-01-15T14:15:00'),
          type: 'anomaly',
          description: 'Large transaction - ฿2,500 single bill',
          severity: 'warning',
        },
        {
          id: 'evt4',
          timestamp: new Date('2024-01-15T16:00:00'),
          type: 'close',
          description: 'Shift closed - All transactions reconciled',
          severity: 'info',
        },
      ],
    },
    {
      id: 'SH002',
      branch: 'Mall Branch',
      cashier: 'Jane Doe',
      shiftType: 'Afternoon',
      startTime: new Date('2024-01-15T14:00:00'),
      endTime: new Date('2024-01-15T22:00:00'),
      billsCount: 38,
      grossSales: 9875.25,
      discounts: 487.50,
      tax: 751.02,
      netSales: 9387.75,
      paymentBreakdown: {
        cash: 2800.00,
        credit: 4200.25,
        bank: 1875.00,
        paylater: 1000.00,
      },
      events: [
        {
          id: 'evt5',
          timestamp: new Date('2024-01-15T14:00:00'),
          type: 'open',
          description: 'Shift opened - Afternoon shift started',
          severity: 'info',
        },
        {
          id: 'evt6',
          timestamp: new Date('2024-01-15T18:45:00'),
          type: 'override',
          description: 'Manager override - Discount approval',
          severity: 'warning',
        },
        {
          id: 'evt7',
          timestamp: new Date('2024-01-15T22:00:00'),
          type: 'close',
          description: 'Shift closed - End of day',
          severity: 'info',
        },
      ],
    },
    {
      id: 'SH003',
      branch: 'Industrial Branch',
      cashier: 'Mike Johnson',
      shiftType: 'Morning',
      startTime: new Date('2024-01-15T07:00:00'),
      endTime: new Date('2024-01-15T15:00:00'),
      billsCount: 52,
      grossSales: 15680.90,
      discounts: 784.50,
      tax: 1191.71,
      netSales: 14896.40,
      paymentBreakdown: {
        cash: 6200.00,
        credit: 4800.90,
        bank: 3200.00,
        paylater: 1480.00,
      },
      cashReconciliation: {
        expected: 6200.00,
        counted: 6225.00,
        variance: 25.00,
      },
      events: [
        {
          id: 'evt8',
          timestamp: new Date('2024-01-15T07:00:00'),
          type: 'open',
          description: 'Shift opened - Early morning shift',
          severity: 'info',
        },
        {
          id: 'evt9',
          timestamp: new Date('2024-01-15T10:30:00'),
          type: 'anomaly',
          description: 'System slow response - 5 second delays',
          severity: 'error',
        },
        {
          id: 'evt10',
          timestamp: new Date('2024-01-15T15:00:00'),
          type: 'close',
          description: 'Shift closed - Handed over to afternoon',
          severity: 'info',
        },
      ],
    },
    {
      id: 'SH004',
      branch: 'Suburb Branch',
      cashier: 'David Chen',
      shiftType: 'Evening',
      startTime: new Date('2024-01-15T16:00:00'),
      endTime: new Date('2024-01-15T20:00:00'),
      billsCount: 28,
      grossSales: 7250.60,
      discounts: 362.50,
      tax: 551.25,
      netSales: 6888.10,
      paymentBreakdown: {
        cash: 2100.00,
        credit: 2800.60,
        bank: 1650.00,
        paylater: 700.00,
      },
      events: [
        {
          id: 'evt11',
          timestamp: new Date('2024-01-15T16:00:00'),
          type: 'open',
          description: 'Shift opened - Evening shift started',
          severity: 'info',
        },
        {
          id: 'evt12',
          timestamp: new Date('2024-01-15T20:00:00'),
          type: 'close',
          description: 'Shift closed - End of business day',
          severity: 'info',
        },
      ],
    },
  ];

  const missingShifts: MissingShift[] = [
    {
      branch: 'Suburb Branch',
      shiftType: 'Morning',
      expectedCloseTime: new Date('2024-01-15T16:00:00'),
      assignedCashier: 'Sarah Wilson',
      status: 'overdue',
    },
    {
      branch: 'Mall Branch',
      shiftType: 'Evening',
      expectedCloseTime: new Date('2024-01-15T22:00:00'),
      assignedCashier: 'Lisa Anderson',
      status: 'critical',
    },
  ];

  // Filter data
  const filteredShifts = useMemo(() => {
    let filtered = mockShiftData;

    // Branch filter
    if (!filters.selectedBranches.includes('All')) {
      filtered = filtered.filter(shift => filters.selectedBranches.includes(shift.branch));
    }

    // Cashier filter
    if (!filters.selectedCashiers.includes('All')) {
      filtered = filtered.filter(shift => filters.selectedCashiers.includes(shift.cashier));
    }

    // Shift type filter
    if (filters.shiftType !== 'all') {
      filtered = filtered.filter(shift => shift.shiftType.toLowerCase() === filters.shiftType);
    }

    return filtered;
  }, [filters]);

  // Calculate totals
  const totals = useMemo(() => {
    return filteredShifts.reduce((acc, shift) => ({
      billsCount: acc.billsCount + shift.billsCount,
      grossSales: acc.grossSales + shift.grossSales,
      discounts: acc.discounts + shift.discounts,
      tax: acc.tax + shift.tax,
      netSales: acc.netSales + shift.netSales,
      cash: acc.cash + shift.paymentBreakdown.cash,
      credit: acc.credit + shift.paymentBreakdown.credit,
      bank: acc.bank + shift.paymentBreakdown.bank,
      paylater: acc.paylater + shift.paymentBreakdown.paylater,
    }), {
      billsCount: 0,
      grossSales: 0,
      discounts: 0,
      tax: 0,
      netSales: 0,
      cash: 0,
      credit: 0,
      bank: 0,
      paylater: 0,
    });
  }, [filteredShifts]);

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

  const handleShiftClick = (shift: ShiftData) => {
    setSelectedShift(shift);
    setShowShiftDetails(true);
  };

  const handleExport = (format: 'csv' | 'pdf') => {
    alert(`Exporting shifts data as ${format.toUpperCase()}...`);
  };

  const handleExportShiftReport = (shift: ShiftData) => {
    alert(`Exporting shift report for ${shift.id} as PDF...`);
  };

  const formatCurrency = (amount: number) => `฿${amount.toLocaleString()}`;
  const formatTime = (date: Date) => date.toLocaleTimeString();
  const formatDate = (date: Date) => date.toLocaleDateString();

  const getEventIcon = (type: string) => {
    switch (type) {
      case 'open': return <CheckCircle className="w-4 h-4 text-green-600" />;
      case 'close': return <XCircle className="w-4 h-4 text-blue-600" />;
      case 'anomaly': return <AlertTriangle className="w-4 h-4 text-orange-600" />;
      case 'break': return <Clock className="w-4 h-4 text-gray-600" />;
      case 'override': return <Users className="w-4 h-4 text-purple-600" />;
      default: return <Clock className="w-4 h-4 text-gray-600" />;
    }
  };

  const getEventColor = (severity: string) => {
    switch (severity) {
      case 'error': return 'bg-red-50 border-red-200';
      case 'warning': return 'bg-orange-50 border-orange-200';
      default: return 'bg-blue-50 border-blue-200';
    }
  };

  return (
    <div className="p-6">
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-3xl font-bold text-gray-900">Shift Management</h1>
          <p className="text-gray-600 mt-2">Monitor and analyze cashier shifts across all branches</p>
        </div>
        <div className="flex items-center space-x-3">
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
            <label className="block text-sm font-medium text-gray-700 mb-2">Shift Type</label>
            <select
              value={filters.shiftType}
              onChange={(e) => handleFilterChange('shiftType', e.target.value)}
              className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
            >
              <option value="all">All Shifts</option>
              <option value="morning">Morning</option>
              <option value="afternoon">Afternoon</option>
              <option value="evening">Evening</option>
              <option value="custom">Custom</option>
            </select>
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

      {/* Shifts Table */}
      <div className="bg-white rounded-lg border border-gray-200 overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full">
            <thead className="bg-gray-50 border-b border-gray-200">
              <tr>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Shift ID</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Branch</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Cashier</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Type</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Start</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">End</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Bills</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Gross</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Discounts</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Tax</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Net</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Cash</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Card</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Transfer</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">PayLater</th>
              </tr>
            </thead>
            <tbody className="bg-white divide-y divide-gray-200">
              {filteredShifts.map((shift) => (
                <tr 
                  key={shift.id} 
                  className="hover:bg-gray-50 cursor-pointer"
                  onClick={() => handleShiftClick(shift)}
                >
                  <td className="px-6 py-4 whitespace-nowrap text-sm font-medium text-blue-600 hover:text-blue-800">
                    #{shift.id}
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">{shift.branch}</td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">{shift.cashier}</td>
                  <td className="px-6 py-4 whitespace-nowrap">
                    <span className={`inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium ${
                      shift.shiftType === 'Morning' ? 'bg-green-100 text-green-800' :
                      shift.shiftType === 'Afternoon' ? 'bg-blue-100 text-blue-800' :
                      shift.shiftType === 'Evening' ? 'bg-purple-100 text-purple-800' :
                      'bg-gray-100 text-gray-800'
                    }`}>
                      {shift.shiftType}
                    </span>
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">{formatTime(shift.startTime)}</td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">{formatTime(shift.endTime)}</td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">{shift.billsCount}</td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">{formatCurrency(shift.grossSales)}</td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-red-600">{formatCurrency(shift.discounts)}</td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">{formatCurrency(shift.tax)}</td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm font-medium text-green-600">{formatCurrency(shift.netSales)}</td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">{formatCurrency(shift.paymentBreakdown.cash)}</td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">{formatCurrency(shift.paymentBreakdown.credit)}</td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">{formatCurrency(shift.paymentBreakdown.bank)}</td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">{formatCurrency(shift.paymentBreakdown.paylater)}</td>
                </tr>
              ))}
            </tbody>
            
            {/* Totals Row */}
            <tfoot className="bg-gray-100 border-t-2 border-gray-300">
              <tr className="font-semibold">
                <td className="px-6 py-4 text-sm text-gray-900" colSpan={6}>TOTALS ({filteredShifts.length} shifts)</td>
                <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">{totals.billsCount}</td>
                <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">{formatCurrency(totals.grossSales)}</td>
                <td className="px-6 py-4 whitespace-nowrap text-sm text-red-600">{formatCurrency(totals.discounts)}</td>
                <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">{formatCurrency(totals.tax)}</td>
                <td className="px-6 py-4 whitespace-nowrap text-sm text-green-600">{formatCurrency(totals.netSales)}</td>
                <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">{formatCurrency(totals.cash)}</td>
                <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">{formatCurrency(totals.credit)}</td>
                <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">{formatCurrency(totals.bank)}</td>
                <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">{formatCurrency(totals.paylater)}</td>
              </tr>
            </tfoot>
          </table>
        </div>
        
        {filteredShifts.length === 0 && (
          <div className="text-center py-12">
            <div className="text-gray-500 text-lg">No shifts found</div>
            <div className="text-gray-400 text-sm mt-2">
              Try adjusting your filters
            </div>
          </div>
        )}
      </div>

      {/* Shift Details Drawer */}
      {showShiftDetails && selectedShift && (
        <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-end z-50">
          <div className="bg-white h-full w-full max-w-4xl shadow-xl flex flex-col">
            <div className="flex items-center justify-between p-6 border-b border-gray-200">
              <div className="flex items-center space-x-3">
                <div className="w-12 h-12 bg-blue-100 rounded-lg flex items-center justify-center">
                  <Clock className="w-6 h-6 text-blue-600" />
                </div>
                <div>
                  <h3 className="text-xl font-semibold text-gray-900">Shift Details - #{selectedShift.id}</h3>
                  <p className="text-sm text-gray-500">{selectedShift.branch} • {selectedShift.cashier}</p>
                </div>
              </div>
              <div className="flex items-center space-x-3">
                <button
                  onClick={() => handleExportShiftReport(selectedShift)}
                  className="flex items-center space-x-2 px-4 py-2 bg-blue-500 hover:bg-blue-600 text-white rounded-lg transition-colors"
                >
                  <FileText className="w-4 h-4" />
                  <span>Export Report</span>
                </button>
                <button
                  onClick={() => setShowShiftDetails(false)}
                  className="text-gray-400 hover:text-gray-600 transition-colors"
                >
                  <X className="w-6 h-6" />
                </button>
              </div>
            </div>
            
            <div className="flex-1 overflow-y-auto p-6">
              {/* Shift Summary */}
              <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6 mb-8">
                <div className="bg-green-50 border border-green-200 rounded-lg p-4">
                  <div className="flex items-center justify-between">
                    <div>
                      <p className="text-sm text-green-600">Gross Sales</p>
                      <p className="text-2xl font-bold text-green-900">{formatCurrency(selectedShift.grossSales)}</p>
                    </div>
                    <TrendingUp className="w-8 h-8 text-green-600" />
                  </div>
                </div>

                <div className="bg-blue-50 border border-blue-200 rounded-lg p-4">
                  <div className="flex items-center justify-between">
                    <div>
                      <p className="text-sm text-blue-600">Bills Processed</p>
                      <p className="text-2xl font-bold text-blue-900">{selectedShift.billsCount}</p>
                    </div>
                    <FileText className="w-8 h-8 text-blue-600" />
                  </div>
                </div>

                <div className="bg-red-50 border border-red-200 rounded-lg p-4">
                  <div className="flex items-center justify-between">
                    <div>
                      <p className="text-sm text-red-600">Discounts</p>
                      <p className="text-2xl font-bold text-red-900">{formatCurrency(selectedShift.discounts)}</p>
                    </div>
                    <Percent className="w-8 h-8 text-red-600" />
                  </div>
                </div>

                <div className="bg-purple-50 border border-purple-200 rounded-lg p-4">
                  <div className="flex items-center justify-between">
                    <div>
                      <p className="text-sm text-purple-600">Net Sales</p>
                      <p className="text-2xl font-bold text-purple-900">{formatCurrency(selectedShift.netSales)}</p>
                    </div>
                    <Calculator className="w-8 h-8 text-purple-600" />
                  </div>
                </div>
              </div>

              {/* Cash Reconciliation */}
              {selectedShift.cashReconciliation && (
                <div className="bg-gray-50 rounded-lg p-6 mb-8">
                  <h4 className="text-lg font-semibold text-gray-900 mb-4">Cash Reconciliation</h4>
                  <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                    <div className="text-center">
                      <p className="text-sm text-gray-600">Expected Cash</p>
                      <p className="text-xl font-bold text-gray-900">{formatCurrency(selectedShift.cashReconciliation.expected)}</p>
                    </div>
                    <div className="text-center">
                      <p className="text-sm text-gray-600">Counted Cash</p>
                      <p className="text-xl font-bold text-gray-900">{formatCurrency(selectedShift.cashReconciliation.counted)}</p>
                    </div>
                    <div className="text-center">
                      <p className="text-sm text-gray-600">Variance</p>
                      <p className={`text-xl font-bold ${
                        selectedShift.cashReconciliation.variance === 0 ? 'text-green-600' :
                        selectedShift.cashReconciliation.variance > 0 ? 'text-blue-600' : 'text-red-600'
                      }`}>
                        {selectedShift.cashReconciliation.variance > 0 ? '+' : ''}{formatCurrency(selectedShift.cashReconciliation.variance)}
                      </p>
                    </div>
                  </div>
                </div>
              )}

              {/* Timeline of Events */}
              <div className="mb-8">
                <h4 className="text-lg font-semibold text-gray-900 mb-4">Shift Timeline</h4>
                <div className="space-y-4">
                  {selectedShift.events.map((event) => (
                    <div key={event.id} className={`flex items-start space-x-3 p-4 rounded-lg border ${getEventColor(event.severity)}`}>
                      <div className="flex-shrink-0 mt-1">
                        {getEventIcon(event.type)}
                      </div>
                      <div className="flex-1 min-w-0">
                        <div className="flex items-center justify-between">
                          <p className="text-sm font-medium text-gray-900">{event.description}</p>
                          <span className="text-xs text-gray-500">{formatTime(event.timestamp)}</span>
                        </div>
                        <p className="text-xs text-gray-600 mt-1 capitalize">{event.type} • {event.severity}</p>
                      </div>
                    </div>
                  ))}
                </div>
              </div>

              {/* Payment Breakdown */}
              <div className="bg-gray-50 rounded-lg p-6">
                <h4 className="text-lg font-semibold text-gray-900 mb-4">Payment Method Breakdown</h4>
                <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
                  <div className="bg-white rounded-lg p-4 border">
                    <div className="flex items-center space-x-2 mb-2">
                      <DollarSign className="w-4 h-4 text-green-600" />
                      <span className="text-sm text-gray-700">Cash</span>
                    </div>
                    <p className="text-lg font-bold text-gray-900">{formatCurrency(selectedShift.paymentBreakdown.cash)}</p>
                  </div>
                  <div className="bg-white rounded-lg p-4 border">
                    <div className="flex items-center space-x-2 mb-2">
                      <CreditCard className="w-4 h-4 text-blue-600" />
                      <span className="text-sm text-gray-700">Credit Card</span>
                    </div>
                    <p className="text-lg font-bold text-gray-900">{formatCurrency(selectedShift.paymentBreakdown.credit)}</p>
                  </div>
                  <div className="bg-white rounded-lg p-4 border">
                    <div className="flex items-center space-x-2 mb-2">
                      <Building2 className="w-4 h-4 text-purple-600" />
                      <span className="text-sm text-gray-700">Bank Transfer</span>
                    </div>
                    <p className="text-lg font-bold text-gray-900">{formatCurrency(selectedShift.paymentBreakdown.bank)}</p>
                  </div>
                  <div className="bg-white rounded-lg p-4 border">
                    <div className="flex items-center space-x-2 mb-2">
                      <Clock className="w-4 h-4 text-orange-600" />
                      <span className="text-sm text-gray-700">PayLater</span>
                    </div>
                    <p className="text-lg font-bold text-gray-900">{formatCurrency(selectedShift.paymentBreakdown.paylater)}</p>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};