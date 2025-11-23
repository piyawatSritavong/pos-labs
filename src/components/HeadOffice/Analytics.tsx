import React, { useState, useMemo } from 'react';
import { 
  BarChart3, 
  TrendingUp, 
  Calendar, 
  Download, 
  Filter, 
  RefreshCw,
  PieChart,
  LineChart,
  Target,
  Zap,
  Clock,
  Building2,
  Package,
  DollarSign,
  Users,
  Activity,
  ArrowUp,
  ArrowDown,
  Minus
} from 'lucide-react';

interface AnalyticsData {
  branches: BranchPerformance[];
  products: ProductPerformance[];
  seasonalTrends: SeasonalData[];
  dayOfWeekData: DayOfWeekData[];
  forecast: ForecastData[];
}

interface BranchPerformance {
  branch: string;
  revenue: number;
  bills: number;
  growth: number;
  avgBillValue: number;
}

interface ProductPerformance {
  name: string;
  category: string;
  unitsSold: number;
  revenue: number;
  growth: number;
  margin: number;
}

interface SeasonalData {
  month: string;
  currentYear: number;
  previousYear: number;
  growth: number;
}

interface DayOfWeekData {
  branch: string;
  monday: number;
  tuesday: number;
  wednesday: number;
  thursday: number;
  friday: number;
  saturday: number;
  sunday: number;
}

interface ForecastData {
  date: Date;
  predicted: number;
  confidenceHigh: number;
  confidenceLow: number;
}

interface FilterState {
  dateRange: string;
  customDateStart: string;
  customDateEnd: string;
  selectedBranches: string[];
  selectedCategories: string[];
}

