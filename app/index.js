const express = require('express');
const { createClient } = require('redis');

const app = express();
const PORT = process.env.PORT || 3000;
const REDIS_URL = process.env.REDIS_URL || 'redis://redis:6379';

const redisClient = createClient({ url: REDIS_URL });

redisClient.on('error', (err) => console.error('Redis Client Error', err));

(async () => {
  await redisClient.connect();

  app.get('/', async (req, res) => {
    let count;
    try {
      count = await redisClient.incr('visitor_count');
    } catch (e) {
      return res.status(500).send('Error connecting to Redis');
    }
    res.send(`<h1>This is the ${count} visitor.</h1>`);
  });

  app.listen(PORT, () => {
    console.log(`Server running on http://localhost:${PORT}`);
  });
})();
