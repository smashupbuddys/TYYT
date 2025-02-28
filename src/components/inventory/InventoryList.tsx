import React from 'react';
import { Plus, Search, QrCode, Printer, Edit, Trash2, Copy } from 'lucide-react';
import type { Product } from '../../types';
import { QRCodeSVG } from 'qrcode.react';
import { format } from 'date-fns';
import { supabase } from '../../lib/supabase';
import { hasPermission } from '../../lib/auth';
import ProductForm from './ProductForm';
import { printQRCodes } from '../../utils/barcodeGenerator';
import { useToast } from '../../hooks/useToast';

interface FilterOptions {
  deadStock: boolean;
  slowMoving: boolean;
  category: string;
  manufacturer: string;
}

const InventoryList = () => {
  const [searchTerm, setSearchTerm] = React.useState('');
  const [showQR, setShowQR] = React.useState<string | null>(null);
  const [products, setProducts] = React.useState<Product[]>([]);
  const [showForm, setShowForm] = React.useState(false);
  const [editingProduct, setEditingProduct] = React.useState<Product | undefined>();
  const [loading, setLoading] = React.useState(true);
  const [error, setError] = React.useState<string | null>(null);
  const [showDeleteConfirm, setShowDeleteConfirm] = React.useState<string | null>(null);
  const { addToast } = useToast();
  const [filters, setFilters] = React.useState<FilterOptions>({
    deadStock: false,
    slowMoving: false,
    category: '',
    manufacturer: ''
  });
  const [categories, setCategories] = React.useState<string[]>([]);
  const [manufacturers, setManufacturers] = React.useState<string[]>([]);
  const [deadStockDays, setDeadStockDays] = React.useState(90); // Default 90 days

  React.useEffect(() => {
    fetchProducts();
  }, []);

  const transformProduct = (data: any): Product => ({
    id: data.id,
    name: data.name,
    description: data.description,
    manufacturer: data.manufacturer,
    sku: data.sku,
    buyPrice: data.buy_price,
    wholesalePrice: data.wholesale_price,
    retailPrice: data.retail_price,
    stockLevel: data.stock_level,
    category: data.category,
    imageUrl: data.image_url,
    qrCode: data.qr_code,
    code128: data.code128,
    cipher: data.cipher,
    additionalInfo: data.additional_info,
    lastSoldAt: data.last_sold_at,
    deadStockStatus: data.dead_stock_status,
    deadStockDays: data.dead_stock_days
  });

  const fetchProducts = async () => {
    try {
      const { data, error } = await supabase
        .from('products')
        .select('*')
        .order('created_at', { ascending: false });

      if (error) throw error;
      const transformedProducts = (data || []).map(transformProduct);
      setProducts(transformedProducts);
      
      // Extract unique categories and manufacturers
      setCategories([...new Set(transformedProducts.map(p => p.category))]);
      setManufacturers([...new Set(transformedProducts.map(p => p.manufacturer))]);
    } catch (error) {
      console.error('Error fetching products:', error);
    } finally {
      setLoading(false);
    }
  };

  const handleAddProduct = async (productData: any) => {
    try {
      // Validate required fields
      const requiredFields = ['manufacturer', 'category', 'buy_price', 'wholesale_price', 'retail_price', 'stock_level'];
      const missingFields = requiredFields.filter(field => !productData[field]);
      
      if (missingFields.length > 0) {
        throw new Error(`Missing required fields: ${missingFields.join(', ')}`);
      }

      // Validate prices
      if (Number(productData.buy_price) <= 0) {
        throw new Error('Buy price must be greater than 0');
      }
      if (Number(productData.wholesale_price) <= Number(productData.buy_price)) {
        throw new Error('Wholesale price must be greater than buy price');
      }
      if (Number(productData.retail_price) <= Number(productData.wholesale_price)) {
        throw new Error('Retail price must be greater than wholesale price');
      }

      // Prepare data for database insert
      const insertData = {
        name: productData.name || null,
        description: productData.description,
        manufacturer: productData.manufacturer,
        category: productData.category,
        buy_price: Number(productData.buy_price),
        wholesale_price: Number(productData.wholesale_price),
        retail_price: Number(productData.retail_price),
        stock_level: Number(productData.stock_level),
        image_url: productData.image_url,
        additional_info: productData.additional_info,
        sku: productData.sku,
        qr_code: productData.qr_code,
        code128: productData.code128,
        cipher: productData.cipher
      };

      // Insert product
      const { data, error } = await supabase
        .from('products')
        .insert([insertData])
        .select()
        .single();

      if (error) throw error;
      if (!data) throw new Error('No data returned from database');

      setProducts(prev => [transformProduct(data), ...prev]);
      setShowForm(false);
      addToast({
        title: 'Success',
        message: 'Product added successfully',
        type: 'success'
      });
    } catch (error: any) {
      console.error('Error adding product:', error);
      addToast({
        title: 'Error',
        message: error.message || 'Failed to add product. Please check your input and try again.',
        type: 'error',
        duration: 7000
      });
    }
  };

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

  const handleDeleteProduct = async (id: string) => {
    if (!window.confirm('Are you sure you want to delete this product?')) return;

    try {
      const { error } = await supabase
        .from('products')
        .delete()
        .eq('id', id);

      if (error) throw error;
      setProducts(prev => prev.filter(p => p.id !== id));
    } catch (error) {
      console.error('Error deleting product:', error);
    }
  };

  const handlePrintLabel = (product: Product) => {
    if (!product.qrCode) return;
    try {
      printQRCodes([product.qrCode], `Print Label - ${product.sku}`);
    } catch (error) {
      console.error('Error printing label:', error);
    }
  };

  const handleCopyToClipboard = (text: string) => {
    // Fallback method if Clipboard API is not available
    const textArea = document.createElement("textarea");
    textArea.value = text;
    document.body.appendChild(textArea);
    textArea.focus();
    textArea.select();

    try {
      const successful = document.execCommand('copy');
      const msg = successful ? 'successful' : 'unsuccessful';
      console.log('Fallback: Copying text command was ' + msg);
      alert('SKU copied to clipboard!');
    } catch (err) {
      console.error('Fallback: Oops, unable to copy', err);
      alert('Failed to copy SKU. Please try again.');
    }

    document.body.removeChild(textArea);
  };

  const filteredProducts = products.filter(product => {
    // Skip items that don't exist
    if (!product) return false;
    
    // Get search term in lowercase once
    const searchLower = searchTerm.toLowerCase();
    
    // Check if any of the product's searchable fields contain the search term
    const matchesSearch = searchTerm === '' || (
      (product.name?.toLowerCase() || '').includes(searchLower) ||
      (product.sku?.toLowerCase() || '').includes(searchLower) ||
      (product.category?.toLowerCase() || '').includes(searchLower) ||
      (product.manufacturer?.toLowerCase() || '').includes(searchLower) ||
      (product.description?.toLowerCase() || '').includes(searchLower)
    );
    
    // Apply category filter
    if (filters.category && product.category !== filters.category) {
      return false;
    }
    
    // Apply manufacturer filter
    if (filters.manufacturer && product.manufacturer !== filters.manufacturer) {
      return false;
    }
    
    // Calculate days since last sold
    const daysSinceLastSold = product.lastSoldAt
      ? Math.floor((new Date().getTime() - new Date(product.lastSoldAt).getTime()) / (1000 * 60 * 60 * 24))
      : 999999; // Very large number for never sold items
    
    // Apply dead stock filter
    if (filters.deadStock && daysSinceLastSold < deadStockDays) {
      return false;
    }
    
    // Apply slow moving filter (items not sold in last 30 days)
    if (filters.slowMoving && daysSinceLastSold < 30) {
      return false;
    }
    
    return matchesSearch;
  });

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="text-gray-500">Loading inventory...</div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
        <h2 className="text-2xl font-bold bg-gradient-to-r from-gray-800 to-gray-600 bg-clip-text text-transparent">
          Inventory Management
        </h2>
        <button 
          onClick={() => setShowForm(true)}
          className="btn btn-primary bg-gradient-to-r from-blue-600 to-blue-700 flex items-center gap-2 w-full sm:w-auto"
        >
          <Plus className="h-5 w-5" />
          Add Product
        </button>
      </div>

      <div className="flex flex-col sm:flex-row gap-4">
        <div className="flex-1">
          <div className="relative">
            <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 text-gray-400 h-5 w-5" />
            <input
              type="text"
              placeholder="Search inventory..."
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
        </div>
      </div>

      <div className="flex items-center gap-4">
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

      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-6">
        {filteredProducts.map((product) => (
          <div key={product.id} className="group relative bg-white rounded-2xl shadow-lg overflow-hidden transition-all duration-300 hover:-translate-y-1 hover:shadow-xl">
            <div className="absolute inset-0 bg-gradient-to-br from-gray-900/5 to-gray-900/30 opacity-0 group-hover:opacity-100 transition-opacity duration-300" />
            <div onClick={() => setEditingProduct(product)} className="cursor-pointer">
              <img
                src={product.imageUrl}
                alt={product.name}
                className="w-full h-40 object-cover transition-transform duration-300 group-hover:scale-105"
              />
              <div className="relative p-6">
                <div className="flex justify-between items-start mb-3">
                  <h3 className="text-lg font-semibold text-gray-900">{product.name}</h3>
                  <div className="text-right">
                    <p className="text-sm font-medium text-gray-900">₹{product.retailPrice.toLocaleString()}</p>
                    <p className="text-xs text-gray-500">MRP</p>
                  </div>
                </div>
                
                <div className="space-y-2 text-sm">
                  <div className="flex justify-between items-center">
                    <span className="text-gray-500">SKU:</span>
                    {hasPermission('view_sensitive_info') ? (
                      <button
                        onClick={() => handleCopyToClipboard(product.sku)}
                        className="font-mono text-gray-900 hover:text-blue-600 flex items-center gap-1"
                        title="Copy SKU to clipboard"
                      >
                        {product.sku.split('-').map((part, i) => (
                          <React.Fragment key={i}>
                            {i > 0 && '-'}
                            <span className={i === 1 ? 'font-bold' : ''}>
                              {part}
                            </span>
                          </React.Fragment>
                        ))}
                        <Copy className="h-3 w-3 ml-1" />
                      </button>
                    ) : (
                      <span className="font-mono text-gray-900">
                        {product.sku.split('-').map((part, i) => (
                          <React.Fragment key={i}>
                            {i > 0 && '-'}
                            <span className={i === 1 ? 'font-bold' : ''}>
                              {part}
                            </span>
                          </React.Fragment>
                        ))}
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
                        <span className="font-medium">₹{product.buyPrice.toLocaleString()}</span>
                      </div>
                      <div className="flex justify-between items-center">
                        <span className="text-gray-500">Wholesale:</span>
                        <span className="font-medium">₹{product.wholesalePrice.toLocaleString()}</span>
                      </div>
                    </>
                  )}

                  <div className="flex justify-between items-center">
                    <span className="text-gray-500">Category:</span>
                    <span className="font-medium">{product.category}</span>
                  </div>

                  <div className="flex justify-between items-center">
                    <span className="text-gray-500">Manufacturer:</span>
                    <span className="font-medium">{product.manufacturer}</span>
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
                onClick={() => handlePrintLabel(product)}
                className="p-2 bg-white/90 backdrop-blur rounded-full shadow-lg hover:bg-white transition-colors duration-200"
                title="Print Label"
              >
                <Printer className="h-4 w-4" />
              </button>
              <button
                onClick={() => setShowQR(showQR === product.id ? null : product.id)}
                className="p-2 bg-white/90 backdrop-blur rounded-full shadow-lg hover:bg-white transition-colors duration-200"
                title="Show QR Code"
              >
                <QrCode className="h-4 w-4" />
              </button>
              <button
                onClick={() => setEditingProduct(product)}
                className="p-2 bg-white/90 backdrop-blur rounded-full shadow-lg hover:bg-white transition-colors duration-200"
                title="Edit Product"
              >
                <Edit className="h-4 w-4" />
              </button>
              <button
                onClick={() => handleDeleteProduct(product.id)}
                className="p-2 bg-white/90 backdrop-blur rounded-full shadow-lg hover:bg-white transition-colors duration-200"
                title="Delete Product"
              >
                <Trash2 className="h-4 w-4" />
              </button>
            </div>
          </div>
        ))}
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
    </div>
  );
};

const getDaysSinceLastSold = (lastSoldAt: string | null) => {
  if (!lastSoldAt) return 999999;
  return Math.floor((new Date().getTime() - new Date(lastSoldAt).getTime()) / (1000 * 60 * 60 * 24));
};

export default InventoryList;