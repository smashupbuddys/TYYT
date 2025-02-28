import React from 'react';
import { BrowserRouter as Router, Routes, Route, Navigate, Outlet } from 'react-router-dom';
import Layout from './components/Layout';
import { ToastContainer } from './components/ToastContainer';
import LoginPage from './components/auth/LoginPage';
import RequireAuth from './components/auth/RequireAuth';
import ManufacturerAnalytics from './components/manufacturers/ManufacturerAnalytics';
import InventoryList from './components/inventory/InventoryList';
import SettingsTabs from './components/settings/SettingsTabs';
import BillMaker from './components/pos/BillMaker';
import SalesAnalytics from './components/dashboard/SalesAnalytics';
import CustomerList from './components/customers/CustomerList';
import VideoCallList from './components/video-calls/VideoCallList';
import VideoCallDetails from './components/video-calls/pages/VideoCallDetails';
import VideoCallRoom from './components/video-calls/pages/VideoCallRoom';
import VideoCallQuotation from './components/video-calls/pages/VideoCallQuotation';
import VideoCallProfiling from './components/video-calls/pages/VideoCallProfiling';
import VideoCallPayment from './components/video-calls/pages/VideoCallPayment';
import VideoCallQC from './components/video-calls/pages/VideoCallQC';
import VideoCallPackaging from './components/video-calls/pages/VideoCallPackaging';
import VideoCallDispatch from './components/video-calls/pages/VideoCallDispatch';
import DispatchList from './components/dispatch/DispatchList';
import { supabase } from './lib/supabase';

const UnauthorizedContent = () => (
  <div className="min-h-screen flex items-center justify-center bg-gray-50">
    <div className="text-center">
      <h1 className="text-4xl font-bold text-gray-900 mb-4">Unauthorized</h1>
      <p className="text-gray-600">You don't have permission to access this page.</p>
    </div>
  </div>
);

function App() {
  const [session, setSession] = React.useState<any>(null);
  const [loading, setLoading] = React.useState(true);
  const prevSessionIdRef = React.useRef<string | null>(null);

  React.useEffect(() => {
    // Get initial session
    supabase.auth.getSession().then(({ data: { session } }) => {
      setSession(session);
      prevSessionIdRef.current = session?.user?.id || null;
      setLoading(false);
    });

    // Listen for auth changes
    const { data: { subscription } } = supabase.auth.onAuthStateChange((_event, session) => {
      const currentSessionId = session?.user?.id || null;
      if (currentSessionId !== prevSessionIdRef.current) {
        setSession(session);
        prevSessionIdRef.current = currentSessionId;
      }
    });

    return () => subscription.unsubscribe();
  }, []); // Empty dependency array

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <div className="text-gray-500">Loading...</div>
      </div>
    );
  }

  return (
    <Router>
      <ToastContainer />
      <Routes>
        <Route 
          path="/login" 
          element={
            session ? (
              <Navigate to="/" replace />
            ) : (
              <LoginPage />
            )
          } 
        />
        <Route
          path="/"
          element={
            <RequireAuth>
              <Layout />
            </RequireAuth>
          }
        >
          <Route index element={
            <RequireAuth permissions={['view_analytics']} fallback={<UnauthorizedContent />}>
              <SalesAnalytics />
            </RequireAuth>
          } />
          <Route path="manufacturers" element={
            <RequireAuth permissions={['view_analytics']} fallback={<UnauthorizedContent />}>
              <ManufacturerAnalytics />
            </RequireAuth>
          } />
          <Route path="inventory" element={
            <RequireAuth permissions={['view_inventory']} fallback={<UnauthorizedContent />}>
              <InventoryList />
            </RequireAuth>
          } />
          <Route path="bill" element={
            <RequireAuth permissions={['view_inventory']} fallback={<UnauthorizedContent />}>
              <BillMaker />
            </RequireAuth>
          } />
          <Route path="settings" element={
            <RequireAuth permissions={['manage_settings']} fallback={<UnauthorizedContent />}>
              <SettingsTabs />
            </RequireAuth>
          } />
          <Route path="customers" element={
            <RequireAuth permissions={['manage_customers']} fallback={<UnauthorizedContent />}>
              <CustomerList />
            </RequireAuth>
          } />
          <Route path="video-calls" element={
            <RequireAuth permissions={['manage_video_calls']} fallback={<UnauthorizedContent />}>
              <VideoCallList />
            </RequireAuth>
          } />
          <Route path="video-calls/:callId" element={
            <RequireAuth permissions={['manage_video_calls']} fallback={<UnauthorizedContent />}>
              <VideoCallDetails />
            </RequireAuth>
          } />
          <Route path="video-calls/:callId/video" element={
            <RequireAuth permissions={['manage_video_calls']} fallback={<UnauthorizedContent />}>
              <VideoCallRoom />
            </RequireAuth>
          } />
          <Route path="video-calls/:callId/quotation" element={
            <RequireAuth permissions={['manage_video_calls']} fallback={<UnauthorizedContent />}>
              <VideoCallQuotation />
            </RequireAuth>
          } />
          <Route path="video-calls/:callId/profiling" element={
            <RequireAuth permissions={['manage_video_calls']} fallback={<UnauthorizedContent />}>
              <VideoCallProfiling />
            </RequireAuth>
          } />
          <Route path="video-calls/:callId/payment" element={
            <RequireAuth permissions={['manage_video_calls']} fallback={<UnauthorizedContent />}>
              <VideoCallPayment />
            </RequireAuth>
          } />
          <Route path="video-calls/:callId/qc" element={
            <RequireAuth permissions={['manage_video_calls']} fallback={<UnauthorizedContent />}>
              <VideoCallQC />
            </RequireAuth>
          } />
          <Route path="video-calls/:callId/packaging" element={
            <RequireAuth permissions={['manage_video_calls']} fallback={<UnauthorizedContent />}>
              <VideoCallPackaging />
            </RequireAuth>
          } />
          <Route path="video-calls/:callId/dispatch" element={
            <RequireAuth permissions={['manage_video_calls']} fallback={<UnauthorizedContent />}>
              <VideoCallDispatch />
            </RequireAuth>
          } />
          <Route path="dispatch/pending" element={
            <RequireAuth permissions={['manage_dispatch']} fallback={<UnauthorizedContent />}>
              <DispatchList />
            </RequireAuth>
          } />
        </Route>
      </Routes>
    </Router>
  );
}

export default App;