import React, { useState } from 'react';
import { 
  Building2, 
  Percent, 
  CreditCard, 
  RefreshCw, 
  Database, 
  QrCode,
  Save,
  Eye,
  EyeOff,
  Upload,
  Download,
  Check,
  AlertTriangle,
  Settings as SettingsIcon,
  Palette,
  Shield,
  Globe,
  Clock,
  FileText,
  Key,
  Webhook,
  HardDrive
} from 'lucide-react';

interface CompanyProfile {
  name: string;
  logo: string;
  taxId: string;
  address: string;
  phone: string;
  email: string;
  website: string;
  brandingColors: {
    primary: string;
    secondary: string;
    accent: string;
  };
}

interface TaxDiscountPolicy {
  vatRate: number;
  roundingPolicy: 'nearest' | 'up' | 'down';
  maxDiscountPercent: number;
  maxDiscountAmount: number;
  requireApprovalAbove: number;
  managerOverrideLimit: number;
}

interface PaymentIntegration {
  id: string;
  name: string;
  enabled: boolean;
  apiKey: string;
  secretKey: string;
  webhookUrl: string;
  testMode: boolean;
}

interface SyncSettings {
  branchSyncInterval: number; // minutes
  conflictResolution: 'branch-wins' | 'hq-wins' | 'manual';
  webhookEndpoint: string;
  retryAttempts: number;
  timeoutSeconds: number;
  enableRealTimeSync: boolean;
}

interface BackupSettings {
  autoBackupEnabled: boolean;
  backupSchedule: string; // cron format
  retentionDays: number;
  storageProvider: 'aws-s3' | 'google-cloud' | 'azure';
  bucketName: string;
  encryptionEnabled: boolean;
}

interface QRCodeTemplate {
  labelSize: 'small' | 'medium' | 'large';
  fontSize: number;
  fontFamily: string;
  priceFormat: 'with-currency' | 'number-only';
  includeBarcode: boolean;
  includeLogo: boolean;
  backgroundColor: string;
  textColor: string;
}

