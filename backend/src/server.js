import express from "express";
import cors from "cors";
import helmet from "helmet";
import dotenv from "dotenv";
import bcrypt from "bcryptjs";
import jwt from "jsonwebtoken";
import pg from "pg";
import { z } from "zod";

dotenv.config();

const app = express();
const { Pool } = pg;

if (!process.env.DATABASE_URL || !process.env.JWT_SECRET) {
  throw new Error("DATABASE_URL and JWT_SECRET are required");
}

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: process.env.DATABASE_SSL === "true"
    ? { rejectUnauthorized: false }
    : undefined
});

app.use(helmet());
app.use(express.json({ limit: "1mb" }));

const origins = (process.env.CLIENT_ORIGINS || "")
  .split(",")
  .map(x => x.trim())
  .filter(Boolean);

app.use(cors({
  origin(origin, callback) {
    if (!origin || origins.length === 0 || origins.includes(origin)) {
      return callback(null, true);
    }
    callback(new Error("Origin not allowed"));
  }
}));

const asyncHandler = fn => (req, res, next) =>
  Promise.resolve(fn(req, res, next)).catch(next);

function tokenFor(user) {
  return jwt.sign(
    { userId: user.id, companyId: user.company_id },
    process.env.JWT_SECRET,
    { expiresIn: "7d" }
  );
}

const auth = asyncHandler(async (req, res, next) => {
  const header = req.headers.authorization || "";
  const token = header.startsWith("Bearer ")
    ? header.slice(7)
    : "";

  if (!token) return res.status(401).json({ error: "تسجيل الدخول مطلوب" });

  try {
    const data = jwt.verify(token, process.env.JWT_SECRET);
    const result = await pool.query(
      `SELECT cm.company_id, cm.user_id, cm.role
       FROM company_members cm
       WHERE cm.user_id = $1 AND cm.company_id = $2`,
      [data.userId, data.companyId]
    );

    if (!result.rows.length) {
      return res.status(403).json({ error: "لا توجد عضوية لهذه الشركة" });
    }

    req.user = {
      id: data.userId,
      companyId: data.companyId,
      role: result.rows[0].role
    };
    next();
  } catch {
    return res.status(401).json({ error: "رمز الدخول غير صالح" });
  }
});

app.get("/health", (req, res) => {
  res.json({ status: "ok", app: "NEXORA BUSINESS" });
});

