// =====================================================================
// src/controllers/PropuestaController.js — Issues #11 y #5
// =====================================================================
const Propuesta = require('../models/Propuesta');

const crear = async (req, res) => {
    try {
        const propuesta = await Propuesta.crear(req.body);
        return res.status(201).json({ exito: true, datos: propuesta });
    } catch (error) {
        console.error('[PropuestaController.crear]', error);
        return res.status(500).json({ exito: false, mensaje: 'Error al crear la propuesta.' });
    }
};

/**
 * GET /api/propuestas/:id_propuesta/leyenda  (Issue #5)
 */
const obtenerLeyendaLegal = async (req, res) => {
    try {
        const leyenda = await Propuesta.obtenerLeyendaLegal(Number(req.params.id_propuesta));
        if (!leyenda) return res.status(404).json({ exito: false, mensaje: 'Propuesta no encontrada.' });
        return res.json({ exito: true, datos: leyenda });
    } catch (error) {
        console.error('[PropuestaController.obtenerLeyendaLegal]', error);
        return res.status(500).json({ exito: false, mensaje: 'Error al obtener la leyenda.' });
    }
};

module.exports = { crear, obtenerLeyendaLegal };
