// =====================================================================
// src/controllers/FolioController.js — Issue #1
// =====================================================================
const Folio = require('../models/Folio');

const obtenerSiguiente = async (req, res) => {
    try {
        const folio = await Folio.generarSiguiente();
        return res.json({ exito: true, folio });
    } catch (error) {
        console.error('[FolioController.obtenerSiguiente]', error);
        return res.status(500).json({ exito: false, mensaje: 'Error al generar folio.' });
    }
};

const consultarPorAnio = async (req, res) => {
    try {
        const anio = Number(req.params.anio);
        if (!anio || isNaN(anio)) {
            return res.status(400).json({ exito: false, mensaje: 'Año inválido.' });
        }
        const info = await Folio.listarPorAnio(anio);
        return res.json({ exito: true, info });
    } catch (error) {
        console.error('[FolioController.consultarPorAnio]', error);
        return res.status(500).json({ exito: false, mensaje: 'Error en la consulta.' });
    }
};

module.exports = { obtenerSiguiente, consultarPorAnio };
