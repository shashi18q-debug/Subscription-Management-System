
require("dotenv").config();

const express = require("express");
const cors = require("cors");
const Database = require("better-sqlite3");
const bcrypt = require("bcryptjs");
const jwt = require("jsonwebtoken");

const app = express();
const PORT = process.env.PORT || 5000;
const JWT_SECRET = process.env.JWT_SECRET;

if (!JWT_SECRET) {
  throw new Error("Please add JWT_SECRET to your .env file");
}

app.use(cors());
app.use(express.json());

const db = new Database("subscriptiq.db");
db.pragma("journal_mode = WAL");
db.pragma("foreign_keys = ON");

// DATABASE TABLES
db.exec(`
CREATE TABLE IF NOT EXISTS users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  email TEXT NOT NULL UNIQUE,
  password TEXT NOT NULL,
  created_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS products (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  name TEXT NOT NULL,
  category TEXT DEFAULT '',
  description TEXT DEFAULT '',
  price REAL NOT NULL DEFAULT 0,
  created_at TEXT DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS plans (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  name TEXT NOT NULL,
  description TEXT DEFAULT '',
  price REAL NOT NULL DEFAULT 0,
  billing_interval TEXT DEFAULT 'Monthly',
  created_at TEXT DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS subscriptions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  customer_name TEXT NOT NULL,
  customer_email TEXT DEFAULT '',
  plan_id INTEGER,
  plan_name TEXT NOT NULL,
  amount REAL NOT NULL DEFAULT 0,
  status TEXT DEFAULT 'Active',
  start_date TEXT DEFAULT CURRENT_DATE,
  created_at TEXT DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (plan_id) REFERENCES plans(id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS invoices (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  subscription_id INTEGER,
  invoice_number TEXT NOT NULL,
  customer_name TEXT NOT NULL,
  issue_date TEXT DEFAULT CURRENT_DATE,
  due_date TEXT DEFAULT CURRENT_DATE,
  amount REAL NOT NULL DEFAULT 0,
  status TEXT DEFAULT 'Pending',
  created_at TEXT DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (subscription_id) REFERENCES subscriptions(id) ON DELETE SET NULL,
  UNIQUE(user_id, invoice_number)
);

CREATE TABLE IF NOT EXISTS payments (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  invoice_id INTEGER,
  amount REAL NOT NULL DEFAULT 0,
  payment_method TEXT DEFAULT 'Manual',
  status TEXT DEFAULT 'Pending',
  payment_date TEXT DEFAULT CURRENT_DATE,
  transaction_id TEXT DEFAULT '',
  created_at TEXT DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (invoice_id) REFERENCES invoices(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_products_user ON products(user_id);
CREATE INDEX IF NOT EXISTS idx_plans_user ON plans(user_id);
CREATE INDEX IF NOT EXISTS idx_subscriptions_user ON subscriptions(user_id);
CREATE INDEX IF NOT EXISTS idx_invoices_user ON invoices(user_id);
CREATE INDEX IF NOT EXISTS idx_payments_user ON payments(user_id);
`);

// AUTHENTICATION MIDDLEWARE
function authenticate(req, res, next) {
  const header = req.headers.authorization || "";
  const token = header.startsWith("Bearer ")
    ? header.slice(7)
    : null;

  if (!token) {
    return res.status(401).json({ message: "Please login first" });
  }

  try {
    const decoded = jwt.verify(token, JWT_SECRET);
    req.user = { id: decoded.id, email: decoded.email };
    next();
  } catch {
    return res.status(401).json({ message: "Invalid or expired token" });
  }
}

function createToken(user) {
  return jwt.sign(
    { id: user.id, email: user.email },
    JWT_SECRET,
    { expiresIn: "7d" }
  );
}

function handleError(res, error) {
  console.error(error);
  if (error.code === "SQLITE_CONSTRAINT_UNIQUE") {
    return res.status(409).json({ message: "This record already exists" });
  }
  res.status(400).json({ message: error.message || "Request failed" });
}

