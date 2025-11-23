import React, { useState, useEffect } from 'react';
import { Minus, Plus, Trash2, Undo2 } from 'lucide-react';
import { CartItem as CartItemType } from '../types';

interface CartItemProps {
  item: CartItemType;
  onQuantityChange: (id: string, unit: string, quantity: number) => void;
  onRemove: (id: string, unit: string) => void;
}

interface UndoSnackbarProps {
  isVisible: boolean;
  itemName: string;
  onUndo: () => void;
  onDismiss: () => void;
}

const UndoSnackbar: React.FC<UndoSnackbarProps> = ({ isVisible, itemName, onUndo, onDismiss }) => {
  useEffect(() => {
    if (isVisible) {
      const timer = setTimeout(() => {
        onDismiss();
      }, 5000);
      return () => clearTimeout(timer);
    }
  }, [isVisible, onDismiss]);

  if (!isVisible) return null;

  return (
    <div className="fixed bottom-4 left-1/2 transform -translate-x-1/2 bg-gray-800 text-white px-4 py-3 rounded-lg shadow-lg flex items-center space-x-3 z-50 animate-slide-up">
      <span className="text-sm">Removed "{itemName}"</span>
      <button
        onClick={onUndo}
        className="flex items-center space-x-1 text-blue-300 hover:text-blue-200 text-sm font-medium"
      >
        <Undo2 className="w-3 h-3" />
        <span>Undo</span>
      </button>
      <button
        onClick={onDismiss}
        className="text-gray-400 hover:text-gray-300 ml-2"
      >
        ×
      </button>
    </div>
  );
};

export const CartItem: React.FC<CartItemProps> = ({ item, onQuantityChange, onRemove }) => {
  const [showUndo, setShowUndo] = useState(false);
  const [removedItem, setRemovedItem] = useState<CartItemType | null>(null);

  const handleQuantityChange = (delta: number) => {
    const newQuantity = Math.max(0, item.quantity + delta);
    if (newQuantity === 0) {
      handleRemove();
    } else {
      onQuantityChange(item.id, item.selectedUnit, newQuantity);
    }
  };

  const handleRemove = () => {
    setRemovedItem(item);
    setShowUndo(true);
    onRemove(item.id, item.selectedUnit);
  };

  const handleUndo = () => {
    if (removedItem) {
      onQuantityChange(removedItem.id, removedItem.selectedUnit, removedItem.quantity);
      setShowUndo(false);
      setRemovedItem(null);
    }
  };

  const handleDismissUndo = () => {
    setShowUndo(false);
    setRemovedItem(null);
  };

  return (
    <>
      <div className="flex items-center space-x-3 bg-gray-50 rounded-lg p-3">
        <img
          src={item.image}
          alt={item.name}
          className="w-12 h-12 rounded-lg object-cover"
        />
        <div className="flex-1 min-w-0">
          <h4 className="font-medium text-gray-900 truncate">{item.name}</h4>
          <p className="text-sm text-gray-500">{item.selectedUnit}</p>
          <p className="text-sm font-medium text-gray-900">฿{item.price.toFixed(2)} each</p>
        </div>
        <div className="flex items-center space-x-2">
          <div className="flex items-center space-x-1 bg-white rounded-lg border border-gray-200">
            <button
              onClick={() => handleQuantityChange(-1)}
              className="w-8 h-8 rounded-l-lg hover:bg-gray-100 flex items-center justify-center transition-colors"
              disabled={item.quantity <= 1}
            >
              <Minus className="w-3 h-3" />
            </button>
            <span className="w-8 text-center text-sm font-medium">{item.quantity}</span>
            <button
              onClick={() => handleQuantityChange(1)}
              className="w-8 h-8 rounded-r-lg hover:bg-gray-100 flex items-center justify-center transition-colors"
            >
              <Plus className="w-3 h-3" />
            </button>
          </div>
          <button
            onClick={handleRemove}
            className="w-8 h-8 rounded-lg bg-red-50 hover:bg-red-100 text-red-600 flex items-center justify-center transition-colors"
          >
            <Trash2 className="w-3 h-3" />
          </button>
        </div>
        <div className="text-right">
          <div className="font-bold text-gray-900">
            ฿{(item.price * item.quantity).toFixed(2)}
          </div>
        </div>
      </div>

      <UndoSnackbar
        isVisible={showUndo}
        itemName={item.name}
        onUndo={handleUndo}
        onDismiss={handleDismissUndo}
      />
    </>
  );
};