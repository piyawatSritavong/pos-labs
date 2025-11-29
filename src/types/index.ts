export interface Product {
  id: string;
  name: string;
  price: number;
  image: string;
  category: string;
  unitTypes: string[];
  description: string;
}

export interface CartItem extends Product {
  quantity: number;
  selectedUnit: string;
}

export interface ParkedBill {
  id: string;
  timestamp: Date;
  cashier: string;
  customerNote?: string;
  items: CartItem[];
  subtotal: number;
  discount: Discount;
  tax: number;
  total: number;
}

export interface CompletedBill extends ParkedBill {
  paymentMethod: string;
  completedAt: Date;
}

export interface Discount {
  type: string;
  value: number;
  amount: number; // calculated discount amount
}

export interface StockItem {
  id: string;
  name: string;
  currentQuantity: number;
  unitType: string;
  lowStockThreshold: number;
  lastUpdated: Date;
  category: string;
}

export interface StockHistory {
  id: string;
  productId: string;
  productName: string;
  action: 'add' | 'remove' | 'update';
  quantityChange: number;
  previousQuantity: number;
  newQuantity: number;
  timestamp: Date;
  cashier: string;
  notes?: string;
}

export interface ShiftSummary {
  id: string;
  cashier: string;
  shiftType: 'Morning' | 'Afternoon' | 'Evening';
  startTime: Date;
  endTime: Date;
  totalSales: number;
  totalDiscounts: number;
  billsProcessed: number;
  paymentBreakdown: {
    cash: number;
    credit: number;
    bank: number;
  };
  parkedBillsCount: number;
}