// REGISTER
app.post("/api/auth/register", async (req, res) => {
  try {
    const { name, email, password } = req.body;

    if (!name || !email || !password) {
      return res.status(400).json({
        message: "Name, email and password are required"
      });
    }

    if (password.length < 8) {
      return res.status(400).json({
        message: "Password must be at least 8 characters"
      });
    }

    const normalizedEmail = email.trim().toLowerCase();

    const existing = db.prepare(
      "SELECT id FROM users WHERE email = ?"
    ).get(normalizedEmail);

    if (existing) {
      return res.status(409).json({ message: "Email already registered" });
    }

    const hashedPassword = await bcrypt.hash(password, 12);

    const result = db.prepare(
      "INSERT INTO users (name, email, password) VALUES (?, ?, ?)"
    ).run(name.trim(), normalizedEmail, hashedPassword);

    const user = {
      id: Number(result.lastInsertRowid),
      name: name.trim(),
      email: normalizedEmail
    };

    res.status(201).json({
      message: "Account created successfully",
      token: createToken(user),
      user
    });
  } catch (error) {
    handleError(res, error);
  }
});

// LOGIN
app.post("/api/auth/login", async (req, res) => {
  try {
    const { email, password } = req.body;

    if (!email || !password) {
      return res.status(400).json({
        message: "Email and password are required"
      });
    }

    const user = db.prepare(
      "SELECT * FROM users WHERE email = ?"
    ).get(email.trim().toLowerCase());

    if (!user || !(await bcrypt.compare(password, user.password))) {
      return res.status(401).json({
        message: "Incorrect email or password"
      });
    }

    res.json({
      message: "Login successful",
      token: createToken(user),
      user: {
        id: user.id,
        name: user.name,
        email: user.email
      }
    });
  } catch (error) {
    handleError(res, error);
  }
});

// CURRENT USER
app.get("/api/auth/me", authenticate, (req, res) => {
  const user = db.prepare(
    "SELECT id, name, email, created_at FROM users WHERE id = ?"
  ).get(req.user.id);

  if (!user) return res.status(404).json({ message: "User not found" });
  res.json(user);
});

// GENERIC CRUD ROUTES
function createCrudRoutes(table, fields, required = []) {
  const router = express.Router();

  router.get("/", authenticate, (req, res) => {
    try {
      const rows = db.prepare(
        `SELECT * FROM ${table} WHERE user_id = ? ORDER BY id DESC`
      ).all(req.user.id);
      res.json(rows);
    } catch (error) {
      handleError(res, error);
    }
  });

  router.get("/:id", authenticate, (req, res) => {
    try {
      const row = db.prepare(
        `SELECT * FROM ${table} WHERE id = ? AND user_id = ?`
      ).get(req.params.id, req.user.id);

      if (!row) return res.status(404).json({ message: "Record not found" });
      res.json(row);
    } catch (error) {
      handleError(res, error);
    }
  });

  router.post("/", authenticate, (req, res) => {
    try {
      const data = {};

      for (const field of fields) {
        if (req.body[field] !== undefined) data[field] = req.body[field];
      }

      for (const field of required) {
        if (data[field] === undefined || data[field] === null || data[field] === "") {
          return res.status(400).json({ message: `${field} is required` });
        }
      }

      const columns = ["user_id", ...Object.keys(data)];
      const values = [req.user.id, ...Object.values(data)];
      const placeholders = columns.map(() => "?").join(", ");

      const result = db.prepare(
        `INSERT INTO ${table} (${columns.join(", ")}) VALUES (${placeholders})`
      ).run(...values);

      const created = db.prepare(
        `SELECT * FROM ${table} WHERE id = ? AND user_id = ?`
      ).get(result.lastInsertRowid, req.user.id);

      res.status(201).json(created);
    } catch (error) {
      handleError(res, error);
    }
  });

  router.put("/:id", authenticate, (req, res) => {
    try {
      const data = {};

      for (const field of fields) {
        if (req.body[field] !== undefined) data[field] = req.body[field];
      }

      const entries = Object.entries(data);

      if (!entries.length) {
        return res.status(400).json({ message: "No fields to update" });
      }

      const assignments = entries.map(([key]) => `${key} = ?`).join(", ");
      const values = entries.map(([, value]) => value);

      const result = db.prepare(
        `UPDATE ${table} SET ${assignments}
         WHERE id = ? AND user_id = ?`
      ).run(...values, req.params.id, req.user.id);

      if (!result.changes) {
        return res.status(404).json({ message: "Record not found" });
      }

      const updated = db.prepare(
        `SELECT * FROM ${table} WHERE id = ? AND user_id = ?`
      ).get(req.params.id, req.user.id);

      res.json(updated);
    } catch (error) {
      handleError(res, error);
    }
  });

  router.delete("/:id", authenticate, (req, res) => {
    try {
      const result = db.prepare(
        `DELETE FROM ${table} WHERE id = ? AND user_id = ?`
      ).run(req.params.id, req.user.id);

      if (!result.changes) {
        return res.status(404).json({ message: "Record not found" });
      }

      res.json({ message: "Deleted successfully" });
    } catch (error) {
      handleError(res, error);
    }
  });

  return router;
}

