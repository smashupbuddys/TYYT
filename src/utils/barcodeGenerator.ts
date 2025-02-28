import { supabase } from '../lib/supabase';
import QRCode from 'qrcode';

// Code 128 Character Sets
const CODE128_SETS = {
  A: {
    chars: ' !"#$%&\'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ',
    startCode: 103
  },
  B: {
    chars: ' !"#$%&\'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~',
    startCode: 104
  },
  C: {
    chars: '0123456789',
    startCode: 105
  }
};

// Code 128 Patterns (104 character codes from 0 to 103)
const CODE128_PATTERNS = [
  '11011001100', '11001101100', '11001100110', '10010011000', '10010001100',
  '10001001100', '10011001000', '10011000100', '10001100100', '11001001000',
  '11001000100', '11000100100', '10110011100', '10011011100', '10011001110',
  '10111001100', '10011101100', '10011100110', '11001110010', '11001011100',
  '11001001110', '11011100100', '11001110100', '11101101110', '11101001100',
  '11100101100', '11100100110', '11101100100', '11100110100', '11100110010',
  '11011011000', '11011000110', '11000110110', '10100011000', '10001011000',
  '10001000110', '10110001000', '10001101000', '10001100010', '11010001000',
  '11000101000', '11000100010', '10110111000', '10110001110', '10001101110',
  '10111011000', '10111000110', '10001110110', '11101110110', '11010001110',
  '11000101110', '11011101000', '11011100010', '11011101110', '11101011000',
  '11101000110', '11100010110', '11101101000', '11101100010', '11100011010',
  '11101111010', '11001000010', '11110001010', '10100110000', '10100001100',
  '10010110000', '10010000110', '10000101100', '10000100110', '10110010000',
  '10110000100', '10011010000', '10011000010', '10000110100', '10000110010',
  '11000010010', '11001010000', '11110111010', '11000010100', '10001111010',
  '10100111100', '10010111100', '10010011110', '10111100100', '10011110100',
  '10011110010', '11110100100', '11110010100', '11110010010', '11011011110',
  '11011110110', '11110110110', '10101111000', '10100011110', '10001011110',
  '10111101000', '10111100010', '11110101000', '11110100010', '10111011110',
  '10111101110', '11101011110', '11110101110', '11010000100', '11010010000',
  '11010011100'
];

// Encode function for Code 128
export function encodeCode128(data: string): string {
  if (!data) {
    throw new Error('Data is required for barcode generation');
  }

  // Start with start character B
  const startCode = CODE128_SETS['B'].startCode;
  
  // Start with quiet zone
  let binary = '0'.repeat(10);
  
  // Add start character
  binary += CODE128_PATTERNS[startCode];
  
  let checksum = startCode;
  let position = 1;

  // Encode characters
  for (const char of data) {
    // Calculate character value in Code 128B
    let charValue;
    if (char >= 'A' && char <= 'Z') {
      charValue = char.charCodeAt(0) - 'A'.charCodeAt(0) + 10;
    } else if (char >= 'a' && char <= 'z') {
      charValue = char.charCodeAt(0) - 'a'.charCodeAt(0) + 36;
    } else if (char >= '0' && char <= '9') {
      charValue = char.charCodeAt(0) - '0'.charCodeAt(0);
    } else {
      // Special characters mapping
      const specialChars: {[key: string]: number} = {
        '/': 47,
        '-': 45,
        ' ': 0,
        '.': 46
      };
      charValue = specialChars[char] || char.charCodeAt(0);
    }
    
    // Add pattern for this character
    binary += CODE128_PATTERNS[charValue];
    
    // Update checksum
    checksum += charValue * position;
    position++;
  }
  
  // Calculate checksum (modulo 103)
  const checksumValue = checksum % 103;
  binary += CODE128_PATTERNS[checksumValue];
  
  // Add stop character and termination bar
  binary += CODE128_PATTERNS[106] + '11';
  
  // Add trailing quiet zone
  binary += '0'.repeat(10);
  
  return binary;
}

