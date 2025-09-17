import express from 'express';
import { Pool } from 'pg';
import { authMiddleware } from './auth.js';
const router = express.Router();
const pool = new Pool({ connectionString: process.env.DATABASE_URL });

// increment trophies (current user)
router.post('/me/trophies', authMiddleware, async (req, res) => {
  const amount = Number(req.body.amount || 1);
  const userId = req.user.sub;
  const r = await pool.query(
    'UPDATE player_stats SET trophies = trophies + $1 WHERE user_id = $2 RETURNING trophies',
    [amount, userId]
  );
  res.json({ trophies: r.rows[0].trophies });
});

// increment games_played
router.post('/me/games', authMiddleware, async (req, res) => {
  const amount = Number(req.body.amount || 1);
  const userId = req.user.sub;
  const r = await pool.query(
    'UPDATE player_stats SET games_played = games_played + $1 WHERE user_id = $2 RETURNING games_played',
    [amount, userId]
  );
  res.json({ games_played: r.rows[0].games_played });
});

// leaderboard
router.get('/leaderboard', async (req, res) => {
  const limit = Number(req.query.limit || 20);
  const r = await pool.query(
    `SELECT u.id, u.username, s.trophies, s.games_played
     FROM users u JOIN player_stats s ON u.id = s.user_id
     ORDER BY s.trophies DESC, s.games_played DESC
     LIMIT $1`,
     [limit]
  );
  res.json(r.rows);
});

export default router;