app.post("/api/auth/register", asyncHandler(async (req, res) => {
  const schema = z.object({
    name: z.string().min(2).max(100),
    email: z.string().email().max(200),
    password: z.string().min(8).max(100),
    companyName: z.string().min(2).max(150)
  });

  const data = schema.parse(req.body);
  const client = await pool.connect();

  try {
    await client.query("BEGIN");

    const existing = await client.query(
      "SELECT id FROM users WHERE email = $1",
      [data.email.toLowerCase()]
    );

    if (existing.rows.length) {
      await client.query("ROLLBACK");
      return res.status(409).json({ error: "البريد الإلكتروني مستخدم" });
    }

    const passwordHash = await bcrypt.hash(data.password, 12);

    const userResult = await client.query(
      `INSERT INTO users (name, email, password_hash)
       VALUES ($1, $2, $3) RETURNING id, name, email`,
      [data.name, data.email.toLowerCase(), passwordHash]
    );

    const companyResult = await client.query(
      `INSERT INTO companies (name)
       VALUES ($1) RETURNING id, name`,
      [data.companyName]
    );

    const user = userResult.rows[0];
    const company = companyResult.rows[0];

    await client.query(
      `INSERT INTO company_members (company_id, user_id, role)
       VALUES ($1, $2, $3)`,
      [company.id, user.id, "owner"]
    );

    await client.query("COMMIT");

    const token = tokenFor({ id: user.id, company_id: company.id });

    res.status(201).json({
      token,
      user,
      company
    });
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}));

app.post("/api/auth/login", asyncHandler(async (req, res) => {
  const schema = z.object({
    email: z.string().email(),
    password: z.string().min(1)
  });

  const data = schema.parse(req.body);

  const result = await pool.query(
    `SELECT u.id, u.name, u.email, u.password_hash,
            cm.company_id, cm.role
     FROM users u
     JOIN company_members cm ON cm.user_id = u.id
     WHERE u.email = $1
     ORDER BY cm.company_id
     LIMIT 1`,
    [data.email.toLowerCase()]
  );

  if (!result.rows.length) {
    return res.status(401).json({ error: "بيانات الدخول غير صحيحة" });
  }

  const user = result.rows[0];
  const valid = await bcrypt.compare(data.password, user.password_hash);

  if (!valid) {
    return res.status(401).json({ error: "بيانات الدخول غير صحيحة" });
  }

  const token = tokenFor({
    id: user.id,
    company_id: user.company_id
  });

  res.json({
    token,
    user: { id: user.id, name: user.name, email: user.email },
    companyId: user.company_id,
    role: user.role
  });
}));

app.get("/api/me", auth, asyncHandler(async (req, res) => {
  const result = await pool.query(
    `SELECT id, name, email FROM users WHERE id = $1`,
    [req.user.id]
  );
  res.json({ user: result.rows[0], companyId: req.user.companyId });
}));

app.get("/api/dashboard", auth, asyncHandler(async (req, res) => {
  const id = req.user.companyId;

  const [products, customers, sales, expenses] = await Promise.all([
    pool.query("SELECT COUNT(*) FROM products WHERE company_id = $1", [id]),
    pool.query("SELECT COUNT(*) FROM customers WHERE company_id = $1", [id]),
    pool.query("SELECT COUNT(*) FROM sales WHERE company_id = $1", [id]),
    pool.query("SELECT COALESCE(SUM(amount),0) AS total FROM expenses WHERE company_id = $1", [id])
  ]);

  res.json({
    products: Number(products.rows[0].count),
    customers: Number(customers.rows[0].count),
    sales: Number(sales.rows[0].count),
    expenses: Number(expenses.rows[0].total)
  });
}));

app.get("/api/products", auth, asyncHandler(async (req, res) => {
  const result = await pool.query(
    "SELECT * FROM products WHERE company_id = $1 ORDER BY id DESC",
    [req.user.companyId]
  );
  res.json(result.rows);
}));

app.post("/api/products", auth, asyncHandler(async (req, res) => {
  const schema = z.object({
    name: z.string().min(1).max(200),
    sku: z.string().max(100).optional(),
    barcode: z.string().max(100).optional(),
    price: z.number().nonnegative(),
    cost: z.number().nonnegative().default(0),
    quantity: z.number().int().nonnegative().default(0)
  });

  const data = schema.parse(req.body);

  const result = await pool.query(
    `INSERT INTO products
     (company_id, name, sku, barcode, price, cost, quantity)
     VALUES ($1,$2,$3,$4,$5,$6,$7) RETURNING *`,
    [
      req.user.companyId,
      data.name,
      data.sku || null,
      data.barcode || null,
      data.price,
      data.cost,
      data.quantity
    ]
  );

  res.status(201).json(result.rows[0]);
}));

app.get("/api/customers", auth, asyncHandler(async (req, res) => {
  const result = await pool.query(
    "SELECT * FROM customers WHERE company_id = $1 ORDER BY id DESC",
    [req.user.companyId]
  );
  res.json(result.rows);
}));

app.post("/api/customers", auth, asyncHandler(async (req, res) => {
  const schema = z.object({
    name: z.string().min(1).max(200),
    phone: z.string().max(50).optional(),
    email: z.string().email().optional()
  });

  const data = schema.parse(req.body);

  const result = await pool.query(
    `INSERT INTO customers (company_id, name, phone, email)
     VALUES ($1,$2,$3,$4) RETURNING *`,
    [
      req.user.companyId,
      data.name,
      data.phone || null,
      data.email || null
    ]
  );

  res.status(201).json(result.rows[0]);
}));

app.get("/api/sales", auth, asyncHandler(async (req, res) => {
  const result = await pool.query(
    "SELECT * FROM sales WHERE company_id = $1 ORDER BY id DESC",
    [req.user.companyId]
  );
  res.json(result.rows);
}));

app.post("/api/sales", auth, asyncHandler(async (req, res) => {
  const schema = z.object({
    customerId: z.number().int().positive().nullable().optional(),
    total: z.number().positive()
  });

  const data = schema.parse(req.body);

  const result = await pool.query(
    `INSERT INTO sales (company_id, customer_id, total)
     VALUES ($1,$2,$3) RETURNING *`,
    [req.user.companyId, data.customerId || null, data.total]
  );

  res.status(201).json(result.rows[0]);
}));

app.post("/api/expenses", auth, asyncHandler(async (req, res) => {
  const schema = z.object({
    title: z.string().min(1).max(200),
    amount: z.number().positive()
  });

  const data = schema.parse(req.body);

  const result = await pool.query(
    `INSERT INTO expenses (company_id, title, amount)
     VALUES ($1,$2,$3) RETURNING *`,
    [req.user.companyId, data.title, data.amount]
  );

  res.status(201).json(result.rows[0]);
}));

app.use((err, req, res, next) => {
  console.error(err);

  if (err instanceof z.ZodError) {
    return res.status(400).json({ error: "البيانات المدخلة غير صحيحة" });
  }

  res.status(500).json({ error: "حدث خطأ في الخادم" });
});

const port = process.env.PORT || 3000;

app.listen(port, () => {
  console.log(`NEXORA BUSINESS API running on port ${port}`);
});