export type BarcodeFormat = 'QR' | 'CODE128' | 'CIPHER';
export type PrintTemplate = 'standard' | 'compact' | 'modern' | 'minimal' | 'detailed' | 'thermal';

export interface BarcodeData {
  sku: string;
  qrCode: string;
  code128: string;
  cipher: string;
}

export interface LabelOptions {
  showPrice?: boolean;
  showSKU?: boolean;
  showCategory?: boolean;
  showManufacturer?: boolean;
  showLogo?: boolean;
  companyName?: string;
  logoUrl?: string;
  fontSize?: number;
  labelWidth?: number;
  labelHeight?: number;
  backgroundColor?: string;
  textColor?: string;
  borderColor?: string;
}

export async function generateBarcodes(
  category: string,
  manufacturer: string,
  priceCode: number,
  retailPrice: number,
  designCode?: number,
  additionalData: string = ''
): Promise<BarcodeData> {
  // Validate inputs
  if (!category || !manufacturer) {
    throw new Error('Category and manufacturer are required for barcode generation');
  }

  if (priceCode <= 0 || retailPrice <= 0) {
    throw new Error('Price code and retail price must be greater than 0');
  }

  try {
    // Get manufacturer code from database
    const { data: manufacturerData, error } = await supabase
      .from('markup_settings')
      .select('code')
      .eq('type', 'manufacturer')
      .eq('name', manufacturer)
      .single();

    if (error || !manufacturerData?.code) {
      throw new Error(`Manufacturer code not found for ${manufacturer}`);
    }

    // Get first two letters of category
    const categoryCode = category.substring(0, 2).toUpperCase();
    const manufacturerCode = manufacturerData.code;
    
    // Convert price to a 4-digit code
    const formattedPriceCode = priceCode.toString().padStart(4, '0');
    
    // Generate random 5-letter code
    const randomCode = Array.from({ length: 5 }, () => 
      String.fromCharCode(65 + Math.floor(Math.random() * 26))
    ).join('');
    
    // Construct SKU with format: PE/PJ02-2399-AGZKO
    const sku = `${categoryCode}/${manufacturerCode}-${formattedPriceCode}-${randomCode}`;

    // Create a JSON object with product details including MRP
    const productData = {
      sku,
      category,
      manufacturer,
      mrp: retailPrice.toFixed(2),
      additionalData
    };

    // Convert to JSON string for QR code
    const qrData = JSON.stringify(productData);
    
    try {
      // Generate Code 128 barcode
      const code128 = encodeCode128(sku);
      
      return {
        sku,
        qrCode: qrData,
        code128,
        cipher: sku
      };
    } catch (error) {
      console.error('Failed to generate barcode:', error);
      throw new Error('Failed to generate product barcode');
    }
  } catch (error) {
    console.error('Error generating barcodes:', error);
    throw error;
  }
}

