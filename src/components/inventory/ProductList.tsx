import React, { useState, useEffect } from 'react';
import { Plus, Search, QrCode, Printer, Edit, Trash2, Copy, Box, AlertTriangle, Filter, ArrowUpDown, Package } from 'lucide-react';
import type { Product } from '../../types';
import { QRCodeSVG } from 'qrcode.react';
import { format } from 'date-fns';
import { supabase } from '../../lib/supabase';
import { hasPermission } from '../../lib/auth';
import ProductForm from './ProductForm';
import { printQRCodes } from '../../utils/barcodeGenerator';
import { useToast } from '../../hooks/useToast';
import { formatCurrency } from '../../utils/quotation';

interface FilterOptions {
  deadStock: boolean;
  slowMoving: boolean;
  category: string;
  manufacturer: string;
  priceRange: {
    min: number;
    max: number;
  };
  stockLevel: {
    min: number;
    max: number;
  };
}

const ProductList = () => {
  const [searchTerm, setSearchTerm] = useState('');
  const [showQR, setShowQR] = useState<string | null>(null);
  const [products, setProducts] = useState<Product[]>([]);
  const [showForm, setShowForm] = useState(false);
  const [editingProduct, setEditingProduct] = useState<Product | undefined>();
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [showDeleteConfirm, setShowDeleteConfirm] = useState<string | null>(null);
  const { addToast } = useToast();
  const [filters, setFilters] = useState<FilterOptions>({
    deadStock: false,
    slowMoving: false,
    category: '',
    manufacturer: '',
    priceRange: { min: 0, max: 1000000 },
    stockLevel: { min: 0, max: 1000 }
  });
  const [categories, setCategories] = useState<string[]>([]);
  const [manufacturers, setManufacturers] = useState<string[]>([]);
  const [sortField, setSortField] = useState<string>('name');
  const [sortOrder, setSortOrder] = useState<'asc' | 'desc'>('asc');
  const [deadStockDays, setDeadStockDays] = useState(90); // Default 90 days

  useEffect(() => {
    fetchProducts();
  }, []);

  const fetchProducts = async () => {
    try {
      setError(null);
      const { data, error } = await supabase
        .from('products')
        .select('*')
        .order(sortField, { ascending: sortOrder === 'asc' });

      if (error) throw error;
      
      const transformedProducts = data.map(transformProduct);
      setProducts(transformedProducts);
      
      // Extract unique categories and manufacturers
      setCategories([...new Set(transformedProducts.map(p => p.category))]);
      setManufacturers([...new Set(transformedProducts.map(p => p.manufacturer))]);
    } catch (error) {
      console.error('Error fetching products:', error);
      addToast({
        title: 'Error',
        message: 'Failed to load products. Please try again.',
        type: 'error'
      });
    } finally {
      setLoading(false);
    }
  };

  const transformProduct = (data: any): Product => ({
    id: data.id,
    name: data.name,
    description: data.description || '',
    manufacturer: data.manufacturer,
    sku: data.sku,
    buyPrice: Number(data.buy_price),
    wholesalePrice: Number(data.wholesale_price),
    retailPrice: Number(data.retail_price),
    stockLevel: Number(data.stock_level),
    category: data.category,
    imageUrl: data.image_url || '',
    qrCode: data.qr_code || '',
    code128: data.code128 || '',
    cipher: data.cipher || '',
    additionalInfo: data.additional_info || '',
    lastSoldAt: data.last_sold_at,
    deadStockStatus: data.dead_stock_status,
    deadStockDays: data.dead_stock_days
  });

  const handleEditProduct = async (productData: any) => {
    if (!editingProduct) return;
    
    try {
      // Validate required numeric fields
      const requiredFields = ['buy_price', 'wholesale_price', 'retail_price', 'stock_level'];
      for (const field of requiredFields) {
        if (!productData[field] || isNaN(Number(productData[field]))) {
          throw new Error(`Invalid ${field.replace('_', ' ')}`);
        }
      }

      // Ensure all prices are positive numbers
      if (productData.buy_price <= 0) throw new Error('Buy price must be greater than 0');
      if (productData.wholesale_price <= productData.buy_price) {
        throw new Error('Wholesale price must be greater than buy price');
      }
      if (productData.retail_price <= productData.wholesale_price) {
        throw new Error('Retail price must be greater than wholesale price');
      }

      // Transform the data to match database column names
      const dbData = {
        name: productData.name,
        description: productData.description,
        manufacturer: productData.manufacturer,
        buy_price: Number(productData.buy_price),
        wholesale_price: Number(productData.wholesale_price),
        retail_price: Number(productData.retail_price),
        stock_level: Number(productData.stock_level),
        category: productData.category,
        image_url: productData.imageUrl,
        qr_code: productData.qrCode,
        code128: productData.code128,
        cipher: productData.cipher,
        additional_info: productData.additionalInfo
      };

      const { data, error } = await supabase
        .from('products')
        .update(dbData)
        .eq('id', editingProduct.id)
        .select()
        .single();

      if (error) throw error;
      setProducts(prev => prev.map(p => p.id === editingProduct.id ? transformProduct(data) : p));
      setEditingProduct(undefined);
      addToast({
        title: 'Success',
        message: 'Product updated successfully',
        type: 'success'
      });
    } catch (error: any) {
      console.error('Error updating product:', error);
      addToast({
        title: 'Error',
        message: error.message || 'Error updating product. Please try again.',
        type: 'error',
        duration: 5000
      });
    }
  };

  const handleAddProduct = async (productData: any) => {
    try {
      // Console log to debug
      console.log('Product data before processing:', productData);
      
      // Create a simplified object with only necessary fields
      const insertData = {};
      
      // Only add fields that we know exist in the database
      const validFields = [
        'name', 'description', 'manufacturer', 'category', 
        'buy_price', 'wholesale_price', 'retail_price', 'stock_level',
        'image_url', 'additional_info', 'sku', 'qr_code', 'code128', 'cipher'
      ];
      
      validFields.forEach(field => {
        if (field in productData) {
          insertData[field] = productData[field];
        }
      });
      
      console.log('Data being sent to Supabase:', insertData);
      
      // Create database record with valid fields only
      const { data, error } = await supabase
        .from('products')
        .insert([insertData])
        .select()
        .single();
        
      console.log('Supabase response:', { data, error });
    } catch (error) {
      console.error('Error adding product:', error);
      addToast({
        title: 'Error',
        message: 'Failed to add product',
        type: 'error'
      });
    }
  };

  const handlePrintLabel = (product: Product) => {
    if (!product.qrCode) return;
    try {
      printQRCodes([product.qrCode], `Print Label - ${product.sku}`);
    } catch (error) {
      console.error('Error printing label:', error);
      addToast({
        title: 'Error',
        message: 'Failed to print label',
        type: 'error'
      });
    }
  };

  const handleCopyToClipboard = (text: string) => {
    navigator.clipboard.writeText(text).then(() => {
      addToast({
        title: 'Success',
        message: 'SKU copied to clipboard',
        type: 'success'
      });
    }).catch(() => {
      // Fallback method if Clipboard API fails
      const textArea = document.createElement("textarea");
      textArea.value = text;
      document.body.appendChild(textArea);
      textArea.focus();
      textArea.select();
      try {
        document.execCommand('copy');
        addToast({
          title: 'Success',
          message: 'SKU copied to clipboard',
          type: 'success'
        });
      } catch (err) {
        addToast({
          title: 'Error',
          message: 'Failed to copy SKU',
          type: 'error'
        });
      }
      document.body.removeChild(textArea);
    });
  };

  const handleDelete = async (id: string) => {
    try {
      const { error } = await supabase
        .from('products')
        .delete()
        .eq('id', id);

      if (error) throw error;
      
      setProducts(prev => prev.filter(p => p.id !== id));
      addToast({
        title: 'Success',
        message: 'Product deleted successfully',
        type: 'success'
      });
    } catch (error) {
      console.error('Error deleting product:', error);
      addToast({
        title: 'Error',
        message: 'Failed to delete product',
        type: 'error'
      });
    }
  };

  const filteredProducts = products.filter(product => {
    // Search filter
    const searchMatch = 
      product.name?.toLowerCase().includes(searchTerm.toLowerCase()) ||
      product.sku.toLowerCase().includes(searchTerm.toLowerCase()) ||
      product.category.toLowerCase().includes(searchTerm.toLowerCase()) ||
      product.manufacturer.toLowerCase().includes(searchTerm.toLowerCase());

    if (!searchMatch) return false;

    // Category filter
    if (filters.category && product.category !== filters.category) {
      return false;
    }
    
    // Manufacturer filter
    if (filters.manufacturer && product.manufacturer !== filters.manufacturer) {
      return false;
    }
    
    // Price range filter
    if (product.retailPrice < filters.priceRange.min || 
        product.retailPrice > filters.priceRange.max) {
      return false;
    }

    // Stock level filter
    if (product.stockLevel < filters.stockLevel.min || 
        product.stockLevel > filters.stockLevel.max) {
      return false;
    }
    
    // Calculate days since last sold
    const daysSinceLastSold = product.lastSoldAt
      ? Math.floor((new Date().getTime() - new Date(product.lastSoldAt).getTime()) / (1000 * 60 * 60 * 24))
      : 999999; // Very large number for never sold items
    
    // Dead stock filter
    if (filters.deadStock && daysSinceLastSold < deadStockDays) {
      return false;
    }
    
    // Slow moving filter (items not sold in last 30 days)
    if (filters.slowMoving && daysSinceLastSold < 30) {
      return false;
    }
    
    return true;
  });

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="text-gray-500">Loading products...</div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
        <h2 className="text-2xl font-bold bg-gradient-to-r from-gray-800 to-gray-600 bg-clip-text text-transparent">
          Product Management
        </h2>
        <button 
          onClick={() => setShowForm(true)}
          className="btn btn-primary bg-gradient-to-r from-blue-600 to-blue-700 flex items-center gap-2 w-full sm:w-auto"
        >
          <Plus className="h-5 w-5" />
          Add Product
        </button>
      </div>

      {/* Search and Filters */}
      <div className="bg-white/90 backdrop-blur-sm rounded-2xl shadow-lg border border-gray-100 p-4">
        <div className="flex flex-col sm:flex-row gap-4">
          <div className="flex-1">
            <div className="relative">
              <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 text-gray-400 h-5 w-5" />
              <input
                type="text"
                placeholder="Search products..."
                className="input pl-10 w-full bg-white/80 backdrop-blur-sm border-gray-200/80 focus:border-blue-500/50 focus:ring-blue-500/50"
                value={searchTerm}
                onChange={(e) => setSearchTerm(e.target.value)}
              />
            </div>
          </div>

          <div className="flex flex-wrap gap-4">
            <select
              className="input w-40 bg-white/80 backdrop-blur-sm border-gray-200/80"
              value={filters.category}
              onChange={(e) => setFilters(prev => ({ ...prev, category: e.target.value }))}
            >
              <option value="">All Categories</option>
              {categories.map(category => (
                <option key={category} value={category}>{category}</option>
              ))}
            </select>

            <select
              className="input w-40 bg-white/80 backdrop-blur-sm border-gray-200/80"
              value={filters.manufacturer}
              onChange={(e) => setFilters(prev => ({ ...prev, manufacturer: e.target.value }))}
            >
              <option value="">All Manufacturers</option>
              {manufacturers.map(manufacturer => (
                <option key={manufacturer} value={manufacturer}>{manufacturer}</option>
              ))}
            </select>

            <button
              onClick={() => setSortOrder(prev => prev === 'asc' ? 'desc' : 'asc')}
              className="btn btn-secondary flex items-center gap-2"
            >
              <ArrowUpDown className="h-4 w-4" />
              {sortOrder === 'asc' ? 'Ascending' : 'Descending'}
            </button>
          </div>
        </div>

        <div className="mt-4 flex flex-wrap gap-4">
          <label className="flex items-center gap-2">
            <input
              type="checkbox"
              checked={filters.deadStock}
              onChange={(e) => setFilters(prev => ({ ...prev, deadStock: e.target.checked }))}
              className="rounded border-gray-300"
            />
            <span className="text-sm">Dead Stock</span>
            {filters.deadStock && (
              <select
                value={deadStockDays}
                onChange={(e) => setDeadStockDays(Number(e.target.value))}
                className="input h-8 text-sm"
              >
                <option value="60">60+ days</option>
                <option value="90">90+ days</option>
                <option value="120">120+ days</option>
              </select>
            )}
          </label>

          <label className="flex items-center gap-2">
            <input
              type="checkbox"
              checked={filters.slowMoving}
              onChange={(e) => setFilters(prev => ({ ...prev, slowMoving: e.target.checked }))}
              className="rounded border-gray-300"
            />
            <span className="text-sm">Slow Moving</span>
          </label>
        </div>
      </div>

      {/* Product Grid */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-6">
        {filteredProducts.map((product) => (
          <div key={product.id} className="group relative bg-white/90 backdrop-blur-sm rounded-2xl shadow-lg overflow-hidden transition-all duration-300 hover:-translate-y-1 hover:shadow-xl border border-gray-100">
            <div className="absolute inset-0 bg-gradient-to-br from-gray-900/5 to-gray-900/30 opacity-0 group-hover:opacity-100 transition-opacity duration-300" />
            
            <div onClick={() => setEditingProduct(product)} className="cursor-pointer">
              {product.imageUrl ? (
                <img
                  src={product.imageUrl}
                  alt={product.name}
                  className="w-full h-40 object-cover transition-transform duration-300 group-hover:scale-105"
                />
              ) : (
                <div className="w-full h-40 bg-gray-100 flex items-center justify-center">
                  <Package className="h-12 w-12 text-gray-400" />
                </div>
              )}
              
              <div className="p-6">
                <div className="flex justify-between items-start mb-3">
                  <h3 className="text-lg font-semibold text-gray-900">{product.name || product.sku}</h3>
                  <div className="text-right">
                    <p className="text-sm font-medium text-gray-900">₹{formatCurrency(product.retailPrice)}</p>
                    <p className="text-xs text-gray-500">MRP</p>
                  </div>
                </div>
                
                <div className="space-y-2 text-sm">
                  <div className="flex justify-between items-center">
                    <span className="text-gray-500">SKU:</span>
                    {hasPermission('view_sensitive_info') ? (
                      <button
                        onClick={(e) => handleCopyToClipboard(product.sku)}
                        className="font-mono text-gray-900 hover:text-blue-600 flex items-center gap-1"
                        title="Copy SKU to clipboard"
                      >
                        {product.sku.split('-').map((part, i) => {
                          return (
                          <React.Fragment key={i}>
                            {i > 0 && '-'}
                            <span className={i === 2 ? 'font-bold text-blue-600' : ''}>
                              {part}
                            </span>
                          </React.Fragment>
                        )})}
                        <Copy className="h-3 w-3 ml-1" />
                      </button>
                    ) : (
                      <span className="font-mono text-gray-900">
                        {product.sku.split('-').map((part, i) => {
                          return (
                          <React.Fragment key={i}>
                            {i > 0 && '-'}
                            <span className={i === 2 ? 'font-bold text-blue-600' : ''}>
                              {part}
                            </span>
                          </React.Fragment>
                        )})}
                      </span>
                    )}
                  </div>

                  <div className="flex justify-between items-center">
                    <span className="text-gray-500">Stock:</span>
                    <span className="font-medium">{product.stockLevel} units</span>
                  </div>

                  {hasPermission('view_sensitive_info') && (
                    <>
                      <div className="flex justify-between items-center">
                        <span className="text-gray-500">Buy Price:</span>
                        <span className="font-medium">₹{formatCurrency(product.buyPrice)}</span>
                      </div>
                      <div className="flex justify-between items-center">
                        <span className="text-gray-500">Wholesale:</span>
                        <span className="font-medium">₹{formatCurrency(product.wholesalePrice)}</span>
                      </div>
                    </>
                  )}

                  <div className="flex justify-between items-center">
                    <span className="text-gray-500">Category:</span>
                    <span className="font-medium">{product.category}</span>
                  </div>

                  <div className="flex justify-between items-center">
                    <span className="text-gray-500">Manufacturer:</span>
                    <div className="flex items-center gap-2">
                      <span className="font-medium">{product.manufacturer}</span>
                      {hasPermission('view_sensitive_info') && (
                        <span className="text-xs bg-blue-100 text-blue-800 px-2 py-0.5 rounded-full font-mono">
                          {product.sku.split('/')[1].split('-')[0]}
                        </span>
                      )}
                    </div>
                  </div>
                </div>

                {product.lastSoldAt && (
                  <div className="mt-3 text-xs">
                    <div className={`px-2 py-1 rounded-full inline-flex items-center ${
                      getDaysSinceLastSold(product.lastSoldAt) >= deadStockDays
                        ? 'bg-red-100 text-red-800'
                        : getDaysSinceLastSold(product.lastSoldAt) >= 30
                        ? 'bg-yellow-100 text-yellow-800'
                        : 'bg-green-100 text-green-800'
                    }`}>
                      Last sold: {format(new Date(product.lastSoldAt), 'dd/MM/yyyy')}
                    </div>
                  </div>
                )}
              </div>
            </div>

            <div className="absolute top-4 right-4 flex gap-2 opacity-0 group-hover:opacity-100 transition-opacity duration-300">
              <button
                onClick={(e) => {
                  e.stopPropagation();
                  handlePrintLabel(product);
                }}
                className="p-2 bg-white/90 backdrop-blur rounded-full shadow-lg hover:bg-white transition-colors duration-200"
                title="Print Label"
              >
                <Printer className="h-4 w-4" />
              </button>
              <button
                onClick={(e) => {
                  e.stopPropagation();
                  setShowQR(showQR === product.id ? null : product.id);
                }}
                className="p-2 bg-white/90 backdrop-blur rounded-full shadow-lg hover:bg-white transition-colors duration-200"
                title="Show QR Code"
              >
                <QrCode className="h-4 w-4" />
              </button>
              <button
                onClick={(e) => {
                  e.stopPropagation();
                  setEditingProduct(product);
                }}
                className="p-2 bg-white/90 backdrop-blur rounded-full shadow-lg hover:bg-white transition-colors duration-200"
                title="Edit Product"
              >
                <Edit className="h-4 w-4" />
              </button>
              <button
                onClick={(e) => {
                  e.stopPropagation();
                  setShowDeleteConfirm(product.id);
                }}
                className="p-2 bg-white/90 backdrop-blur rounded-full shadow-lg hover:bg-white transition-colors duration-200"
                title="Delete Product"
              >
                <Trash2 className="h-4 w-4" />
              </button>
            </div>

            {showQR === product.id && (
              <div className="absolute inset-0 bg-white/95 backdrop-blur flex items-center justify-center">
                <div className="text-center">
                  <QRCodeSVG value={product.qrCode} size={128} />
                  <button
                    onClick={() => setShowQR(null)}
                    className="mt-4 btn btn-secondary"
                  >
                    Close
                  </button>
                </div>
              </div>
            )}
          </div>
        ))}

        {filteredProducts.length === 0 && (
          <div className="col-span-full text-center py-12">
            <div className="flex justify-center mb-4">
              <AlertTriangle className="h-12 w-12 text-gray-400" />
            </div>
            <h3 className="text-lg font-medium text-gray-900">No products found</h3>
            <p className="mt-1 text-gray-500">
              {searchTerm 
                ? 'Try adjusting your search terms'
                : 'Add some products to get started'}
            </p>
          </div>
        )}
      </div>

      {(showForm || editingProduct) && (
        <ProductForm
          product={editingProduct}
          onClose={() => {
            setShowForm(false);
            setEditingProduct(undefined);
          }}
          onSubmit={editingProduct ? handleEditProduct : handleAddProduct}
        />
      )}

      {showDeleteConfirm && (
        <div className="fixed inset-0 bg-black/60 backdrop-blur-sm flex items-center justify-center z-50">
          <div className="bg-white rounded-lg p-6 max-w-md mx-4">
            <h3 className="text-lg font-semibold mb-4">Confirm Delete</h3>
            <p className="text-gray-600 mb-6">Are you sure you want to delete this product? This action cannot be undone.</p>
            <div className="flex justify-end gap-4">
              <button
                onClick={() => setShowDeleteConfirm(null)}
                className="btn btn-secondary"
              >
                Cancel
              </button>
              <button
                onClick={() => {
                  if (showDeleteConfirm) {
                    handleDelete(showDeleteConfirm);
                    setShowDeleteConfirm(null);
                  }
                }}
                className="btn btn-primary bg-red-600 hover:bg-red-700"
              >
                Delete
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

const getDaysSinceLastSold = (lastSoldAt: string | null) => {
  if (!lastSoldAt) return 999999;
  return Math.floor((new Date().getTime() - new Date(lastSoldAt).getTime()) / (1000 * 60 * 60 * 24));
};

export default ProductList;