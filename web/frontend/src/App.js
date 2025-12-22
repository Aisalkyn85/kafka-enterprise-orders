import React, { useState, useEffect } from 'react';
import './App.css';

function App() {
  const [analytics, setAnalytics] = useState(null);
  const [orders, setOrders] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [lastUpdated, setLastUpdated] = useState(null);

  const fetchAnalytics = async () => {
    try {
      const response = await fetch('/api/analytics');
      const data = await response.json();
      
      if (data.error) {
        setError(data.error);
      } else {
        setOrders(data.orders || []);
        setError(null);
      }
      setLastUpdated(new Date().toLocaleTimeString());
    } catch (err) {
      setError('Failed to fetch data: ' + err.message);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchAnalytics();
    const interval = setInterval(fetchAnalytics, 5000); // Refresh every 5 seconds
    return () => clearInterval(interval);
  }, []);

  // Calculate stats
  const totalOrders = orders.length;
  const totalSales = orders.reduce((sum, order) => {
    const amount = order?.order_analytics?.amount || order?.amount || 0;
    return sum + parseFloat(amount);
  }, 0);
  const avgOrderValue = totalOrders > 0 ? (totalSales / totalOrders).toFixed(2) : 0;

  return (
    <div className="dashboard">
      {/* Header */}
      <header className="header">
        <div className="header-content">
          <div className="logo">
            <span className="logo-icon">📊</span>
            <h1>Kafka Enterprise Orders</h1>
          </div>
          <div className="header-info">
            <span className="status-badge">
              <span className="status-dot"></span>
              Live
            </span>
            {lastUpdated && <span className="last-updated">Updated: {lastUpdated}</span>}
          </div>
        </div>
      </header>

      {/* Main Content */}
      <main className="main-content">
        {/* Stats Cards */}
        <section className="stats-section">
          <div className="stat-card">
            <div className="stat-icon orders-icon">📦</div>
            <div className="stat-info">
              <span className="stat-label">Total Orders</span>
              <span className="stat-value">{totalOrders}</span>
            </div>
          </div>
          
          <div className="stat-card">
            <div className="stat-icon sales-icon">💰</div>
            <div className="stat-info">
              <span className="stat-label">Total Sales</span>
              <span className="stat-value">${totalSales.toFixed(2)}</span>
            </div>
          </div>
          
          <div className="stat-card">
            <div className="stat-icon avg-icon">📈</div>
            <div className="stat-info">
              <span className="stat-label">Avg Order Value</span>
              <span className="stat-value">${avgOrderValue}</span>
            </div>
          </div>
          
          <div className="stat-card">
            <div className="stat-icon status-icon">⚡</div>
            <div className="stat-info">
              <span className="stat-label">System Status</span>
              <span className="stat-value status-active">Active</span>
            </div>
          </div>
        </section>

        {/* Orders Table */}
        <section className="orders-section">
          <div className="section-header">
            <h2>Recent Orders</h2>
            <button className="refresh-btn" onClick={fetchAnalytics}>
              🔄 Refresh
            </button>
          </div>

          {loading && (
            <div className="loading">
              <div className="spinner"></div>
              <p>Loading orders...</p>
            </div>
          )}

          {error && (
            <div className="error-message">
              <span className="error-icon">⚠️</span>
              <div>
                <strong>Connection Error</strong>
                <p>{error}</p>
                <small>Make sure Couchbase is configured and accessible.</small>
              </div>
            </div>
          )}

          {!loading && !error && orders.length === 0 && (
            <div className="empty-state">
              <span className="empty-icon">📭</span>
              <h3>No Orders Yet</h3>
              <p>Orders will appear here once the producer starts sending data to Kafka.</p>
            </div>
          )}

          {!loading && orders.length > 0 && (
            <div className="table-container">
              <table className="orders-table">
                <thead>
                  <tr>
                    <th>Order ID</th>
                    <th>Customer ID</th>
                    <th>Amount</th>
                    <th>Country</th>
                    <th>Status</th>
                    <th>Created At</th>
                  </tr>
                </thead>
                <tbody>
                  {orders.map((item, index) => {
                    const order = item?.order_analytics || item;
                    return (
                      <tr key={index}>
                        <td className="order-id">#{order.order_id || 'N/A'}</td>
                        <td>{order.customer_id || 'N/A'}</td>
                        <td className="amount">${parseFloat(order.amount || 0).toFixed(2)}</td>
                        <td>
                          <span className="country-badge">{order.country || 'N/A'}</span>
                        </td>
                        <td>
                          <span className={`status-badge-sm ${(order.status || '').toLowerCase()}`}>
                            {order.status || 'N/A'}
                          </span>
                        </td>
                        <td className="timestamp">{order.created_at || 'N/A'}</td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          )}
        </section>

        {/* Architecture Info */}
        <section className="info-section">
          <h2>System Architecture</h2>
          <div className="architecture">
            <div className="arch-item">
              <span className="arch-icon">📤</span>
              <span className="arch-label">Producer</span>
              <span className="arch-desc">Generates Orders</span>
            </div>
            <div className="arch-arrow">→</div>
            <div className="arch-item">
              <span className="arch-icon">📨</span>
              <span className="arch-label">Kafka</span>
              <span className="arch-desc">Confluent Cloud</span>
            </div>
            <div className="arch-arrow">→</div>
            <div className="arch-item">
              <span className="arch-icon">⚙️</span>
              <span className="arch-label">Consumers</span>
              <span className="arch-desc">Fraud/Payment/Analytics</span>
            </div>
            <div className="arch-arrow">→</div>
            <div className="arch-item">
              <span className="arch-icon">🗄️</span>
              <span className="arch-label">Couchbase</span>
              <span className="arch-desc">Analytics DB</span>
            </div>
          </div>
        </section>
      </main>

      {/* Footer */}
      <footer className="footer">
        <p>Kafka Enterprise Orders Dashboard • Powered by AWS ECS, Confluent Cloud & Couchbase</p>
      </footer>
    </div>
  );
}

export default App;
