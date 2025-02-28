import React, { useRef, useEffect, useState } from 'react';
import ProductSearch from './ProductSearch';
import type { Product } from '../../types';
import { processScannedSku } from '../../utils/scannerUtils'; 
import { X, Search, Phone, User } from 'lucide-react';
import { supabase } from '../../lib/supabase';
import { formatPhoneNumber } from '../../utils/phoneUtils';

interface ProductScannerProps {
  scanning: boolean;
  scannedSku: string;
  onScannedSkuChange: (sku: string) => void;
  onProductSelect: (product: Product) => void;
  onCustomerSelect?: (customer: any) => void;
  bulkMode?: boolean;
  onBulkScan?: (items: Array<{sku: string, quantity: number}>) => void;
  onScanningChange: (scanning: boolean) => void;
}

const ProductScanner: React.FC<ProductScannerProps> = ({
  scanning,
  scannedSku,
  onScannedSkuChange,
  onProductSelect,
  onCustomerSelect,
  bulkMode = false,
  onBulkScan,
  onScanningChange
}) => {
  const scanInputRef = useRef<HTMLInputElement>(null);
  const lastKeyTime = useRef<number>(0);
  const buffer = useRef<string>('');
  const isShiftPressed = useRef<boolean>(false);
  const [bulkItems, setBulkItems] = useState<Array<{sku: string, quantity: number}>>([]);
  const [debugMode, setDebugMode] = useState<boolean>(false);
  const [showContactSearch, setShowContactSearch] = useState(false);
  const [searchTerm, setSearchTerm] = useState('');
  const [searchResults, setSearchResults] = useState<any[]>([]);
  const [searching, setSearching] = useState(false);
  const searchTimeout = useRef<NodeJS.Timeout>();
  const SCAN_TIMEOUT = 30; // 30ms timeout for ultra-rapid scanning (was 50ms)
  const SKU_PATTERN = "RIMO1200597"; // The expected SKU pattern

  // Pre-load audio for faster beep response
  const beepAudio = useRef<HTMLAudioElement | null>(null);
  
  useEffect(() => {
    // Create and preload the audio element once
    beepAudio.current = new Audio('path/to/beep.mp3');
    beepAudio.current.preload = 'auto';
    
    // Cleanup on unmount
    return () => {
      beepAudio.current = null;
    };
  }, []);
  
  const playSuccessBeep = () => {
    // Use the preloaded audio element for faster response
    if (beepAudio.current) {
      // Clone the audio element for concurrent playback
      const audioClone = beepAudio.current.cloneNode() as HTMLAudioElement;
      audioClone.volume = 0.5; // Lower volume for better performance
      audioClone.play().catch(err => {
        if (debugMode) console.log('Audio play error:', err);
      });
    }
  };

  // Pre-compile regex pattern for faster matching
  const skuRegex = new RegExp(SKU_PATTERN, 'g');
  
  useEffect(() => {
    if (scanning) {
      scanInputRef.current?.focus();
      
      // Cache DOM operations for better performance
      const inputElement = scanInputRef.current;
      
      const handleKeyDown = (e: KeyboardEvent) => {
        // Check for ESC key
        if (e.key === 'Escape') {
          e.preventDefault();
          onScanningChange(false);
          return;
        }
        
        // Toggle debug mode with Ctrl+D
        if (e.ctrlKey && e.key === 'd') {
          e.preventDefault();
          setDebugMode(prev => !prev);
          console.log('Debug mode:', !debugMode);
          return;
        }
        
        // Track shift key press
        if (e.key === 'Shift') {
          isShiftPressed.current = true;
          return;
        }

        const now = Date.now();
        
        // If it's been more than SCAN_TIMEOUT since the last keypress, reset the buffer
        if (now - lastKeyTime.current > SCAN_TIMEOUT && e.key !== 'Shift') {
          if (debugMode) console.log('Buffer reset due to timeout');
          buffer.current = '';
        }
        
        // Update last key time (only for non-modifier keys)
        if (e.key !== 'Shift' && e.key !== 'Control' && e.key !== 'Alt') {
          lastKeyTime.current = now;
        }

        // Process keypress (optimized for speed)
        if (e.key === 'Enter') {
          e.preventDefault();
          processBuffer();
        } else if (e.key !== 'Shift' && e.key !== 'Control' && e.key !== 'Alt') {
          // Only add actual characters to the buffer, not modifier keys
          buffer.current += e.key;
          
          // Fast check if the buffer is getting too long (prevents memory issues with very long scans)
          if (buffer.current.length > 1000) {
            buffer.current = buffer.current.substring(buffer.current.length - 200);
          }
          
          // Faster pattern check using endsWith
          if (buffer.current.endsWith(SKU_PATTERN)) {
            // Process the SKU immediately for faster response
            processSku(SKU_PATTERN);
            
            // Optimize by only keeping what's after the last pattern
            const patternIndex = buffer.current.lastIndexOf(SKU_PATTERN);
            buffer.current = buffer.current.substring(patternIndex + SKU_PATTERN.length);
            
            if (debugMode) console.log('Pattern processed, remaining buffer:', buffer.current);
          }
          
          if (debugMode) console.log('Buffer updated:', buffer.current);
        }
      };
      
      // Helper function to process the current buffer (optimized)
      const processBuffer = () => {
        if (!buffer.current) return;
        
        if (debugMode) console.log('Processing scan buffer:', buffer.current);
        
        // Use regex to find all matches at once (faster for multiple occurrences)
        const matches = buffer.current.match(skuRegex);
        
        if (matches && matches.length > 0) {
          // Process all matched patterns at once
          for (const match of matches) {
            processSku(match);
          }
        } else {
          // Process as a regular SKU
          processSku(buffer.current);
        }
        
        // Clear buffer after processing
        buffer.current = '';
      };
      
      // Fast lookup map for bulk items
      const bulkItemsMap = new Map();
      bulkItems.forEach(item => {
        bulkItemsMap.set(item.sku, item);
      });
      
      // Helper function to process a SKU (optimized)
      const processSku = (sku: string) => {
        if (!sku) return;
        
        if (bulkMode) {
          // Use a faster approach for bulk mode with Map lookup
          const existingItem = bulkItemsMap.get(sku);
          
          if (existingItem) {
            // Update existing item quantity (faster than array operations)
            setBulkItems(prev => {
              // Using direct array mutation for speed in this specific update case
              const updatedItems = [...prev];
              const index = updatedItems.findIndex(item => item.sku === sku);
              if (index !== -1) {
                updatedItems[index] = { 
                  ...updatedItems[index], 
                  quantity: updatedItems[index].quantity + 1 
                };
              }
              return updatedItems;
            });
          } else {
            // Add new item
            setBulkItems(prev => [...prev, { sku, quantity: 1 }]);
          }
          
          // Play success beep (only if audio is enabled)
          requestAnimationFrame(() => {
            playSuccessBeep();
          });
        } else {
          // Process immediately
          processScannedSku(sku, onProductSelect, onScannedSkuChange);
        }
      };

      // Debounced key up handler for better performance
      const handleKeyUp = (e: KeyboardEvent) => {
        // Track shift key release
        if (e.key === 'Shift') {
          isShiftPressed.current = false;
        }
      };

      window.addEventListener('keydown', handleKeyDown);
      window.addEventListener('keyup', handleKeyUp);
      
      return () => {
        window.removeEventListener('keydown', handleKeyDown);
        window.removeEventListener('keyup', handleKeyUp);
      };
    }
  }, [scanning, onScannedSkuChange, onProductSelect, bulkMode, bulkItems, debugMode]);

  const handleBulkComplete = async () => {
    if (onBulkScan && bulkItems.length > 0) {
      await onBulkScan(bulkItems);
      setBulkItems([]);
    }
  };

  // For manual input submission
  const handleManualSubmit = (inputSku: string) => {
    if (!inputSku) return;
    
    if (bulkMode) {
      const existingItem = bulkItems.find(item => item.sku === inputSku);
      if (existingItem) {
        setBulkItems(prev => prev.map(item => 
          item.sku === inputSku 
            ? { ...item, quantity: item.quantity + 1 }
            : item
        ));
      } else {
        setBulkItems(prev => [...prev, { sku: inputSku, quantity: 1 }]);
      }
      onScannedSkuChange('');
      playSuccessBeep();
    } else {
      processScannedSku(inputSku, onProductSelect, onScannedSkuChange);
    }
  };

  // Handle contact search
  const handleContactSearch = async (term: string) => {
    setSearchTerm(term);
    
    // Clear previous timeout
    if (searchTimeout.current) {
      clearTimeout(searchTimeout.current);
    }

    // Don't search if term is too short
    if (term.length < 2) {
      setSearchResults([]);
      return;
    }

    // Debounce search
    searchTimeout.current = setTimeout(async () => {
      try {
        setSearching(true);
        
        // Search by name or phone
        const { data, error } = await supabase
          .from('customers')
          .select('*')
          .or(`name.ilike.%${term}%,phone.ilike.%${term}%`)
          .limit(5);

        if (error) throw error;
        setSearchResults(data || []);
      } catch (error) {
        console.error('Error searching contacts:', error);
      } finally {
        setSearching(false);
      }
    }, 300);
  };

  const handleSelectContact = (customer: any) => {
    if (onCustomerSelect) {
      onCustomerSelect(customer);
    }
    setShowContactSearch(false);
    setSearchTerm('');
    setSearchResults([]);
  };

  return scanning ? (
    <div className="relative scanning-container">
      <div className="absolute left-0 top-0 bottom-0 w-2">
        <div className="h-full w-full bg-green-500 opacity-25 animate-pulse" />
      </div>
      
      {/* Contact Search Button */}
      <button
        onClick={() => setShowContactSearch(true)}
        className="absolute right-4 top-4 btn btn-secondary flex items-center gap-2 z-10"
      >
        <User className="h-4 w-4" />
        <span>Search Contacts</span>
      </button>

      {/* Contact Search Modal */}
      {showContactSearch && (
        <div className="fixed inset-0 bg-black/60 backdrop-blur-sm flex items-center justify-center z-50">
          <div className="bg-white rounded-lg w-full max-w-lg mx-4">
            <div className="flex justify-between items-center p-4 border-b">
              <h3 className="text-lg font-medium">Search Contacts</h3>
              <button
                onClick={() => {
                  setShowContactSearch(false);
                  setSearchTerm('');
                  setSearchResults([]);
                }}
                className="text-gray-500 hover:text-gray-700"
              >
                <X className="h-5 w-5" />
              </button>
            </div>

            <div className="p-4">
              <div className="relative">
                <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 text-gray-400 h-5 w-5" />
                <input
                  type="text"
                  placeholder="Search by name or phone..."
                  className="input pl-10 w-full"
                  value={searchTerm}
                  onChange={(e) => handleContactSearch(e.target.value)}
                />
              </div>

              <div className="mt-4 space-y-2 max-h-96 overflow-y-auto">
                {searching ? (
                  <div className="text-center py-4 text-gray-500">
                    Searching...
                  </div>
                ) : searchResults.length > 0 ? (
                  searchResults.map((customer) => (
                    <button
                      key={customer.id}
                      onClick={() => handleSelectContact(customer)}
                      className="w-full text-left p-3 hover:bg-gray-50 rounded-lg flex items-center gap-3"
                    >
                      <div className="h-10 w-10 rounded-full bg-blue-100 flex items-center justify-center">
                        <span className="text-blue-600 font-semibold">
                          {customer.name[0].toUpperCase()}
                        </span>
                      </div>
                      <div>
                        <div className="font-medium">{customer.name}</div>
                        <div className="text-sm text-gray-500 flex items-center gap-2">
                          <Phone className="h-3.5 w-3.5" />
                          <span className="font-mono">
                            {formatPhoneNumber(customer.phone)}
                          </span>
                          <span className={`px-2 py-0.5 rounded-full text-xs ${
                            customer.type === 'wholesaler'
                              ? 'bg-purple-100 text-purple-800'
                              : 'bg-green-100 text-green-800'
                          }`}>
                            {customer.type}
                          </span>
                        </div>
                      </div>
                    </button>
                  ))
                ) : searchTerm.length > 0 ? (
                  <div className="text-center py-4 text-gray-500">
                    No contacts found
                  </div>
                ) : null}
              </div>
            </div>
          </div>
        </div>
      )}

      {debugMode && (
        <div className="bg-yellow-800 text-yellow-200 p-2 text-sm mb-2 rounded">
          <p>Debug Mode Active - Press Ctrl+D to toggle</p>
          <p>Current Buffer: {buffer.current}</p>
          <p>Expected Pattern: {SKU_PATTERN}</p>
          <p>Items Scanned: {bulkItems.length}</p>
        </div>
      )}
      <div className="space-y-4">
        <input
          type="text"
          value={scannedSku}
          onChange={(e) => onScannedSkuChange(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'Enter') {
              e.preventDefault();
              handleManualSubmit(scannedSku);
            }
          }}
          placeholder={bulkMode ? "Scan items in bulk..." : "Scan barcode or enter SKU..."}
          className="input w-full bg-gray-900 text-white font-mono text-lg tracking-wider pl-4"
          ref={scanInputRef}
          autoComplete="off"
          autoFocus
          spellCheck={false}
          onBlur={() => {
            // Re-focus the input when it loses focus
            if (scanning) {
              setTimeout(() => scanInputRef.current?.focus(), 100);
            }
          }}
        />

        {bulkMode && (
          <div className="bg-gray-800 rounded-lg p-4">
            <div className="flex justify-between items-center mb-4">
              <h3 className="text-white font-medium">Scanned Items ({bulkItems.length})</h3>
              <div className="space-x-2">
                <button
                  onClick={() => setBulkItems([])}
                  className="btn btn-secondary text-sm"
                  disabled={bulkItems.length === 0}
                >
                  Clear All
                </button>
                <button
                  onClick={handleBulkComplete}
                  className="btn btn-primary text-sm"
                  disabled={bulkItems.length === 0}
                >
                  Complete Bulk Scan
                </button>
              </div>
            </div>
            
            <div className="space-y-2 max-h-60 overflow-y-auto">
              {bulkItems.map((item, index) => (
                <div key={index} className="flex items-center justify-between bg-gray-700 p-2 rounded">
                  <span className="font-mono text-white">{item.sku}</span>
                  <div className="flex items-center gap-2">
                    <span className="text-white">×{item.quantity}</span>
                    <button
                      onClick={() => setBulkItems(prev => prev.filter((_, i) => i !== index))}
                      className="text-red-400 hover:text-red-300 p-1"
                    >
                      <X className="h-4 w-4" />
                    </button>
                  </div>
                </div>
              ))}
            </div>
          </div>
        )}
      </div>
      <div className="absolute right-3 top-1/2 transform -translate-y-1/2 flex items-center gap-2">
        <div className="text-white text-sm">
          {bulkMode ? 'Bulk Inventory Mode' : 'Scanning Mode'} Active
        </div>
        <div className="w-3 h-3 bg-green-500 rounded-full animate-pulse">
          <div className="absolute w-3 h-3 bg-green-500 rounded-full animate-ping" />
        </div>
      </div>
    </div>
  ) : (
    <ProductSearch onSelect={onProductSelect} />
  );
};

export default ProductScanner;