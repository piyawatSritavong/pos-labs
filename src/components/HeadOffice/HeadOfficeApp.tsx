import React, { useState } from 'react';
import { HeadOfficeLayout } from './HeadOfficeLayout';
import { Dashboard } from './Dashboard';
import { Branches } from './Branches';
import { SalesReports } from './SalesReports';
import { StockManagement } from './StockManagement';
import { ShiftManagement } from './ShiftManagement';
import { BillsArchive } from './BillsArchive';
import { UsersRoles } from './UsersRoles';
import { Settings } from './Settings';
import { Notifications } from './Notifications';

export const HeadOfficeApp: React.FC = () => {
  const [activeView, setActiveView] = useState('dashboard');

  const renderContent = () => {
    switch (activeView) {
      case 'dashboard':
        return <Dashboard />;
      case 'branches':
        return <Branches />;
      case 'sales':
        return <SalesReports />;
      case 'stock':
        return <StockManagement />;
      case 'shifts':
        return <ShiftManagement />;
      case 'bills':
        return <BillsArchive />;
      case 'users':
        return <UsersRoles />;
      case 'settings':
        return <Settings />;
      case 'notifications':
        return <Notifications />;
      default:
        return <Dashboard />;
    }
  };

  return (
    <HeadOfficeLayout activeView={activeView} onViewChange={setActiveView}>
      {renderContent()}
    </HeadOfficeLayout>
  );
};