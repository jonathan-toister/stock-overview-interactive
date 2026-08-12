import { BrowserRouter, Link, Route, Routes } from 'react-router-dom';
import ReportPage from './pages/ReportPage';
import StockPage from './pages/StockPage';

export default function App() {
  return (
    <BrowserRouter>
      <header className="topbar">
        <Link to="/" className="brand">
          My stocks
        </Link>
      </header>
      <main className="page">
        <Routes>
          <Route path="/" element={<ReportPage />} />
          <Route path="/stock/:symbol" element={<StockPage />} />
        </Routes>
      </main>
    </BrowserRouter>
  );
}
