import React, { useState, useMemo } from 'react';
import { 
  Users, 
  Shield, 
  FileText, 
  Search, 
  Plus, 
  Edit, 
  Lock, 
  Unlock, 
  RotateCcw, 
  Trash2, 
  Eye, 
  Download, 
  X,
  Mail,
  Calendar,
  MapPin,
  AlertTriangle,
  CheckCircle,
  Clock,
  User,
  Settings,
  Activity
} from 'lucide-react';

interface User {
  id: string;
  name: string;
  email: string;
  roles: string[];
  lastLogin: Date | null;
  status: 'active' | 'locked' | 'pending';
  createdAt: Date;
  branch?: string;
  phone?: string;
}

interface Role {
  id: string;
  name: string;
  description: string;
  permissions: Permission[];
  userCount: number;
  isSystem: boolean;
}

interface Permission {
  section: 'sales' | 'stock' | 'shifts' | 'bills' | 'users' | 'settings';
  actions: {
    view: boolean;
    edit: boolean;
    export: boolean;
    delete: boolean;
  };
}

interface AuditLog {
  id: string;
  timestamp: Date;
  user: string;
  action: string;
  section: string;
  objectRef?: string;
  ipAddress: string;
  userAgent: string;
  details?: string;
  severity: 'info' | 'warning' | 'critical';
}

interface FilterState {
  searchQuery: string;
  roleFilter: string;
  statusFilter: string;
  dateRange: string;
  customDateStart: string;
  customDateEnd: string;
}

