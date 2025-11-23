import { Product } from '../types';

export const products: Product[] = [
  // Roofing
  {
    id: 'roof-1',
    name: 'Metal Roofing Sheets',
    price: 25.99,
    image: 'https://images.pexels.com/photos/416400/pexels-photo-416400.jpeg?auto=compress&cs=tinysrgb&w=400',
    category: 'roofing',
    unitTypes: ['per sheet', 'per pack', 'per bundle'],
    description: 'Galvanized steel roofing sheets'
  },
  {
    id: 'roof-2',
    name: 'Clay Roof Tiles',
    price: 3.50,
    image: 'https://images.pexels.com/photos/271711/pexels-photo-271711.jpeg?auto=compress&cs=tinysrgb&w=400',
    category: 'roofing',
    unitTypes: ['per piece', 'per box', 'per pallet'],
    description: 'Traditional clay roof tiles'
  },
  {
    id: 'roof-3',
    name: 'Roofing Membrane',
    price: 89.99,
    image: 'https://images.pexels.com/photos/2598682/pexels-photo-2598682.jpeg?auto=compress&cs=tinysrgb&w=400',
    category: 'roofing',
    unitTypes: ['per roll', 'per meter'],
    description: 'Waterproof roofing membrane'
  },

  // Cement
  {
    id: 'cement-1',
    name: 'Portland Cement',
    price: 12.50,
    image: 'https://images.pexels.com/photos/5864239/pexels-photo-5864239.jpeg?auto=compress&cs=tinysrgb&w=400',
    category: 'cement',
    unitTypes: ['per bag', 'per ton', 'per pallet'],
    description: '50kg bag of Portland cement'
  },
  {
    id: 'cement-2',
    name: 'Ready Mix Concrete',
    price: 125.00,
    image: 'https://images.pexels.com/photos/1108101/pexels-photo-1108101.jpeg?auto=compress&cs=tinysrgb&w=400',
    category: 'cement',
    unitTypes: ['per cubic meter', 'per load'],
    description: 'Ready-to-use concrete mix'
  },
  {
    id: 'cement-3',
    name: 'Mortar Mix',
    price: 8.75,
    image: 'https://images.pexels.com/photos/8442441/pexels-photo-8442441.jpeg?auto=compress&cs=tinysrgb&w=400',
    category: 'cement',
    unitTypes: ['per bag', 'per pallet'],
    description: 'Pre-mixed mortar for masonry'
  },

  // Steel
  {
    id: 'steel-1',
    name: 'Steel Rebar',
    price: 45.00,
    image: 'https://images.pexels.com/photos/1108102/pexels-photo-1108102.jpeg?auto=compress&cs=tinysrgb&w=400',
    category: 'steel',
    unitTypes: ['per piece', 'per bundle', 'per ton'],
    description: '12mm steel reinforcement bar'
  },
  {
    id: 'steel-2',
    name: 'Steel I-Beam',
    price: 156.00,
    image: 'https://images.pexels.com/photos/1266810/pexels-photo-1266810.jpeg?auto=compress&cs=tinysrgb&w=400',
    category: 'steel',
    unitTypes: ['per piece', 'per meter', 'per ton'],
    description: 'Structural steel I-beam'
  },
  {
    id: 'steel-3',
    name: 'Steel Wire Mesh',
    price: 28.50,
    image: 'https://images.pexels.com/photos/4207892/pexels-photo-4207892.jpeg?auto=compress&cs=tinysrgb&w=400',
    category: 'steel',
    unitTypes: ['per roll', 'per sheet', 'per meter'],
    description: 'Welded steel wire mesh'
  },

  // Paint
  {
    id: 'paint-1',
    name: 'Exterior Wall Paint',
    price: 34.99,
    image: 'https://images.pexels.com/photos/1547813/pexels-photo-1547813.jpeg?auto=compress&cs=tinysrgb&w=400',
    category: 'paint',
    unitTypes: ['per gallon', 'per quart', 'per case'],
    description: 'Weather-resistant exterior paint'
  },
  {
    id: 'paint-2',
    name: 'Interior Paint',
    price: 29.99,
    image: 'https://images.pexels.com/photos/1669799/pexels-photo-1669799.jpeg?auto=compress&cs=tinysrgb&w=400',
    category: 'paint',
    unitTypes: ['per gallon', 'per quart', 'per case'],
    description: 'Premium interior wall paint'
  },
  {
    id: 'paint-3',
    name: 'Paint Primer',
    price: 24.99,
    image: 'https://images.pexels.com/photos/1266810/pexels-photo-1266810.jpeg?auto=compress&cs=tinysrgb&w=400',
    category: 'paint',
    unitTypes: ['per gallon', 'per quart'],
    description: 'Universal paint primer'
  },

  // Tools
  {
    id: 'tools-1',
    name: 'Power Drill',
    price: 89.99,
    image: 'https://images.pexels.com/photos/1249611/pexels-photo-1249611.jpeg?auto=compress&cs=tinysrgb&w=400',
    category: 'tools',
    unitTypes: ['per piece', 'per set'],
    description: 'Cordless power drill with battery'
  },
  {
    id: 'tools-2',
    name: 'Circular Saw',
    price: 145.00,
    image: 'https://images.pexels.com/photos/1266810/pexels-photo-1266810.jpeg?auto=compress&cs=tinysrgb&w=400',
    category: 'tools',
    unitTypes: ['per piece'],
    description: 'Electric circular saw'
  },
  {
    id: 'tools-3',
    name: 'Hammer Set',
    price: 35.50,
    image: 'https://images.pexels.com/photos/1249611/pexels-photo-1249611.jpeg?auto=compress&cs=tinysrgb&w=400',
    category: 'tools',
    unitTypes: ['per set', 'per piece'],
    description: 'Professional hammer set'
  },

  // Hardware
  {
    id: 'hardware-1',
    name: 'Hex Bolts',
    price: 0.45,
    image: 'https://images.pexels.com/photos/1669799/pexels-photo-1669799.jpeg?auto=compress&cs=tinysrgb&w=400',
    category: 'hardware',
    unitTypes: ['per piece', 'per dozen', 'per box', 'per pound'],
    description: 'Galvanized hex bolts M10'
  },
  {
    id: 'hardware-2',
    name: 'Wood Screws',
    price: 0.25,
    image: 'https://images.pexels.com/photos/209235/pexels-photo-209235.jpeg?auto=compress&cs=tinysrgb&w=400',
    category: 'hardware',
    unitTypes: ['per piece', 'per dozen', 'per box', 'per pound'],
    description: 'Self-tapping wood screws'
  },
  {
    id: 'hardware-3',
    name: 'Washers',
    price: 0.15,
    image: 'https://images.pexels.com/photos/1266810/pexels-photo-1266810.jpeg?auto=compress&cs=tinysrgb&w=400',
    category: 'hardware',
    unitTypes: ['per piece', 'per dozen', 'per box', 'per pound'],
    description: 'Flat washers, various sizes'
  },
];