// Function to print multiple barcode labels
export async function printBarcodeLabels(
  barcodes: BarcodeData[],
  format: BarcodeFormat = 'CODE128',
  template: PrintTemplate = 'standard',
  title: string = 'Print Labels',
  options: LabelOptions = {}
): Promise<void> {
  try {
    // Create temporary iframe for printing
    const iframe = document.createElement('iframe');
    iframe.style.display = 'none';
    document.body.appendChild(iframe);
    
    const iframeDoc = iframe.contentWindow?.document;
    if (!iframeDoc) {
      throw new Error('Failed to create print frame');
    }
    
    // Start writing HTML
    iframeDoc.write(`
      <!DOCTYPE html>
      <html>
        <head>
          <title>${title}</title>
          <style>
            @page { size: A4; margin: 10mm; }
            @media print {
              body { margin: 0; }
              .label-grid { page-break-inside: auto; }
            }
            body { 
              font-family: Arial, sans-serif;
              margin: 0;
              padding: 10px;
            }
            .label-grid {
              display: grid;
              grid-template-columns: repeat(${template === 'thermal' ? '1' : '3'}, 1fr);
              gap: 10px;
              justify-items: center;
            }
          </style>
        </head>
        <body>
          <div class="label-grid">
    `);
    
    // Generate HTML for each barcode
    const labelPromises = barcodes.map(async (barcode) => {
      let labelHTML = generateLabelHTML(barcode, format, options, template);
      
      // Replace placeholder with actual barcode/QR code
      if (format === 'QR') {
        try {
          // Generate QR code as data URL
          const qrDataUrl = await generateQRCodeDataURL(
            barcode.qrCode, 
            { width: Math.floor(options.labelWidth || 200 * 0.6), margin: 1 }
          );
          // Replace placeholder with actual QR code
          labelHTML = labelHTML.replace('QRCODE_PLACEHOLDER', qrDataUrl);
        } catch (error) {
          console.error('Error generating QR code data URL:', error);
          labelHTML = labelHTML.replace('QRCODE_PLACEHOLDER', '');
        }
      } else { // CODE128
        try {
          // Create a temporary canvas to generate the barcode
          const tempCanvas = document.createElement('canvas');
          const height = Math.floor((options.labelHeight || 100) * 0.3);
          const moduleWidth = Math.max(1, Math.floor((options.labelWidth || 200 * 0.8) / 100));
          
          drawCode128Barcode(tempCanvas, barcode.sku, {
            width: moduleWidth,
            height: height,
            showText: false,
            fontSize: options.fontSize || 12,
            textMargin: 2
          });
          
          // Replace placeholder with actual barcode image
          labelHTML = labelHTML.replace('BARCODE_PLACEHOLDER', tempCanvas.toDataURL('image/png'));
        } catch (error) {
          console.error('Error generating Code 128 barcode:', error);
          labelHTML = labelHTML.replace('BARCODE_PLACEHOLDER', '');
        }
      }
      
      return labelHTML;
    });
    
    // Wait for all labels to be generated
    const labelElements = await Promise.all(labelPromises);
    
    // Add labels to the document
    iframeDoc.write(labelElements.join(''));
    
    // Close HTML and initiate printing
    iframeDoc.write(`
          </div>
          <script>
            window.onload = () => {
              setTimeout(() => {
                window.focus();
                window.print();
                document.body.removeChild(window.frameElement);
              }, 500);
            };
          </script>
        </body>
      </html>
    `);
    
    iframeDoc.close();
  } catch (error) {
    console.error('Error printing barcode labels:', error);
    throw error;
  }
}

// Function specifically for printing QR codes
export async function printQRCodes(
  qrCodes: string[],
  title: string = 'Print QR Codes',
  template: PrintTemplate = 'standard',
  format: BarcodeFormat = 'QR'
): Promise<void> {
  try {
    // Convert QR codes to BarcodeData format
    const barcodeData = qrCodes.map(code => {
      let productData;
      
      try {
        // Try to parse the code as JSON
        productData = typeof code === 'string' ? JSON.parse(code) : code;
      } catch {
        // If parsing fails, create a minimal product data object
        productData = { sku: 'UNKNOWN', mrp: '0.00' };
      }
      
      return {
        sku: productData.sku || 'UNKNOWN',
        qrCode: typeof code === 'string' ? code : JSON.stringify(code),
        code128: '',
        cipher: productData.sku || 'UNKNOWN'
      };
    });
    
    // Print the barcodes
    await printBarcodeLabels(barcodeData, format, template, title);
  } catch (error) {
    console.error('Error printing QR codes:', error);
    throw error;
  }
}

