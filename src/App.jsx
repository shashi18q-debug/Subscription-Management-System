import { useState } from "react";
import { loginUser, registerUser, logoutUser } from "./api";
import "./App.css";

const initialProducts = [
  { id: 1, name: "Cloud Workspace", category: "Software", price: 1200 },
  { id: 2, name: "Analytics Pro", category: "Analytics", price: 2500 },
  { id: 3, name: "Business Suite", category: "Business", price: 3500 },
];

const initialSubscriptions = [
  { id: "SUB-1001", customer: "Acme Solutions", plan: "Pro Monthly", amount: 2500, status: "Active" },
  { id: "SUB-1002", customer: "Nova Technologies", plan: "Basic Monthly", amount: 1200, status: "Active" },
  { id: "SUB-1003", customer: "Vertex Labs", plan: "Enterprise", amount: 8500, status: "Paused" },
  { id: "SUB-1004", customer: "Bluewave Studio", plan: "Pro Monthly", amount: 2500, status: "Active" },
];

const initialInvoices = [
  { id: "INV-2026-001", customer: "Acme Solutions", date: "2026-10-01", amount: 2500, status: "Paid" },
  { id: "INV-2026-002", customer: "Nova Technologies", date: "2026-10-05", amount: 1200, status: "Pending" },
  { id: "INV-2026-003", customer: "Vertex Labs", date: "2026-10-10", amount: 8500, status: "Overdue" },
  { id: "INV-2026-004", customer: "Bluewave Studio", date: "2026-10-15", amount: 2500, status: "Paid" },
];

const money = (amount) =>
  new Intl.NumberFormat("en-IN", {
    style: "currency",
    currency: "INR",
    maximumFractionDigits: 0,
  }).format(Number(amount) || 0);

