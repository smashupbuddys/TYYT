import { supabase } from './supabase';

export interface UserRole {
  id: string;
  name: string;
  role: 'admin' | 'manager' | 'sales' | 'qc' | 'packaging' | 'dispatch';
  permissions: string[];
}

export const ROLE_PERMISSIONS = {
  admin: [
    'manage_staff',
    'manage_settings',
    'manage_inventory',
    'view_sensitive_info',
    'manage_customers',
    'view_analytics',
    'view_inventory',
    'manage_qc',
    'manage_packaging',
    'manage_dispatch'
  ],
  manager: [
    'manage_inventory',
    'manage_customers',
  ],
  sales: [
    'view_inventory',
    'manage_customers',
  ],
  qc: [
    'view_inventory',
    'manage_qc'
  ],
  packaging: [
    'view_inventory',
    'manage_packaging'
  ],
  dispatch: [
    'view_inventory',
    'manage_dispatch'
  ]
};

export const signInWithEmail = async (email: string, password: string) => {
  try {
    if (!email || !password) {
      throw new Error('Please enter both email and password');
    }

    // Special handling for demo users
    const isDemoUser = email.endsWith('@example.com');
    if (isDemoUser) {
      const role = email.split('@')[0]; // admin, manager, or sales
      const staffId = `00000000-0000-0000-0000-00000000000${role === 'admin' ? '1' : role === 'manager' ? '2' : '3'}`;
      
      // Store staff details in local storage
      localStorage.setItem('staffRole', role);
      localStorage.setItem('staffId', staffId);
      localStorage.setItem('staffName', `${role.charAt(0).toUpperCase() + role.slice(1)} User`);
      
      return {
        user: { id: staffId, email },
        staff: {
          id: staffId,
          name: `${role.charAt(0).toUpperCase() + role.slice(1)} User`,
          email,
          role,
          active: true
        }
      };
    }

    const { data: authData, error: authError } = await supabase.auth.signInWithPassword({
      email,
      password
    });

    if (authError) {
      if (authError.message === 'Invalid login credentials') {
        throw new Error('Invalid email or password');
      } else if (authError.status === 0) {
        throw new Error('Connection error. Please check your internet connection.');
      } else if (authError.message.includes('rate limit')) {
        throw new Error('Too many login attempts. Please try again later.');
      }
      throw new Error(authError.message);
    }

    if (!authData.user) {
      throw new Error('No user data returned');
    }

    // Get staff details
    const { data: staffData, error: staffError } = await supabase
      .from('staff')
      .select('*')
      .eq('email', email)
      .single();

    if (staffError) {
      throw new Error('Staff account not found. Please contact your administrator.');
    }

    // Store staff details in local storage
    localStorage.setItem('staffRole', staffData.role);
    localStorage.setItem('staffId', staffData.id);
    localStorage.setItem('staffName', staffData.name);

    return { user: authData.user, staff: staffData };
  } catch (error) {
    console.error('Authentication error:', error);
    throw error;
  }
};

export const signOut = async () => {
  try {
    const { error } = await supabase.auth.signOut();
    if (error) throw error;

    // Clear local storage
    localStorage.removeItem('staffRole');
    localStorage.removeItem('staffId');
    localStorage.removeItem('staffName');
  } catch (error) {
    console.error('Error signing out:', error);
    throw error;
  }
};

export const createStaffUser = async (email: string, password: string, name: string, role: string) => {
  try {
    // Create auth user
    const { data: authData, error: authError } = await supabase.auth.signUp({
      email,
      password,
      options: {
        data: {
          role
        }
      }
    });

    if (authError) throw authError;

    // Create staff record
    const { data: staffData, error: staffError } = await supabase
      .from('staff')
      .insert([
        {
          id: authData.user?.id,
          name,
          email,
          role,
          active: true
        }
      ])
      .select()
      .single();

    if (staffError) throw staffError;

    return { user: authData.user, staff: staffData };
  } catch (error) {
    console.error('Error creating staff user:', error);
    throw error;
  }
};

export const getCurrentUser = async () => {
  try {
    const { data: { session }, error } = await supabase.auth.getSession();
    if (error || !session) return null;

    const { data: staff, error: staffError } = await supabase
      .from('staff')
      .select('*')
      .eq('id', session.user.id)
      .single();

    if (staffError || !staff) return null;

    return {
      ...session.user,
      role: staff.role,
      name: staff.name,
      permissions: ROLE_PERMISSIONS[staff.role as keyof typeof ROLE_PERMISSIONS] || []
    };
  } catch (error) {
    console.error('Error getting current user:', error);
    return null;
  }
};

export const hasPermission = (permission: string): boolean => {
  const role = localStorage.getItem('staffRole');
  if (!role) return false;
  
  // Admin has access to everything
  if (role === 'admin') return true;
  
  // For other roles, check specific permissions
  return ROLE_PERMISSIONS[role as keyof typeof ROLE_PERMISSIONS]?.includes(permission) || false;
};

export const isAuthenticated = (): boolean => {
  return !!localStorage.getItem('staffRole') && !!localStorage.getItem('staffId');
};