// Helper function to generate label HTML
function generateLabelHTML(
  data: BarcodeData,
  format: BarcodeFormat = 'CODE128',
  options: LabelOptions = {},
  template: PrintTemplate = 'standard'
): string {
  const {
    showPrice = true,
    showSKU = true,
    showCategory = false,
    showManufacturer = false,
    showLogo = false,
    companyName = '',
    logoUrl = '',
    fontSize = 12,
    labelWidth = 200,
    labelHeight = 100,
    backgroundColor = '#FFFFFF',
    textColor = '#000000',
    borderColor = '#CCCCCC'
  } = options;
  
  const parsedData = parseQRCode(data.qrCode);
  const sku = data.sku;
  const mrp = parsedData ? parsedData.mrp : '';
  const category = parsedData ? parsedData.category : '';
  const manufacturer = parsedData ? parsedData.manufacturer : '';
  
  // Different templates
  let templateStyle = '';
  
  switch(template) {
    case 'thermal':
      templateStyle = `
        border: none;
        padding: 5px;
        width: ${labelWidth}px;
        height: auto;
        min-height: ${labelHeight}px;
      `;
      break;
    case 'modern':
      templateStyle = `
        border-radius: 5px;
        box-shadow: 0 1px 3px rgba(0,0,0,0.1);
        background: linear-gradient(to bottom, #FFFFFF, #F8F8F8);
        padding: 12px;
      `;
      break;
    case 'minimal':
      templateStyle = `
        border: none;
        padding: 5px;
        background-color: transparent;
      `;
      break;
    case 'detailed':
      templateStyle = `
        border-radius: 0;
        border: 2px solid ${borderColor};
        padding: 15px;
        background-color: ${backgroundColor};
      `;
      break;
    case 'compact':
      templateStyle = `
        padding: 5px;
        height: ${labelHeight * 0.8}px;
        width: ${labelWidth * 0.8}px;
      `;
      break;
    default: // standard
      templateStyle = `
        border: 1px solid ${borderColor};
        padding: 10px;
      `;
  }
  
  let html = `
    <div style="
      width: ${labelWidth}px;
      height: ${labelHeight}px;
      background-color: ${backgroundColor};
      color: ${textColor};
      font-family: Arial, sans-serif;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      box-sizing: border-box;
      margin: 0;
      page-break-inside: avoid;
      ${templateStyle}
    ">
  `;
  
  // Add company logo and name if requested
  if (showLogo && logoUrl) {
    html += `
      <div style="margin-bottom: 5px; text-align: center;">
        <img src="${logoUrl}" style="max-height: 20px; max-width: 80px;" alt="${companyName}" />
      </div>
    `;
  } else if (companyName) {
    html += `
      <div style="font-size: ${fontSize - 2}px; margin-bottom: 5px; text-align: center;">
        ${companyName}
      </div>
    `;
  }
  
  // Add barcode/QR code placeholder
  if (format === 'QR') {
    html += `
      <div style="text-align: center;">
        <img src="QRCODE_PLACEHOLDER" style="width: 80px; height: 80px;" alt="QR Code" />
      </div>
    `;
  } else { // CODE128
    html += `
      <div style="text-align: center;">
        <div style="width: 100%; height: 50px; background-image: url('BARCODE_PLACEHOLDER'); background-repeat: no-repeat; background-position: center; background-size: contain;"></div>
      </div>
    `;
  }
  
  // Add price if requested
  if (showPrice && mrp) {
    html += `
      <div style="font-weight: bold; font-size: ${fontSize + 2}px; margin-top: 5px;">
        MRP: ₹${parseFloat(mrp).toLocaleString()}
      </div>
    `;
  }
  
  // Add SKU if requested
  if (showSKU && sku) {
    html += `
      <div style="font-family: monospace; font-size: ${fontSize}px; margin-top: 2px;">
        ${sku}
      </div>
    `;
  }
  
  // Add category and manufacturer if requested
  if ((showCategory && category) || (showManufacturer && manufacturer)) {
    html += `<div style="font-size: ${fontSize - 4}px; margin-top: 2px;">`;
    
    if (showCategory && category) {
      html += `${category}`;
    }
    
    if (showCategory && category && showManufacturer && manufacturer) {
      html += ` - `;
    }
    
    if (showManufacturer && manufacturer) {
      html += `${manufacturer}`;
    }
    
    html += `</div>`;
  }
  
  html += `</div>`;
  return html;
}  const manufacturer = parsedData ? parsedData.manufacturer : '';
  
  // Different templates
  let templateStyle = '';
  
  switch(template) {
    case 'thermal':
      templateStyle = `
        border: none;
        padding: 5px;
        width: ${labelWidth}px;
        height: auto;
        min-height: ${labelHeight}px;
      `;
      break;
    case 'modern':
      templateStyle = `
        border-radius: 5px;
        box-shadow: 0 1px 3px rgba(0,0,0,0.1);
        background: linear-gradient(to bottom, #FFFFFF, #F8F8F8);
        padding: 12px;
      `;
      break;
    case 'minimal':
      templateStyle = `
        border: none;
        padding: 5px;
        background-color: transparent;
      `;
      break;
    case 'detailed':
      templateStyle = `
        border-radius: 0;
        border: 2px solid ${borderColor};
        padding: 15px;
        background-color: ${backgroundColor};
      `;
      break;
    case 'compact':
      templateStyle = `
        padding: 5px;
        height: ${labelHeight * 0.8}px;
        width: ${labelWidth * 0.8}px;
      `;
      break;
    default: // standard
      templateStyle = `
        border: 1px solid ${borderColor};
        padding: 10px;
      `;
  }
  
  let html = `
    <div style="
      width: ${labelWidth}px;
      height: ${labelHeight}px;
      background-color: ${backgroundColor};
      color: ${textColor};
      font-family: Arial, sans-serif;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      box-sizing: border-box;
      margin: 0;
      page-break-inside: avoid;
      ${templateStyle}
    ">
  `;
  
  // Add company logo and name if requested
  if (showLogo && logoUrl) {
    html += `
      <div style="margin-bottom: 5px; text-align: center;">
        <img src="${logoUrl}" style="max-height: 20px; max-width: 80px;" alt="${companyName}" />
      </div>
    `;
  } else if (companyName) {
    html += `
      <div style="font-size: ${fontSize - 2}px; margin-bottom: 5px; text-align: center;">
        ${companyName}
      </div>
    `;
  }
  
  // Add barcode/QR code placeholder
  if (format === 'QR') {
    html += `
      <div style="text-align: center;">
        <img src="QRCODE_PLACEHOLDER" style="width: 80px; height: 80px;" alt="QR Code" />
      </div>
    `;
  } else { // CODE128
    html += `
      <div style="text-align: center;">
        <div style="width: 100%; height: 50px; background-image: url('BARCODE_PLACEHOLDER'); background-repeat: no-repeat; background-position: center; background-size: contain;"></div>
      </div>
    `;
  }
  
  // Add price if requested
  if (showPrice && mrp) {
    html += `
      <div style="font-weight: bold; font-size: ${fontSize + 2}px; margin-top: 5px;">
        MRP: ₹${parseFloat(mrp).toLocaleString()}
      </div>
    `;
  }
  
  // Add SKU if requested
  if (showSKU && sku) {
    html += `
      <div style="font-family: monospace; font-size: ${fontSize}px; margin-top: 2px;">
        ${sku}
      </div>
    `;
  }
  
  // Add category and manufacturer if requested
  if ((showCategory && category) || (showManufacturer && manufacturer)) {
    html += `<div style="font-size: ${fontSize - 4}px; margin-top: 2px;">`;
    
    if (showCategory && category) {
      html += `${category}`;
    }
    
    if (showCategory && category && showManufacturer && manufacturer) {
      html += ` - `;
    }
    
    if (showManufacturer && manufacturer) {
      html += `${manufacturer}`;
    }
    
    html += `</div>`;
  }
  
  html += `</div>`;
  return html;
  