function App() {
  const [page, setPage] = useState("Dashboard");
  const [isLoggedIn, setIsLoggedIn] = useState(
    Boolean(localStorage.getItem("token"))
  );
  const [products, setProducts] = useState(initialProducts);
  const [subscriptions, setSubscriptions] = useState(initialSubscriptions);
  const [invoices, setInvoices] = useState(initialInvoices);
  const [search, setSearch] = useState("");
  const [showForm, setShowForm] = useState(false);
  const [productName, setProductName] = useState("");
  const [productPrice, setProductPrice] = useState("");
  const [notice, setNotice] = useState("");
  const [selectedPlan, setSelectedPlan] = useState(null);

  function notify(message) {
    setNotice(message);
    window.setTimeout(() => setNotice(""), 3000);
  }

  function handleLogout() {
    logoutUser();
    setIsLoggedIn(false);
    setPage("Dashboard");
    setNotice("");
  }

  if (!isLoggedIn) {
    return <AuthScreen onLogin={() => setIsLoggedIn(true)} />;
  }

  const activeSubscriptions = subscriptions.filter(
    (item) => item.status === "Active"
  ).length;

  const collected = invoices
    .filter((item) => item.status === "Paid")
    .reduce((sum, item) => sum + item.amount, 0);

  const outstanding = invoices
    .filter((item) => item.status !== "Paid")
    .reduce((sum, item) => sum + item.amount, 0);

  const overdue = invoices.filter(
    (item) => item.status === "Overdue"
  ).length;

  const navGroups = [
    {
      title: "OVERVIEW",
      items: [{ name: "Dashboard", icon: "▦" }],
    },
    {
      title: "MANAGEMENT",
      items: [
        { name: "Products", icon: "◈" },
        { name: "Plans", icon: "◇" },
        { name: "Subscriptions", icon: "↻" },
        { name: "Invoices", icon: "▤" },
      ],
    },
  ];

  function addProduct(event) {
    event.preventDefault();

    if (!productName.trim() || Number(productPrice) <= 0) {
      notify("Enter a product name and a valid price.");
      return;
    }

    setProducts([
      ...products,
      {
        id: Date.now(),
        name: productName.trim(),
        category: "Software",
        price: Number(productPrice),
      },
    ]);

    setProductName("");
    setProductPrice("");
    setShowForm(false);
    notify("Product added successfully.");
  }

  function markPaid(id) {
    setInvoices(
      invoices.map((invoice) =>
        invoice.id === id ? { ...invoice, status: "Paid" } : invoice
      )
    );
    notify("Invoice marked as paid.");
  }

  function toggleSubscription(id) {
    setSubscriptions(
      subscriptions.map((item) =>
        item.id === id
          ? {
              ...item,
              status: item.status === "Active" ? "Paused" : "Active",
            }
          : item
      )
    );
    notify("Subscription status updated.");
  }

  function renderTable(headers, rows) {
    return (
      <div className="table-wrap">
        <table>
          <thead>
            <tr>
              {headers.map((header) => (
                <th key={header}>{header}</th>
              ))}
            </tr>
          </thead>
          <tbody>{rows}</tbody>
        </table>
      </div>
    );
  }

  function renderDashboard() {
    return (
      <>
        <div className="welcome">
          <div>
            <p className="eyebrow">YOUR BUSINESS AT A GLANCE</p>
            <h2>Welcome back, Admin 👋</h2>
            <p>Here is what is happening with your subscriptions today.</p>
          </div>
          <button
            className="primary-btn"
            onClick={() => {
              setPage("Products");
              setShowForm(true);
            }}
          >
            + Add product
          </button>
        </div>

        <div className="stats-grid">
          <StatCard
            icon="↻"
            label="Active subscriptions"
            value={activeSubscriptions}
            detail="Currently running"
          />
          <StatCard
            icon="₹"
            label="Payments collected"
            value={money(collected)}
            detail="From paid invoices"
          />
          <StatCard
            icon="◷"
            label="Outstanding amount"
            value={money(outstanding)}
            detail="Awaiting payment"
          />
          <StatCard
            icon="!"
            label="Overdue invoices"
            value={overdue}
            detail="Need your attention"
          />
        </div>

        <div className="content-grid">
          <section className="panel">
            <div className="panel-heading">
              <div>
                <h3>Recent subscriptions</h3>
                <p>Keep track of your customers</p>
              </div>
              <button
                className="text-btn"
                onClick={() => setPage("Subscriptions")}
              >
                View all →
              </button>
            </div>

            {renderTable(
              ["Subscription", "Customer", "Amount", "Status"],
              subscriptions.slice(0, 4).map((item) => (
                <tr key={item.id}>
                  <td className="strong-cell">{item.id}</td>
                  <td>{item.customer}</td>
                  <td>{money(item.amount)}</td>
                  <td><Status value={item.status} /></td>
                </tr>
              ))
            )}
          </section>

          <section className="panel">
            <div className="panel-heading">
              <div>
                <h3>Invoice overview</h3>
                <p>Payment activity</p>
              </div>
              <button
                className="text-btn"
                onClick={() => setPage("Invoices")}
              >
                View all →
              </button>
            </div>

            <div className="invoice-summary">
              <div>
                <span>Paid invoices</span>
                <strong>
                  {invoices.filter((item) => item.status === "Paid").length}
                </strong>
              </div>
              <div>
                <span>Pending invoices</span>
                <strong>
                  {invoices.filter((item) => item.status === "Pending").length}
                </strong>
              </div>
              <div>
                <span>Overdue invoices</span>
                <strong className="danger-text">{overdue}</strong>
              </div>
            </div>

            <button
              className="secondary-btn full-btn"
              onClick={() => setPage("Invoices")}
            >
              Manage invoices
            </button>
          </section>
        </div>
      </>
    );
  }

  function renderProducts() {
    const filtered = products.filter((product) =>
      product.name.toLowerCase().includes(search.toLowerCase())
    );

    return (
      <section className="panel">
        <div className="panel-heading">
          <div>
            <h3>Product catalogue</h3>
            <p>Manage the products your business offers.</p>
          </div>
          <button
            className="primary-btn"
            onClick={() => setShowForm(!showForm)}
          >
            + Add product
          </button>
        </div>

        {showForm && (
          <form className="product-form" onSubmit={addProduct}>
            <label>
              Product name
              <input
                value={productName}
                onChange={(event) => setProductName(event.target.value)}
                placeholder="e.g. Cloud Workspace"
                required
              />
            </label>

            <label>
              Price (₹)
              <input
                type="number"
                min="1"
                value={productPrice}
                onChange={(event) => setProductPrice(event.target.value)}
                placeholder="1200"
                required
              />
            </label>

            <button className="primary-btn" type="submit">
              Save product
            </button>

            <button
              className="secondary-btn"
              type="button"
              onClick={() => setShowForm(false)}
            >
              Cancel
            </button>
          </form>
        )}

        <div className="toolbar">
          <input
            value={search}
            onChange={(event) => setSearch(event.target.value)}
            placeholder="Search products..."
          />
          <span>{filtered.length} products</span>
        </div>

        {renderTable(
          ["Product", "Category", "Price", "Billing", "Action"],
          filtered.map((product) => (
            <tr key={product.id}>
              <td className="strong-cell">{product.name}</td>
              <td>{product.category}</td>
              <td>{money(product.price)}</td>
              <td>Monthly</td>
              <td>
                <button
                  className="text-btn"
                  onClick={() => notify("Product details: " + product.name)}
                >
                  View details
                </button>
              </td>
            </tr>
          ))
        )}
      </section>
    );
  }

  function renderPlans() {
    const plans = [
      {
        name: "Basic",
        price: 1200,
        features: "Essential features",
        color: "basic",
      },
      {
        name: "Professional",
        price: 2500,
        features: "Advanced analytics and support",
        color: "pro",
      },
      {
        name: "Enterprise",
        price: 8500,
        features: "Premium support and custom features",
        color: "enterprise",
      },
    ];

    return (
      <div className="plan-grid">
        {plans.map((plan) => (
          <section className="panel plan-card" key={plan.name}>
            <div className={"plan-icon " + plan.color}>◇</div>
            <p className="eyebrow">SUBSCRIPTION PLAN</p>
            <h3>{plan.name}</h3>
            <h2>
              {money(plan.price)}
              <small> / month</small>
            </h2>
            <p>{plan.features}</p>
            <button
              className="secondary-btn full-btn"
              onClick={() => setSelectedPlan(plan)}
            >
              View plan
            </button>
          </section>
        ))}
      </div>
    );
  }

  function renderSubscriptions() {
    const filtered = subscriptions.filter((item) =>
      (item.id + item.customer + item.plan + item.status)
        .toLowerCase()
        .includes(search.toLowerCase())
    );

    return (
      <section className="panel">
        <div className="panel-heading">
          <div>
            <h3>All subscriptions</h3>
            <p>Track customer plans and subscription status.</p>
          </div>
          <button
            className="primary-btn"
            onClick={() =>
              notify("Subscription creation will be connected next.")
            }
          >
            + New subscription
          </button>
        </div>

        <div className="toolbar">
          <input
            value={search}
            onChange={(event) => setSearch(event.target.value)}
            placeholder="Search subscriptions..."
          />
          <span>{filtered.length} subscriptions</span>
        </div>

        {renderTable(
          ["ID", "Customer", "Plan", "Amount", "Status", "Action"],
          filtered.map((item) => (
            <tr key={item.id}>
              <td className="strong-cell">{item.id}</td>
              <td>{item.customer}</td>
              <td>{item.plan}</td>
              <td>{money(item.amount)}</td>
              <td><Status value={item.status} /></td>
              <td>
                <button
                  className="text-btn"
                  onClick={() => toggleSubscription(item.id)}
                >
                  {item.status === "Active" ? "Pause" : "Activate"}
                </button>
              </td>
            </tr>
          ))
        )}
      </section>
    );
  }

  function renderInvoices() {
    const filtered = invoices.filter((item) =>
      (item.id + item.customer + item.status)
        .toLowerCase()
        .includes(search.toLowerCase())
    );

    return (
      <section className="panel">
        <div className="panel-heading">
          <div>
            <h3>Invoices</h3>
            <p>Monitor payments and outstanding balances.</p>
          </div>
          <button
            className="primary-btn"
            onClick={() =>
              notify("Invoice creation will be connected to the backend.")
            }
          >
            + Create invoice
          </button>
        </div>

        <div className="toolbar">
          <input
            value={search}
            onChange={(event) => setSearch(event.target.value)}
            placeholder="Search invoices..."
          />
          <span>{filtered.length} invoices</span>
        </div>

        {renderTable(
          ["Invoice", "Customer", "Issue date", "Amount", "Status", "Action"],
          filtered.map((item) => (
            <tr key={item.id}>
              <td className="strong-cell">{item.id}</td>
              <td>{item.customer}</td>
              <td>{item.date}</td>
              <td>{money(item.amount)}</td>
              <td><Status value={item.status} /></td>
              <td>
                {item.status !== "Paid" ? (
                  <button
                    className="text-btn"
                    onClick={() => markPaid(item.id)}
                  >
                    Mark paid
                  </button>
                ) : (
                  <span className="muted">Completed</span>
                )}
              </td>
            </tr>
          ))
        )}
      </section>
    );
  }

  const descriptions = {
    Dashboard: "Monitor your business performance.",
    Products: "Manage products and their prices.",
    Plans: "Configure subscription pricing and billing.",
    Subscriptions: "Manage recurring customer subscriptions.",
    Invoices: "Track invoices, payments, and overdue balances.",
  };

  return (
    <div className="app-shell">
      <aside className="sidebar">
        <div className="brand">
          <div className="brand-mark">S</div>
          <div>
            <strong>SubscriptIQ</strong>
            <span>SUBSCRIPTION MANAGER</span>
          </div>
        </div>

        <div className="workspace">
          <div className="avatar">B</div>
          <div>
            <strong>Brightloop Software</strong>
            <span>Administrator</span>
          </div>
          <span className="chevron">⌄</span>
        </div>

        {navGroups.map((group) => (
          <div className="nav-group" key={group.title}>
            <p className="nav-label">{group.title}</p>
            {group.items.map((item) => (
              <button
                key={item.name}
                className={
                  "nav-item " + (page === item.name ? "selected" : "")
                }
                onClick={() => {
                  setPage(item.name);
                  setSearch("");
                  setShowForm(false);
                }}
              >
                <span className="nav-icon">{item.icon}</span>
                {item.name}
                {item.name === "Invoices" && overdue > 0 && (
                  <span className="nav-count">{overdue}</span>
                )}
              </button>
            ))}
          </div>
        ))}

        <div className="sidebar-bottom">
          <div className="profile-avatar">AD</div>
          <div>
            <strong>Admin User</strong>
            <span>Signed in</span>
          </div>
          <button
            className="logout-btn"
            onClick={handleLogout}
            type="button"
            title="Log out"
          >
            Log out
          </button>
        </div>
      </aside>

      <main className="main-area">
        <header className="topbar">
          <div className="breadcrumbs">
            Workspace <span>/</span> <strong>{page}</strong>
          </div>
          <div className="top-actions">
            <span className="date-label">
              {new Date().toLocaleDateString("en-IN", {
                day: "numeric",
                month: "short",
                year: "numeric",
              })}
            </span>
            <button
              className="notification-btn"
              onClick={() => setPage("Invoices")}
              title="View invoices"
            >
              ♧<i />
            </button>
            <div className="top-avatar">AD</div>
          </div>
        </header>

        <div className="page-content">
          <div className="page-title">
            <div>
              <p className="eyebrow">BRIGHTLOOP SOFTWARE / WORKSPACE</p>
              <h1>{page}</h1>
              <p>{descriptions[page]}</p>
            </div>
          </div>

          {page === "Dashboard" && renderDashboard()}
          {page === "Products" && renderProducts()}
          {page === "Plans" && renderPlans()}
          {page === "Subscriptions" && renderSubscriptions()}
          {page === "Invoices" && renderInvoices()}

          <footer>
            © 2026 SubscriptIQ
            <span>Subscription Management System</span>
          </footer>
        </div>
      </main>

      {notice && <div className="toast">{notice}</div>}

      {selectedPlan && (
        <div
          className="modal-backdrop"
          onClick={() => setSelectedPlan(null)}
        >
          <section
            className="plan-modal"
            role="dialog"
            aria-modal="true"
            aria-labelledby="plan-modal-title"
            onClick={(event) => event.stopPropagation()}
          >
            <button
              className="modal-close"
              onClick={() => setSelectedPlan(null)}
              aria-label="Close plan details"
            >
              ×
            </button>

            <p className="eyebrow">SUBSCRIPTION PLAN</p>
            <h2 id="plan-modal-title">{selectedPlan.name}</h2>
            <h3>
              {money(selectedPlan.price)} <small>/ month</small>
            </h3>
            <p>{selectedPlan.features}</p>

            <button
              className="primary-btn full-btn"
              onClick={() => setSelectedPlan(null)}
            >
              Done
            </button>
          </section>
        </div>
      )}
    </div>
  );
}

