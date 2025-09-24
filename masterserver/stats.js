import express from 'express';
import { Pool } from 'pg';
import { authMiddleware } from './auth.js';
const router = express.Router();
const pool = new Pool({ connectionString: process.env.DATABASE_URL });

// increment trophies (current user)
router.post('/me/trophies', authMiddleware, async (req, res) => {
  const allowed = [-10, 30];
  const amount = Number(req.body.amount);

  if (!allowed.includes(amount)) {
    return res.status(400).json({ error: 'Invalid trophy amount' });
  }

  const userId = req.user.sub;
  try {
    const r = await pool.query(
      'UPDATE player_stats SET trophies = trophies + $1 WHERE user_id = $2 RETURNING trophies',
      [amount, userId]
    );
    return res.json({ trophies: r.rows[0].trophies });
  } catch (err) {
    console.error('DB error:', err);
    return res.status(500).json({ error: 'Database error' });
  }
});

// increment games_played
router.post('/me/games', authMiddleware, async (req, res) => {
  const amount = Number(req.body.amount || 1);

  // only +1 allowed
  if (amount !== 1) {
    return res.status(400).json({ error: 'Invalid game increment' });
  }

  const userId = req.user.sub;
  try {
    const r = await pool.query(
      'UPDATE player_stats SET games_played = games_played + 1 WHERE user_id = $1 RETURNING games_played',
      [userId]
    );
    return res.json({ games_played: r.rows[0].games_played });
  } catch (err) {
    console.error('DB error:', err);
    return res.status(500).json({ error: 'Database error' });
  }
});

router.get('/leaderboard', async (req, res) => {
  const limit = Number(req.query.limit || 20);
  try {
    const r = await pool.query(
      `SELECT u.id, u.username, s.trophies, s.games_played
       FROM users u JOIN player_stats s ON u.id = s.user_id
       ORDER BY s.trophies DESC, s.games_played DESC
       LIMIT $1`,
       [limit]
    );
    return res.json(r.rows);
  } catch (err) {
    console.error('DB error:', err);
    return res.status(500).json({ error: 'Database error' });
  }
});

export default router;
