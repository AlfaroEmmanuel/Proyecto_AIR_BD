// =====================================================================
// app.js — Punto de entrada del servidor Express
// Sistema de Gestión Legislativa AIR
// =====================================================================
require('dotenv').config();

const express = require('express');
const path    = require('path');
const apiRoutes = require('./src/routes/api');

const app  = express();
const PORT = process.env.PORT || 3000;

// Middlewares
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Servir vistas estáticas
app.use(express.static(path.join(__dirname, 'src', 'views')));
app.use('/public', express.static(path.join(__dirname, 'public')));

// API
app.use('/api', apiRoutes);

// Pantalla de inicio → login
app.get('/', (req, res) => {
    res.sendFile(path.join(__dirname, 'src', 'views', 'login.html'));
});

// Manejo global de errores
app.use((err, req, res, next) => {
    console.error('[ERROR]', err);
    res.status(500).json({ exito: false, mensaje: 'Error interno del servidor.' });
});

app.listen(PORT, () => {
    console.log(`✅ Servidor AIR escuchando en http://localhost:${PORT}`);
});
