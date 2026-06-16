// =====================================================================
// src/controllers/CatalogoController.js
// GET /api/catalogos — alimenta los <select> de los formularios.
// =====================================================================
const Catalogo = require('../models/Catalogo');

const listar = async (_req, res) => {
    try {
        return res.json({ exito: true, datos: await Catalogo.listarTodos() });
    } catch (error) {
        console.error('[CatalogoController.listar]', error);
        return res.status(500).json({ exito: false, mensaje: 'Error al cargar los catálogos.' });
    }
};

module.exports = { listar };
