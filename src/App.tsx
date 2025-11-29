import React, { useState, useMemo } from 'react';
import { HeadOfficeApp } from './components/HeadOffice/HeadOfficeApp';
import { Header } from './components/Header';
import { CategoryTabs } from './components/CategoryTabs';
import { ProductCard } from './components/ProductCard';
import { InvoicePanel } from './components/InvoicePanel';
import { QRCodeGenerator } from './components/QRCodeGenerator';
import { ParkedBillsDrawer } from './components/ParkedBillsDrawer';
import { BillsHistory } from './components/BillsHistory';
import { StockManagement } from './components/StockManagement';
import { ShiftClosing } from './components/ShiftClosing';
import { ConfirmationModal } from './components/ConfirmationModal';
import { products } from './data/products';
import { stockItems, stockHistory } from './data/stockData';
import { CartItem, ParkedBill, CompletedBill, Discount, StockItem, StockHistory } from './types';

function App(): React.ReactNode {
  const isHeadOffice = window.location.pathname === '/headoffice';

  const [currentView, setCurrentView] = useState<'pos' | 'bills' | 'stock'>('pos');
  const [activeCategory, setActiveCategory] = useState('all');
  const [searchQuery, setSearchQuery] = useState('');
  const [cartItems, setCartItems] = useState<CartItem[]>([]);
  const [discount, setDiscount] = useState<Discount>({ type: 'percentage', value: 0, amount: 0 });
  const [parkedBills, setParkedBills] = useState<ParkedBill[]>([]);
  const [completedBills, setCompletedBills] = useState<CompletedBill[]>([]);
  const [selectedPaymentMethod, setSelectedPaymentMethod] = useState<string | null>(null);
  const [stockData, setStockData] = useState<StockItem[]>(stockItems);
  const [stockHistoryData, setStockHistoryData] = useState<StockHistory[]>(stockHistory);
  
  // UI State
  const [showQRGenerator, setShowQRGenerator] = useState(false);
  const [showParkedBills, setShowParkedBills] = useState(false);
  const [showCancelModal, setShowCancelModal] = useState(false);
  const [showShiftClosing, setShowShiftClosing] = useState(false);

  // Calculate low stock count
  const lowStockCount = stockData.filter(item => item.currentQuantity <= item.lowStockThreshold).length;

  const filteredProducts = useMemo(() => {
    let filtered = products;
    
    if (activeCategory !== 'all') {
      filtered = filtered.filter(product => product.category === activeCategory);
    }
    
    if (searchQuery) {
      filtered = filtered.filter(product =>
        product.name.toLowerCase().includes(searchQuery.toLowerCase()) ||
        product.description.toLowerCase().includes(searchQuery.toLowerCase())
      );
    }
    
    return filtered;
  }, [activeCategory, searchQuery]);

  if (isHeadOffice) {
    return <HeadOfficeApp />;
  }

  const handleAddToCart = (item: CartItem) => {
    setCartItems(prevItems => {
      const existingItemIndex = prevItems.findIndex(
        cartItem => cartItem.id === item.id && cartItem.selectedUnit === item.selectedUnit
      );
      
      if (existingItemIndex >= 0) {
        const updatedItems = [...prevItems];
        updatedItems[existingItemIndex] = item;
        return updatedItems;
      } else {
        return [...prevItems, item];
      }
    });
  };

  const handleQuantityChange = (id: string, unit: string, quantity: number) => {
    setCartItems(prevItems => {
      return prevItems.map(item => {
        if (item.id === id && item.selectedUnit === unit) {
          return { ...item, quantity };
        }
        return item;
      });
    });
  };

  const handleRemoveItem = (id: string, unit: string) => {
    setCartItems(prevItems => {
      return prevItems.filter(item => !(item.id === id && item.selectedUnit === unit));
    });
  };

  const handleDiscountChange = (newDiscount: Discount) => {
    setDiscount(newDiscount);
  };

  const handleCancelBill = () => {
    setShowCancelModal(true);
  };

  const confirmCancelBill = () => {
    setCartItems([]);
    setDiscount({ type: 'percentageaskjdhaksjdh', value: 0, amount: 0 });
    setSelectedPaymentMethod(null);
    setShowCancelModal(false);
  };

  const handleParkBill = () => {
    if (cartItems.length === 0) return;
    
    const subtotal = cartItems.reduce((sum, item) => sum + (item.price * item.quantity), 0);
    const discountedSubtotal = subtotal - discount.amount;
    const tax = discountedSubtotal * 0.08;
    const total = discountedSubtotal + tax;
    
    const parkedBill: ParkedBill = {
      id: `PB${Date.now()}`,
      timestamp: new Date(),
      cashier: 'John Smith',
      items: [...cartItems],
      subtotal,
      discount: { ...discount },
      tax,
      total,
    };
    
    setParkedBills(prev => [...prev, parkedBill]);
    setCartItems([]);
    setDiscount({ type: 'percentage', value: 0, amount: 0 });
    setSelectedPaymentMethod(null);
    alert('Bill parked successfully!');
  };

  const handleResumeBill = (bill: ParkedBill) => {
    setCartItems(bill.items);
    setDiscount(bill.discount);
    setSelectedPaymentMethod(null);
    setParkedBills(prev => prev.filter(parkedBill => parkedBill.id !== bill.id));
    setShowParkedBills(false);
  };

  const handleDeleteParkedBill = (billId: string) => {
    setParkedBills(prev => prev.filter(bill => bill.id !== billId));
  };

  const handlePrintProvisional = (bill: ParkedBill) => {
    // In a real app, this would generate a provisional receipt
    alert(`Printing provisional receipt for Bill #${bill.id}`);
  };

  const handlePlaceOrder = () => {
    if (cartItems.length > 0 && selectedPaymentMethod) {
      const subtotal = cartItems.reduce((sum, item) => sum + (item.price * item.quantity), 0);
      const discountedSubtotal = subtotal - discount.amount;
      const tax = discountedSubtotal * 0.08;
      const total = discountedSubtotal + tax;
      
      const completedBill: CompletedBill = {
        id: `CB${Date.now()}`,
        timestamp: new Date(),
        cashier: 'John Smith',
        items: [...cartItems],
        subtotal,
        discount: { ...discount },
        tax,
        total,
        paymentMethod: selectedPaymentMethod,
        completedAt: new Date(),
      };
      
      setCompletedBills(prev => [...prev, completedBill]);
      setCartItems([]);
      setDiscount({ type: 'percentage', value: 0, amount: 0 });
      setSelectedPaymentMethod(null);
      alert('Order placed successfully!');
    }
  };

  const handleViewBill = (bill: CompletedBill) => {
    alert(`Viewing Bill #${bill.id}`);
  };

  const handleReprintBill = (bill: CompletedBill) => {
    alert(`Reprinting Bill #${bill.id}`);
  };

  const handleExportBill = (bill: CompletedBill) => {
    alert(`Exporting Bill #${bill.id}`);
  };

  const handleExportDaily = (date: string) => {
    alert(`Exporting daily report for ${date}`);
  };

  const handleUpdateStock = (itemId: string, newQuantity: number, notes?: string) => {
    setStockData(prev => prev.map(item => {
      if (item.id === itemId) {
        const historyEntry: StockHistory = {
          id: `hist-${Date.now()}`,
          productId: itemId,
          productName: item.name,
          action: 'update',
          quantityChange: newQuantity - item.currentQuantity,
          previousQuantity: item.currentQuantity,
          newQuantity,
          timestamp: new Date(),
          cashier: 'John Smith',
          notes,
        };
        setStockHistoryData(prev => [historyEntry, ...prev]);
        
        return {
          ...item,
          currentQuantity: newQuantity,
          lastUpdated: new Date(),
        };
      }
      return item;
    }));
    alert('Stock updated successfully!');
  };

  const handleAddNewStockItem = (item: Omit<StockItem, 'id' | 'lastUpdated'>) => {
    const newItem: StockItem = {
      ...item,
      id: `stock-${Date.now()}`,
      lastUpdated: new Date(),
    };
    setStockData(prev => [...prev, newItem]);
    alert('New item added successfully!');
  };

  const handleExportStock = () => {
    alert('Exporting stock report...');
  };

  const handleCloseShift = () => {
    setShowShiftClosing(true);
  };

  const handleConfirmCloseShift = () => {
    setShowShiftClosing(false);
    alert('Shift closed successfully! Please log out and have the next cashier log in.');
  };

  if (currentView === 'stock') {
    return (
      <div className="min-h-screen bg-gray-50">
        <Header 
          onSearch={setSearchQuery} 
          searchQuery={searchQuery}
          onOpenQRGenerator={() => setShowQRGenerator(true)}
          onOpenParkedBills={() => setShowParkedBills(true)}
          onOpenBillsHistory={() => setCurrentView('bills')}
          onOpenStock={() => setCurrentView('stock')}
          onCloseShift={handleCloseShift}
          parkedBillsCount={parkedBills.length}
          lowStockCount={lowStockCount}
        />
        <div className="flex items-center justify-between p-6 border-b border-gray-200 bg-white">
          <button
            onClick={() => setCurrentView('pos')}
            className="text-blue-600 hover:text-blue-800 font-medium"
          >
            ← Back to POS
          </button>
        </div>
        <StockManagement
          stockItems={stockData}
          stockHistory={stockHistoryData}
          onUpdateStock={handleUpdateStock}
          onAddNewItem={handleAddNewStockItem}
          onExportStock={handleExportStock}
        />
        
        <QRCodeGenerator
          isOpen={showQRGenerator}
          onClose={() => setShowQRGenerator(false)}
        />
        
        <ParkedBillsDrawer
          isOpen={showParkedBills}
          onClose={() => setShowParkedBills(false)}
          parkedBills={parkedBills}
          onResumeBill={handleResumeBill}
          onDeleteBill={handleDeleteParkedBill}
          onPrintProvisional={handlePrintProvisional}
        />
        
        <ShiftClosing
          isOpen={showShiftClosing}
          onClose={() => setShowShiftClosing(false)}
          shiftSummary={{
            id: `shift-${Date.now()}`,
            cashier: 'John Smith',
            shiftType: 'Morning',
            startTime: new Date(Date.now() - 8 * 60 * 60 * 1000),
            endTime: new Date(),
            totalSales: completedBills.reduce((sum, bill) => sum + bill.total, 0),
            totalDiscounts: completedBills.reduce((sum, bill) => sum + bill.discount.amount, 0),
            billsProcessed: completedBills.length,
            paymentBreakdown: {
              cash: completedBills.filter(b => b.paymentMethod === 'cash').reduce((sum, bill) => sum + bill.total, 0),
              credit: completedBills.filter(b => b.paymentMethod === 'credit').reduce((sum, bill) => sum + bill.total, 0),
              bank: completedBills.filter(b => b.paymentMethod === 'bank').reduce((sum, bill) => sum + bill.total, 0),
            },
            parkedBillsCount: parkedBills.length,
          }}
          onConfirmClose={handleConfirmCloseShift}
        />
      </div>
    );
  }

  if (currentView === 'bills') {
    return (
      <div className="min-h-screen bg-gray-50">
        <Header 
          onSearch={setSearchQuery} 
          searchQuery={searchQuery}
          onOpenQRGenerator={() => setShowQRGenerator(true)}
          onOpenParkedBills={() => setShowParkedBills(true)}
          onOpenBillsHistory={() => setCurrentView('pos')}
          parkedBillsCount={parkedBills.length}
          onOpenStock={() => setCurrentView('stock')}
          onCloseShift={handleCloseShift}
          lowStockCount={lowStockCount}
        />
        <div className="flex items-center justify-between p-6 border-b border-gray-200 bg-white">
          <button
            onClick={() => setCurrentView('pos')}
            className="text-blue-600 hover:text-blue-800 font-medium"
          >
            ← Back to POS
          </button>
        </div>
        <BillsHistory
          bills={completedBills}
          onViewBill={handleViewBill}
          onReprintBill={handleReprintBill}
          onExportBill={handleExportBill}
          onExportDaily={handleExportDaily}
        />
        
        <QRCodeGenerator
          isOpen={showQRGenerator}
          onClose={() => setShowQRGenerator(false)}
        />
        
        <ParkedBillsDrawer
          isOpen={showParkedBills}
          onClose={() => setShowParkedBills(false)}
          parkedBills={parkedBills}
          onResumeBill={handleResumeBill}
          onDeleteBill={handleDeleteParkedBill}
          onPrintProvisional={handlePrintProvisional}
        />
        
        <ShiftClosing
          isOpen={showShiftClosing}
          onClose={() => setShowShiftClosing(false)}
          shiftSummary={{
            id: `shift-${Date.now()}`,
            cashier: 'John Smith',
            shiftType: 'Morning',
            startTime: new Date(Date.now() - 8 * 60 * 60 * 1000),
            endTime: new Date(),
            totalSales: completedBills.reduce((sum, bill) => sum + bill.total, 0),
            totalDiscounts: completedBills.reduce((sum, bill) => sum + bill.discount.amount, 0),
            billsProcessed: completedBills.length,
            paymentBreakdown: {
              cash: completedBills.filter(b => b.paymentMethod === 'cash').reduce((sum, bill) => sum + bill.total, 0),
              credit: completedBills.filter(b => b.paymentMethod === 'credit').reduce((sum, bill) => sum + bill.total, 0),
              bank: completedBills.filter(b => b.paymentMethod === 'bank').reduce((sum, bill) => sum + bill.total, 0),
            },
            parkedBillsCount: parkedBills.length,
          }}
          onConfirmClose={handleConfirmCloseShift}
        />
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-gray-50 flex flex-col">
      <Header 
        onSearch={setSearchQuery} 
        searchQuery={searchQuery}
        onOpenQRGenerator={() => setShowQRGenerator(true)}
        onOpenParkedBills={() => setShowParkedBills(true)}
        onOpenBillsHistory={() => setCurrentView('bills')}
        parkedBillsCount={parkedBills.length}
        onOpenStock={() => setCurrentView('stock')}
        onCloseShift={handleCloseShift}
        lowStockCount={lowStockCount}
      />
      
      <div className="flex flex-1">
        <div className="flex-1 flex flex-col">
          <CategoryTabs 
            activeCategory={activeCategory}
            onCategoryChange={setActiveCategory}
          />
          
          <main className="flex-1 p-6">
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-6">
              {filteredProducts.map((product) => (
                <ProductCard
                  key={product.id}
                  product={product}
                  onAddToCart={handleAddToCart}
                />
              ))}
            </div>
            
            {filteredProducts.length === 0 && (
              <div className="text-center py-12">
                <div className="text-gray-500 text-lg">No products found</div>
                <div className="text-gray-400 text-sm mt-2">
                  Try adjusting your search or category filter
                </div>
              </div>
            )}
          </main>
        </div>
        
        <InvoicePanel 
          cartItems={cartItems}
          discount={discount}
          onDiscountChange={handleDiscountChange}
          onQuantityChange={handleQuantityChange}
          onRemoveItem={handleRemoveItem}
          onPlaceOrder={handlePlaceOrder}
          onCancelBill={handleCancelBill}
          onParkBill={handleParkBill}
          selectedPaymentMethod={selectedPaymentMethod}
          onPaymentMethodSelect={setSelectedPaymentMethod}
        />
      </div>
      
      <QRCodeGenerator
        isOpen={showQRGenerator}
        onClose={() => setShowQRGenerator(false)}
      />
      
      <ParkedBillsDrawer
        isOpen={showParkedBills}
        onClose={() => setShowParkedBills(false)}
        parkedBills={parkedBills}
        onResumeBill={handleResumeBill}
        onDeleteBill={handleDeleteParkedBill}
        onPrintProvisional={handlePrintProvisional}
      />
      
      <ConfirmationModal
        isOpen={showCancelModal}
        title="Cancel Bill"
        message="Are you sure you want to cancel this bill? All items will be removed from the cart."
        confirmText="Yes, Cancel"
        cancelText="Keep Bill"
        onConfirm={confirmCancelBill}
        onCancel={() => setShowCancelModal(false)}
        type="danger"
      />
      
      <ShiftClosing
        isOpen={showShiftClosing}
        onClose={() => setShowShiftClosing(false)}
        shiftSummary={{
          id: `shift-${Date.now()}`,
          cashier: 'John Smith',
          shiftType: 'Morning',
          startTime: new Date(Date.now() - 8 * 60 * 60 * 1000),
          endTime: new Date(),
          totalSales: completedBills.reduce((sum, bill) => sum + bill.total, 0),
          totalDiscounts: completedBills.reduce((sum, bill) => sum + bill.discount.amount, 0),
          billsProcessed: completedBills.length,
          paymentBreakdown: {
            cash: completedBills.filter(b => b.paymentMethod === 'cash').reduce((sum, bill) => sum + bill.total, 0),
            credit: completedBills.filter(b => b.paymentMethod === 'credit').reduce((sum, bill) => sum + bill.total, 0),
            bank: completedBills.filter(b => b.paymentMethod === 'bank').reduce((sum, bill) => sum + bill.total, 0),
          },
          parkedBillsCount: parkedBills.length,
        }}
        onConfirmClose={handleConfirmCloseShift}
      />
    </div>
  );
}

export default App;