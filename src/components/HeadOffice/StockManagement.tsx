import React, { useState, useMemo } from 'react';
import { 
  Package, 
  AlertTriangle, 
  Search, 
  Filter, 
  Download, 
  Plus, 
  ArrowRightLeft, 
  History, 
  Eye, 
  Edit, 
  Truck, 
  CheckCircle, 
  Clock, 
  X,
  Building2,
  Calendar,
  FileText,
  Send
} from 'lucide-react';

interface StockItem {
  id: string;
  productName: string;
  sku: string;
  category: string;
  branch: string;
  onHandQty: number;
  unitType: string;
  reorderPoint: number;
  lastUpdated: Date;
  supplier: string;
  costPrice: number;
  isLowStock: boolean;
}

interface TransferRequest {
  id: string;
  productName: string;
  fromBranch: string;
  toBranch: string;
  quantity: number;
  unitType: string;
  status: 'pending' | 'approved' | 'shipped' | 'received';
  requestDate: Date;
  requestedBy: string;
  notes?: string;
}

interface StockHistory {
  id: string;
  productName: string;
  branch: string;
  action: 'adjustment' | 'restock' | 'transfer' | 'sale';
  quantityChange: number;
  previousQty: number;
  newQty: number;
  timestamp: Date;
  reason: string;
  performedBy: string;
}

interface FilterState {
  selectedBranches: string[];
  category: string;
  lowStockOnly: boolean;
  unitType: string;
  supplier: string;
  searchQuery: string;
}

