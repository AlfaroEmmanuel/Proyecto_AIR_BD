// =====================================================================
// src/controllers/ComisionController.js — Issue #6
// =====================================================================
const Comision = require('../models/Comision');

const listar = async (_req, res) => {
    try {
        return res.json({ exito: true, datos: await Comision.listar() });
    } catch (error) {
        console.error('[ComisionController.listar]', error);
        return res.status(500).json({ exito: false, mensaje: 'Error en la consulta.' });
    }
};

const obtenerDetalle = async (req, res) => {
    try {
        const com = await Comision.obtenerDetalle(Number(req.params.id_comision));
        if (!com) return res.status(404).json({ exito: false, mensaje: 'Comisión no encontrada.' });
        return res.json({ exito: true, datos: com });
    } catch (error) {
        console.error('[ComisionController.obtenerDetalle]', error);
        return res.status(500).json({ exito: false, mensaje: 'Error en la consulta.' });
    }
};

const crear = async (req, res) => {
    try {
        const com = await Comision.crear(req.body);
        return res.status(201).json({ exito: true, datos: com });
    } catch (error) {
        console.error('[ComisionController.crear]', error);
        return res.status(500).json({ exito: false, mensaje: 'Error al crear la comisión.' });
    }
};

/**
 * POST /api/comisiones/:id_comision/integrantes
 * body: { integrantes: [{ cedula, id_rol }, ...] }
 */
const agregarIntegrantes = async (req, res) => {
    try {
        const { integrantes } = req.body;
        if (!Array.isArray(integrantes) || integrantes.length === 0) {
            return res.status(400).json({ exito: false, mensaje: '"integrantes" debe ser un arreglo no vacío.' });
        }
        const r = await Comision.agregarIntegrantes(Number(req.params.id_comision), integrantes);
        return res.status(201).json({ exito: true, mensaje: `${r.total_insertados} integrante(s) agregado(s).`, ...r });
    } catch (error) {
        // El trigger fn_validar_rol_unico_comision lanza "ROL DUPLICADO"
        if (error.message && error.message.includes('ROL DUPLICADO')) {
            return res.status(409).json({ exito: false, mensaje: error.message });
        }
        console.error('[ComisionController.agregarIntegrantes]', error);
        return res.status(500).json({ exito: false, mensaje: 'Error al agregar integrantes.' });
    }
};

module.exports = { listar, obtenerDetalle, crear, agregarIntegrantes };
