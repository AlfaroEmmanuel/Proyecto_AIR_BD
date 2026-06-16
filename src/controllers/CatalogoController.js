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

const periodos = async (req, res) => {
    try {
        const datos = await Catalogo.listarPeriodos();
        return res.json({ exito: true, datos });
    } catch (error) {
        console.error('[CatalogoController.periodos]', error);
        return res.status(500).json({ exito: false, mensaje: 'Error al consultar periodos de gestión.' });
    }
};

const sectores = async (req, res) => {
    try {
        const datos = await Catalogo.listarSectores();
        return res.json({ exito: true, datos });
    } catch (error) {
        console.error('[CatalogoController.sectores]', error);
        return res.status(500).json({ exito: false, mensaje: 'Error al consultar sectores.' });
    }
};

module.exports = { listar, periodos, sectores };
