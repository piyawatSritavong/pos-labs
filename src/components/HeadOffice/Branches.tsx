import React, { useState } from 'react';
import { Building2, Wifi, WifiOff, Settings, MessageSquare, FileText, Search, Plus, Eye, AlertTriangle, Clock, Lock, RefreshCw, Bell, X, Phone, MapPin, Calendar, Activity, AlertCircle } from 'lucide-react';

interface Branch {
  id: string;
  name: string;
  code: string;
  manager: string;
  contact: string;
  address: string;
  status: 'online' | 'offline' | 'degraded';
  lastSync: Date;
  dailySales: number;
  activeCashiers: number;
  openHours: string;
  taxOverride?: number;
  queueLength: number;
  errorLogs: ErrorLog[];
}

interface ErrorLog {
  id: string;
  timestamp: Date;
  level: 'error' | 'warning' | 'info';
  message: string;
  details?: string;
}

export const Branches: React.FC = () => {
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedBranch, setSelectedBranch] = useState<Branch | null>(null);
  const [showAddModal, setShowAddModal] = useState(false);
  const [showDetailsDrawer, setShowDetailsDrawer] = useState(false);
  
  const branches: Branch[] = [
    {
      id: 'BR001',
      name: 'Downtown Branch',
      code: 'DT001',
      manager: 'Sarah Johnson',
      contact: '+66 2 123 4567',
      address: '123 Main Street, Silom, Bangkok 10500',
      status: 'online',
      lastSync: new Date(Date.now() - 5 * 60 * 1000), // 5 minutes ago
      dailySales: 45230.50,
      activeCashiers: 3,
      openHours: '08:00 - 20:00',
      queueLength: 2,
      errorLogs: [
        {
          id: 'err1',
          timestamp: new Date(Date.now() - 30 * 60 * 1000),
          level: 'warning',
          message: 'Low stock alert for Clay Roof Tiles',
          details: 'Current stock: 8, Threshold: 10'
        },
        {
          id: 'err2',
          timestamp: new Date(Date.now() - 2 * 60 * 60 * 1000),
          level: 'info',
          message: 'Shift change completed',
          details: 'Morning shift closed by John Smith'
        }
      ]
    },
    {
      id: 'BR002',
      name: 'Mall Branch',
      code: 'ML001',
      manager: 'Mike Chen',
      contact: '+66 2 234 5678',
      address: 'Central Plaza, Level 2, Unit 201, Bangkok 10330',
      status: 'online',
      lastSync: new Date(Date.now() - 2 * 60 * 1000), // 2 minutes ago
      dailySales: 38920.75,
      activeCashiers: 2,
      openHours: '10:00 - 22:00',
      queueLength: 0,
      errorLogs: [
        {
          id: 'err3',
          timestamp: new Date(Date.now() - 45 * 60 * 1000),
          level: 'error',
          message: 'Payment gateway timeout',
          details: 'Credit card processing failed for transaction CB002'
        }
      ]
    },
    {
      id: 'BR003',
      name: 'Industrial Branch',
      code: 'IN001',
      manager: 'David Wilson',
      contact: '+66 2 345 6789',
      address: '456 Industrial Road, Lat Krabang, Bangkok 10520',
      status: 'offline',
      lastSync: new Date(Date.now() - 2 * 60 * 60 * 1000), // 2 hours ago
      dailySales: 32150.25,
      activeCashiers: 0,
      openHours: '07:00 - 19:00',
      queueLength: 0,
      errorLogs: [
        {
          id: 'err4',
          timestamp: new Date(Date.now() - 2 * 60 * 60 * 1000),
          level: 'error',
          message: 'Connection lost',
          details: 'Network connectivity issues detected'
        },
        {
          id: 'err5',
          timestamp: new Date(Date.now() - 3 * 60 * 60 * 1000),
          level: 'warning',
          message: 'High transaction volume',
          details: 'Processing 50+ transactions per hour'
        }
      ]
    },
    {
      id: 'BR004',
      name: 'Suburb Branch',
      code: 'SB001',
      manager: 'Lisa Anderson',
      contact: '+66 2 456 7890',
      address: '789 Suburb Avenue, Nonthaburi 11000',
      status: 'degraded',
      lastSync: new Date(Date.now() - 15 * 60 * 1000), // 15 minutes ago
      dailySales: 19129.00,
      activeCashiers: 1,
      openHours: '08:30 - 19:30',
      taxOverride: 7.5,
      queueLength: 5,
      errorLogs: [
        {
          id: 'err6',
          timestamp: new Date(Date.now() - 10 * 60 * 1000),
          level: 'warning',
          message: 'Slow response times',
          details: 'Average response time: 3.2 seconds'
        },
        {
          id: 'err7',
          timestamp: new Date(Date.now() - 20 * 60 * 1000),
          level: 'info',
          message: 'Stock update completed',
          details: 'Updated 25 items from central inventory'
        }
      ]
    }
  ];

  const filteredBranches = branches.filter(branch =>
    branch.name.toLowerCase().includes(searchQuery.toLowerCase()) ||
    branch.code.toLowerCase().includes(searchQuery.toLowerCase()) ||
    branch.manager.toLowerCase().includes(searchQuery.toLowerCase())
  );

  const formatLastSync = (date: Date) => {
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

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'online': return 'bg-green-100 text-green-800';
      case 'offline': return 'bg-red-100 text-red-800';
      case 'degraded': return 'bg-orange-100 text-orange-800';
      default: return 'bg-gray-100 text-gray-800';
    }
  };

  const getStatusIcon = (status: string) => {
    switch (status) {
      case 'online': return <Wifi className="w-3 h-3" />;
      case 'offline': return <WifiOff className="w-3 h-3" />;
      case 'degraded': return <AlertTriangle className="w-3 h-3" />;
      default: return <WifiOff className="w-3 h-3" />;
    }
  };

  const handleViewDetails = (branch: Branch) => {
    setSelectedBranch(branch);
    setShowDetailsDrawer(true);
  };

  const handleForceSync = (branchId: string) => {
    alert(`Force sync initiated for branch ${branchId}`);
  };

  const handleLockBranch = (branchId: string) => {
    alert(`Branch ${branchId} login locked`);
  };

  const handlePushNotice = (branchId: string) => {
    alert(`Pushing notice to branch ${branchId}`);
  };

  const handleExportCSV = () => {
    alert('Exporting branches list to CSV...');
  };

  return (
    <div className="p-6">
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-3xl font-bold text-gray-900">Branch Management</h1>
          <p className="text-gray-600 mt-2">Monitor and manage all branch locations</p>
        </div>
        <div className="flex items-center space-x-3">
          <button
            onClick={handleExportCSV}
            className="px-4 py-2 bg-green-500 hover:bg-green-600 text-white rounded-lg transition-colors"
          >
            Export CSV
          </button>
          <button
            onClick={() => setShowAddModal(true)}
            className="flex items-center space-x-2 px-4 py-2 bg-blue-500 hover:bg-blue-600 text-white rounded-lg transition-colors"
          >
            <Plus className="w-4 h-4" />
            <span>Add Branch</span>
          </button>
        </div>
      </div>

      {/* Search and Filters */}
      <div className="bg-white rounded-lg border border-gray-200 p-4 mb-6">
        <div className="flex items-center space-x-4">
          <div className="relative flex-1">
            <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 text-gray-400 w-4 h-4" />
            <input
              type="text"
              placeholder="Search branches by name, code, or manager..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="pl-10 pr-4 py-2 w-full border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
            />
          </div>
          <select className="px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent">
            <option value="all">All Status</option>
            <option value="online">Online</option>
            <option value="offline">Offline</option>
            <option value="degraded">Degraded</option>
          </select>
        </div>
      </div>

      {/* Branches Table */}
      <div className="bg-white rounded-lg border border-gray-200 overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full">
            <thead className="bg-gray-50 border-b border-gray-200">
              <tr>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Branch
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Manager
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Contact
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Status
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Last Sync
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Daily Sales
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Actions
                </th>
              </tr>
            </thead>
            <tbody className="bg-white divide-y divide-gray-200">
              {filteredBranches.map((branch) => (
                <tr 
                  key={branch.id} 
                  className="hover:bg-gray-50 cursor-pointer"
                  onClick={() => handleViewDetails(branch)}
                >
                  <td className="px-6 py-4 whitespace-nowrap">
                    <div className="flex items-center space-x-3">
                      <div className="w-10 h-10 bg-blue-100 rounded-lg flex items-center justify-center">
                        <Building2 className="w-5 h-5 text-blue-600" />
                      </div>
                      <div>
                        <div className="text-sm font-medium text-gray-900">{branch.name}</div>
                        <div className="text-sm text-gray-500">Code: {branch.code}</div>
                      </div>
                    </div>
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                    {branch.manager}
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                    {branch.contact}
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap">
                    <span className={`inline-flex items-center space-x-1 px-2.5 py-0.5 rounded-full text-xs font-medium ${getStatusColor(branch.status)}`}>
                      {getStatusIcon(branch.status)}
                      <span className="capitalize">{branch.status}</span>
                    </span>
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                    {formatLastSync(branch.lastSync)}
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
                    ฿{branch.dailySales.toLocaleString()}
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                    <div className="flex items-center space-x-2">
                      <button
                        onClick={(e) => {
                          e.stopPropagation();
                          handleViewDetails(branch);
                        }}
                        className="text-blue-600 hover:text-blue-800 transition-colors"
                        title="View Details"
                      >
                        <Eye className="w-4 h-4" />
                      </button>
                      <button
                        onClick={(e) => {
                          e.stopPropagation();
                          alert(`Viewing reports for ${branch.name}`);
                        }}
                        className="text-green-600 hover:text-green-800 transition-colors"
                        title="View Reports"
                      >
                        <FileText className="w-4 h-4" />
                      </button>
                      <button
                        onClick={(e) => {
                          e.stopPropagation();
                          alert(`Opening settings for ${branch.name}`);
                        }}
                        className="text-gray-600 hover:text-gray-800 transition-colors"
                        title="Settings"
                      >
                        <Settings className="w-4 h-4" />
                      </button>
                      <button
                        onClick={(e) => {
                          e.stopPropagation();
                          alert(`Sending announcement to ${branch.name}`);
                        }}
                        className="text-purple-600 hover:text-purple-800 transition-colors"
                        title="Send Announcement"
                      >
                        <MessageSquare className="w-4 h-4" />
                      </button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        
        {filteredBranches.length === 0 && (
          <div className="text-center py-12">
            <div className="text-gray-500 text-lg">No branches found</div>
            <div className="text-gray-400 text-sm mt-2">
              Try adjusting your search criteria
            </div>
          </div>
        )}
      </div>

      {/* Branch Details Drawer */}
      {showDetailsDrawer && selectedBranch && (
        <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-end z-50">
          <div className="bg-white h-full w-full max-w-2xl shadow-xl flex flex-col">
            <div className="flex items-center justify-between p-6 border-b border-gray-200">
              <div className="flex items-center space-x-3">
                <div className="w-12 h-12 bg-blue-100 rounded-lg flex items-center justify-center">
                  <Building2 className="w-6 h-6 text-blue-600" />
                </div>
                <div>
                  <h3 className="text-xl font-semibold text-gray-900">{selectedBranch.name}</h3>
                  <p className="text-sm text-gray-500">Code: {selectedBranch.code}</p>
                </div>
              </div>
              <button
                onClick={() => setShowDetailsDrawer(false)}
                className="text-gray-400 hover:text-gray-600 transition-colors"
              >
                <X className="w-6 h-6" />
              </button>
            </div>
            
            <div className="flex-1 overflow-y-auto p-6">
              {/* Profile Section */}
              <div className="mb-8">
                <h4 className="text-lg font-semibold text-gray-900 mb-4 flex items-center space-x-2">
                  <Building2 className="w-5 h-5" />
                  <span>Branch Profile</span>
                </h4>
                <div className="bg-gray-50 rounded-lg p-4 space-y-3">
                  <div className="flex items-center space-x-2">
                    <MapPin className="w-4 h-4 text-gray-500" />
                    <span className="text-sm text-gray-700">{selectedBranch.address}</span>
                  </div>
                  <div className="flex items-center space-x-2">
                    <Phone className="w-4 h-4 text-gray-500" />
                    <span className="text-sm text-gray-700">{selectedBranch.contact}</span>
                  </div>
                  <div className="flex items-center space-x-2">
                    <Calendar className="w-4 h-4 text-gray-500" />
                    <span className="text-sm text-gray-700">Hours: {selectedBranch.openHours}</span>
                  </div>
                  <div className="flex items-center space-x-2">
                    <span className="text-sm text-gray-700">Manager: {selectedBranch.manager}</span>
                  </div>
                  {selectedBranch.taxOverride && (
                    <div className="flex items-center space-x-2">
                      <span className="text-sm text-gray-700">Tax Override: {selectedBranch.taxOverride}%</span>
                    </div>
                  )}
                </div>
              </div>

              {/* Health Section */}
              <div className="mb-8">
                <h4 className="text-lg font-semibold text-gray-900 mb-4 flex items-center space-x-2">
                  <Activity className="w-5 h-5" />
                  <span>System Health</span>
                </h4>
                <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-4">
                  <div className="bg-gray-50 rounded-lg p-4">
                    <div className="text-sm text-gray-600">Status</div>
                    <div className={`inline-flex items-center space-x-1 px-2 py-1 rounded-full text-xs font-medium ${getStatusColor(selectedBranch.status)}`}>
                      {getStatusIcon(selectedBranch.status)}
                      <span className="capitalize">{selectedBranch.status}</span>
                    </div>
                  </div>
                  <div className="bg-gray-50 rounded-lg p-4">
                    <div className="text-sm text-gray-600">Last Sync</div>
                    <div className="text-lg font-semibold text-gray-900">{formatLastSync(selectedBranch.lastSync)}</div>
                  </div>
                  <div className="bg-gray-50 rounded-lg p-4">
                    <div className="text-sm text-gray-600">Queue Length</div>
                    <div className="text-lg font-semibold text-gray-900">{selectedBranch.queueLength}</div>
                  </div>
                </div>

                {/* Error Logs */}
                <div className="bg-gray-50 rounded-lg p-4">
                  <h5 className="font-medium text-gray-900 mb-3">Recent Logs (Last 10)</h5>
                  <div className="space-y-2 max-h-48 overflow-y-auto">
                    {selectedBranch.errorLogs.map((log) => (
                      <div key={log.id} className="flex items-start space-x-3 p-2 bg-white rounded border">
                        <div className={`w-2 h-2 rounded-full mt-2 ${
                          log.level === 'error' ? 'bg-red-500' :
                          log.level === 'warning' ? 'bg-orange-500' : 'bg-blue-500'
                        }`}></div>
                        <div className="flex-1 min-w-0">
                          <div className="flex items-center justify-between">
                            <span className="text-sm font-medium text-gray-900">{log.message}</span>
                            <span className="text-xs text-gray-500">{formatLastSync(log.timestamp)}</span>
                          </div>
                          {log.details && (
                            <p className="text-xs text-gray-600 mt-1">{log.details}</p>
                          )}
                        </div>
                      </div>
                    ))}
                  </div>
                </div>
              </div>

              {/* Quick Actions */}
              <div>
                <h4 className="text-lg font-semibold text-gray-900 mb-4">Quick Actions</h4>
                <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
                  <button
                    onClick={() => handleForceSync(selectedBranch.id)}
                    className="flex items-center justify-center space-x-2 p-3 bg-blue-50 text-blue-700 rounded-lg hover:bg-blue-100 transition-colors"
                  >
                    <RefreshCw className="w-4 h-4" />
                    <span>Force Sync</span>
                  </button>
                  <button
                    onClick={() => handleLockBranch(selectedBranch.id)}
                    className="flex items-center justify-center space-x-2 p-3 bg-red-50 text-red-700 rounded-lg hover:bg-red-100 transition-colors"
                  >
                    <Lock className="w-4 h-4" />
                    <span>Lock Login</span>
                  </button>
                  <button
                    onClick={() => handlePushNotice(selectedBranch.id)}
                    className="flex items-center justify-center space-x-2 p-3 bg-green-50 text-green-700 rounded-lg hover:bg-green-100 transition-colors"
                  >
                    <Bell className="w-4 h-4" />
                    <span>Push Notice</span>
                  </button>
                </div>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Add Branch Modal */}
      {showAddModal && (
        <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
          <div className="bg-white rounded-lg shadow-xl max-w-md w-full mx-4">
            <div className="flex items-center justify-between p-6 border-b border-gray-200">
              <h3 className="text-lg font-semibold text-gray-900">Add New Branch</h3>
              <button
                onClick={() => setShowAddModal(false)}
                className="text-gray-400 hover:text-gray-600 transition-colors"
              >
                <X className="w-5 h-5" />
              </button>
            </div>
            
            <div className="p-6">
              <div className="space-y-4">
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">Branch Name</label>
                  <input
                    type="text"
                    className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                    placeholder="Enter branch name"
                  />
                </div>
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">Branch Code</label>
                  <input
                    type="text"
                    className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                    placeholder="Enter branch code"
                  />
                </div>
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">Manager</label>
                  <input
                    type="text"
                    className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                    placeholder="Enter manager name"
                  />
                </div>
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">Contact</label>
                  <input
                    type="text"
                    className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                    placeholder="Enter contact number"
                  />
                </div>
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">Address</label>
                  <textarea
                    rows={3}
                    className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                    placeholder="Enter full address"
                  />
                </div>
              </div>
            </div>
            
            <div className="flex items-center justify-end space-x-3 p-6 border-t border-gray-200">
              <button
                onClick={() => setShowAddModal(false)}
                className="px-4 py-2 text-sm font-medium text-gray-700 bg-gray-100 hover:bg-gray-200 rounded-lg transition-colors"
              >
                Cancel
              </button>
              <button
                onClick={() => {
                  alert('Branch added successfully!');
                  setShowAddModal(false);
                }}
                className="px-4 py-2 text-sm font-medium text-white bg-blue-500 hover:bg-blue-600 rounded-lg transition-colors"
              >
                Add Branch
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};