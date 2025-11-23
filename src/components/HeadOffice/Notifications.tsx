import React, { useState, useMemo } from 'react';
import { 
  Bell, 
  Send, 
  Users, 
  Building2, 
  Mail, 
  Eye, 
  Archive, 
  RefreshCw, 
  Plus, 
  X, 
  AlertTriangle, 
  CheckCircle, 
  Clock, 
  FileText, 
  Paperclip, 
  Trash2,
  Filter,
  Search,
  Calendar,
  Target,
  MessageSquare,
  Megaphone,
  Shield,
  Zap
} from 'lucide-react';

interface Notification {
  id: string;
  title: string;
  body: string;
  type: 'notice' | 'promotion' | 'policy' | 'alert';
  createdBy: string;
  createdAt: Date;
  audience: {
    branches: string[];
    roles: string[];
  };
  deliveryStatus: {
    sent: number;
    delivered: number;
    read: number;
    total: number;
  };
  readReceipts: ReadReceipt[];
  attachments?: Attachment[];
  emailWebhook?: boolean;
  status: 'draft' | 'sent' | 'archived';
}

interface ReadReceipt {
  branch: string;
  cashier: string;
  readAt: Date;
  acknowledged: boolean;
}

interface Attachment {
  id: string;
  name: string;
  size: number;
  type: string;
}

interface FilterState {
  searchQuery: string;
  messageType: string;
  status: string;
  dateRange: string;
  customDateStart: string;
  customDateEnd: string;
  createdBy: string;
}