function AuthScreen({ onLogin }) {
  const [mode, setMode] = useState("login");
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [confirm, setConfirm] = useState("");
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);

  const passwordValid =
    password.length > 8 &&
    /[A-Z]/.test(password) &&
    /[a-z]/.test(password) &&
    /[^A-Za-z0-9]/.test(password);

  async function submit(event) {
    event.preventDefault();
    setError("");

    if (!email.trim() || !password) {
      setError("Enter your email and password.");
      return;
    }

    if (mode === "signup" && !name.trim()) {
      setError("Enter your name.");
      return;
    }

    if (mode === "signup" && !passwordValid) {
      setError(
        "Password must be longer than 8 characters and include uppercase, lowercase, and a special character."
      );
      return;
    }

    if (mode === "signup" && password !== confirm) {
      setError("Passwords do not match.");
      return;
    }

    try {
      setLoading(true);

      if (mode === "signup") {
        await registerUser(name.trim(), email.trim(), password);
      } else {
        await loginUser(email.trim(), password);
      }

      onLogin();
    } catch (err) {
      setError(err.message || "Authentication failed. Please try again.");
    } finally {
      setLoading(false);
    }
  }

  const fieldStyle = {
    width: "100%",
    boxSizing: "border-box",
    padding: "12px 14px",
    border: "1px solid #d8deea",
    borderRadius: 10,
    font: "inherit",
    marginTop: 6,
  };

  return (
    <div
      style={{
        minHeight: "100vh",
        display: "grid",
        placeItems: "center",
        padding: 24,
        background: "#f4f6fb",
        fontFamily: "inherit",
      }}
    >
      <section
        style={{
          width: "100%",
          maxWidth: 430,
          background: "white",
          padding: 32,
          borderRadius: 18,
          boxShadow: "0 18px 60px #1b2b4b18",
          boxSizing: "border-box",
        }}
      >
        <div
          style={{
            display: "flex",
            alignItems: "center",
            gap: 12,
            marginBottom: 28,
          }}
        >
          <div
            style={{
              background: "#4f46e5",
              color: "white",
              width: 42,
              height: 42,
              display: "grid",
              placeItems: "center",
              borderRadius: 12,
              fontWeight: 800,
            }}
          >
            S
          </div>
          <strong style={{ fontSize: 20 }}>SubscriptIQ</strong>
        </div>

        <h1 style={{ margin: "0 0 8px", fontSize: 26 }}>
          {mode === "login" ? "Welcome back" : "Create your account"}
        </h1>

        <p style={{ color: "#68738a", margin: "0 0 24px" }}>
          {mode === "login"
            ? "Sign in to manage your subscriptions."
            : "Sign up to get started with SubscriptIQ."}
        </p>

        <form onSubmit={submit} style={{ display: "grid", gap: 15 }}>
          {mode === "signup" && (
            <label>
              Name
              <input
                style={fieldStyle}
                value={name}
                onChange={(event) => setName(event.target.value)}
                placeholder="Your name"
                required
              />
            </label>
          )}

          <label>
            Email
            <input
              style={fieldStyle}
              type="email"
              value={email}
              onChange={(event) => setEmail(event.target.value)}
              placeholder="you@example.com"
              required
            />
          </label>

          <label>
            Password
            <input
              style={fieldStyle}
              type="password"
              value={password}
              onChange={(event) => setPassword(event.target.value)}
              placeholder="Enter password"
              required
            />
          </label>

          {mode === "signup" && (
            <>
              <label>
                Confirm password
                <input
                  style={fieldStyle}
                  type="password"
                  value={confirm}
                  onChange={(event) => setConfirm(event.target.value)}
                  placeholder="Re-enter password"
                  required
                />
              </label>
              <small style={{ color: "#68738a" }}>
                Use more than 8 characters with uppercase, lowercase, and a
                special character.
              </small>
            </>
          )}

          {error && (
            <p role="alert" style={{ color: "#b42318", margin: 0, fontSize: 14 }}>
              {error}
            </p>
          )}

          <button
            type="submit"
            disabled={loading}
            style={{
              border: 0,
              borderRadius: 10,
              padding: 13,
              color: "white",
              background: loading ? "#999" : "#4f46e5",
              fontWeight: 700,
              cursor: loading ? "not-allowed" : "pointer",
            }}
          >
            {loading
              ? "Please wait..."
              : mode === "login"
                ? "Sign in"
                : "Create account"}
          </button>
        </form>

        <p style={{ textAlign: "center", color: "#68738a", marginBottom: 0 }}>
          {mode === "login" ? "New here? " : "Already have an account? "}
          <button
            type="button"
            onClick={() => {
              setMode(mode === "login" ? "signup" : "login");
              setError("");
            }}
            style={{
              border: 0,
              background: "none",
              color: "#4f46e5",
              fontWeight: 700,
              cursor: "pointer",
            }}
          >
            {mode === "login" ? "Sign up" : "Sign in"}
          </button>
        </p>

        <p
          style={{
            textAlign: "center",
            fontSize: 12,
            color: "#8992a5",
            marginBottom: 0,
          }}
        >
          SubscriptIQ · Secure account access
        </p>
      </section>
    </div>
  );
}

function StatCard({ icon, label, value, detail }) {
  return (
    <section className="stat-card">
      <div className="stat-top">
        <span>{label}</span>
        <span className="stat-icon">{icon}</span>
      </div>
      <h2>{value}</h2>
      <p>
        <span className="trend">↗</span> {detail}
      </p>
    </section>
  );
}

function Status({ value }) {
  const className = String(value).toLowerCase().replace(/\s+/g, "-");

  return (
    <span className={"status " + className}>
      <i />
      {value}
    </span>
  );
}

export default App;