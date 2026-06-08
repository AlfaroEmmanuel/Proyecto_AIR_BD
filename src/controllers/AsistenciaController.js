// =====================================================================
// src/controllers/AsistenciaController.js — Issue #12
// =====================================================================
const Asistencia = require('../models/Asistencia');

const obtenerPadronVigente = async (_req, res) => {
    try {
        return res.json({ exito: true, datos: await Asistencia.obtenerPadronVigente() });
    } catch (error) {
        console.error('[AsistenciaController.obtenerPadronVigente]', error);
        return res.status(500).json({ exito: false, mensaje: 'Error al cargar el padrón.' });
    }
};

/**
 * POST /api/asistencias/sesion/:id_sesion   body: { presentes: ["1-1111-1111", ...] }
 */
const registrarAsistenciaSesion = async (req, res) => {
    try {
        const { id_sesion } = req.params;
        const { presentes } = req.body;
        if (!Array.isArray(presentes)) {
            return res.status(400).json({ exito: false, mensaje: '"presentes" debe ser un arreglo de cédulas.' });
        }
        const r = await Asistencia.registrarMasivo({
            id_sesion: Number(id_sesion),
            presentes,
            id_usuario: req.usuario ? req.usuario.id : null
        });
        return res.status(201).json({
            exito: true,
            mensaje: `Asistencia registrada: ${r.total_presentes} presentes de ${r.total_padron} en el padrón.`,
            ...r
        });
    } catch (error) {
        console.error('[AsistenciaController.registrarAsistenciaSesion]', error);
        return res.status(500).json({ exito: false, mensaje: 'Error al registrar asistencia.' });
    }
};

const obtenerAsistenciasAsambleista = async (req, res) => {
    try {
        const { cedula } = req.params;
        const { desde, hasta } = req.query;
        const datos = await Asistencia.obtenerPorAsambleista({ cedula, desde, hasta });
        return res.json({ exito: true, datos });
    } catch (error) {
        console.error('[AsistenciaController.obtenerAsistencias]', error);
        return res.status(500).json({ exito: false, mensaje: 'Error en la consulta.' });
    }
};

const calcularPorcentaje = async (req, res) => {
    try {
        const { cedula } = req.params;
        const { desde, hasta } = req.query;
        const datos = await Asistencia.calcularPorcentaje({ cedula, desde, hasta });
        return res.json({ exito: true, datos });
    } catch (error) {
        console.error('[AsistenciaController.calcularPorcentaje]', error);
        return res.status(500).json({ exito: false, mensaje: 'Error en el cálculo.' });
    }
};

module.exports = {
    obtenerPadronVigente,
    registrarAsistenciaSesion,
    obtenerAsistenciasAsambleista,
    calcularPorcentaje
};