export const UsersRoles: React.FC = () => {
  const [activeTab, setActiveTab] = useState<'users' | 'roles' | 'audit'>('users');
  const [filters, setFilters] = useState<FilterState>({
    searchQuery: '',
    roleFilter: 'all',
    statusFilter: 'all',
    dateRange: 'today',
    customDateStart: '',
    customDateEnd: '',
  });

  const [selectedUsers, setSelectedUsers] = useState<string[]>([]);
  const [selectedUser, setSelectedUser] = useState<User | null>(null);
  const [selectedRole, setSelectedRole] = useState<Role | null>(null);
  const [showInviteModal, setShowInviteModal] = useState(false);
  const [showRoleModal, setShowRoleModal] = useState(false);
  const [showConfirmModal, setShowConfirmModal] = useState(false);
  const [confirmAction, setConfirmAction] = useState<{
    type: string;
    user?: User;
    role?: Role;
    callback: () => void;
  } | null>(null);
  const [actionReason, setActionReason] = useState('');

  // Mock data
  const mockUsers: User[] = [
    {
      id: 'user-1',
      name: 'Sarah Johnson',
      email: 'sarah.johnson@constructmart.com',
      roles: ['HQ Admin'],
      lastLogin: new Date(Date.now() - 2 * 60 * 60 * 1000),
      status: 'active',
      createdAt: new Date('2023-01-15'),
      phone: '+66 2 123 4567',
    },
    {
      id: 'user-2',
      name: 'Mike Chen',
      email: 'mike.chen@constructmart.com',
      roles: ['Branch Manager'],
      lastLogin: new Date(Date.now() - 30 * 60 * 1000),
      status: 'active',
      createdAt: new Date('2023-03-20'),
      branch: 'Mall Branch',
      phone: '+66 2 234 5678',
    },
    {
      id: 'user-3',
      name: 'Lisa Anderson',
      email: 'lisa.anderson@constructmart.com',
      roles: ['Auditor'],
      lastLogin: new Date(Date.now() - 4 * 60 * 60 * 1000),
      status: 'active',
      createdAt: new Date('2023-02-10'),
      phone: '+66 2 345 6789',
    },
    {
      id: 'user-4',
      name: 'David Wilson',
      email: 'david.wilson@constructmart.com',
      roles: ['Branch Manager'],
      lastLogin: null,
      status: 'pending',
      createdAt: new Date('2024-01-10'),
      branch: 'Industrial Branch',
      phone: '+66 2 456 7890',
    },
    {
      id: 'user-5',
      name: 'Emma Davis',
      email: 'emma.davis@constructmart.com',
      roles: ['Branch Manager'],
      lastLogin: new Date(Date.now() - 7 * 24 * 60 * 60 * 1000),
      status: 'locked',
      createdAt: new Date('2023-06-15'),
      branch: 'Suburb Branch',
      phone: '+66 2 567 8901',
    },
  ];

  const mockRoles: Role[] = [
    {
      id: 'role-1',
      name: 'HQ Admin',
      description: 'Full system access for head office administrators',
      userCount: 1,
      isSystem: true,
      permissions: [
        { section: 'sales', actions: { view: true, edit: true, export: true, delete: true } },
        { section: 'stock', actions: { view: true, edit: true, export: true, delete: true } },
        { section: 'shifts', actions: { view: true, edit: true, export: true, delete: true } },
        { section: 'bills', actions: { view: true, edit: true, export: true, delete: true } },
        { section: 'users', actions: { view: true, edit: true, export: true, delete: true } },
        { section: 'settings', actions: { view: true, edit: true, export: false, delete: false } },
      ],
    },
    {
      id: 'role-2',
      name: 'Branch Manager',
      description: 'Branch-level management with limited head office access',
      userCount: 3,
      isSystem: false,
      permissions: [
        { section: 'sales', actions: { view: true, edit: true, export: true, delete: false } },
        { section: 'stock', actions: { view: true, edit: true, export: true, delete: false } },
        { section: 'shifts', actions: { view: true, edit: true, export: true, delete: false } },
        { section: 'bills', actions: { view: true, edit: false, export: true, delete: false } },
        { section: 'users', actions: { view: false, edit: false, export: false, delete: false } },
        { section: 'settings', actions: { view: true, edit: false, export: false, delete: false } },
      ],
    },
    {
      id: 'role-3',
      name: 'Auditor',
      description: 'Read-only access for auditing and compliance',
      userCount: 1,
      isSystem: false,
      permissions: [
        { section: 'sales', actions: { view: true, edit: false, export: true, delete: false } },
        { section: 'stock', actions: { view: true, edit: false, export: true, delete: false } },
        { section: 'shifts', actions: { view: true, edit: false, export: true, delete: false } },
        { section: 'bills', actions: { view: true, edit: false, export: true, delete: false } },
        { section: 'users', actions: { view: true, edit: false, export: true, delete: false } },
        { section: 'settings', actions: { view: true, edit: false, export: false, delete: false } },
      ],
    },
  ];

  const mockAuditLogs: AuditLog[] = [
    {
      id: 'audit-1',
      timestamp: new Date(Date.now() - 30 * 60 * 1000),
      user: 'Sarah Johnson',
      action: 'User Created',
      section: 'users',
      objectRef: 'user-4',
      ipAddress: '192.168.1.100',
      userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
      details: 'Created new Branch Manager account for David Wilson',
      severity: 'info',
    },
    {
      id: 'audit-2',
      timestamp: new Date(Date.now() - 2 * 60 * 60 * 1000),
      user: 'Mike Chen',
      action: 'Password Reset',
      section: 'users',
      objectRef: 'user-2',
      ipAddress: '192.168.1.105',
      userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)',
      details: 'Password reset requested and completed',
      severity: 'warning',
    },
    {
      id: 'audit-3',
      timestamp: new Date(Date.now() - 4 * 60 * 60 * 1000),
      user: 'Sarah Johnson',
      action: 'Account Locked',
      section: 'users',
      objectRef: 'user-5',
      ipAddress: '192.168.1.100',
      userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
      details: 'Account locked due to multiple failed login attempts',
      severity: 'critical',
    },
    {
      id: 'audit-4',
      timestamp: new Date(Date.now() - 6 * 60 * 60 * 1000),
      user: 'Lisa Anderson',
      action: 'Data Export',
      section: 'sales',
      objectRef: 'sales-report-2024-01',
      ipAddress: '192.168.1.110',
      userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
      details: 'Exported sales report for January 2024',
      severity: 'info',
    },
  ];

  // Filter data
  const filteredUsers = useMemo(() => {
    let filtered = mockUsers;

    if (filters.searchQuery) {
      filtered = filtered.filter(user =>
        user.name.toLowerCase().includes(filters.searchQuery.toLowerCase()) ||
        user.email.toLowerCase().includes(filters.searchQuery.toLowerCase())
      );
    }

    if (filters.roleFilter !== 'all') {
      filtered = filtered.filter(user => user.roles.includes(filters.roleFilter));
    }

    if (filters.statusFilter !== 'all') {
      filtered = filtered.filter(user => user.status === filters.statusFilter);
    }

    return filtered;
  }, [filters]);

  const filteredAuditLogs = useMemo(() => {
    let filtered = mockAuditLogs;

    if (filters.searchQuery) {
      filtered = filtered.filter(log =>
        log.user.toLowerCase().includes(filters.searchQuery.toLowerCase()) ||
        log.action.toLowerCase().includes(filters.searchQuery.toLowerCase()) ||
        log.section.toLowerCase().includes(filters.searchQuery.toLowerCase())
      );
    }

    return filtered;
  }, [filters]);

  const handleFilterChange = (key: keyof FilterState, value: any) => {
    setFilters(prev => ({ ...prev, [key]: value }));
  };

  const handleSelectUser = (userId: string) => {
    setSelectedUsers(prev => 
      prev.includes(userId) 
        ? prev.filter(id => id !== userId)
        : [...prev, userId]
    );
  };

  const handleSelectAll = () => {
    if (selectedUsers.length === filteredUsers.length) {
      setSelectedUsers([]);
    } else {
      setSelectedUsers(filteredUsers.map(user => user.id));
    }
  };

  const handleUserAction = (type: string, user: User) => {
    setConfirmAction({
      type,
      user,
      callback: () => {
        switch (type) {
          case 'lock':
            alert(`Account locked for ${user.name}. Reason: ${actionReason}`);
            break;
          case 'unlock':
            alert(`Account unlocked for ${user.name}. Reason: ${actionReason}`);
            break;
          case 'reset':
            alert(`Password reset sent to ${user.email}. Reason: ${actionReason}`);
            break;
          case 'delete':
            alert(`Account deleted for ${user.name}. Reason: ${actionReason}`);
            break;
        }
        setShowConfirmModal(false);
        setActionReason('');
        setConfirmAction(null);
      }
    });
    setShowConfirmModal(true);
  };

  const handleRoleAction = (type: string, role: Role) => {
    setConfirmAction({
      type,
      role,
      callback: () => {
        switch (type) {
          case 'delete':
            alert(`Role "${role.name}" deleted. Reason: ${actionReason}`);
            break;
        }
        setShowConfirmModal(false);
        setActionReason('');
        setConfirmAction(null);
      }
    });
    setShowConfirmModal(true);
  };

  const handleInviteUser = () => {
    alert('User invitation sent successfully!');
    setShowInviteModal(false);
  };

  const handleSaveRole = () => {
    alert('Role permissions updated successfully!');
    setShowRoleModal(false);
    setSelectedRole(null);
  };

  const handleExportAudit = () => {
    alert('Exporting audit logs to CSV...');
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

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'active': return 'bg-green-100 text-green-800';
      case 'locked': return 'bg-red-100 text-red-800';
      case 'pending': return 'bg-yellow-100 text-yellow-800';
      default: return 'bg-gray-100 text-gray-800';
    }
  };

  const getStatusIcon = (status: string) => {
    switch (status) {
      case 'active': return <CheckCircle className="w-3 h-3" />;
      case 'locked': return <Lock className="w-3 h-3" />;
      case 'pending': return <Clock className="w-3 h-3" />;
      default: return <User className="w-3 h-3" />;
    }
  };

  const getSeverityColor = (severity: string) => {
    switch (severity) {
      case 'critical': return 'bg-red-100 text-red-800 border-red-200';
      case 'warning': return 'bg-orange-100 text-orange-800 border-orange-200';
      case 'info': return 'bg-blue-100 text-blue-800 border-blue-200';
      default: return 'bg-gray-100 text-gray-800 border-gray-200';
    }
  };

  const getSeverityIcon = (severity: string) => {
    switch (severity) {
      case 'critical': return <AlertTriangle className="w-4 h-4" />;
      case 'warning': return <AlertTriangle className="w-4 h-4" />;
      case 'info': return <Activity className="w-4 h-4" />;
      default: return <Activity className="w-4 h-4" />;
    }
  };

  return (
    <div className="p-6">
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-3xl font-bold text-gray-900">Users & Roles</h1>
          <p className="text-gray-600 mt-2">Manage user accounts, roles, and permissions</p>
        </div>
        <div className="flex items-center space-x-3">
          {activeTab === 'audit' && (
            <button
              onClick={handleExportAudit}
              className="flex items-center space-x-2 px-4 py-2 bg-green-500 hover:bg-green-600 text-white rounded-lg transition-colors"
            >
              <Download className="w-4 h-4" />
              <span>Export Audit</span>
            </button>
          )}
          {activeTab === 'users' && (
            <button
              onClick={() => setShowInviteModal(true)}
              className="flex items-center space-x-2 px-4 py-2 bg-blue-500 hover:bg-blue-600 text-white rounded-lg transition-colors"
            >
              <Plus className="w-4 h-4" />
              <span>Invite User</span>
            </button>
          )}
          {activeTab === 'roles' && (
            <button
              onClick={() => {
                setSelectedRole(null);
                setShowRoleModal(true);
              }}
              className="flex items-center space-x-2 px-4 py-2 bg-purple-500 hover:bg-purple-600 text-white rounded-lg transition-colors"
            >
              <Plus className="w-4 h-4" />
              <span>Create Role</span>
            </button>
          )}
        </div>
      </div>

      {/* Tab Navigation */}
      <div className="bg-white rounded-lg border border-gray-200 overflow-hidden mb-6">
        <div className="border-b border-gray-200">
          <nav className="flex space-x-8 px-6">
            <button
              onClick={() => setActiveTab('users')}
              className={`py-4 px-1 border-b-2 font-medium text-sm ${
                activeTab === 'users'
                  ? 'border-blue-500 text-blue-600'
                  : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'
              }`}
            >
              <div className="flex items-center space-x-2">
                <Users className="w-4 h-4" />
                <span>Users</span>
              </div>
            </button>
            <button
              onClick={() => setActiveTab('roles')}
              className={`py-4 px-1 border-b-2 font-medium text-sm ${
                activeTab === 'roles'
                  ? 'border-blue-500 text-blue-600'
                  : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'
              }`}
            >
              <div className="flex items-center space-x-2">
                <Shield className="w-4 h-4" />
                <span>Roles</span>
              </div>
            </button>
            <button
              onClick={() => setActiveTab('audit')}
              className={`py-4 px-1 border-b-2 font-medium text-sm ${
                activeTab === 'audit'
                  ? 'border-blue-500 text-blue-600'
                  : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'
              }`}
            >
              <div className="flex items-center space-x-2">
                <FileText className="w-4 h-4" />
                <span>Audit Logs</span>
              </div>
            </button>
          </nav>
        </div>

        {/* Filters */}
        <div className="p-4 border-b border-gray-200">
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
            <div className="relative">
              <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 text-gray-400 w-4 h-4" />
              <input
                type="text"
                placeholder={`Search ${activeTab}...`}
                value={filters.searchQuery}
                onChange={(e) => handleFilterChange('searchQuery', e.target.value)}
                className="pl-10 pr-4 py-2 w-full border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
              />
            </div>

            {activeTab === 'users' && (
              <>
                <select
                  value={filters.roleFilter}
                  onChange={(e) => handleFilterChange('roleFilter', e.target.value)}
                  className="px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                >
                  <option value="all">All Roles</option>
                  {mockRoles.map(role => (
                    <option key={role.id} value={role.name}>{role.name}</option>
                  ))}
                </select>

                <select
                  value={filters.statusFilter}
                  onChange={(e) => handleFilterChange('statusFilter', e.target.value)}
                  className="px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                >
                  <option value="all">All Status</option>
                  <option value="active">Active</option>
                  <option value="locked">Locked</option>
                  <option value="pending">Pending</option>
                </select>
              </>
            )}

            {activeTab === 'audit' && (
              <select
                value={filters.dateRange}
                onChange={(e) => handleFilterChange('dateRange', e.target.value)}
                className="px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
              >
                <option value="today">Today</option>
                <option value="week">This Week</option>
                <option value="month">This Month</option>
                <option value="custom">Custom Range</option>
              </select>
            )}
          </div>
        </div>

        {/* Users Table */}
        {activeTab === 'users' && (
          <>
            {selectedUsers.length > 0 && (
              <div className="bg-blue-50 border-b border-blue-200 px-6 py-3">
                <div className="flex items-center justify-between">
                  <span className="text-sm text-blue-700">
                    {selectedUsers.length} user{selectedUsers.length !== 1 ? 's' : ''} selected
                  </span>
                  <div className="flex items-center space-x-2">
                    <button
                      onClick={() => alert('Bulk action: Lock selected users')}
                      className="px-3 py-1 bg-red-500 hover:bg-red-600 text-white text-sm rounded transition-colors"
                    >
                      Bulk Lock
                    </button>
                    <button
                      onClick={() => setSelectedUsers([])}
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
                        checked={selectedUsers.length === filteredUsers.length && filteredUsers.length > 0}
                        onChange={handleSelectAll}
                        className="rounded border-gray-300 text-blue-600 focus:ring-blue-500"
                      />
                    </th>
                    <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">User</th>
                    <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Role(s)</th>
                    <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Last Login</th>
                    <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Status</th>
                    <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Actions</th>
                  </tr>
                </thead>
                <tbody className="bg-white divide-y divide-gray-200">
                  {filteredUsers.map((user) => (
                    <tr key={user.id} className="hover:bg-gray-50">
                      <td className="px-6 py-4 whitespace-nowrap">
                        <input
                          type="checkbox"
                          checked={selectedUsers.includes(user.id)}
                          onChange={() => handleSelectUser(user.id)}
                          className="rounded border-gray-300 text-blue-600 focus:ring-blue-500"
                        />
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap">
                        <div className="flex items-center space-x-3">
                          <div className="w-10 h-10 bg-blue-100 rounded-full flex items-center justify-center">
                            <User className="w-5 h-5 text-blue-600" />
                          </div>
                          <div>
                            <div className="text-sm font-medium text-gray-900">{user.name}</div>
                            <div className="text-sm text-gray-500">{user.email}</div>
                            {user.branch && (
                              <div className="text-xs text-gray-400">{user.branch}</div>
                            )}
                          </div>
                        </div>
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap">
                        <div className="flex flex-wrap gap-1">
                          {user.roles.map(role => (
                            <span key={role} className="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-purple-100 text-purple-800">
                              {role}
                            </span>
                          ))}
                        </div>
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                        {user.lastLogin ? formatTime(user.lastLogin) : 'Never'}
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap">
                        <span className={`inline-flex items-center space-x-1 px-2.5 py-0.5 rounded-full text-xs font-medium ${getStatusColor(user.status)}`}>
                          {getStatusIcon(user.status)}
                          <span className="capitalize">{user.status}</span>
                        </span>
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                        <div className="flex items-center space-x-2">
                          <button
                            onClick={() => alert(`Viewing details for ${user.name}`)}
                            className="text-blue-600 hover:text-blue-800 transition-colors"
                            title="View Details"
                          >
                            <Eye className="w-4 h-4" />
                          </button>
                          <button
                            onClick={() => handleUserAction('reset', user)}
                            className="text-green-600 hover:text-green-800 transition-colors"
                            title="Reset Password"
                          >
                            <RotateCcw className="w-4 h-4" />
                          </button>
                          {user.status === 'active' ? (
                            <button
                              onClick={() => handleUserAction('lock', user)}
                              className="text-red-600 hover:text-red-800 transition-colors"
                              title="Lock Account"
                            >
                              <Lock className="w-4 h-4" />
                            </button>
                          ) : (
                            <button
                              onClick={() => handleUserAction('unlock', user)}
                              className="text-green-600 hover:text-green-800 transition-colors"
                              title="Unlock Account"
                            >
                              <Unlock className="w-4 h-4" />
                            </button>
                          )}
                          <button
                            onClick={() => handleUserAction('delete', user)}
                            className="text-red-600 hover:text-red-800 transition-colors"
                            title="Delete User"
                          >
                            <Trash2 className="w-4 h-4" />
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

        {/* Roles Table */}
        {activeTab === 'roles' && (
          <div className="overflow-x-auto">
            <table className="w-full">
              <thead className="bg-gray-50 border-b border-gray-200">
                <tr>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Role</th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Description</th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Users</th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Type</th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Actions</th>
                </tr>
              </thead>
              <tbody className="bg-white divide-y divide-gray-200">
                {mockRoles.map((role) => (
                  <tr key={role.id} className="hover:bg-gray-50">
                    <td className="px-6 py-4 whitespace-nowrap">
                      <div className="flex items-center space-x-3">
                        <div className="w-10 h-10 bg-purple-100 rounded-lg flex items-center justify-center">
                          <Shield className="w-5 h-5 text-purple-600" />
                        </div>
                        <div>
                          <div className="text-sm font-medium text-gray-900">{role.name}</div>
                        </div>
                      </div>
                    </td>
                    <td className="px-6 py-4">
                      <div className="text-sm text-gray-900 max-w-xs">{role.description}</div>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                      {role.userCount} user{role.userCount !== 1 ? 's' : ''}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap">
                      <span className={`inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium ${
                        role.isSystem ? 'bg-blue-100 text-blue-800' : 'bg-gray-100 text-gray-800'
                      }`}>
                        {role.isSystem ? 'System' : 'Custom'}
                      </span>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                      <div className="flex items-center space-x-2">
                        <button
                          onClick={() => {
                            setSelectedRole(role);
                            setShowRoleModal(true);
                          }}
                          className="text-blue-600 hover:text-blue-800 transition-colors"
                          title="Edit Permissions"
                        >
                          <Edit className="w-4 h-4" />
                        </button>
                        {!role.isSystem && (
                          <button
                            onClick={() => handleRoleAction('delete', role)}
                            className="text-red-600 hover:text-red-800 transition-colors"
                            title="Delete Role"
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
        )}

        {/* Audit Logs Table */}
        {activeTab === 'audit' && (
          <div className="overflow-x-auto">
            <table className="w-full">
              <thead className="bg-gray-50 border-b border-gray-200">
                <tr>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Timestamp</th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">User</th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Action</th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Section</th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">IP Address</th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Severity</th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Details</th>
                </tr>
              </thead>
              <tbody className="bg-white divide-y divide-gray-200">
                {filteredAuditLogs.map((log) => (
                  <tr key={log.id} className="hover:bg-gray-50">
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                      {log.timestamp.toLocaleDateString()}<br />
                      {log.timestamp.toLocaleTimeString()}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">{log.user}</td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">{log.action}</td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500 capitalize">{log.section}</td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">{log.ipAddress}</td>
                    <td className="px-6 py-4 whitespace-nowrap">
                      <span className={`inline-flex items-center space-x-1 px-2.5 py-0.5 rounded-full text-xs font-medium border ${getSeverityColor(log.severity)}`}>
                        {getSeverityIcon(log.severity)}
                        <span className="capitalize">{log.severity}</span>
                      </span>
                    </td>
                    <td className="px-6 py-4 text-sm text-gray-500 max-w-xs truncate">
                      {log.details}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}

        {(activeTab === 'users' ? filteredUsers : activeTab === 'roles' ? mockRoles : filteredAuditLogs).length === 0 && (
          <div className="text-center py-12">
            <div className="text-gray-500 text-lg">No {activeTab} found</div>
            <div className="text-gray-400 text-sm mt-2">
              Try adjusting your search or filters
            </div>
          </div>
        )}
      </div>

      {/* Invite User Modal */}
      {showInviteModal && (
        <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
          <div className="bg-white rounded-lg shadow-xl max-w-md w-full mx-4">
            <div className="flex items-center justify-between p-6 border-b border-gray-200">
              <h3 className="text-lg font-semibold text-gray-900">Invite New User</h3>
              <button
                onClick={() => setShowInviteModal(false)}
                className="text-gray-400 hover:text-gray-600 transition-colors"
              >
                <X className="w-5 h-5" />
              </button>
            </div>
            
            <div className="p-6">
              <div className="space-y-4">
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">Full Name</label>
                  <input
                    type="text"
                    className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                    placeholder="Enter full name"
                  />
                </div>
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">Email Address</label>
                  <input
                    type="email"
                    className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                    placeholder="Enter email address"
                  />
                </div>
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">Role</label>
                  <select className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent">
                    {mockRoles.map(role => (
                      <option key={role.id} value={role.id}>{role.name}</option>
                    ))}
                  </select>
                </div>
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">Branch (Optional)</label>
                  <select className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent">
                    <option value="">No specific branch</option>
                    <option value="downtown">Downtown Branch</option>
                    <option value="mall">Mall Branch</option>
                    <option value="industrial">Industrial Branch</option>
                    <option value="suburb">Suburb Branch</option>
                  </select>
                </div>
              </div>
            </div>
            
            <div className="flex items-center justify-end space-x-3 p-6 border-t border-gray-200">
              <button
                onClick={() => setShowInviteModal(false)}
                className="px-4 py-2 text-sm font-medium text-gray-700 bg-gray-100 hover:bg-gray-200 rounded-lg transition-colors"
              >
                Cancel
              </button>
              <button
                onClick={handleInviteUser}
                className="px-4 py-2 text-sm font-medium text-white bg-blue-500 hover:bg-blue-600 rounded-lg transition-colors"
              >
                Send Invitation
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Role Permissions Modal */}
      {showRoleModal && (
        <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
          <div className="bg-white rounded-lg shadow-xl max-w-4xl w-full mx-4 max-h-[90vh] overflow-y-auto">
            <div className="flex items-center justify-between p-6 border-b border-gray-200">
              <h3 className="text-lg font-semibold text-gray-900">
                {selectedRole ? `Edit Role: ${selectedRole.name}` : 'Create New Role'}
              </h3>
              <button
                onClick={() => setShowRoleModal(false)}
                className="text-gray-400 hover:text-gray-600 transition-colors"
              >
                <X className="w-5 h-5" />
              </button>
            </div>
            
            <div className="p-6">
              <div className="space-y-6">
                <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                  <div>
                    <label className="block text-sm font-medium text-gray-700 mb-2">Role Name</label>
                    <input
                      type="text"
                      defaultValue={selectedRole?.name || ''}
                      className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                      placeholder="Enter role name"
                    />
                  </div>
                  <div>
                    <label className="block text-sm font-medium text-gray-700 mb-2">Description</label>
                    <input
                      type="text"
                      defaultValue={selectedRole?.description || ''}
                      className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                      placeholder="Enter role description"
                    />
                  </div>
                </div>

                <div>
                  <h4 className="text-lg font-semibold text-gray-900 mb-4">Permissions Matrix</h4>
                  <div className="overflow-x-auto">
                    <table className="w-full border border-gray-200 rounded-lg">
                      <thead className="bg-gray-50">
                        <tr>
                          <th className="px-4 py-3 text-left text-sm font-medium text-gray-700">Section</th>
                          <th className="px-4 py-3 text-center text-sm font-medium text-gray-700">View</th>
                          <th className="px-4 py-3 text-center text-sm font-medium text-gray-700">Edit</th>
                          <th className="px-4 py-3 text-center text-sm font-medium text-gray-700">Export</th>
                          <th className="px-4 py-3 text-center text-sm font-medium text-gray-700">Delete</th>
                        </tr>
                      </thead>
                      <tbody className="divide-y divide-gray-200">
                        {['sales', 'stock', 'shifts', 'bills', 'users', 'settings'].map((section) => {
                          const permission = selectedRole?.permissions.find(p => p.section === section);
                          return (
                            <tr key={section} className="hover:bg-gray-50">
                              <td className="px-4 py-3 text-sm font-medium text-gray-900 capitalize">{section}</td>
                              <td className="px-4 py-3 text-center">
                                <input
                                  type="checkbox"
                                  defaultChecked={permission?.actions.view || false}
                                  className="rounded border-gray-300 text-blue-600 focus:ring-blue-500"
                                />
                              </td>
                              <td className="px-4 py-3 text-center">
                                <input
                                  type="checkbox"
                                  defaultChecked={permission?.actions.edit || false}
                                  className="rounded border-gray-300 text-blue-600 focus:ring-blue-500"
                                />
                              </td>
                              <td className="px-4 py-3 text-center">
                                <input
                                  type="checkbox"
                                  defaultChecked={permission?.actions.export || false}
                                  className="rounded border-gray-300 text-blue-600 focus:ring-blue-500"
                                />
                              </td>
                              <td className="px-4 py-3 text-center">
                                <input
                                  type="checkbox"
                                  defaultChecked={permission?.actions.delete || false}
                                  className="rounded border-gray-300 text-blue-600 focus:ring-blue-500"
                                />
                              </td>
                            </tr>
                          );
                        })}
                      </tbody>
                    </table>
                  </div>
                </div>
              </div>
            </div>
            
            <div className="flex items-center justify-end space-x-3 p-6 border-t border-gray-200">
              <button
                onClick={() => setShowRoleModal(false)}
                className="px-4 py-2 text-sm font-medium text-gray-700 bg-gray-100 hover:bg-gray-200 rounded-lg transition-colors"
              >
                Cancel
              </button>
              <button
                onClick={handleSaveRole}
                className="px-4 py-2 text-sm font-medium text-white bg-blue-500 hover:bg-blue-600 rounded-lg transition-colors"
              >
                Save Role
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Confirmation Modal */}
      {showConfirmModal && confirmAction && (
        <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
          <div className="bg-white rounded-lg shadow-xl max-w-md w-full mx-4">
            <div className="flex items-center justify-between p-6 border-b border-gray-200">
              <h3 className="text-lg font-semibold text-gray-900">Confirm Action</h3>
              <button
                onClick={() => setShowConfirmModal(false)}
                className="text-gray-400 hover:text-gray-600 transition-colors"
              >
                <X className="w-5 h-5" />
              </button>
            </div>
            
            <div className="p-6">
              <div className="flex items-center space-x-3 p-4 rounded-lg border border-orange-200 bg-orange-50 mb-4">
                <AlertTriangle className="w-5 h-5 text-orange-600 flex-shrink-0" />
                <div>
                  <p className="text-sm font-medium text-orange-800">
                    {confirmAction.type === 'lock' && `Lock account for ${confirmAction.user?.name}`}
                    {confirmAction.type === 'unlock' && `Unlock account for ${confirmAction.user?.name}`}
                    {confirmAction.type === 'reset' && `Reset password for ${confirmAction.user?.name}`}
                    {confirmAction.type === 'delete' && confirmAction.user && `Delete account for ${confirmAction.user.name}`}
                    {confirmAction.type === 'delete' && confirmAction.role && `Delete role "${confirmAction.role.name}"`}
                  </p>
                  <p className="text-sm text-orange-600">This action requires a reason and cannot be undone.</p>
                </div>
              </div>
              
              <div className="mb-4">
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  Reason <span className="text-red-500">*</span>
                </label>
                <textarea
                  value={actionReason}
                  onChange={(e) => setActionReason(e.target.value)}
                  rows={3}
                  className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                  placeholder="Please provide a detailed reason for this action..."
                />
              </div>
            </div>
            
            <div className="flex items-center justify-end space-x-3 p-6 border-t border-gray-200">
              <button
                onClick={() => setShowConfirmModal(false)}
                className="px-4 py-2 text-sm font-medium text-gray-700 bg-gray-100 hover:bg-gray-200 rounded-lg transition-colors"
              >
                Cancel
              </button>
              <button
                onClick={confirmAction.callback}
                disabled={!actionReason.trim()}
                className="px-4 py-2 text-sm font-medium text-white bg-red-500 hover:bg-red-600 disabled:bg-gray-300 disabled:cursor-not-allowed rounded-lg transition-colors"
              >
                Confirm Action
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};