// =====================================================================
// src/controllers/PropuestaController.js — Issues #11 y #5 (+ proponentes)
// =====================================================================
const Propuesta = require('../models/Propuesta');

const crear = async (req, res) => {
    try {
        const { titulo, id_sesion, id_tipo_mayoria } = req.body;
        if (!titulo || !id_sesion || !id_tipo_mayoria) {
            return res.status(400).json({ exito: false, mensaje: 'Faltan campos: titulo, id_sesion, id_tipo_mayoria.' });
        }
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

/**
 * POST /api/propuestas/:id_propuesta/proponentes
 * body: { proponentes: [{ cedula, rol? }, ...] }
 */
const agregarProponentes = async (req, res) => {
    try {
        const { proponentes } = req.body;
        if (!Array.isArray(proponentes) || proponentes.length === 0) {
            return res.status(400).json({ exito: false, mensaje: '"proponentes" debe ser un arreglo no vacío.' });
        }
        const r = await Propuesta.agregarProponentes(Number(req.params.id_propuesta), proponentes);
        return res.status(201).json({ exito: true, mensaje: `${r.total_insertados} proponente(s) asignado(s).`, ...r });
    } catch (error) {
        console.error('[PropuestaController.agregarProponentes]', error);
        return res.status(500).json({ exito: false, mensaje: 'Error al asignar proponentes.' });
    }
};

module.exports = { crear, obtenerLeyendaLegal, agregarProponentes };
