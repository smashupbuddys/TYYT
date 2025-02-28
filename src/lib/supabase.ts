import { createClient } from '@supabase/supabase-js';
import type { Database } from '../types/supabase';

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL;
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY;

if (!supabaseUrl || !supabaseAnonKey) {
  throw new Error('Missing Supabase environment variables. Please connect to Supabase using the "Connect to Supabase" button.');
}

// Add retry logic for failed requests
export interface RetryOptions {
  maxRetries?: number;
  retryDelay?: number | ((attempt: number) => number);
  shouldRetry?: (error: any) => boolean;
  onRetry?: (attempt: number, error: any) => void;
  onError?: (error: any) => void;
}

// Create custom fetch with retry logic
const customFetchWithRetry = async (url: string, options: RequestInit): Promise<Response> => {
  const MAX_RETRIES = 3;
  const INITIAL_DELAY = 1000; // Start with 1s delay
  const MAX_DELAY = 5000; // Maximum delay of 5 seconds
  const BACKOFF_FACTOR = 1.5; // Exponential backoff factor
  const NETWORK_ERRORS = [
    'Failed to fetch',
    'NetworkError',
    'Network request failed',
    'Network Error',
    'net::ERR_INTERNET_DISCONNECTED',
    'net::ERR_CONNECTION_REFUSED'
  ];

  let lastError;
  for (let attempt = 0; attempt < MAX_RETRIES; attempt++) {
    try {
      const response = await fetch(url, options);
      if (!response.ok) {
        const errorText = await response.text();
        throw new Error(`HTTP error! status: ${response.status}, message: ${errorText}`);
      }
      return response;
    } catch (error) {
      lastError = error;
      const isNetworkError = NETWORK_ERRORS.some(msg => 
        error.message?.includes(msg) || error.toString().includes(msg)
      );

      if (isNetworkError) {
        console.warn(`Network error on attempt ${attempt + 1}/${MAX_RETRIES}:`, error);
      }

      if (attempt < MAX_RETRIES - 1) {
        // Calculate delay with exponential backoff and jitter
        const delay = Math.min(
          INITIAL_DELAY * Math.pow(BACKOFF_FACTOR, attempt) * (0.9 + Math.random() * 0.2),
          MAX_DELAY
        );
        await new Promise(resolve => 
          setTimeout(resolve, delay)
        );
        console.warn(`Retry attempt ${attempt + 1}/${MAX_RETRIES} after ${Math.round(delay)}ms`);
      }
    }
  }
  throw lastError;
};

export const supabase = createClient<Database>(
  supabaseUrl,
  supabaseAnonKey,
  {
    auth: {
      autoRefreshToken: true,
      persistSession: true
    },
    global: {
      headers: { 'x-client-info': 'jms@1.0.0' },
      fetch: customFetchWithRetry
    }
  }
);

// Add error handling for network issues
supabase.auth.onAuthStateChange((event, session) => {
  if (event === 'SIGNED_OUT') {
    console.log('User signed out');
  }
});

// Generic retry function for database operations
export const fetchWithRetry = async (
  operation: () => Promise<any>,
  options: RetryOptions = {}
): Promise<any> => {
  const {
    maxRetries = 3,
    retryDelay = 500,
    onRetry = (attempt: number, error: any) => {
      console.warn(`Retry attempt ${attempt + 1}/${maxRetries}:`, error);
    },
    shouldRetry = (error: any) => (
      error.message === 'Failed to fetch' ||
      error.message?.includes('NetworkError') ||
      error.message?.includes('network') ||
      error.status === 503 ||
      error.status === 504
    )
  } = options;

  let lastError;
  for (let attempt = 0; attempt < maxRetries; attempt++) {
    try {
      const result = await operation();
      return result;
    } catch (error: any) {
      lastError = error;
      
      if (attempt < maxRetries - 1 && shouldRetry(error)) {
        onRetry(attempt, error);
        // Calculate delay with exponential backoff and jitter
        const delay = Math.min(
          retryDelay * Math.pow(1.5, attempt) * (0.9 + Math.random() * 0.2),
          5000 // Max 5 second delay
        );
        await new Promise(resolve => 
          setTimeout(resolve, delay)
        );
        continue;
      }
      break;
    }
  }

  // Add more context to the error
  if (lastError) {
    lastError.message = `Connection error: Failed after ${maxRetries} attempts. Please check your internet connection and try again.`;
    lastError.details = `Last error: ${lastError.message}`;
    lastError.hint = 'Please check your internet connection. The app will automatically retry when connectivity is restored.';
  }

  throw lastError;
};