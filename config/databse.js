const { Pool } = require('pg');

// Configuración flexible: detecta si está en AWS RDS o local
const pool = new Pool({
    user: process.env.DB_USER || 'postgres',
    host: process.env.DB_HOST || 'localhost',
    database: process.env.DB_NAME || 'proyecto_air',
    password: process.env.DB_PASSWORD || 'EMMA28072006am.', 
    port: process.env.DB_PORT || 5430,
});

module.exports = pool;