export const StockManagement: React.FC = () => {
  const [activeTab, setActiveTab] = useState<'inventory' | 'transfers' | 'history'>('inventory');
  const [filters, setFilters] = useState<FilterState>({
    selectedBranches: ['All'],
    category: 'all',
    lowStockOnly: false,
    unitType: 'all',
    supplier: 'all',
    searchQuery: '',
  });
  
  const [selectedItems, setSelectedItems] = useState<string[]>([]);
  const [showRestockModal, setShowRestockModal] = useState(false);
  const [showTransferModal, setShowTransferModal] = useState(false);
  const [selectedProduct, setSelectedProduct] = useState<StockItem | null>(null);

  // Mock data
  const branches = ['Downtown Branch', 'Mall Branch', 'Industrial Branch', 'Suburb Branch'];
  const categories = ['roofing', 'cement', 'steel', 'paint', 'tools', 'hardware'];
  const unitTypes = ['piece', 'pack', 'box', 'dozen', 'roll', 'bag', 'gallon'];
  const suppliers = ['BuildCorp Ltd', 'Steel Masters', 'Paint Pro', 'Tool World', 'Hardware Plus'];

  const mockStockData: StockItem[] = [
    {
      id: 'STK001',
      productName: 'Metal Roofing Sheets',
      sku: 'MRS-001',
      category: 'roofing',
      branch: 'Downtown Branch',
      onHandQty: 45,
      unitType: 'piece',
      reorderPoint: 20,
      lastUpdated: new Date('2024-01-15T10:30:00'),
      supplier: 'BuildCorp Ltd',
      costPrice: 20.50,
      isLowStock: false,
    },
    {
      id: 'STK002',
      productName: 'Clay Roof Tiles',
      sku: 'CRT-002',
      category: 'roofing',
      branch: 'Downtown Branch',
      onHandQty: 8,
      unitType: 'piece',
      reorderPoint: 15,
      lastUpdated: new Date('2024-01-14T14:20:00'),
      supplier: 'BuildCorp Ltd',
      costPrice: 2.80,
      isLowStock: true,
    },
    {
      id: 'STK003',
      productName: 'Portland Cement',
      sku: 'PC-003',
      category: 'cement',
      branch: 'Mall Branch',
      onHandQty: 120,
      unitType: 'bag',
      reorderPoint: 50,
      lastUpdated: new Date('2024-01-15T11:45:00'),
      supplier: 'BuildCorp Ltd',
      costPrice: 10.00,
      isLowStock: false,
    },
    {
      id: 'STK004',
      productName: 'Steel Rebar',
      sku: 'SR-004',
      category: 'steel',
      branch: 'Industrial Branch',
      onHandQty: 25,
      unitType: 'piece',
      reorderPoint: 30,
      lastUpdated: new Date('2024-01-15T12:00:00'),
      supplier: 'Steel Masters',
      costPrice: 35.00,
      isLowStock: true,
    },
    {
      id: 'STK005',
      productName: 'Exterior Paint',
      sku: 'EP-005',
      category: 'paint',
      branch: 'Suburb Branch',
      onHandQty: 12,
      unitType: 'gallon',
      reorderPoint: 20,
      lastUpdated: new Date('2024-01-13T16:00:00'),
      supplier: 'Paint Pro',
      costPrice: 28.00,
      isLowStock: true,
    },
    {
      id: 'STK006',
      productName: 'Power Drill',
      sku: 'PD-006',
      category: 'tools',
      branch: 'Mall Branch',
      onHandQty: 18,
      unitType: 'piece',
      reorderPoint: 10,
      lastUpdated: new Date('2024-01-15T11:00:00'),
      supplier: 'Tool World',
      costPrice: 72.00,
      isLowStock: false,
    },
    {
      id: 'STK007',
      productName: 'Hex Bolts',
      sku: 'HB-007',
      category: 'hardware',
      branch: 'Downtown Branch',
      onHandQty: 450,
      unitType: 'piece',
      reorderPoint: 200,
      lastUpdated: new Date('2024-01-15T12:30:00'),
      supplier: 'Hardware Plus',
      costPrice: 0.35,
      isLowStock: false,
    },
    {
      id: 'STK008',
      productName: 'Wood Screws',
      sku: 'WS-008',
      category: 'hardware',
      branch: 'Suburb Branch',
      onHandQty: 85,
      unitType: 'piece',
      reorderPoint: 150,
      lastUpdated: new Date('2024-01-13T15:15:00'),
      supplier: 'Hardware Plus',
      costPrice: 0.20,
      isLowStock: true,
    },
  ];

  const mockTransfers: TransferRequest[] = [
    {
      id: 'TR001',
      productName: 'Metal Roofing Sheets',
      fromBranch: 'Downtown Branch',
      toBranch: 'Mall Branch',
      quantity: 20,
      unitType: 'piece',
      status: 'pending',
      requestDate: new Date('2024-01-15T09:00:00'),
      requestedBy: 'Mall Manager',
      notes: 'Urgent restock needed for weekend sales',
    },
    {
      id: 'TR002',
      productName: 'Portland Cement',
      fromBranch: 'Industrial Branch',
      toBranch: 'Suburb Branch',
      quantity: 50,
      unitType: 'bag',
      status: 'approved',
      requestDate: new Date('2024-01-14T14:30:00'),
      requestedBy: 'Suburb Manager',
    },
    {
      id: 'TR003',
      productName: 'Steel Rebar',
      fromBranch: 'Downtown Branch',
      toBranch: 'Industrial Branch',
      quantity: 15,
      unitType: 'piece',
      status: 'shipped',
      requestDate: new Date('2024-01-13T11:20:00'),
      requestedBy: 'Industrial Manager',
    },
  ];

  const mockHistory: StockHistory[] = [
    {
      id: 'SH001',
      productName: 'Clay Roof Tiles',
      branch: 'Downtown Branch',
      action: 'adjustment',
      quantityChange: -5,
      previousQty: 13,
      newQty: 8,
      timestamp: new Date('2024-01-14T14:20:00'),
      reason: 'Damaged items removed',
      performedBy: 'John Smith',
    },
    {
      id: 'SH002',
      productName: 'Portland Cement',
      branch: 'Mall Branch',
      action: 'restock',
      quantityChange: 100,
      previousQty: 20,
      newQty: 120,
      timestamp: new Date('2024-01-15T11:45:00'),
      reason: 'Weekly delivery',
      performedBy: 'System Auto',
    },
  ];

  // Filter data
  const filteredStockData = useMemo(() => {
    let filtered = mockStockData;

    // Branch filter
    if (!filters.selectedBranches.includes('All')) {
      filtered = filtered.filter(item => filters.selectedBranches.includes(item.branch));
    }

    // Category filter
    if (filters.category !== 'all') {
      filtered = filtered.filter(item => item.category === filters.category);
    }

    // Low stock filter
    if (filters.lowStockOnly) {
      filtered = filtered.filter(item => item.isLowStock);
    }

    // Unit type filter
    if (filters.unitType !== 'all') {
      filtered = filtered.filter(item => item.unitType === filters.unitType);
    }

    // Supplier filter
    if (filters.supplier !== 'all') {
      filtered = filtered.filter(item => item.supplier === filters.supplier);
    }

    // Search filter
    if (filters.searchQuery) {
      filtered = filtered.filter(item =>
        item.productName.toLowerCase().includes(filters.searchQuery.toLowerCase()) ||
        item.sku.toLowerCase().includes(filters.searchQuery.toLowerCase())
      );
    }

    return filtered;
  }, [filters]);

  const lowStockItems = mockStockData.filter(item => item.isLowStock);

  const handleFilterChange = (key: keyof FilterState, value: any) => {
    setFilters(prev => ({ ...prev, [key]: value }));
  };

  const handleBranchSelect = (branch: string) => {
    if (branch === 'All') {
      setFilters(prev => ({ ...prev, selectedBranches: ['All'] }));
    } else {
      setFilters(prev => {
        const filtered = prev.selectedBranches.filter(b => b !== 'All');
        if (filtered.includes(branch)) {
          const newSelection = filtered.filter(b => b !== branch);
          return { ...prev, selectedBranches: newSelection.length === 0 ? ['All'] : newSelection };
        } else {
          return { ...prev, selectedBranches: [...filtered, branch] };
        }
      });
    }
  };

  const handleSelectItem = (itemId: string) => {
    setSelectedItems(prev => 
      prev.includes(itemId) 
        ? prev.filter(id => id !== itemId)
        : [...prev, itemId]
    );
  };

  const handleSelectAll = () => {
    if (selectedItems.length === filteredStockData.length) {
      setSelectedItems([]);
    } else {
      setSelectedItems(filteredStockData.map(item => item.id));
    }
  };

  const handleBulkRestock = () => {
    alert(`Creating restock requests for ${selectedItems.length} items...`);
    setSelectedItems([]);
  };

  const handleExport = (format: 'csv' | 'pdf') => {
    alert(`Exporting inventory as ${format.toUpperCase()}...`);
  };

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'pending': return 'bg-yellow-100 text-yellow-800';
      case 'approved': return 'bg-blue-100 text-blue-800';
      case 'shipped': return 'bg-purple-100 text-purple-800';
      case 'received': return 'bg-green-100 text-green-800';
      default: return 'bg-gray-100 text-gray-800';
    }
  };

  const getStatusIcon = (status: string) => {
    switch (status) {
      case 'pending': return <Clock className="w-3 h-3" />;
      case 'approved': return <CheckCircle className="w-3 h-3" />;
      case 'shipped': return <Truck className="w-3 h-3" />;
      case 'received': return <Package className="w-3 h-3" />;
      default: return <Clock className="w-3 h-3" />;
    }
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
    <div className="p-6">
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-3xl font-bold text-gray-900">Stock Management</h1>
          <p className="text-gray-600 mt-2">Consolidated inventory across all branches</p>
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
          <button
            onClick={() => setShowRestockModal(true)}
            className="flex items-center space-x-2 px-4 py-2 bg-blue-500 hover:bg-blue-600 text-white rounded-lg transition-colors"
          >
            <Plus className="w-4 h-4" />
            <span>Create Restock</span>
          </button>
        </div>
      </div>

      {/* Sticky Filter Bar */}
      <div className="sticky top-0 z-10 bg-white rounded-lg border border-gray-200 p-4 mb-6 shadow-sm">
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 mb-4">
          <div className="relative">
            <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 text-gray-400 w-4 h-4" />
            <input
              type="text"
              placeholder="Search products or SKU..."
              value={filters.searchQuery}
              onChange={(e) => handleFilterChange('searchQuery', e.target.value)}
              className="pl-10 pr-4 py-2 w-full border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
            />
          </div>

          <select
            value={filters.category}
            onChange={(e) => handleFilterChange('category', e.target.value)}
            className="px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
          >
            <option value="all">All Categories</option>
            {categories.map(category => (
              <option key={category} value={category}>{category}</option>
            ))}
          </select>

          <select
            value={filters.unitType}
            onChange={(e) => handleFilterChange('unitType', e.target.value)}
            className="px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
          >
            <option value="all">All Unit Types</option>
            {unitTypes.map(unit => (
              <option key={unit} value={unit}>{unit}</option>
            ))}
          </select>

          <select
            value={filters.supplier}
            onChange={(e) => handleFilterChange('supplier', e.target.value)}
            className="px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
          >
            <option value="all">All Suppliers</option>
            {suppliers.map(supplier => (
              <option key={supplier} value={supplier}>{supplier}</option>
            ))}
          </select>
        </div>

        <div className="flex items-center justify-between">
          <div>
            <label className="flex items-center space-x-2">
              <input
                type="checkbox"
                checked={filters.lowStockOnly}
                onChange={(e) => handleFilterChange('lowStockOnly', e.target.checked)}
                className="rounded border-gray-300 text-blue-600 focus:ring-blue-500"
              />
              <span className="text-sm text-gray-700">Show Low Stock Only</span>
            </label>
          </div>

          <div className="flex flex-wrap gap-2">
            {['All', ...branches].map(branch => (
              <button
                key={branch}
                onClick={() => handleBranchSelect(branch)}
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
      </div>

      {/* Low Stock Alert Panel */}
      {lowStockItems.length > 0 && (
        <div className="bg-orange-50 border border-orange-200 rounded-lg p-6 mb-6">
          <div className="flex items-center justify-between mb-4">
            <div className="flex items-center space-x-2">
              <AlertTriangle className="w-5 h-5 text-orange-600" />
              <h3 className="text-lg font-semibold text-orange-800">Low Stock Alert</h3>
              <span className="bg-orange-200 text-orange-800 px-2 py-1 rounded-full text-sm font-medium">
                {lowStockItems.length} items
              </span>
            </div>
            <button
              onClick={() => setShowRestockModal(true)}
              className="flex items-center space-x-2 px-4 py-2 bg-orange-500 hover:bg-orange-600 text-white rounded-lg transition-colors"
            >
              <Plus className="w-4 h-4" />
              <span>Bulk Restock</span>
            </button>
          </div>
          
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {lowStockItems.slice(0, 6).map((item) => (
              <div key={item.id} className="bg-white border border-orange-200 rounded-lg p-4">
                <div className="flex items-start justify-between mb-2">
                  <div>
                    <h4 className="font-medium text-gray-900">{item.productName}</h4>
                    <p className="text-sm text-gray-500">{item.branch} • {item.category}</p>
                  </div>
                  <AlertTriangle className="w-4 h-4 text-orange-500 flex-shrink-0" />
                </div>
                <div className="flex items-center justify-between">
                  <div>
                    <span className="text-sm text-gray-600">Stock: </span>
                    <span className="font-medium text-orange-600">{item.onHandQty} {item.unitType}</span>
                  </div>
                  <div>
                    <span className="text-sm text-gray-600">Min: </span>
                    <span className="font-medium text-gray-900">{item.reorderPoint}</span>
                  </div>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Tab Navigation */}
      <div className="bg-white rounded-lg border border-gray-200 overflow-hidden mb-6">
        <div className="border-b border-gray-200">
          <nav className="flex space-x-8 px-6">
            <button
              onClick={() => setActiveTab('inventory')}
              className={`py-4 px-1 border-b-2 font-medium text-sm ${
                activeTab === 'inventory'
                  ? 'border-blue-500 text-blue-600'
                  : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'
              }`}
            >
              Inventory
            </button>
            <button
              onClick={() => setActiveTab('transfers')}
              className={`py-4 px-1 border-b-2 font-medium text-sm ${
                activeTab === 'transfers'
                  ? 'border-blue-500 text-blue-600'
                  : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'
              }`}
            >
              Transfer Requests
            </button>
            <button
              onClick={() => setActiveTab('history')}
              className={`py-4 px-1 border-b-2 font-medium text-sm ${
                activeTab === 'history'
                  ? 'border-blue-500 text-blue-600'
                  : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'
              }`}
            >
              History
            </button>
          </nav>
        </div>

        {/* Inventory Table */}
        {activeTab === 'inventory' && (
          <>
            {/* Bulk Actions Bar */}
            {selectedItems.length > 0 && (
              <div className="bg-blue-50 border-b border-blue-200 px-6 py-3">
                <div className="flex items-center justify-between">
                  <span className="text-sm text-blue-700">
                    {selectedItems.length} item{selectedItems.length !== 1 ? 's' : ''} selected
                  </span>
                  <div className="flex items-center space-x-2">
                    <button
                      onClick={handleBulkRestock}
                      className="px-3 py-1 bg-blue-500 hover:bg-blue-600 text-white text-sm rounded transition-colors"
                    >
                      Bulk Restock
                    </button>
                    <button
                      onClick={() => setSelectedItems([])}
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
                        checked={selectedItems.length === filteredStockData.length && filteredStockData.length > 0}
                        onChange={handleSelectAll}
                        className="rounded border-gray-300 text-blue-600 focus:ring-blue-500"
                      />
                    </th>
                    <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Product</th>
                    <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">SKU</th>
                    <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Category</th>
                    <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Branch</th>
                    <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Stock</th>
                    <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Unit</th>
                    <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Reorder Point</th>
                    <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Last Updated</th>
                    <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Actions</th>
                  </tr>
                </thead>
                <tbody className="bg-white divide-y divide-gray-200">
                  {filteredStockData.map((item) => (
                    <tr key={item.id} className="hover:bg-gray-50">
                      <td className="px-6 py-4 whitespace-nowrap">
                        <input
                          type="checkbox"
                          checked={selectedItems.includes(item.id)}
                          onChange={() => handleSelectItem(item.id)}
                          className="rounded border-gray-300 text-blue-600 focus:ring-blue-500"
                        />
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap">
                        <div className="flex items-center space-x-3">
                          <div className="w-8 h-8 bg-blue-100 rounded-lg flex items-center justify-center">
                            <Package className="w-4 h-4 text-blue-600" />
                          </div>
                          <div>
                            <div className="text-sm font-medium text-gray-900">{item.productName}</div>
                            <div className="text-sm text-gray-500">{item.supplier}</div>
                          </div>
                        </div>
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">{item.sku}</td>
                      <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">{item.category}</td>
                      <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">{item.branch}</td>
                      <td className="px-6 py-4 whitespace-nowrap">
                        <div className="flex items-center space-x-2">
                          <span className={`text-sm font-medium ${item.isLowStock ? 'text-red-600' : 'text-gray-900'}`}>
                            {item.onHandQty}
                          </span>
                          {item.isLowStock && (
                            <AlertTriangle className="w-4 h-4 text-red-500" />
                          )}
                        </div>
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">{item.unitType}</td>
                      <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">{item.reorderPoint}</td>
                      <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">{formatTime(item.lastUpdated)}</td>
                      <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                        <div className="flex items-center space-x-2">
                          <button
                            onClick={() => {
                              setSelectedProduct(item);
                              setShowRestockModal(true);
                            }}
                            className="text-blue-600 hover:text-blue-800 transition-colors"
                            title="Create Restock Request"
                          >
                            <Plus className="w-4 h-4" />
                          </button>
                          <button
                            onClick={() => alert(`Viewing details for ${item.productName}`)}
                            className="text-green-600 hover:text-green-800 transition-colors"
                            title="View Details"
                          >
                            <Eye className="w-4 h-4" />
                          </button>
                          <button
                            onClick={() => alert(`Editing ${item.productName}`)}
                            className="text-gray-600 hover:text-gray-800 transition-colors"
                            title="Edit Item"
                          >
                            <Edit className="w-4 h-4" />
                          </button>
                        </div>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </>
        )}

        {/* Transfer Requests Table */}
        {activeTab === 'transfers' && (
          <div className="overflow-x-auto">
            <table className="w-full">
              <thead className="bg-gray-50 border-b border-gray-200">
                <tr>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Request ID</th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Product</th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">From Branch</th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">To Branch</th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Quantity</th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Status</th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Request Date</th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Actions</th>
                </tr>
              </thead>
              <tbody className="bg-white divide-y divide-gray-200">
                {mockTransfers.map((transfer) => (
                  <tr key={transfer.id} className="hover:bg-gray-50">
                    <td className="px-6 py-4 whitespace-nowrap text-sm font-medium text-blue-600">
                      #{transfer.id}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">{transfer.productName}</td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">{transfer.fromBranch}</td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">{transfer.toBranch}</td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                      {transfer.quantity} {transfer.unitType}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap">
                      <span className={`inline-flex items-center space-x-1 px-2.5 py-0.5 rounded-full text-xs font-medium ${getStatusColor(transfer.status)}`}>
                        {getStatusIcon(transfer.status)}
                        <span className="capitalize">{transfer.status}</span>
                      </span>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                      {transfer.requestDate.toLocaleDateString()}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                      <div className="flex items-center space-x-2">
                        <button
                          onClick={() => alert(`Viewing transfer ${transfer.id}`)}
                          className="text-blue-600 hover:text-blue-800 transition-colors"
                          title="View Details"
                        >
                          <Eye className="w-4 h-4" />
                        </button>
                        {transfer.status === 'pending' && (
                          <button
                            onClick={() => alert(`Approving transfer ${transfer.id}`)}
                            className="text-green-600 hover:text-green-800 transition-colors"
                            title="Approve Transfer"
                          >
                            <CheckCircle className="w-4 h-4" />
                          </button>
                        )}
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}

        {/* History Table */}
        {activeTab === 'history' && (
          <div className="overflow-x-auto">
            <table className="w-full">
              <thead className="bg-gray-50 border-b border-gray-200">
                <tr>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Product</th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Branch</th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Action</th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Change</th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Previous</th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">New</th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Reason</th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Performed By</th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Date</th>
                </tr>
              </thead>
              <tbody className="bg-white divide-y divide-gray-200">
                {mockHistory.map((entry) => (
                  <tr key={entry.id} className="hover:bg-gray-50">
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">{entry.productName}</td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">{entry.branch}</td>
                    <td className="px-6 py-4 whitespace-nowrap">
                      <span className={`inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium ${
                        entry.action === 'adjustment' ? 'bg-orange-100 text-orange-800' :
                        entry.action === 'restock' ? 'bg-green-100 text-green-800' :
                        entry.action === 'transfer' ? 'bg-blue-100 text-blue-800' :
                        'bg-red-100 text-red-800'
                      }`}>
                        {entry.action}
                      </span>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm font-medium">
                      <span className={entry.quantityChange > 0 ? 'text-green-600' : 'text-red-600'}>
                        {entry.quantityChange > 0 ? '+' : ''}{entry.quantityChange}
                      </span>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">{entry.previousQty}</td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">{entry.newQty}</td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">{entry.reason}</td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">{entry.performedBy}</td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">{formatTime(entry.timestamp)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}

        {filteredStockData.length === 0 && activeTab === 'inventory' && (
          <div className="text-center py-12">
            <div className="text-gray-500 text-lg">No inventory found</div>
            <div className="text-gray-400 text-sm mt-2">
              Try adjusting your filters
            </div>
          </div>
        )}
      </div>

      {/* Restock Request Modal */}
      {showRestockModal && (
        <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
          <div className="bg-white rounded-lg shadow-xl max-w-md w-full mx-4">
            <div className="flex items-center justify-between p-6 border-b border-gray-200">
              <h3 className="text-lg font-semibold text-gray-900">Create Restock Request</h3>
              <button
                onClick={() => {
                  setShowRestockModal(false);
                  setSelectedProduct(null);
                }}
                className="text-gray-400 hover:text-gray-600 transition-colors"
              >
                <X className="w-5 h-5" />
              </button>
            </div>
            
            <div className="p-6">
              <div className="space-y-4">
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">Product</label>
                  <input
                    type="text"
                    value={selectedProduct?.productName || ''}
                    readOnly
                    className="w-full px-3 py-2 border border-gray-300 rounded-lg bg-gray-50"
                  />
                </div>
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">Target Branch</label>
                  <select className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent">
                    {branches.map(branch => (
                      <option key={branch} value={branch}>{branch}</option>
                    ))}
                  </select>
                </div>
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">Quantity</label>
                  <input
                    type="number"
                    placeholder="Enter quantity"
                    className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                  />
                </div>
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">Requested Date</label>
                  <input
                    type="date"
                    className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                  />
                </div>
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">Notes</label>
                  <textarea
                    rows={3}
                    placeholder="Additional notes..."
                    className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                  />
                </div>
              </div>
            </div>
            
            <div className="flex items-center justify-end space-x-3 p-6 border-t border-gray-200">
              <button
                onClick={() => {
                  setShowRestockModal(false);
                  setSelectedProduct(null);
                }}
                className="px-4 py-2 text-sm font-medium text-gray-700 bg-gray-100 hover:bg-gray-200 rounded-lg transition-colors"
              >
                Cancel
              </button>
              <button
                onClick={() => {
                  alert('Restock request created successfully!');
                  setShowRestockModal(false);
                  setSelectedProduct(null);
                }}
                className="px-4 py-2 text-sm font-medium text-white bg-blue-500 hover:bg-blue-600 rounded-lg transition-colors"
              >
                Create Request
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};