export const Analytics: React.FC = () => {
  const [filters, setFilters] = useState<FilterState>({
    dateRange: '30D',
    customDateStart: '',
    customDateEnd: '',
    selectedBranches: ['All'],
    selectedCategories: ['All'],
  });

  const [productView, setProductView] = useState<'units' | 'revenue'>('revenue');
  const [selectedBranch, setSelectedBranch] = useState<string | null>(null);
  const [selectedProduct, setSelectedProduct] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(false);

  // Mock data - in real app, this would come from API
  const branches = ['Downtown Branch', 'Mall Branch', 'Industrial Branch', 'Suburb Branch'];
  const categories = ['roofing', 'cement', 'steel', 'paint', 'tools', 'hardware'];

  const mockAnalyticsData: AnalyticsData = {
    branches: [
      { branch: 'Industrial Branch', revenue: 156780, bills: 245, growth: 12.5, avgBillValue: 640.12 },
      { branch: 'Downtown Branch', revenue: 145230, bills: 342, growth: 8.3, avgBillValue: 424.80 },
      { branch: 'Mall Branch', revenue: 128920, bills: 298, growth: -2.1, avgBillValue: 432.55 },
      { branch: 'Suburb Branch', revenue: 89129, bills: 362, growth: 15.7, avgBillValue: 246.27 },
    ],
    products: [
      { name: 'Steel Rebar', category: 'steel', unitsSold: 1250, revenue: 56250, growth: 18.5, margin: 0.28 },
      { name: 'Portland Cement', category: 'cement', unitsSold: 2100, revenue: 26250, growth: 12.3, margin: 0.22 },
      { name: 'Metal Roofing Sheets', category: 'roofing', unitsSold: 890, revenue: 23114, growth: -5.2, margin: 0.31 },
      { name: 'Exterior Paint', category: 'paint', unitsSold: 650, revenue: 22735, growth: 8.7, margin: 0.35 },
      { name: 'Power Drill', category: 'tools', unitsSold: 180, revenue: 16198, growth: 22.1, margin: 0.42 },
      { name: 'Clay Roof Tiles', category: 'roofing', unitsSold: 3200, revenue: 11200, growth: -8.3, margin: 0.25 },
    ],
    seasonalTrends: [
      { month: 'Jan', currentYear: 520000, previousYear: 480000, growth: 8.3 },
      { month: 'Feb', currentYear: 485000, previousYear: 465000, growth: 4.3 },
      { month: 'Mar', currentYear: 612000, previousYear: 580000, growth: 5.5 },
      { month: 'Apr', currentYear: 678000, previousYear: 620000, growth: 9.4 },
      { month: 'May', currentYear: 720000, previousYear: 685000, growth: 5.1 },
      { month: 'Jun', currentYear: 695000, previousYear: 710000, growth: -2.1 },
    ],
    dayOfWeekData: [
      { branch: 'Downtown Branch', monday: 18500, tuesday: 22300, wednesday: 25100, thursday: 23800, friday: 28900, saturday: 32100, sunday: 15200 },
      { branch: 'Mall Branch', monday: 15200, tuesday: 18900, wednesday: 21500, thursday: 24300, friday: 26800, saturday: 35600, sunday: 22100 },
      { branch: 'Industrial Branch', monday: 28900, tuesday: 31200, wednesday: 29800, thursday: 32500, friday: 30100, saturday: 18500, sunday: 12300 },
      { branch: 'Suburb Branch', monday: 12100, tuesday: 14800, wednesday: 16200, thursday: 15900, friday: 18500, saturday: 21300, sunday: 16800 },
    ],
    forecast: Array.from({ length: 30 }, (_, i) => ({
      date: new Date(Date.now() + i * 24 * 60 * 60 * 1000),
      predicted: 45000 + Math.sin(i / 7) * 8000 + Math.random() * 5000,
      confidenceHigh: 52000 + Math.sin(i / 7) * 8000 + Math.random() * 3000,
      confidenceLow: 38000 + Math.sin(i / 7) * 8000 + Math.random() * 3000,
    })),
  };

  // Filter data based on current filters
  const filteredData = useMemo(() => {
    let data = { ...mockAnalyticsData };

    // Branch filter
    if (!filters.selectedBranches.includes('All')) {
      data.branches = data.branches.filter(branch => filters.selectedBranches.includes(branch.branch));
      data.dayOfWeekData = data.dayOfWeekData.filter(item => filters.selectedBranches.includes(item.branch));
    }

    // Category filter for products
    if (!filters.selectedCategories.includes('All')) {
      data.products = data.products.filter(product => filters.selectedCategories.includes(product.category));
    }

    // Apply drill-through filters
    if (selectedBranch) {
      data.branches = data.branches.filter(branch => branch.branch === selectedBranch);
      data.dayOfWeekData = data.dayOfWeekData.filter(item => item.branch === selectedBranch);
    }

    if (selectedProduct) {
      data.products = data.products.filter(product => product.name === selectedProduct);
    }

    return data;
  }, [filters, selectedBranch, selectedProduct]);

  const handleFilterChange = (key: keyof FilterState, value: any) => {
    setFilters(prev => ({ ...prev, [key]: value }));
  };

  const handleMultiSelectChange = (key: 'selectedBranches' | 'selectedCategories', value: string) => {
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

  const handleBranchClick = (branch: string) => {
    setSelectedBranch(selectedBranch === branch ? null : branch);
  };

  const handleProductClick = (product: string) => {
    setSelectedProduct(selectedProduct === product ? null : product);
  };

  const handleRefreshData = () => {
    setIsLoading(true);
    setTimeout(() => setIsLoading(false), 2000);
  };

  const handleExportChart = (format: 'png' | 'pdf') => {
    alert(`Exporting charts as ${format.toUpperCase()}...`);
  };

  const formatCurrency = (amount: number) => `฿${amount.toLocaleString()}`;
  const formatNumber = (num: number) => num.toLocaleString();

  const getGrowthIcon = (growth: number) => {
    if (growth > 0) return <ArrowUp className="w-3 h-3 text-green-600" />;
    if (growth < 0) return <ArrowDown className="w-3 h-3 text-red-600" />;
    return <Minus className="w-3 h-3 text-gray-600" />;
  };

  const getGrowthColor = (growth: number) => {
    if (growth > 0) return 'text-green-600';
    if (growth < 0) return 'text-red-600';
    return 'text-gray-600';
  };

  const LoadingSkeleton = ({ height = 'h-64' }: { height?: string }) => (
    <div className={`${height} bg-gray-100 rounded-lg animate-pulse flex items-center justify-center`}>
      <RefreshCw className="w-8 h-8 text-gray-400 animate-spin" />
    </div>
  );

  return (
    <div className="p-6">
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-3xl font-bold text-gray-900">Analytics Dashboard</h1>
          <p className="text-gray-600 mt-2">Advanced insights and performance analytics</p>
        </div>
        <div className="flex items-center space-x-3">
          <button
            onClick={handleRefreshData}
            className="flex items-center space-x-2 px-4 py-2 bg-blue-500 hover:bg-blue-600 text-white rounded-lg transition-colors"
          >
            <RefreshCw className={`w-4 h-4 ${isLoading ? 'animate-spin' : ''}`} />
            <span>Refresh</span>
          </button>
          <button
            onClick={() => handleExportChart('png')}
            className="flex items-center space-x-2 px-4 py-2 bg-green-500 hover:bg-green-600 text-white rounded-lg transition-colors"
          >
            <Download className="w-4 h-4" />
            <span>Export PNG</span>
          </button>
          <button
            onClick={() => handleExportChart('pdf')}
            className="flex items-center space-x-2 px-4 py-2 bg-red-500 hover:bg-red-600 text-white rounded-lg transition-colors"
          >
            <Download className="w-4 h-4" />
            <span>Export PDF</span>
          </button>
        </div>
      </div>

      {/* Filters */}
      <div className="bg-white rounded-lg border border-gray-200 p-4 mb-6">
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 mb-4">
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-2">Date Range</label>
            <select
              value={filters.dateRange}
              onChange={(e) => handleFilterChange('dateRange', e.target.value)}
              className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
            >
              <option value="7D">Last 7 Days</option>
              <option value="30D">Last 30 Days</option>
              <option value="90D">Last 90 Days</option>
              <option value="1Y">Last Year</option>
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
        </div>

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
            <label className="block text-sm font-medium text-gray-700 mb-2">Categories</label>
            <div className="flex flex-wrap gap-2">
              {['All', ...categories].map(category => (
                <button
                  key={category}
                  onClick={() => handleMultiSelectChange('selectedCategories', category)}
                  className={`px-3 py-1 rounded-full text-sm font-medium transition-colors ${
                    filters.selectedCategories.includes(category)
                      ? 'bg-blue-500 text-white'
                      : 'bg-gray-100 text-gray-700 hover:bg-gray-200'
                  }`}
                >
                  {category}
                </button>
              ))}
            </div>
          </div>
        </div>

        {/* Active Drill-through Filters */}
        {(selectedBranch || selectedProduct) && (
          <div className="mt-4 pt-4 border-t border-gray-200">
            <div className="flex items-center space-x-2">
              <Filter className="w-4 h-4 text-blue-600" />
              <span className="text-sm font-medium text-gray-700">Active Filters:</span>
              {selectedBranch && (
                <span className="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-blue-100 text-blue-800">
                  Branch: {selectedBranch}
                  <button
                    onClick={() => setSelectedBranch(null)}
                    className="ml-1 text-blue-600 hover:text-blue-800"
                  >
                    ×
                  </button>
                </span>
              )}
              {selectedProduct && (
                <span className="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800">
                  Product: {selectedProduct}
                  <button
                    onClick={() => setSelectedProduct(null)}
                    className="ml-1 text-green-600 hover:text-green-800"
                  >
                    ×
                  </button>
                </span>
              )}
            </div>
          </div>
        )}
      </div>

      {/* Top Branches by Revenue */}
      <div className="bg-white rounded-lg border border-gray-200 p-6 mb-6">
        <div className="flex items-center justify-between mb-4">
          <h3 className="text-lg font-semibold text-gray-900 flex items-center space-x-2">
            <BarChart3 className="w-5 h-5 text-blue-600" />
            <span>Top Branches by Revenue</span>
          </h3>
          <div className="text-sm text-gray-500">Click bars to drill down</div>
        </div>
        
        {isLoading ? (
          <LoadingSkeleton />
        ) : (
          <div className="space-y-4">
            {filteredData.branches.map((branch, index) => (
              <div
                key={branch.branch}
                onClick={() => handleBranchClick(branch.branch)}
                className={`cursor-pointer transition-all duration-200 hover:bg-gray-50 p-3 rounded-lg ${
                  selectedBranch === branch.branch ? 'bg-blue-50 border border-blue-200' : ''
                }`}
              >
                <div className="flex items-center justify-between mb-2">
                  <div className="flex items-center space-x-3">
                    <div className="w-8 h-8 bg-blue-100 rounded-lg flex items-center justify-center">
                      <Building2 className="w-4 h-4 text-blue-600" />
                    </div>
                    <div>
                      <h4 className="font-medium text-gray-900">{branch.branch}</h4>
                      <p className="text-sm text-gray-500">{branch.bills} bills • Avg: {formatCurrency(branch.avgBillValue)}</p>
                    </div>
                  </div>
                  <div className="text-right">
                    <p className="text-lg font-bold text-gray-900">{formatCurrency(branch.revenue)}</p>
                    <div className={`flex items-center space-x-1 text-sm ${getGrowthColor(branch.growth)}`}>
                      {getGrowthIcon(branch.growth)}
                      <span>{Math.abs(branch.growth).toFixed(1)}%</span>
                    </div>
                  </div>
                </div>
                <div className="w-full bg-gray-200 rounded-full h-2">
                  <div
                    className="bg-blue-500 h-2 rounded-full transition-all duration-500"
                    style={{ width: `${(branch.revenue / Math.max(...filteredData.branches.map(b => b.revenue))) * 100}%` }}
                  />
                </div>
              </div>
            ))}
          </div>
        )}
      </div>

      {/* Top Products */}
      <div className="bg-white rounded-lg border border-gray-200 p-6 mb-6">
        <div className="flex items-center justify-between mb-4">
          <h3 className="text-lg font-semibold text-gray-900 flex items-center space-x-2">
            <Package className="w-5 h-5 text-green-600" />
            <span>Top Products by {productView === 'units' ? 'Units Sold' : 'Revenue'}</span>
          </h3>
          <div className="flex items-center space-x-3">
            <div className="flex bg-gray-100 rounded-lg p-1">
              <button
                onClick={() => setProductView('revenue')}
                className={`px-3 py-1 rounded text-sm font-medium transition-colors ${
                  productView === 'revenue' ? 'bg-white text-gray-900 shadow-sm' : 'text-gray-600'
                }`}
              >
                Revenue
              </button>
              <button
                onClick={() => setProductView('units')}
                className={`px-3 py-1 rounded text-sm font-medium transition-colors ${
                  productView === 'units' ? 'bg-white text-gray-900 shadow-sm' : 'text-gray-600'
                }`}
              >
                Units
              </button>
            </div>
            <div className="text-sm text-gray-500">Click products to drill down</div>
          </div>
        </div>
        
        {isLoading ? (
          <LoadingSkeleton />
        ) : (
          <div className="space-y-4">
            {filteredData.products
              .sort((a, b) => productView === 'units' ? b.unitsSold - a.unitsSold : b.revenue - a.revenue)
              .slice(0, 6)
              .map((product) => (
                <div
                  key={product.name}
                  onClick={() => handleProductClick(product.name)}
                  className={`cursor-pointer transition-all duration-200 hover:bg-gray-50 p-3 rounded-lg ${
                    selectedProduct === product.name ? 'bg-green-50 border border-green-200' : ''
                  }`}
                >
                  <div className="flex items-center justify-between mb-2">
                    <div className="flex items-center space-x-3">
                      <div className="w-8 h-8 bg-green-100 rounded-lg flex items-center justify-center">
                        <Package className="w-4 h-4 text-green-600" />
                      </div>
                      <div>
                        <h4 className="font-medium text-gray-900">{product.name}</h4>
                        <p className="text-sm text-gray-500">{product.category} • {product.margin * 100}% margin</p>
                      </div>
                    </div>
                    <div className="text-right">
                      <p className="text-lg font-bold text-gray-900">
                        {productView === 'units' ? formatNumber(product.unitsSold) : formatCurrency(product.revenue)}
                      </p>
                      <div className={`flex items-center space-x-1 text-sm ${getGrowthColor(product.growth)}`}>
                        {getGrowthIcon(product.growth)}
                        <span>{Math.abs(product.growth).toFixed(1)}%</span>
                      </div>
                    </div>
                  </div>
                  <div className="w-full bg-gray-200 rounded-full h-2">
                    <div
                      className="bg-green-500 h-2 rounded-full transition-all duration-500"
                      style={{ 
                        width: `${productView === 'units' 
                          ? (product.unitsSold / Math.max(...filteredData.products.map(p => p.unitsSold))) * 100
                          : (product.revenue / Math.max(...filteredData.products.map(p => p.revenue))) * 100
                        }%` 
                      }}
                    />
                  </div>
                </div>
              ))}
          </div>
        )}
      </div>

      {/* Seasonal Trends */}
      <div className="bg-white rounded-lg border border-gray-200 p-6 mb-6">
        <div className="flex items-center justify-between mb-4">
          <h3 className="text-lg font-semibold text-gray-900 flex items-center space-x-2">
            <LineChart className="w-5 h-5 text-purple-600" />
            <span>Seasonal Trends (Year-over-Year)</span>
          </h3>
        </div>
        
        {isLoading ? (
          <LoadingSkeleton />
        ) : (
          <div className="space-y-4">
            {filteredData.seasonalTrends.map((trend) => (
              <div key={trend.month} className="flex items-center justify-between p-3 bg-gray-50 rounded-lg">
                <div className="flex items-center space-x-4">
                  <div className="w-12 h-12 bg-purple-100 rounded-lg flex items-center justify-center">
                    <Calendar className="w-6 h-6 text-purple-600" />
                  </div>
                  <div>
                    <h4 className="font-medium text-gray-900">{trend.month} 2024</h4>
                    <p className="text-sm text-gray-500">vs {trend.month} 2023</p>
                  </div>
                </div>
                <div className="flex items-center space-x-6">
                  <div className="text-right">
                    <p className="text-sm text-gray-500">Current Year</p>
                    <p className="font-bold text-gray-900">{formatCurrency(trend.currentYear)}</p>
                  </div>
                  <div className="text-right">
                    <p className="text-sm text-gray-500">Previous Year</p>
                    <p className="font-medium text-gray-700">{formatCurrency(trend.previousYear)}</p>
                  </div>
                  <div className={`flex items-center space-x-1 ${getGrowthColor(trend.growth)}`}>
                    {getGrowthIcon(trend.growth)}
                    <span className="font-medium">{Math.abs(trend.growth).toFixed(1)}%</span>
                  </div>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>

      {/* Day of Week Performance */}
      <div className="bg-white rounded-lg border border-gray-200 p-6 mb-6">
        <div className="flex items-center justify-between mb-4">
          <h3 className="text-lg font-semibold text-gray-900 flex items-center space-x-2">
            <Activity className="w-5 h-5 text-orange-600" />
            <span>Day-of-Week Performance by Branch</span>
          </h3>
        </div>
        
        {isLoading ? (
          <LoadingSkeleton />
        ) : (
          <div className="space-y-6">
            {filteredData.dayOfWeekData.map((branchData) => (
              <div key={branchData.branch} className="border border-gray-200 rounded-lg p-4">
                <h4 className="font-medium text-gray-900 mb-4">{branchData.branch}</h4>
                <div className="grid grid-cols-7 gap-2">
                  {['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'].map((day, index) => {
                    const dayKey = day.toLowerCase() as keyof Omit<DayOfWeekData, 'branch'>;
                    const value = branchData[dayKey];
                    const maxValue = Math.max(
                      branchData.monday, branchData.tuesday, branchData.wednesday,
                      branchData.thursday, branchData.friday, branchData.saturday, branchData.sunday
                    );
                    
                    return (
                      <div key={day} className="text-center">
                        <div className="text-xs text-gray-500 mb-1">{day.slice(0, 3)}</div>
                        <div className="h-20 bg-gray-100 rounded flex items-end justify-center p-1">
                          <div
                            className="bg-orange-500 rounded w-full transition-all duration-500"
                            style={{ height: `${(value / maxValue) * 100}%`, minHeight: '4px' }}
                          />
                        </div>
                        <div className="text-xs font-medium text-gray-900 mt-1">
                          {formatCurrency(value)}
                        </div>
                      </div>
                    );
                  })}
                </div>
              </div>
            ))}
          </div>
        )}
      </div>

      {/* Revenue Forecast */}
      <div className="bg-white rounded-lg border border-gray-200 p-6">
        <div className="flex items-center justify-between mb-4">
          <h3 className="text-lg font-semibold text-gray-900 flex items-center space-x-2">
            <Target className="w-5 h-5 text-indigo-600" />
            <span>30-Day Revenue Forecast</span>
          </h3>
          <div className="flex items-center space-x-2 text-sm text-gray-500">
            <div className="w-3 h-3 bg-indigo-500 rounded"></div>
            <span>Predicted</span>
            <div className="w-3 h-3 bg-indigo-200 rounded"></div>
            <span>Confidence Band</span>
          </div>
        </div>
        
        {isLoading ? (
          <LoadingSkeleton height="h-80" />
        ) : (
          <div className="h-80 flex items-center justify-center bg-gray-50 rounded-lg">
            <div className="text-center">
              <TrendingUp className="w-16 h-16 text-indigo-400 mx-auto mb-4" />
              <p className="text-lg font-medium text-gray-700">Revenue Forecast Chart</p>
              <p className="text-sm text-gray-500 mt-2">
                Interactive forecast visualization with confidence intervals
              </p>
              <div className="mt-4 grid grid-cols-3 gap-4 text-center">
                <div>
                  <p className="text-sm text-gray-500">Avg. Daily Forecast</p>
                  <p className="text-lg font-bold text-indigo-600">
                    {formatCurrency(filteredData.forecast.reduce((sum, f) => sum + f.predicted, 0) / filteredData.forecast.length)}
                  </p>
                </div>
                <div>
                  <p className="text-sm text-gray-500">30-Day Total</p>
                  <p className="text-lg font-bold text-gray-900">
                    {formatCurrency(filteredData.forecast.reduce((sum, f) => sum + f.predicted, 0))}
                  </p>
                </div>
                <div>
                  <p className="text-sm text-gray-500">Confidence</p>
                  <p className="text-lg font-bold text-green-600">85%</p>
                </div>
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
  );
};