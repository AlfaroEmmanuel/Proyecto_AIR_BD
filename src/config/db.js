// =====================================================================
// src/config/db.js — Conexión a PostgreSQL (Pool)
// =====================================================================
const { Pool } = require('pg');

const pool = new Pool({
    user:     process.env.DB_USER     || 'postgres',
    host:     process.env.DB_HOST     || 'localhost',
    database: process.env.DB_NAME     || 'prueba_proyecto_air',
    password: process.env.DB_PASSWORD || 'postgres',
    port:     Number(process.env.DB_PORT) || 5430,
    max: 20,
    idleTimeoutMillis: 30000,
});

pool.on('error', (err) => {
    console.error('[DB] Error inesperado en cliente inactivo:', err);
});

module.exports = pool;
