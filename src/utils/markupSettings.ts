import type { MarkupSetting } from '../types';

// This would typically come from your database/API
const defaultMarkupSettings: MarkupSetting[] = [
  { id: '1', type: 'manufacturer', name: 'Cartier', markup: 0.3 },
  { id: '2', type: 'manufacturer', name: 'Tiffany', markup: 0.35 },
  { id: '3', type: 'manufacturer', name: 'Pandora', markup: 0.25 },
  { id: '4', type: 'manufacturer', name: 'Swarovski', markup: 0.28 },
  { id: '5', type: 'manufacturer', name: 'Local', markup: 0.2 },
  { id: '6', type: 'category', name: 'Rings', markup: 0.25 },
  { id: '7', type: 'category', name: 'Necklaces', markup: 0.3 },
  { id: '8', type: 'category', name: 'Earrings', markup: 0.28 },
  { id: '9', type: 'category', name: 'Bracelets', markup: 0.32 },
  { id: '10', type: 'category', name: 'Watches', markup: 0.4 },
];

export function getMarkupForProduct(manufacturer: string, category: string): number {
  const manufacturerSetting = defaultMarkupSettings.find(
    setting => setting.type === 'manufacturer' && setting.name === manufacturer
  );
  
  const categorySetting = defaultMarkupSettings.find(
    setting => setting.type === 'category' && setting.name === category
  );

  // Use manufacturer markup if available, otherwise use category markup, or fall back to 20%
  return (manufacturerSetting?.markup || categorySetting?.markup || 0.2);
}
