import express from 'express';
import { Pool } from 'pg';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';

const router = express.Router();
const pool = new Pool({ connectionString: process.env.DATABASE_URL });
const JWT_SECRET = process.env.JWT_SECRET || 'devsecret';

// generate token
function makeToken(user) {
  return jwt.sign({ sub: user.id, username: user.username }, JWT_SECRET, { expiresIn: '7d' });
}

// register
router.post('/register', async (req, res) => {
  const { username, password } = req.body;
  if (!username || !password) return res.status(400).json({ error:'username+password required' });
  const hash = await bcrypt.hash(password, 10);
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const r = await client.query(
      'INSERT INTO users (username, password_hash) VALUES ($1,$2) RETURNING id, username, created_at',
      [username, hash]
    );
    const user = r.rows[0];
    await client.query('INSERT INTO player_stats (user_id) VALUES ($1)', [user.id]);
    await client.query('COMMIT');
    const token = makeToken(user);
    res.json({ token, user: { id: user.id, username: user.username } });
  } catch (e) {
    await client.query('ROLLBACK');
    if (e.code === '23505') return res.status(409).json({ error: 'username exists' });
    console.error(e);
    res.status(500).json({ error: 'db error' });
  } finally { client.release(); }
});

// login
router.post('/login', async (req, res) => {
  const { username, password } = req.body;
  const r = await pool.query('SELECT id, username, password_hash FROM users WHERE username = $1', [username]);
  const user = r.rows[0];
  if (!user) return res.status(401).json({ error: 'invalid' });
  const ok = await bcrypt.compare(password, user.password_hash);
  if (!ok) return res.status(401).json({ error: 'invalid' });
  const token = makeToken(user);
  res.json({ token, user: { id: user.id, username: user.username } });
});

// auth middleware
export function authMiddleware(req, res, next) {
  const a = req.headers.authorization;
  if (!a) return res.status(401).json({ error: 'no token' });
  const token = a.split(' ')[1];
  try {
    req.user = jwt.verify(token, JWT_SECRET);
    next();
  } catch (e) {
    return res.status(401).json({ error: 'invalid token' });
  }
}

export default router;
