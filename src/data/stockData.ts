import { StockItem, StockHistory } from '../types';

export const stockItems: StockItem[] = [
  // Roofing
  {
    id: 'stock-roof-1',
    name: 'Metal Roofing Sheets',
    currentQuantity: 45,
    unitType: 'per sheet',
    lowStockThreshold: 10,
    lastUpdated: new Date('2024-01-15T10:30:00'),
    category: 'roofing',
  },
  {
    id: 'stock-roof-2',
    name: 'Clay Roof Tiles',
    currentQuantity: 8, // Low stock
    unitType: 'per piece',
    lowStockThreshold: 10,
    lastUpdated: new Date('2024-01-14T14:20:00'),
    category: 'roofing',
  },
  {
    id: 'stock-roof-3',
    name: 'Roofing Membrane',
    currentQuantity: 25,
    unitType: 'per roll',
    lowStockThreshold: 5,
    lastUpdated: new Date('2024-01-15T09:15:00'),
    category: 'roofing',
  },

  // Cement
  {
    id: 'stock-cement-1',
    name: 'Portland Cement',
    currentQuantity: 120,
    unitType: 'per bag',
    lowStockThreshold: 20,
    lastUpdated: new Date('2024-01-15T11:45:00'),
    category: 'cement',
  },
  {
    id: 'stock-cement-2',
    name: 'Ready Mix Concrete',
    currentQuantity: 15,
    unitType: 'per cubic meter',
    lowStockThreshold: 5,
    lastUpdated: new Date('2024-01-15T08:30:00'),
    category: 'cement',
  },
  {
    id: 'stock-cement-3',
    name: 'Mortar Mix',
    currentQuantity: 6, // Low stock
    unitType: 'per bag',
    lowStockThreshold: 10,
    lastUpdated: new Date('2024-01-13T16:00:00'),
    category: 'cement',
  },

  // Steel
  {
    id: 'stock-steel-1',
    name: 'Steel Rebar',
    currentQuantity: 85,
    unitType: 'per piece',
    lowStockThreshold: 15,
    lastUpdated: new Date('2024-01-15T12:00:00'),
    category: 'steel',
  },
  {
    id: 'stock-steel-2',
    name: 'Steel I-Beam',
    currentQuantity: 12,
    unitType: 'per piece',
    lowStockThreshold: 5,
    lastUpdated: new Date('2024-01-14T15:30:00'),
    category: 'steel',
  },
  {
    id: 'stock-steel-3',
    name: 'Steel Wire Mesh',
    currentQuantity: 35,
    unitType: 'per roll',
    lowStockThreshold: 10,
    lastUpdated: new Date('2024-01-15T10:15:00'),
    category: 'steel',
  },

  // Paint
  {
    id: 'stock-paint-1',
    name: 'Exterior Wall Paint',
    currentQuantity: 28,
    unitType: 'per gallon',
    lowStockThreshold: 10,
    lastUpdated: new Date('2024-01-15T13:20:00'),
    category: 'paint',
  },
  {
    id: 'stock-paint-2',
    name: 'Interior Paint',
    currentQuantity: 42,
    unitType: 'per gallon',
    lowStockThreshold: 15,
    lastUpdated: new Date('2024-01-15T09:45:00'),
    category: 'paint',
  },
  {
    id: 'stock-paint-3',
    name: 'Paint Primer',
    currentQuantity: 7, // Low stock
    unitType: 'per gallon',
    lowStockThreshold: 10,
    lastUpdated: new Date('2024-01-12T14:30:00'),
    category: 'paint',
  },

  // Tools
  {
    id: 'stock-tools-1',
    name: 'Power Drill',
    currentQuantity: 18,
    unitType: 'per piece',
    lowStockThreshold: 5,
    lastUpdated: new Date('2024-01-15T11:00:00'),
    category: 'tools',
  },
  {
    id: 'stock-tools-2',
    name: 'Circular Saw',
    currentQuantity: 9,
    unitType: 'per piece',
    lowStockThreshold: 3,
    lastUpdated: new Date('2024-01-14T16:45:00'),
    category: 'tools',
  },
  {
    id: 'stock-tools-3',
    name: 'Hammer Set',
    currentQuantity: 22,
    unitType: 'per set',
    lowStockThreshold: 8,
    lastUpdated: new Date('2024-01-15T10:30:00'),
    category: 'tools',
  },

  // Hardware
  {
    id: 'stock-hardware-1',
    name: 'Hex Bolts',
    currentQuantity: 450,
    unitType: 'per piece',
    lowStockThreshold: 100,
    lastUpdated: new Date('2024-01-15T12:30:00'),
    category: 'hardware',
  },
  {
    id: 'stock-hardware-2',
    name: 'Wood Screws',
    currentQuantity: 85, // Low stock
    unitType: 'per piece',
    lowStockThreshold: 100,
    lastUpdated: new Date('2024-01-13T15:15:00'),
    category: 'hardware',
  },
  {
    id: 'stock-hardware-3',
    name: 'Washers',
    currentQuantity: 320,
    unitType: 'per piece',
    lowStockThreshold: 150,
    lastUpdated: new Date('2024-01-15T11:15:00'),
    category: 'hardware',
  },
];

export const stockHistory: StockHistory[] = [
  {
    id: 'hist-1',
    productId: 'stock-roof-1',
    productName: 'Metal Roofing Sheets',
    action: 'add',
    quantityChange: 50,
    previousQuantity: 25,
    newQuantity: 75,
    timestamp: new Date('2024-01-15T10:30:00'),
    cashier: 'John Smith',
    notes: 'New shipment received',
  },
  {
    id: 'hist-2',
    productId: 'stock-cement-1',
    productName: 'Portland Cement',
    action: 'remove',
    quantityChange: -10,
    previousQuantity: 130,
    newQuantity: 120,
    timestamp: new Date('2024-01-15T11:45:00'),
    cashier: 'John Smith',
    notes: 'Sold to customer',
  },
  {
    id: 'hist-3',
    productId: 'stock-paint-3',
    productName: 'Paint Primer',
    action: 'update',
    quantityChange: -3,
    previousQuantity: 10,
    newQuantity: 7,
    timestamp: new Date('2024-01-12T14:30:00'),
    cashier: 'Jane Doe',
    notes: 'Inventory adjustment - damaged items',
  },
];