export const Notifications: React.FC = () => {
  const [activeTab, setActiveTab] = useState<'compose' | 'outbox'>('compose');
  const [filters, setFilters] = useState<FilterState>({
    searchQuery: '',
    messageType: 'all',
    status: 'all',
    dateRange: 'week',
    customDateStart: '',
    customDateEnd: '',
    createdBy: 'all',
  });

  // Compose form state
  const [composeForm, setComposeForm] = useState({
    title: '',
    body: '',
    type: 'notice' as 'notice' | 'promotion' | 'policy' | 'alert',
    selectedBranches: ['All'] as string[],
    selectedRoles: ['All'] as string[],
    emailWebhook: false,
    attachments: [] as Attachment[],
  });

  const [selectedNotifications, setSelectedNotifications] = useState<string[]>([]);
  const [showPreview, setShowPreview] = useState(false);
  const [showReadReceipts, setShowReadReceipts] = useState(false);
  const [selectedNotification, setSelectedNotification] = useState<Notification | null>(null);
  const [showConfirmModal, setShowConfirmModal] = useState(false);
  const [confirmAction, setConfirmAction] = useState<{
    type: string;
    notification?: Notification;
    callback: () => void;
  } | null>(null);

  // Mock data
  const branches = ['Downtown Branch', 'Mall Branch', 'Industrial Branch', 'Suburb Branch'];
  const roles = ['Branch Manager', 'Cashier', 'Stock Manager', 'Auditor'];
  const creators = ['Sarah Johnson', 'Mike Chen', 'Lisa Anderson'];

  const mockNotifications: Notification[] = [
    {
      id: 'NOT001',
      title: 'New Discount Policy Effective Immediately',
      body: 'Please note that the maximum discount percentage has been reduced from 25% to 20% for all transactions. Manager approval is now required for discounts above 15%. This change is effective immediately across all branches.',
      type: 'policy',
      createdBy: 'Sarah Johnson',
      createdAt: new Date('2024-01-15T09:00:00'),
      audience: {
        branches: ['All'],
        roles: ['Branch Manager', 'Cashier'],
      },
      deliveryStatus: {
        sent: 8,
        delivered: 8,
        read: 6,
        total: 8,
      },
      readReceipts: [
        { branch: 'Downtown Branch', cashier: 'John Smith', readAt: new Date('2024-01-15T09:15:00'), acknowledged: true },
        { branch: 'Downtown Branch', cashier: 'Sarah Wilson', readAt: new Date('2024-01-15T09:30:00'), acknowledged: true },
        { branch: 'Mall Branch', cashier: 'Jane Doe', readAt: new Date('2024-01-15T10:00:00'), acknowledged: true },
        { branch: 'Mall Branch', cashier: 'Lisa Anderson', readAt: new Date('2024-01-15T10:15:00'), acknowledged: false },
        { branch: 'Industrial Branch', cashier: 'Mike Johnson', readAt: new Date('2024-01-15T11:00:00'), acknowledged: true },
        { branch: 'Suburb Branch', cashier: 'David Chen', readAt: new Date('2024-01-15T11:30:00'), acknowledged: true },
      ],
      emailWebhook: true,
      status: 'sent',
    },
    {
      id: 'NOT002',
      title: 'Weekend Sale Promotion - 15% Off Paint Products',
      body: 'This weekend only! Offer 15% discount on all paint products. Use promotion code PAINT15 in the POS system. Valid from Saturday 8 AM to Sunday 8 PM.',
      type: 'promotion',
      createdBy: 'Mike Chen',
      createdAt: new Date('2024-01-14T16:30:00'),
      audience: {
        branches: ['Downtown Branch', 'Mall Branch'],
        roles: ['Cashier'],
      },
      deliveryStatus: {
        sent: 4,
        delivered: 4,
        read: 4,
        total: 4,
      },
      readReceipts: [
        { branch: 'Downtown Branch', cashier: 'John Smith', readAt: new Date('2024-01-14T16:45:00'), acknowledged: true },
        { branch: 'Downtown Branch', cashier: 'Sarah Wilson', readAt: new Date('2024-01-14T17:00:00'), acknowledged: true },
        { branch: 'Mall Branch', cashier: 'Jane Doe', readAt: new Date('2024-01-14T17:15:00'), acknowledged: true },
        { branch: 'Mall Branch', cashier: 'Lisa Anderson', readAt: new Date('2024-01-14T17:30:00'), acknowledged: true },
      ],
      emailWebhook: false,
      status: 'sent',
    },
    {
      id: 'NOT003',
      title: 'System Maintenance Scheduled',
      body: 'Scheduled system maintenance will occur tonight from 11 PM to 2 AM. POS systems may experience brief interruptions. Please ensure all transactions are completed before 11 PM.',
      type: 'alert',
      createdBy: 'Sarah Johnson',
      createdAt: new Date('2024-01-13T14:00:00'),
      audience: {
        branches: ['All'],
        roles: ['Branch Manager'],
      },
      deliveryStatus: {
        sent: 4,
        delivered: 4,
        read: 3,
        total: 4,
      },
      readReceipts: [
        { branch: 'Downtown Branch', cashier: 'Manager A', readAt: new Date('2024-01-13T14:15:00'), acknowledged: true },
        { branch: 'Mall Branch', cashier: 'Manager B', readAt: new Date('2024-01-13T14:30:00'), acknowledged: true },
        { branch: 'Industrial Branch', cashier: 'Manager C', readAt: new Date('2024-01-13T15:00:00'), acknowledged: true },
      ],
      emailWebhook: true,
      status: 'sent',
    },
    {
      id: 'NOT004',
      title: 'New Product Categories Added',
      body: 'We have added new product categories: Insulation and Plumbing. Please familiarize yourself with the new inventory items and their pricing.',
      type: 'notice',
      createdBy: 'Lisa Anderson',
      createdAt: new Date('2024-01-12T11:00:00'),
      audience: {
        branches: ['Industrial Branch', 'Suburb Branch'],
        roles: ['Stock Manager', 'Cashier'],
      },
      deliveryStatus: {
        sent: 4,
        delivered: 4,
        read: 2,
        total: 4,
      },
      readReceipts: [
        { branch: 'Industrial Branch', cashier: 'Mike Johnson', readAt: new Date('2024-01-12T11:30:00'), acknowledged: false },
        { branch: 'Suburb Branch', cashier: 'David Chen', readAt: new Date('2024-01-12T12:00:00'), acknowledged: true },
      ],
      emailWebhook: false,
      status: 'sent',
    },
    {
      id: 'NOT005',
      title: 'Draft: Quarterly Inventory Review',
      body: 'Quarterly inventory review will be conducted next month. All branches must prepare their stock reports and reconciliation documents.',
      type: 'notice',
      createdBy: 'Sarah Johnson',
      createdAt: new Date('2024-01-15T15:30:00'),
      audience: {
        branches: ['All'],
        roles: ['Branch Manager', 'Stock Manager'],
      },
      deliveryStatus: {
        sent: 0,
        delivered: 0,
        read: 0,
        total: 6,
      },
      readReceipts: [],
      emailWebhook: false,
      status: 'draft',
    },
  ];

  // Filter notifications
  const filteredNotifications = useMemo(() => {
    let filtered = mockNotifications;

    if (filters.searchQuery) {
      filtered = filtered.filter(notification =>
        notification.title.toLowerCase().includes(filters.searchQuery.toLowerCase()) ||
        notification.body.toLowerCase().includes(filters.searchQuery.toLowerCase())
      );
    }

    if (filters.messageType !== 'all') {
      filtered = filtered.filter(notification => notification.type === filters.messageType);
    }

    if (filters.status !== 'all') {
      filtered = filtered.filter(notification => notification.status === filters.status);
    }

    if (filters.createdBy !== 'all') {
      filtered = filtered.filter(notification => notification.createdBy === filters.createdBy);
    }

    return filtered;
  }, [filters]);

  const handleFilterChange = (key: keyof FilterState, value: any) => {
    setFilters(prev => ({ ...prev, [key]: value }));
  };

  const handleBranchSelect = (branch: string) => {
    if (branch === 'All') {
      setComposeForm(prev => ({ ...prev, selectedBranches: ['All'] }));
    } else {
      setComposeForm(prev => {
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

  const handleRoleSelect = (role: string) => {
    if (role === 'All') {
      setComposeForm(prev => ({ ...prev, selectedRoles: ['All'] }));
    } else {
      setComposeForm(prev => {
        const filtered = prev.selectedRoles.filter(r => r !== 'All');
        if (filtered.includes(role)) {
          const newSelection = filtered.filter(r => r !== role);
          return { ...prev, selectedRoles: newSelection.length === 0 ? ['All'] : newSelection };
        } else {
          return { ...prev, selectedRoles: [...filtered, role] };
        }
      });
    }
  };

  const handleSelectNotification = (notificationId: string) => {
    setSelectedNotifications(prev => 
      prev.includes(notificationId) 
        ? prev.filter(id => id !== notificationId)
        : [...prev, notificationId]
    );
  };

  const handleSelectAll = () => {
    if (selectedNotifications.length === filteredNotifications.length) {
      setSelectedNotifications([]);
    } else {
      setSelectedNotifications(filteredNotifications.map(notification => notification.id));
    }
  };

  const validateForm = () => {
    if (!composeForm.title.trim()) {
      alert('Please enter a title');
      return false;
    }
    if (!composeForm.body.trim()) {
      alert('Please enter a message body');
      return false;
    }
    if (composeForm.selectedBranches.length === 0) {
      alert('Please select at least one branch');
      return false;
    }
    if (composeForm.selectedRoles.length === 0) {
      alert('Please select at least one role');
      return false;
    }
    return true;
  };

  const handleSendNotification = () => {
    if (!validateForm()) return;

    const audienceCount = calculateAudienceSize();
    alert(`Notification sent successfully to ${audienceCount} recipients!`);
    
    // Reset form
    setComposeForm({
      title: '',
      body: '',
      type: 'notice',
      selectedBranches: ['All'],
      selectedRoles: ['All'],
      emailWebhook: false,
      attachments: [],
    });
  };

  const handleSaveDraft = () => {
    if (!composeForm.title.trim()) {
      alert('Please enter a title to save draft');
      return;
    }
    alert('Draft saved successfully!');
  };

  const calculateAudienceSize = () => {
    // Mock calculation - in real app, this would query actual user counts
    const branchMultiplier = composeForm.selectedBranches.includes('All') ? 4 : composeForm.selectedBranches.length;
    const roleMultiplier = composeForm.selectedRoles.includes('All') ? 3 : composeForm.selectedRoles.length;
    return branchMultiplier * roleMultiplier;
  };

  const handleNotificationAction = (type: string, notification: Notification) => {
    setConfirmAction({
      type,
      notification,
      callback: () => {
        switch (type) {
          case 'resend':
            alert(`Resending notification: ${notification.title}`);
            break;
          case 'archive':
            alert(`Archived notification: ${notification.title}`);
            break;
          case 'delete':
            alert(`Deleted notification: ${notification.title}`);
            break;
        }
        setShowConfirmModal(false);
        setConfirmAction(null);
      }
    });
    setShowConfirmModal(true);
  };

  const handleViewReadReceipts = (notification: Notification) => {
    setSelectedNotification(notification);
    setShowReadReceipts(true);
  };

  const handleBulkArchive = () => {
    alert(`Archiving ${selectedNotifications.length} notifications...`);
    setSelectedNotifications([]);
  };

  const handleExportOutbox = () => {
    alert('Exporting outbox to CSV...');
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

  const getTypeColor = (type: string) => {
    switch (type) {
      case 'notice': return 'bg-blue-100 text-blue-800';
      case 'promotion': return 'bg-green-100 text-green-800';
      case 'policy': return 'bg-orange-100 text-orange-800';
      case 'alert': return 'bg-red-100 text-red-800';
      default: return 'bg-gray-100 text-gray-800';
    }
  };

  const getTypeIcon = (type: string) => {
    switch (type) {
      case 'notice': return <Bell className="w-3 h-3" />;
      case 'promotion': return <Megaphone className="w-3 h-3" />;
      case 'policy': return <Shield className="w-3 h-3" />;
      case 'alert': return <AlertTriangle className="w-3 h-3" />;
      default: return <Bell className="w-3 h-3" />;
    }
  };

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'sent': return 'bg-green-100 text-green-800';
      case 'draft': return 'bg-gray-100 text-gray-800';
      case 'archived': return 'bg-purple-100 text-purple-800';
      default: return 'bg-gray-100 text-gray-800';
    }
  };

  const getStatusIcon = (status: string) => {
    switch (status) {
      case 'sent': return <CheckCircle className="w-3 h-3" />;
      case 'draft': return <Clock className="w-3 h-3" />;
      case 'archived': return <Archive className="w-3 h-3" />;
      default: return <Clock className="w-3 h-3" />;
    }
  };

  const getReadRate = (notification: Notification) => {
    if (notification.deliveryStatus.total === 0) return 0;
    return Math.round((notification.deliveryStatus.read / notification.deliveryStatus.total) * 100);
  };

  return (
    <div className="p-6">
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-3xl font-bold text-gray-900">Notifications Center</h1>
          <p className="text-gray-600 mt-2">Send announcements and track delivery across all branches</p>
        </div>
        <div className="flex items-center space-x-3">
          <button
            onClick={handleExportOutbox}
            className="flex items-center space-x-2 px-4 py-2 bg-green-500 hover:bg-green-600 text-white rounded-lg transition-colors"
          >
            <FileText className="w-4 h-4" />
            <span>Export Outbox</span>
          </button>
        </div>
      </div>

      {/* Tab Navigation */}
      <div className="bg-white rounded-lg border border-gray-200 overflow-hidden mb-6">
        <div className="border-b border-gray-200">
          <nav className="flex space-x-8 px-6">
            <button
              onClick={() => setActiveTab('compose')}
              className={`py-4 px-1 border-b-2 font-medium text-sm ${
                activeTab === 'compose'
                  ? 'border-blue-500 text-blue-600'
                  : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'
              }`}
            >
              <div className="flex items-center space-x-2">
                <Plus className="w-4 h-4" />
                <span>Compose</span>
              </div>
            </button>
            <button
              onClick={() => setActiveTab('outbox')}
              className={`py-4 px-1 border-b-2 font-medium text-sm ${
                activeTab === 'outbox'
                  ? 'border-blue-500 text-blue-600'
                  : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'
              }`}
            >
              <div className="flex items-center space-x-2">
                <Send className="w-4 h-4" />
                <span>Outbox</span>
              </div>
            </button>
          </nav>
        </div>

        {/* Compose Tab */}
        {activeTab === 'compose' && (
          <div className="p-6">
            <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
              {/* Compose Form */}
              <div className="lg:col-span-2 space-y-6">
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">Message Title</label>
                  <input
                    type="text"
                    value={composeForm.title}
                    onChange={(e) => setComposeForm(prev => ({ ...prev, title: e.target.value }))}
                    placeholder="Enter notification title..."
                    className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                  />
                </div>

                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">Message Type</label>
                  <div className="grid grid-cols-2 md:grid-cols-4 gap-2">
                    {[
                      { id: 'notice', label: 'Notice', icon: Bell, color: 'blue' },
                      { id: 'promotion', label: 'Promotion', icon: Megaphone, color: 'green' },
                      { id: 'policy', label: 'Policy Update', icon: Shield, color: 'orange' },
                      { id: 'alert', label: 'System Alert', icon: AlertTriangle, color: 'red' },
                    ].map((type) => (
                      <button
                        key={type.id}
                        onClick={() => setComposeForm(prev => ({ ...prev, type: type.id as any }))}
                        className={`flex items-center space-x-2 p-3 border rounded-lg transition-colors ${
                          composeForm.type === type.id
                            ? `border-${type.color}-500 bg-${type.color}-50 text-${type.color}-700`
                            : 'border-gray-200 hover:bg-gray-50'
                        }`}
                      >
                        <type.icon className="w-4 h-4" />
                        <span className="text-sm font-medium">{type.label}</span>
                      </button>
                    ))}
                  </div>
                </div>

                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">Message Body</label>
                  <textarea
                    value={composeForm.body}
                    onChange={(e) => setComposeForm(prev => ({ ...prev, body: e.target.value }))}
                    rows={8}
                    placeholder="Enter your message here..."
                    className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                  />
                  <div className="flex items-center justify-between mt-2">
                    <div className="text-sm text-gray-500">
                      {composeForm.body.length} characters
                    </div>
                    <div className="flex items-center space-x-2">
                      <button className="text-sm text-blue-600 hover:text-blue-800">
                        <strong>Bold</strong>
                      </button>
                      <button className="text-sm text-blue-600 hover:text-blue-800">
                        <em>Italic</em>
                      </button>
                      <button className="text-sm text-blue-600 hover:text-blue-800">
                        • List
                      </button>
                    </div>
                  </div>
                </div>

                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">Attachments</label>
                  <div className="border-2 border-dashed border-gray-300 rounded-lg p-6 text-center">
                    <Paperclip className="w-8 h-8 text-gray-400 mx-auto mb-2" />
                    <p className="text-sm text-gray-500">Drag and drop files here, or click to browse</p>
                    <button className="mt-2 px-4 py-2 bg-gray-100 hover:bg-gray-200 text-gray-700 rounded-lg transition-colors">
                      Choose Files
                    </button>
                  </div>
                </div>

                <div>
                  <label className="flex items-center space-x-2">
                    <input
                      type="checkbox"
                      checked={composeForm.emailWebhook}
                      onChange={(e) => setComposeForm(prev => ({ ...prev, emailWebhook: e.target.checked }))}
                      className="rounded border-gray-300 text-blue-600 focus:ring-blue-500"
                    />
                    <span className="text-sm text-gray-700">Send email notifications</span>
                  </label>
                  <p className="text-xs text-gray-500 mt-1">
                    Also send notifications via email webhook to branch managers
                  </p>
                </div>
              </div>

              {/* Audience Selection */}
              <div className="space-y-6">
                <div>
                  <h3 className="text-lg font-semibold text-gray-900 mb-4 flex items-center space-x-2">
                    <Target className="w-5 h-5 text-blue-600" />
                    <span>Audience</span>
                  </h3>

                  <div className="mb-4">
                    <label className="block text-sm font-medium text-gray-700 mb-2">Target Branches</label>
                    <div className="space-y-2">
                      {['All', ...branches].map(branch => (
                        <label key={branch} className="flex items-center space-x-2">
                          <input
                            type="checkbox"
                            checked={composeForm.selectedBranches.includes(branch)}
                            onChange={() => handleBranchSelect(branch)}
                            className="rounded border-gray-300 text-blue-600 focus:ring-blue-500"
                          />
                          <span className="text-sm text-gray-700">{branch}</span>
                        </label>
                      ))}
                    </div>
                  </div>

                  <div className="mb-4">
                    <label className="block text-sm font-medium text-gray-700 mb-2">Target Roles</label>
                    <div className="space-y-2">
                      {['All', ...roles].map(role => (
                        <label key={role} className="flex items-center space-x-2">
                          <input
                            type="checkbox"
                            checked={composeForm.selectedRoles.includes(role)}
                            onChange={() => handleRoleSelect(role)}
                            className="rounded border-gray-300 text-blue-600 focus:ring-blue-500"
                          />
                          <span className="text-sm text-gray-700">{role}</span>
                        </label>
                      ))}
                    </div>
                  </div>

                  <div className="bg-blue-50 border border-blue-200 rounded-lg p-4">
                    <div className="flex items-center space-x-2 mb-2">
                      <Users className="w-4 h-4 text-blue-600" />
                      <span className="text-sm font-medium text-blue-800">Estimated Audience</span>
                    </div>
                    <div className="text-2xl font-bold text-blue-900">{calculateAudienceSize()} recipients</div>
                    <div className="text-sm text-blue-700 mt-1">
                      {composeForm.selectedBranches.join(', ')} • {composeForm.selectedRoles.join(', ')}
                    </div>
                  </div>
                </div>

                {/* Preview */}
                <div>
                  <h3 className="text-lg font-semibold text-gray-900 mb-4">Preview</h3>
                  <div className="border border-gray-200 rounded-lg p-4 bg-gray-50">
                    <div className="flex items-center space-x-2 mb-3">
                      <span className={`inline-flex items-center space-x-1 px-2.5 py-0.5 rounded-full text-xs font-medium ${getTypeColor(composeForm.type)}`}>
                        {getTypeIcon(composeForm.type)}
                        <span className="capitalize">{composeForm.type}</span>
                      </span>
                      {composeForm.emailWebhook && (
                        <span className="inline-flex items-center space-x-1 px-2.5 py-0.5 rounded-full text-xs font-medium bg-purple-100 text-purple-800">
                          <Mail className="w-3 h-3" />
                          <span>Email</span>
                        </span>
                      )}
                    </div>
                    <h4 className="font-semibold text-gray-900 mb-2">
                      {composeForm.title || 'Notification Title'}
                    </h4>
                    <p className="text-sm text-gray-700 whitespace-pre-wrap">
                      {composeForm.body || 'Your message will appear here...'}
                    </p>
                    <div className="mt-3 pt-3 border-t border-gray-300 text-xs text-gray-500">
                      From: Head Office • {new Date().toLocaleString()}
                    </div>
                  </div>
                </div>

                {/* Action Buttons */}
                <div className="flex items-center space-x-3">
                  <button
                    onClick={handleSendNotification}
                    className="flex items-center space-x-2 px-6 py-3 bg-blue-500 hover:bg-blue-600 text-white rounded-lg transition-colors"
                  >
                    <Send className="w-4 h-4" />
                    <span>Send Notification</span>
                  </button>
                  <button
                    onClick={handleSaveDraft}
                    className="flex items-center space-x-2 px-6 py-3 bg-gray-500 hover:bg-gray-600 text-white rounded-lg transition-colors"
                  >
                    <FileText className="w-4 h-4" />
                    <span>Save Draft</span>
                  </button>
                  <button
                    onClick={() => setShowPreview(true)}
                    className="flex items-center space-x-2 px-6 py-3 bg-purple-500 hover:bg-purple-600 text-white rounded-lg transition-colors"
                  >
                    <Eye className="w-4 h-4" />
                    <span>Full Preview</span>
                  </button>
                </div>
              </div>
            </div>
          </div>
        )}

        {/* Outbox Tab */}
        {activeTab === 'outbox' && (
          <>
            {/* Filters */}
            <div className="p-4 border-b border-gray-200">
              <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
                <div className="relative">
                  <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 text-gray-400 w-4 h-4" />
                  <input
                    type="text"
                    placeholder="Search notifications..."
                    value={filters.searchQuery}
                    onChange={(e) => handleFilterChange('searchQuery', e.target.value)}
                    className="pl-10 pr-4 py-2 w-full border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                  />
                </div>

                <select
                  value={filters.messageType}
                  onChange={(e) => handleFilterChange('messageType', e.target.value)}
                  className="px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                >
                  <option value="all">All Types</option>
                  <option value="notice">Notice</option>
                  <option value="promotion">Promotion</option>
                  <option value="policy">Policy Update</option>
                  <option value="alert">System Alert</option>
                </select>

                <select
                  value={filters.status}
                  onChange={(e) => handleFilterChange('status', e.target.value)}
                  className="px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                >
                  <option value="all">All Status</option>
                  <option value="draft">Draft</option>
                  <option value="sent">Sent</option>
                  <option value="archived">Archived</option>
                </select>

                <select
                  value={filters.createdBy}
                  onChange={(e) => handleFilterChange('createdBy', e.target.value)}
                  className="px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                >
                  <option value="all">All Creators</option>
                  {creators.map(creator => (
                    <option key={creator} value={creator}>{creator}</option>
                  ))}
                </select>
              </div>
            </div>

            {/* Bulk Actions Bar */}
            {selectedNotifications.length > 0 && (
              <div className="bg-blue-50 border-b border-blue-200 px-6 py-3">
                <div className="flex items-center justify-between">
                  <span className="text-sm text-blue-700">
                    {selectedNotifications.length} notification{selectedNotifications.length !== 1 ? 's' : ''} selected
                  </span>
                  <div className="flex items-center space-x-2">
                    <button
                      onClick={handleBulkArchive}
                      className="px-3 py-1 bg-purple-500 hover:bg-purple-600 text-white text-sm rounded transition-colors"
                    >
                      Bulk Archive
                    </button>
                    <button
                      onClick={() => setSelectedNotifications([])}
                      className="px-3 py-1 bg-gray-500 hover:bg-gray-600 text-white text-sm rounded transition-colors"
                    >
                      Clear Selection
                    </button>
                  </div>
                </div>
              </div>
            )}

            {/* Notifications Table */}
            <div className="overflow-x-auto">
              <table className="w-full">
                <thead className="bg-gray-50 border-b border-gray-200">
                  <tr>
                    <th className="px-6 py-3 text-left">
                      <input
                        type="checkbox"
                        checked={selectedNotifications.length === filteredNotifications.length && filteredNotifications.length > 0}
                        onChange={handleSelectAll}
                        className="rounded border-gray-300 text-blue-600 focus:ring-blue-500"
                      />
                    </th>
                    <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Message</th>
                    <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Type</th>
                    <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Created By</th>
                    <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Audience</th>
                    <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Sent Time</th>
                    <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Read Rate</th>
                    <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Status</th>
                    <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Actions</th>
                  </tr>
                </thead>
                <tbody className="bg-white divide-y divide-gray-200">
                  {filteredNotifications.map((notification) => (
                    <tr key={notification.id} className="hover:bg-gray-50">
                      <td className="px-6 py-4 whitespace-nowrap">
                        <input
                          type="checkbox"
                          checked={selectedNotifications.includes(notification.id)}
                          onChange={() => handleSelectNotification(notification.id)}
                          className="rounded border-gray-300 text-blue-600 focus:ring-blue-500"
                        />
                      </td>
                      <td className="px-6 py-4">
                        <div className="max-w-xs">
                          <div className="text-sm font-medium text-gray-900 truncate">{notification.title}</div>
                          <div className="text-sm text-gray-500 truncate">{notification.body}</div>
                        </div>
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap">
                        <span className={`inline-flex items-center space-x-1 px-2.5 py-0.5 rounded-full text-xs font-medium ${getTypeColor(notification.type)}`}>
                          {getTypeIcon(notification.type)}
                          <span className="capitalize">{notification.type}</span>
                        </span>
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">{notification.createdBy}</td>
                      <td className="px-6 py-4 whitespace-nowrap">
                        <div className="text-sm text-gray-900">
                          {notification.audience.branches.join(', ')}
                        </div>
                        <div className="text-xs text-gray-500">
                          {notification.audience.roles.join(', ')}
                        </div>
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                        {notification.status === 'sent' ? formatTime(notification.createdAt) : '-'}
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap">
                        {notification.status === 'sent' ? (
                          <div className="text-sm">
                            <div className="font-medium text-gray-900">{getReadRate(notification)}%</div>
                            <div className="text-xs text-gray-500">
                              {notification.deliveryStatus.read}/{notification.deliveryStatus.total} read
                            </div>
                          </div>
                        ) : (
                          <span className="text-sm text-gray-400">-</span>
                        )}
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap">
                        <span className={`inline-flex items-center space-x-1 px-2.5 py-0.5 rounded-full text-xs font-medium ${getStatusColor(notification.status)}`}>
                          {getStatusIcon(notification.status)}
                          <span className="capitalize">{notification.status}</span>
                        </span>
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                        <div className="flex items-center space-x-2">
                          <button
                            onClick={() => handleViewReadReceipts(notification)}
                            className="text-blue-600 hover:text-blue-800 transition-colors"
                            title="View Read Receipts"
                          >
                            <Eye className="w-4 h-4" />
                          </button>
                          {notification.status === 'sent' && (
                            <button
                              onClick={() => handleNotificationAction('resend', notification)}
                              className="text-green-600 hover:text-green-800 transition-colors"
                              title="Resend"
                            >
                              <RefreshCw className="w-4 h-4" />
                            </button>
                          )}
                          <button
                            onClick={() => handleNotificationAction('archive', notification)}
                            className="text-purple-600 hover:text-purple-800 transition-colors"
                            title="Archive"
                          >
                            <Archive className="w-4 h-4" />
                          </button>
                          <button
                            onClick={() => handleNotificationAction('delete', notification)}
                            className="text-red-600 hover:text-red-800 transition-colors"
                            title="Delete"
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

            {filteredNotifications.length === 0 && (
              <div className="text-center py-12">
                <div className="text-gray-500 text-lg">No notifications found</div>
                <div className="text-gray-400 text-sm mt-2">
                  Try adjusting your filters or create a new notification
                </div>
              </div>
            )}
          </>
        )}
      </div>

      {/* Read Receipts Drawer */}
      {showReadReceipts && selectedNotification && (
        <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-end z-50">
          <div className="bg-white h-full w-full max-w-2xl shadow-xl flex flex-col">
            <div className="flex items-center justify-between p-6 border-b border-gray-200">
              <h3 className="text-xl font-semibold text-gray-900">Read Receipts - {selectedNotification.title}</h3>
              <button
                onClick={() => setShowReadReceipts(false)}
                className="text-gray-400 hover:text-gray-600 transition-colors"
              >
                <X className="w-6 h-6" />
              </button>
            </div>
            
            <div className="flex-1 overflow-y-auto p-6">
              {/* Delivery Summary */}
              <div className="grid grid-cols-1 md:grid-cols-4 gap-4 mb-6">
                <div className="bg-blue-50 border border-blue-200 rounded-lg p-4">
                  <div className="text-blue-600 text-sm font-medium">Sent</div>
                  <div className="text-2xl font-bold text-blue-900">{selectedNotification.deliveryStatus.sent}</div>
                </div>
                <div className="bg-green-50 border border-green-200 rounded-lg p-4">
                  <div className="text-green-600 text-sm font-medium">Delivered</div>
                  <div className="text-2xl font-bold text-green-900">{selectedNotification.deliveryStatus.delivered}</div>
                </div>
                <div className="bg-purple-50 border border-purple-200 rounded-lg p-4">
                  <div className="text-purple-600 text-sm font-medium">Read</div>
                  <div className="text-2xl font-bold text-purple-900">{selectedNotification.deliveryStatus.read}</div>
                </div>
                <div className="bg-orange-50 border border-orange-200 rounded-lg p-4">
                  <div className="text-orange-600 text-sm font-medium">Read Rate</div>
                  <div className="text-2xl font-bold text-orange-900">{getReadRate(selectedNotification)}%</div>
                </div>
              </div>

              {/* Read Receipts List */}
              <div>
                <h4 className="text-lg font-semibold text-gray-900 mb-4">Individual Read Receipts</h4>
                <div className="space-y-3">
                  {selectedNotification.readReceipts.map((receipt, index) => (
                    <div key={index} className="flex items-center justify-between p-4 bg-gray-50 rounded-lg">
                      <div className="flex items-center space-x-3">
                        <div className="w-10 h-10 bg-blue-100 rounded-full flex items-center justify-center">
                          <Users className="w-5 h-5 text-blue-600" />
                        </div>
                        <div>
                          <div className="text-sm font-medium text-gray-900">{receipt.cashier}</div>
                          <div className="text-sm text-gray-500">{receipt.branch}</div>
                        </div>
                      </div>
                      <div className="text-right">
                        <div className="text-sm text-gray-900">{formatTime(receipt.readAt)}</div>
                        <div className={`text-xs ${receipt.acknowledged ? 'text-green-600' : 'text-orange-600'}`}>
                          {receipt.acknowledged ? 'Acknowledged' : 'Not Acknowledged'}
                        </div>
                      </div>
                    </div>
                  ))}
                </div>

                {selectedNotification.readReceipts.length === 0 && (
                  <div className="text-center py-8">
                    <MessageSquare className="w-12 h-12 text-gray-400 mx-auto mb-4" />
                    <div className="text-gray-500">No read receipts yet</div>
                    <div className="text-gray-400 text-sm mt-2">
                      Recipients will appear here once they read the notification
                    </div>
                  </div>
                )}
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Full Preview Modal */}
      {showPreview && (
        <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
          <div className="bg-white rounded-lg shadow-xl max-w-2xl w-full mx-4 max-h-[80vh] overflow-y-auto">
            <div className="flex items-center justify-between p-6 border-b border-gray-200">
              <h3 className="text-xl font-semibold text-gray-900">Notification Preview</h3>
              <button
                onClick={() => setShowPreview(false)}
                className="text-gray-400 hover:text-gray-600 transition-colors"
              >
                <X className="w-6 h-6" />
              </button>
            </div>
            
            <div className="p-6">
              <div className="bg-gray-50 rounded-lg p-6 border border-gray-200">
                <div className="flex items-center space-x-2 mb-4">
                  <span className={`inline-flex items-center space-x-1 px-3 py-1 rounded-full text-sm font-medium ${getTypeColor(composeForm.type)}`}>
                    {getTypeIcon(composeForm.type)}
                    <span className="capitalize">{composeForm.type}</span>
                  </span>
                  {composeForm.emailWebhook && (
                    <span className="inline-flex items-center space-x-1 px-3 py-1 rounded-full text-sm font-medium bg-purple-100 text-purple-800">
                      <Mail className="w-4 h-4" />
                      <span>Email Enabled</span>
                    </span>
                  )}
                </div>
                
                <h2 className="text-2xl font-bold text-gray-900 mb-4">
                  {composeForm.title || 'Notification Title'}
                </h2>
                
                <div className="prose prose-sm max-w-none mb-6">
                  <p className="text-gray-700 whitespace-pre-wrap">
                    {composeForm.body || 'Your message will appear here...'}
                  </p>
                </div>

                <div className="border-t border-gray-300 pt-4">
                  <div className="grid grid-cols-1 md:grid-cols-2 gap-4 text-sm">
                    <div>
                      <span className="text-gray-500">Target Branches:</span>
                      <p className="font-medium text-gray-900">{composeForm.selectedBranches.join(', ')}</p>
                    </div>
                    <div>
                      <span className="text-gray-500">Target Roles:</span>
                      <p className="font-medium text-gray-900">{composeForm.selectedRoles.join(', ')}</p>
                    </div>
                    <div>
                      <span className="text-gray-500">Estimated Recipients:</span>
                      <p className="font-medium text-gray-900">{calculateAudienceSize()} users</p>
                    </div>
                    <div>
                      <span className="text-gray-500">Created:</span>
                      <p className="font-medium text-gray-900">{new Date().toLocaleString()}</p>
                    </div>
                  </div>
                </div>
              </div>
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
                    {confirmAction.type === 'resend' && `Resend notification: ${confirmAction.notification?.title}`}
                    {confirmAction.type === 'archive' && `Archive notification: ${confirmAction.notification?.title}`}
                    {confirmAction.type === 'delete' && `Delete notification: ${confirmAction.notification?.title}`}
                  </p>
                  <p className="text-sm text-orange-600">
                    {confirmAction.type === 'delete' ? 'This action cannot be undone.' : 'This action will affect all recipients.'}
                  </p>
                </div>
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
                className={`px-4 py-2 text-sm font-medium text-white rounded-lg transition-colors ${
                  confirmAction.type === 'delete' ? 'bg-red-500 hover:bg-red-600' : 'bg-blue-500 hover:bg-blue-600'
                }`}
              >
                {confirmAction.type === 'resend' && 'Resend'}
                {confirmAction.type === 'archive' && 'Archive'}
                {confirmAction.type === 'delete' && 'Delete'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};