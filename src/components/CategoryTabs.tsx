import React from 'react';

const categories = [
  { id: 'all', name: 'All Products', icon: '🏗️' },
  { id: 'roofing', name: 'Roofing', icon: '🏠' },
  { id: 'cement', name: 'Cement', icon: '🧱' },
  { id: 'steel', name: 'Steel', icon: '⚙️' },
  { id: 'paint', name: 'Paint', icon: '🎨' },
  { id: 'tools', name: 'Tools', icon: '🔨' },
  { id: 'hardware', name: 'Hardware', icon: '🔩' },
];

interface CategoryTabsProps {
  activeCategory: string;
  onCategoryChange: (category: string) => void;
}

export const CategoryTabs: React.FC<CategoryTabsProps> = ({ activeCategory, onCategoryChange }) => {
  return (
    <div className="bg-white border-b border-gray-200">
      <div className="px-6 py-4">
        <div className="flex space-x-2 overflow-x-auto">
          {categories.map((category) => (
            <button
              key={category.id}
              onClick={() => onCategoryChange(category.id)}
              className={`flex items-center space-x-2 px-4 py-2 rounded-lg whitespace-nowrap transition-colors ${
                activeCategory === category.id
                  ? 'bg-blue-500 text-white'
                  : 'bg-gray-100 text-gray-700 hover:bg-gray-200'
              }`}
            >
              <span className="text-lg">{category.icon}</span>
              <span className="font-medium">{category.name}</span>
            </button>
          ))}
        </div>
      </div>
    </div>
  );
};