export const Settings: React.FC = () => {
  const [activeSection, setActiveSection] = useState('company');
  const [hasChanges, setHasChanges] = useState(false);
  const [showSuccess, setShowSuccess] = useState(false);
  const [maskedFields, setMaskedFields] = useState<Record<string, boolean>>({
    'payment-cash-key': true,
    'payment-card-key': true,
    'payment-transfer-key': true,
    'webhook-endpoint': true,
    'backup-credentials': true,
  });

  // Mock data - in real app, this would come from API
  const [companyProfile, setCompanyProfile] = useState<CompanyProfile>({
    name: 'ConstructMart Co., Ltd.',
    logo: '/logo.png',
    taxId: '0123456789012',
    address: '123 Business District, Bangkok 10500, Thailand',
    phone: '+66 2 123 4567',
    email: 'info@constructmart.com',
    website: 'https://constructmart.com',
    brandingColors: {
      primary: '#3B82F6',
      secondary: '#6B7280',
      accent: '#10B981',
    },
  });

  const [taxPolicy, setTaxPolicy] = useState<TaxDiscountPolicy>({
    vatRate: 7.0,
    roundingPolicy: 'nearest',
    maxDiscountPercent: 20,
    maxDiscountAmount: 5000,
    requireApprovalAbove: 1000,
    managerOverrideLimit: 10000,
  });

  const [paymentIntegrations, setPaymentIntegrations] = useState<PaymentIntegration[]>([
    {
      id: 'cash',
      name: 'Cash Payments',
      enabled: true,
      apiKey: '',
      secretKey: '',
      webhookUrl: '',
      testMode: false,
    },
    {
      id: 'card',
      name: 'Credit/Debit Cards',
      enabled: true,
      apiKey: 'pk_live_51H*********************',
      secretKey: 'sk_live_51H*********************',
      webhookUrl: 'https://api.constructmart.com/webhooks/stripe',
      testMode: false,
    },
    {
      id: 'transfer',
      name: 'Bank Transfer',
      enabled: true,
      apiKey: 'bt_api_key_*********************',
      secretKey: 'bt_secret_*********************',
      webhookUrl: 'https://api.constructmart.com/webhooks/bank',
      testMode: false,
    },
    {
      id: 'paylater',
      name: 'PayLater Service',
      enabled: false,
      apiKey: 'pl_api_*********************',
      secretKey: 'pl_secret_*********************',
      webhookUrl: 'https://api.constructmart.com/webhooks/paylater',
      testMode: true,
    },
  ]);

  const [syncSettings, setSyncSettings] = useState<SyncSettings>({
    branchSyncInterval: 15,
    conflictResolution: 'hq-wins',
    webhookEndpoint: 'https://api.constructmart.com/webhooks/branch-sync',
    retryAttempts: 3,
    timeoutSeconds: 30,
    enableRealTimeSync: true,
  });

  const [backupSettings, setBackupSettings] = useState<BackupSettings>({
    autoBackupEnabled: true,
    backupSchedule: '0 2 * * *', // Daily at 2 AM
    retentionDays: 90,
    storageProvider: 'aws-s3',
    bucketName: 'constructmart-backups',
    encryptionEnabled: true,
  });

  const [qrTemplate, setQRTemplate] = useState<QRCodeTemplate>({
    labelSize: 'medium',
    fontSize: 12,
    fontFamily: 'Arial',
    priceFormat: 'with-currency',
    includeBarcode: true,
    includeLogo: true,
    backgroundColor: '#FFFFFF',
    textColor: '#000000',
  });

  const sections = [
    { id: 'company', label: 'Company Profile', icon: Building2 },
    { id: 'tax', label: 'Tax & Discounts', icon: Percent },
    { id: 'payments', label: 'Payment Integrations', icon: CreditCard },
    { id: 'sync', label: 'Sync Settings', icon: RefreshCw },
    { id: 'backups', label: 'Backups', icon: Database },
  ];

  const handleSave = () => {
    // In real app, this would save to API
    setHasChanges(false);
    setShowSuccess(true);
    setTimeout(() => setShowSuccess(false), 3000);
  };

  const toggleFieldVisibility = (fieldId: string) => {
    setMaskedFields(prev => ({
      ...prev,
      [fieldId]: !prev[fieldId]
    }));
  };

  const maskValue = (value: string, show: boolean) => {
    if (show || !value) return value;
    return '*'.repeat(Math.min(value.length, 20));
  };

  const handleManualBackup = () => {
    alert('Manual backup initiated. You will receive an email when complete.');
  };

  const handleTestWebhook = (endpoint: string) => {
    alert(`Testing webhook: ${endpoint}`);
  };

  const handleUploadLogo = () => {
    alert('Logo upload functionality would be implemented here');
  };

  return (
    <div className="p-6">
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-3xl font-bold text-gray-900">System Settings</h1>
          <p className="text-gray-600 mt-2">Configure system-wide settings and integrations</p>
        </div>
        <div className="flex items-center space-x-3">
          {hasChanges && (
            <span className="text-sm text-orange-600 flex items-center space-x-1">
              <AlertTriangle className="w-4 h-4" />
              <span>Unsaved changes</span>
            </span>
          )}
          <button
            onClick={handleSave}
            disabled={!hasChanges}
            className="flex items-center space-x-2 px-4 py-2 bg-blue-500 hover:bg-blue-600 disabled:bg-gray-300 disabled:cursor-not-allowed text-white rounded-lg transition-colors"
          >
            <Save className="w-4 h-4" />
            <span>Save Changes</span>
          </button>
        </div>
      </div>

      {/* Success Toast */}
      {showSuccess && (
        <div className="fixed top-4 right-4 bg-green-500 text-white px-6 py-3 rounded-lg shadow-lg flex items-center space-x-2 z-50">
          <Check className="w-5 h-5" />
          <span>Settings saved successfully!</span>
        </div>
      )}

      <div className="flex gap-6">
        {/* Sidebar Navigation */}
        <div className="w-64 bg-white rounded-lg border border-gray-200 p-4">
          <nav className="space-y-2">
            {sections.map((section) => (
              <button
                key={section.id}
                onClick={() => setActiveSection(section.id)}
                className={`w-full flex items-center space-x-3 px-3 py-2 rounded-lg text-left transition-colors ${
                  activeSection === section.id
                    ? 'bg-blue-50 text-blue-700 border-r-2 border-blue-700'
                    : 'text-gray-700 hover:bg-gray-100'
                }`}
              >
                <section.icon className="w-5 h-5" />
                <span className="font-medium">{section.label}</span>
              </button>
            ))}
          </nav>
        </div>

        {/* Main Content */}
        <div className="flex-1 bg-white rounded-lg border border-gray-200 p-6">
          {/* Company Profile */}
          {activeSection === 'company' && (
            <div className="space-y-6">
              <div className="flex items-center space-x-3 mb-6">
                <Building2 className="w-6 h-6 text-blue-600" />
                <h2 className="text-xl font-semibold text-gray-900">Company Profile</h2>
              </div>

              <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">Company Name</label>
                  <input
                    type="text"
                    value={companyProfile.name}
                    onChange={(e) => {
                      setCompanyProfile(prev => ({ ...prev, name: e.target.value }));
                      setHasChanges(true);
                    }}
                    className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                  />
                </div>

                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">Tax ID</label>
                  <input
                    type="text"
                    value={companyProfile.taxId}
                    onChange={(e) => {
                      setCompanyProfile(prev => ({ ...prev, taxId: e.target.value }));
                      setHasChanges(true);
                    }}
                    className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                  />
                </div>

                <div className="md:col-span-2">
                  <label className="block text-sm font-medium text-gray-700 mb-2">Address</label>
                  <textarea
                    value={companyProfile.address}
                    onChange={(e) => {
                      setCompanyProfile(prev => ({ ...prev, address: e.target.value }));
                      setHasChanges(true);
                    }}
                    rows={3}
                    className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                  />
                </div>

                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">Phone</label>
                  <input
                    type="text"
                    value={companyProfile.phone}
                    onChange={(e) => {
                      setCompanyProfile(prev => ({ ...prev, phone: e.target.value }));
                      setHasChanges(true);
                    }}
                    className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                  />
                </div>

                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">Email</label>
                  <input
                    type="email"
                    value={companyProfile.email}
                    onChange={(e) => {
                      setCompanyProfile(prev => ({ ...prev, email: e.target.value }));
                      setHasChanges(true);
                    }}
                    className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                  />
                </div>
              </div>

              {/* Logo Upload */}
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">Company Logo</label>
                <div className="flex items-center space-x-4">
                  <div className="w-16 h-16 bg-gray-100 rounded-lg flex items-center justify-center">
                    <Building2 className="w-8 h-8 text-gray-400" />
                  </div>
                  <button
                    onClick={handleUploadLogo}
                    className="flex items-center space-x-2 px-4 py-2 bg-gray-100 hover:bg-gray-200 text-gray-700 rounded-lg transition-colors"
                  >
                    <Upload className="w-4 h-4" />
                    <span>Upload Logo</span>
                  </button>
                </div>
              </div>

              {/* Branding Colors */}
              <div>
                <h3 className="text-lg font-semibold text-gray-900 mb-4 flex items-center space-x-2">
                  <Palette className="w-5 h-5" />
                  <span>Branding Colors</span>
                </h3>
                <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                  <div>
                    <label className="block text-sm font-medium text-gray-700 mb-2">Primary Color</label>
                    <div className="flex items-center space-x-2">
                      <input
                        type="color"
                        value={companyProfile.brandingColors.primary}
                        onChange={(e) => {
                          setCompanyProfile(prev => ({
                            ...prev,
                            brandingColors: { ...prev.brandingColors, primary: e.target.value }
                          }));
                          setHasChanges(true);
                        }}
                        className="w-12 h-10 border border-gray-300 rounded cursor-pointer"
                      />
                      <input
                        type="text"
                        value={companyProfile.brandingColors.primary}
                        onChange={(e) => {
                          setCompanyProfile(prev => ({
                            ...prev,
                            brandingColors: { ...prev.brandingColors, primary: e.target.value }
                          }));
                          setHasChanges(true);
                        }}
                        className="flex-1 px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                      />
                    </div>
                  </div>

                  <div>
                    <label className="block text-sm font-medium text-gray-700 mb-2">Secondary Color</label>
                    <div className="flex items-center space-x-2">
                      <input
                        type="color"
                        value={companyProfile.brandingColors.secondary}
                        onChange={(e) => {
                          setCompanyProfile(prev => ({
                            ...prev,
                            brandingColors: { ...prev.brandingColors, secondary: e.target.value }
                          }));
                          setHasChanges(true);
                        }}
                        className="w-12 h-10 border border-gray-300 rounded cursor-pointer"
                      />
                      <input
                        type="text"
                        value={companyProfile.brandingColors.secondary}
                        onChange={(e) => {
                          setCompanyProfile(prev => ({
                            ...prev,
                            brandingColors: { ...prev.brandingColors, secondary: e.target.value }
                          }));
                          setHasChanges(true);
                        }}
                        className="flex-1 px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                      />
                    </div>
                  </div>

                  <div>
                    <label className="block text-sm font-medium text-gray-700 mb-2">Accent Color</label>
                    <div className="flex items-center space-x-2">
                      <input
                        type="color"
                        value={companyProfile.brandingColors.accent}
                        onChange={(e) => {
                          setCompanyProfile(prev => ({
                            ...prev,
                            brandingColors: { ...prev.brandingColors, accent: e.target.value }
                          }));
                          setHasChanges(true);
                        }}
                        className="w-12 h-10 border border-gray-300 rounded cursor-pointer"
                      />
                      <input
                        type="text"
                        value={companyProfile.brandingColors.accent}
                        onChange={(e) => {
                          setCompanyProfile(prev => ({
                            ...prev,
                            brandingColors: { ...prev.brandingColors, accent: e.target.value }
                          }));
                          setHasChanges(true);
                        }}
                        className="flex-1 px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                      />
                    </div>
                  </div>
                </div>
              </div>
            </div>
          )}

          {/* Tax & Discount Policy */}
          {activeSection === 'tax' && (
            <div className="space-y-6">
              <div className="flex items-center space-x-3 mb-6">
                <Percent className="w-6 h-6 text-green-600" />
                <h2 className="text-xl font-semibold text-gray-900">Tax & Discount Policy</h2>
              </div>

              <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">VAT Rate (%)</label>
                  <input
                    type="number"
                    step="0.1"
                    value={taxPolicy.vatRate}
                    onChange={(e) => {
                      setTaxPolicy(prev => ({ ...prev, vatRate: parseFloat(e.target.value) || 0 }));
                      setHasChanges(true);
                    }}
                    className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                  />
                </div>

                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">Rounding Policy</label>
                  <select
                    value={taxPolicy.roundingPolicy}
                    onChange={(e) => {
                      setTaxPolicy(prev => ({ ...prev, roundingPolicy: e.target.value as any }));
                      setHasChanges(true);
                    }}
                    className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                  >
                    <option value="nearest">Round to Nearest</option>
                    <option value="up">Round Up</option>
                    <option value="down">Round Down</option>
                  </select>
                </div>

                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">Max Discount (%)</label>
                  <input
                    type="number"
                    value={taxPolicy.maxDiscountPercent}
                    onChange={(e) => {
                      setTaxPolicy(prev => ({ ...prev, maxDiscountPercent: parseInt(e.target.value) || 0 }));
                      setHasChanges(true);
                    }}
                    className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                  />
                </div>

                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">Max Discount Amount (฿)</label>
                  <input
                    type="number"
                    value={taxPolicy.maxDiscountAmount}
                    onChange={(e) => {
                      setTaxPolicy(prev => ({ ...prev, maxDiscountAmount: parseInt(e.target.value) || 0 }));
                      setHasChanges(true);
                    }}
                    className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                  />
                </div>

                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">Require Approval Above (฿)</label>
                  <input
                    type="number"
                    value={taxPolicy.requireApprovalAbove}
                    onChange={(e) => {
                      setTaxPolicy(prev => ({ ...prev, requireApprovalAbove: parseInt(e.target.value) || 0 }));
                      setHasChanges(true);
                    }}
                    className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                  />
                </div>

                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">Manager Override Limit (฿)</label>
                  <input
                    type="number"
                    value={taxPolicy.managerOverrideLimit}
                    onChange={(e) => {
                      setTaxPolicy(prev => ({ ...prev, managerOverrideLimit: parseInt(e.target.value) || 0 }));
                      setHasChanges(true);
                    }}
                    className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                  />
                </div>
              </div>
            </div>
          )}

          {/* Payment Integrations */}
          {activeSection === 'payments' && (
            <div className="space-y-6">
              <div className="flex items-center space-x-3 mb-6">
                <CreditCard className="w-6 h-6 text-purple-600" />
                <h2 className="text-xl font-semibold text-gray-900">Payment Integrations</h2>
              </div>

              <div className="space-y-6">
                {paymentIntegrations.map((integration) => (
                  <div key={integration.id} className="border border-gray-200 rounded-lg p-6">
                    <div className="flex items-center justify-between mb-4">
                      <div className="flex items-center space-x-3">
                        <div className={`w-3 h-3 rounded-full ${integration.enabled ? 'bg-green-500' : 'bg-gray-300'}`}></div>
                        <h3 className="text-lg font-semibold text-gray-900">{integration.name}</h3>
                        {integration.testMode && (
                          <span className="px-2 py-1 bg-yellow-100 text-yellow-800 text-xs font-medium rounded-full">
                            Test Mode
                          </span>
                        )}
                      </div>
                      <label className="flex items-center">
                        <input
                          type="checkbox"
                          checked={integration.enabled}
                          onChange={(e) => {
                            setPaymentIntegrations(prev => prev.map(p => 
                              p.id === integration.id ? { ...p, enabled: e.target.checked } : p
                            ));
                            setHasChanges(true);
                          }}
                          className="rounded border-gray-300 text-blue-600 focus:ring-blue-500"
                        />
                        <span className="ml-2 text-sm text-gray-700">Enabled</span>
                      </label>
                    </div>

                    {integration.enabled && integration.apiKey && (
                      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                        <div>
                          <label className="block text-sm font-medium text-gray-700 mb-2">API Key</label>
                          <div className="flex items-center space-x-2">
                            <input
                              type="text"
                              value={maskValue(integration.apiKey, !maskedFields[`payment-${integration.id}-key`])}
                              readOnly
                              className="flex-1 px-3 py-2 border border-gray-300 rounded-lg bg-gray-50"
                            />
                            <button
                              onClick={() => toggleFieldVisibility(`payment-${integration.id}-key`)}
                              className="p-2 text-gray-400 hover:text-gray-600"
                            >
                              {maskedFields[`payment-${integration.id}-key`] ? <Eye className="w-4 h-4" /> : <EyeOff className="w-4 h-4" />}
                            </button>
                          </div>
                        </div>

                        <div>
                          <label className="block text-sm font-medium text-gray-700 mb-2">Secret Key</label>
                          <div className="flex items-center space-x-2">
                            <input
                              type="text"
                              value={maskValue(integration.secretKey, !maskedFields[`payment-${integration.id}-secret`])}
                              readOnly
                              className="flex-1 px-3 py-2 border border-gray-300 rounded-lg bg-gray-50"
                            />
                            <button
                              onClick={() => toggleFieldVisibility(`payment-${integration.id}-secret`)}
                              className="p-2 text-gray-400 hover:text-gray-600"
                            >
                              {maskedFields[`payment-${integration.id}-secret`] ? <Eye className="w-4 h-4" /> : <EyeOff className="w-4 h-4" />}
                            </button>
                          </div>
                        </div>

                        {integration.webhookUrl && (
                          <div className="md:col-span-2">
                            <label className="block text-sm font-medium text-gray-700 mb-2">Webhook URL</label>
                            <div className="flex items-center space-x-2">
                              <input
                                type="text"
                                value={integration.webhookUrl}
                                readOnly
                                className="flex-1 px-3 py-2 border border-gray-300 rounded-lg bg-gray-50"
                              />
                              <button
                                onClick={() => handleTestWebhook(integration.webhookUrl)}
                                className="px-3 py-2 bg-blue-500 hover:bg-blue-600 text-white text-sm rounded-lg transition-colors"
                              >
                                Test
                              </button>
                            </div>
                          </div>
                        )}
                      </div>
                    )}
                  </div>
                ))}
              </div>
            </div>
          )}

          {/* Sync Settings */}
          {activeSection === 'sync' && (
            <div className="space-y-6">
              <div className="flex items-center space-x-3 mb-6">
                <RefreshCw className="w-6 h-6 text-blue-600" />
                <h2 className="text-xl font-semibold text-gray-900">Sync Settings</h2>
              </div>

              <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">Branch Sync Interval (minutes)</label>
                  <input
                    type="number"
                    value={syncSettings.branchSyncInterval}
                    onChange={(e) => {
                      setSyncSettings(prev => ({ ...prev, branchSyncInterval: parseInt(e.target.value) || 15 }));
                      setHasChanges(true);
                    }}
                    className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                  />
                </div>

                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">Conflict Resolution</label>
                  <select
                    value={syncSettings.conflictResolution}
                    onChange={(e) => {
                      setSyncSettings(prev => ({ ...prev, conflictResolution: e.target.value as any }));
                      setHasChanges(true);
                    }}
                    className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                  >
                    <option value="hq-wins">Head Office Wins</option>
                    <option value="branch-wins">Branch Wins</option>
                    <option value="manual">Manual Resolution</option>
                  </select>
                </div>

                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">Retry Attempts</label>
                  <input
                    type="number"
                    value={syncSettings.retryAttempts}
                    onChange={(e) => {
                      setSyncSettings(prev => ({ ...prev, retryAttempts: parseInt(e.target.value) || 3 }));
                      setHasChanges(true);
                    }}
                    className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                  />
                </div>

                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">Timeout (seconds)</label>
                  <input
                    type="number"
                    value={syncSettings.timeoutSeconds}
                    onChange={(e) => {
                      setSyncSettings(prev => ({ ...prev, timeoutSeconds: parseInt(e.target.value) || 30 }));
                      setHasChanges(true);
                    }}
                    className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                  />
                </div>

                <div className="md:col-span-2">
                  <label className="block text-sm font-medium text-gray-700 mb-2">Webhook Endpoint</label>
                  <div className="flex items-center space-x-2">
                    <input
                      type="text"
                      value={maskValue(syncSettings.webhookEndpoint, !maskedFields['webhook-endpoint'])}
                      onChange={(e) => {
                        setSyncSettings(prev => ({ ...prev, webhookEndpoint: e.target.value }));
                        setHasChanges(true);
                      }}
                      className="flex-1 px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                    />
                    <button
                      onClick={() => toggleFieldVisibility('webhook-endpoint')}
                      className="p-2 text-gray-400 hover:text-gray-600"
                    >
                      {maskedFields['webhook-endpoint'] ? <Eye className="w-4 h-4" /> : <EyeOff className="w-4 h-4" />}
                    </button>
                    <button
                      onClick={() => handleTestWebhook(syncSettings.webhookEndpoint)}
                      className="px-3 py-2 bg-blue-500 hover:bg-blue-600 text-white text-sm rounded-lg transition-colors"
                    >
                      Test
                    </button>
                  </div>
                </div>

                <div className="md:col-span-2">
                  <label className="flex items-center space-x-2">
                    <input
                      type="checkbox"
                      checked={syncSettings.enableRealTimeSync}
                      onChange={(e) => {
                        setSyncSettings(prev => ({ ...prev, enableRealTimeSync: e.target.checked }));
                        setHasChanges(true);
                      }}
                      className="rounded border-gray-300 text-blue-600 focus:ring-blue-500"
                    />
                    <span className="text-sm text-gray-700">Enable Real-time Sync</span>
                  </label>
                  <p className="text-xs text-gray-500 mt-1">
                    When enabled, changes will sync immediately instead of waiting for the scheduled interval
                  </p>
                </div>
              </div>
            </div>
          )}

          {/* Backups */}
          {activeSection === 'backups' && (
            <div className="space-y-6">
              <div className="flex items-center space-x-3 mb-6">
                <Database className="w-6 h-6 text-green-600" />
                <h2 className="text-xl font-semibold text-gray-900">Backup Settings</h2>
              </div>

              <div className="bg-blue-50 border border-blue-200 rounded-lg p-4 mb-6">
                <div className="flex items-center space-x-2 mb-2">
                  <HardDrive className="w-5 h-5 text-blue-600" />
                  <h3 className="font-semibold text-blue-800">Manual Backup</h3>
                </div>
                <p className="text-blue-700 text-sm mb-3">
                  Create an immediate backup of all system data including transactions, inventory, and user data.
                </p>
                <button
                  onClick={handleManualBackup}
                  className="flex items-center space-x-2 px-4 py-2 bg-blue-500 hover:bg-blue-600 text-white rounded-lg transition-colors"
                >
                  <Download className="w-4 h-4" />
                  <span>Create Manual Backup</span>
                </button>
              </div>

              <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                <div>
                  <label className="flex items-center space-x-2 mb-4">
                    <input
                      type="checkbox"
                      checked={backupSettings.autoBackupEnabled}
                      onChange={(e) => {
                        setBackupSettings(prev => ({ ...prev, autoBackupEnabled: e.target.checked }));
                        setHasChanges(true);
                      }}
                      className="rounded border-gray-300 text-blue-600 focus:ring-blue-500"
                    />
                    <span className="text-sm font-medium text-gray-700">Enable Automatic Backups</span>
                  </label>
                </div>

                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">Retention Period (days)</label>
                  <input
                    type="number"
                    value={backupSettings.retentionDays}
                    onChange={(e) => {
                      setBackupSettings(prev => ({ ...prev, retentionDays: parseInt(e.target.value) || 90 }));
                      setHasChanges(true);
                    }}
                    className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                  />
                </div>

                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">Storage Provider</label>
                  <select
                    value={backupSettings.storageProvider}
                    onChange={(e) => {
                      setBackupSettings(prev => ({ ...prev, storageProvider: e.target.value as any }));
                      setHasChanges(true);
                    }}
                    className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                  >
                    <option value="aws-s3">Amazon S3</option>
                    <option value="google-cloud">Google Cloud Storage</option>
                    <option value="azure">Azure Blob Storage</option>
                  </select>
                </div>

                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">Bucket Name</label>
                  <input
                    type="text"
                    value={backupSettings.bucketName}
                    onChange={(e) => {
                      setBackupSettings(prev => ({ ...prev, bucketName: e.target.value }));
                      setHasChanges(true);
                    }}
                    className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                  />
                </div>

                <div className="md:col-span-2">
                  <label className="block text-sm font-medium text-gray-700 mb-2">Backup Schedule</label>
                  <input
                    type="text"
                    value={backupSettings.backupSchedule}
                    onChange={(e) => {
                      setBackupSettings(prev => ({ ...prev, backupSchedule: e.target.value }));
                      setHasChanges(true);
                    }}
                    placeholder="0 2 * * * (Daily at 2 AM)"
                    className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                  />
                  <p className="text-xs text-gray-500 mt-1">Use cron format (minute hour day month weekday)</p>
                </div>

                <div className="md:col-span-2">
                  <label className="flex items-center space-x-2">
                    <input
                      type="checkbox"
                      checked={backupSettings.encryptionEnabled}
                      onChange={(e) => {
                        setBackupSettings(prev => ({ ...prev, encryptionEnabled: e.target.checked }));
                        setHasChanges(true);
                      }}
                      className="rounded border-gray-300 text-blue-600 focus:ring-blue-500"
                    />
                    <span className="text-sm text-gray-700">Enable Backup Encryption</span>
                  </label>
                  <p className="text-xs text-gray-500 mt-1">
                    Encrypt backup files using AES-256 encryption before uploading to storage
                  </p>
                </div>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
};