// Function to parse QR code data
function parseQRCode(qrCode: string): Record<string, any> | null {
  try {
    return JSON.parse(qrCode);
  } catch (error) {
    console.error('Error parsing QR code data:', error);
    return null;
  }
}

// Generate QR code as data URL 
async function generateQRCodeDataURL(data: string, options = { width: 128, margin: 1 }): Promise<string> {
  try {
    return await QRCode.toDataURL(data, {
      width: options.width,
      margin: options.margin,
      errorCorrectionLevel: 'H'
    });
  } catch (error) {
    console.error('Error generating QR code:', error);
    throw new Error('Failed to generate QR code');
  }
}

// Draw Code 128 barcode on canvas
export function drawCode128Barcode(canvas: HTMLCanvasElement, data: string, options = { 
  width: 2, 
  height: 80, 
  showText: true, 
  fontSize: 12,
  textMargin: 5
}): void {
  try {
    const ctx = canvas.getContext('2d');
    if (!ctx) throw new Error('Canvas context not available');
    
    const binary = encodeCode128(data);
    
    // Calculate and set canvas dimensions
    const barcodeWidth = binary.length * options.width;
    const textHeight = options.showText ? options.fontSize + options.textMargin : 0;
    const totalHeight = options.height + textHeight;
    
    canvas.width = barcodeWidth;
    canvas.height = totalHeight;
    
    // Clear canvas
    ctx.fillStyle = '#FFFFFF';
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    
    // Draw barcode
    ctx.fillStyle = '#000000';
    for (let i = 0; i < binary.length; i++) {
      if (binary[i] === '1') {
        ctx.fillRect(i * options.width, 0, options.width, options.height);
      }
    }
    
    // Draw text
    if (options.showText) {
      ctx.fillStyle = '#000000';
      ctx.font = `${options.fontSize}px monospace`;
      ctx.textAlign = 'center';
      ctx.textBaseline = 'top';
      
      // Split SKU into parts for highlighting if it contains hyphens
      const parts = data.split('-');
      if (parts.length > 1) {
        const textY = options.height + options.textMargin;
        const textX = canvas.width / 2;
        
        // Calculate total width
        const fullText = data;
        const fullWidth = ctx.measureText(fullText).width;
        let currentX = textX - (fullWidth / 2);
        
        // Draw each part
        for (let i = 0; i < parts.length; i++) {
          if (i > 0) {
            ctx.fillText('-', currentX, textY);
            currentX += ctx.measureText('-').width;
          }
          
          // Make price code bold (third segment)
          if (i === 1) {
            ctx.font = `bold ${options.fontSize}px monospace`;
          } else {
            ctx.font = `${options.fontSize}px monospace`;
          }
          
          ctx.fillText(parts[i], currentX + (ctx.measureText(parts[i]).width / 2), textY);
          currentX += ctx.measureText(parts[i]).width;
        }
      } else {
        // No hyphens, draw as single text
        ctx.fillText(data, canvas.width / 2, options.height + options.textMargin);
      }
    }
  } catch (error) {
    console.error('Error drawing Code 128 barcode:', error);
    throw error;
  }
}

// A simplified function to directly print a set of barcodes for testing
export async function quickPrintBarcodes(skus: string[], format: BarcodeFormat = 'CODE128', template: PrintTemplate = 'standard'): Promise<void> {
  try {
    // Convert SKUs to barcode data
    const barcodeData = skus.map(sku => {
      return {
        sku,
        qrCode: JSON.stringify({ sku, mrp: "0.00" }),
        code128: encodeCode128(sku),
        cipher: sku
      };
    });
    
    // Print the barcodes
    await printBarcodeLabels(barcodeData, format, template, "Quick Print Labels");
  } catch (error) {
    console.error('Error in quick print:', error);
    throw error;
  }
}

// Custom barcode template function
export function createCustomTemplate(
  templateName: string, 
  style: Record<string, string>, 
  content: (data: BarcodeData, options: LabelOptions) => string
): void {
  // Implementation for custom templates
  console.log(`Custom template ${templateName} created`);
}

// Export types and functions
export default {
  generateBarcodes,
  printBarcodeLabels,
  printQRCodes,
  encodeCode128,
  drawCode128Barcode,
  quickPrintBarcodes,
  createCustomTemplate
};