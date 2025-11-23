import React, { useState } from 'react';
import { X, QrCode, Printer } from 'lucide-react';

interface QRCodeGeneratorProps {
  isOpen: boolean;
  onClose: () => void;
}

export const QRCodeGenerator: React.FC<QRCodeGeneratorProps> = ({ isOpen, onClose }) => {
  const [price, setPrice] = useState('');
  const [quantity, setQuantity] = useState(1);

  const generateQRCode = (text: string) => {
    // Simple QR code placeholder - in a real app, you'd use a QR library
    return `https://api.qrserver.com/v1/create-qr-code/?size=150x150&data=${encodeURIComponent(text)}`;
  };

  const handlePrint = () => {
    const printWindow = window.open('', '_blank');
    if (!printWindow) return;

    const qrData = `Price: ฿${price}`;
    const qrUrl = generateQRCode(qrData);
    
    const labelsPerRow = 3;
    const rows = Math.ceil(quantity / labelsPerRow);
    
    let labelsHTML = '';
    for (let i = 0; i < quantity; i++) {
      labelsHTML += `
        <div style="
          display: inline-block;
          width: 200px;
          height: 200px;
          margin: 10px;
          text-align: center;
          border: 1px solid #ddd;
          padding: 10px;
          vertical-align: top;
        ">
          <img src="${qrUrl}" alt="QR Code" style="width: 120px; height: 120px; margin-bottom: 10px;" />
          <div style="font-size: 14px; font-weight: bold;">฿${price}</div>
        </div>
      `;
    }

    printWindow.document.write(`
      <html>
        <head>
          <title>QR Code Labels</title>
          <style>
            body { font-family: Arial, sans-serif; margin: 20px; }
            @media print {
              body { margin: 0; }
            }
          </style>
        </head>
        <body>
          <h2>QR Code Price Labels</h2>
          <div>${labelsHTML}</div>
        </body>
      </html>
    `);
    
    printWindow.document.close();
    printWindow.print();
  };

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
      <div className="bg-white rounded-lg shadow-xl max-w-2xl w-full mx-4">
        <div className="flex items-center justify-between p-6 border-b border-gray-200">
          <h3 className="text-lg font-semibold text-gray-900 flex items-center space-x-2">
            <QrCode className="w-5 h-5" />
            <span>QR Code Generator</span>
          </h3>
          <button
            onClick={onClose}
            className="text-gray-400 hover:text-gray-600 transition-colors"
          >
            <X className="w-5 h-5" />
          </button>
        </div>
        
        <div className="p-6">
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            <div>
              <div className="space-y-4">
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">
                    Price (THB)
                  </label>
                  <input
                    type="number"
                    value={price}
                    onChange={(e) => setPrice(e.target.value)}
                    placeholder="Enter price"
                    className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                  />
                </div>
                
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">
                    Quantity
                  </label>
                  <input
                    type="number"
                    value={quantity}
                    onChange={(e) => setQuantity(Math.max(1, parseInt(e.target.value) || 1))}
                    min="1"
                    className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                  />
                </div>
              </div>
            </div>
            
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-2">
                Preview
              </label>
              <div className="border border-gray-300 rounded-lg p-4 text-center bg-gray-50">
                {price ? (
                  <div>
                    <img
                      src={generateQRCode(`Price: ฿${price}`)}
                      alt="QR Code Preview"
                      className="w-32 h-32 mx-auto mb-2"
                    />
                    <div className="text-sm font-medium text-gray-900">฿{price}</div>
                  </div>
                ) : (
                  <div className="text-gray-500 py-8">
                    Enter a price to see preview
                  </div>
                )}
              </div>
            </div>
          </div>
        </div>
        
        <div className="flex items-center justify-end space-x-3 p-6 border-t border-gray-200">
          <button
            onClick={onClose}
            className="px-4 py-2 text-sm font-medium text-gray-700 bg-gray-100 hover:bg-gray-200 rounded-lg transition-colors"
          >
            Cancel
          </button>
          <button
            onClick={handlePrint}
            disabled={!price}
            className="px-4 py-2 text-sm font-medium text-white bg-blue-500 hover:bg-blue-600 disabled:bg-gray-300 disabled:cursor-not-allowed rounded-lg transition-colors flex items-center space-x-2"
          >
            <Printer className="w-4 h-4" />
            <span>Print Labels</span>
          </button>
        </div>
      </div>
    </div>
  );
};