// PRODUCTS
app.use("/api/products", createCrudRoutes(
  "products",
  ["name", "category", "description", "price"],
  ["name"]
));

// PLANS
app.use("/api/plans", createCrudRoutes(
  "plans",
  ["name", "description", "price", "billing_interval"],
  ["name"]
));

// SUBSCRIPTIONS
app.use("/api/subscriptions", createCrudRoutes(
  "subscriptions",
  [
    "customer_name",
    "customer_email",
    "plan_id",
    "plan_name",
    "amount",
    "status",
    "start_date"
  ],
  ["customer_name", "plan_name"]
));

// INVOICES
app.use("/api/invoices", createCrudRoutes(
  "invoices",
  [
    "subscription_id",
    "invoice_number",
    "customer_name",
    "issue_date",
    "due_date",
    "amount",
    "status"
  ],
  ["invoice_number", "customer_name"]
));

// PAYMENTS
app.use("/api/payments", createCrudRoutes(
  "payments",
  [
    "invoice_id",
    "amount",
    "payment_method",
    "status",
    "payment_date",
    "transaction_id"
  ],
  ["amount"]
));

// DASHBOARD SUMMARY
app.get("/api/dashboard", authenticate, (req, res) => {
  try {
    const id = req.user.id;

    const products = db.prepare(
      "SELECT COUNT(*) AS count FROM products WHERE user_id = ?"
    ).get(id).count;

    const plans = db.prepare(
      "SELECT COUNT(*) AS count FROM plans WHERE user_id = ?"
    ).get(id).count;

    const subscriptions = db.prepare(`
      SELECT
        COUNT(*) AS total,
        SUM(CASE WHEN status = 'Active' THEN 1 ELSE 0 END) AS active,
        SUM(CASE WHEN status = 'Cancelled' THEN 1 ELSE 0 END) AS cancelled
      FROM subscriptions WHERE user_id = ?
    `).get(id);

    const invoices = db.prepare(`
      SELECT
        COUNT(*) AS total,
        SUM(CASE WHEN status = 'Paid' THEN amount ELSE 0 END) AS paid_amount,
        SUM(CASE WHEN status != 'Paid' THEN amount ELSE 0 END) AS pending_amount
      FROM invoices WHERE user_id = ?
    `).get(id);

    const payments = db.prepare(`
      SELECT COALESCE(SUM(amount), 0) AS total
      FROM payments WHERE user_id = ? AND status = 'Completed'
    `).get(id);

    res.json({
      products,
      plans,
      subscriptions: {
        total: subscriptions.total || 0,
        active: subscriptions.active || 0,
        cancelled: subscriptions.cancelled || 0
      },
      invoices: {
        total: invoices.total || 0,
        paid_amount: invoices.paid_amount || 0,
        pending_amount: invoices.pending_amount || 0
      },
      completed_payments: payments.total || 0
    });
  } catch (error) {
    handleError(res, error);
  }
});

// HEALTH CHECK
app.get("/api/health", (req, res) => {
  res.json({
    status: "OK",
    message: "SubscriptIQ backend is running"
  });
});

// UNKNOWN ROUTE
app.use((req, res) => {
  res.status(404).json({ message: "API route not found" });
});

// START SERVER
app.listen(PORT, () => {
  console.log(`SubscriptIQ backend running at http://localhost:${PORT}`);
  console.log("SQLite database: subscriptiq.db");
});
