// =====================================================================
// src/controllers/AnulacionController.js — Issue #15 (reconciliado)
// Envelope { exito, mensaje, datos }, usuario req.usuario.id.
// =====================================================================
const Anulacion = require('../models/Anulacion');

const MOTIVO_MIN = 10;

const AnulacionController = {

    // POST /api/anulaciones/anular   body: { folio, motivo }
    async anular(req, res) {
        try {
            const { folio, motivo } = req.body;
            if (!folio || !motivo) {
                return res.status(400).json({ exito: false, mensaje: 'Los campos folio y motivo son obligatorios.' });
            }
            if (motivo.trim().length < MOTIVO_MIN) {
                return res.status(400).json({ exito: false, mensaje: `El motivo debe tener al menos ${MOTIVO_MIN} caracteres.` });
            }
            const idUsuarioAdmin = req.usuario && req.usuario.id;
            if (!idUsuarioAdmin) {
                return res.status(401).json({ exito: false, mensaje: 'No se pudo identificar al administrador.' });
            }

            const r = await Anulacion.anular(folio, motivo.trim(), idUsuarioAdmin);
            if (!r.ok) {
                return res.status(400).json({ exito: false, mensaje: r.mensaje });
            }
            return res.json({ exito: true, mensaje: r.mensaje, datos: { folio_anulado: r.folio_anulado } });
        } catch (error) {
            console.error('[AnulacionController.anular]', error.message);
            return res.status(500).json({ exito: false, mensaje: 'Error al anular la certificación.' });
        }
    },

    // POST /api/anulaciones/sustituir
    async sustituir(req, res) {
        try {
            const { folio_anulado, motivo_sustitucion, cedula_asambleista, nombre_completo, sector, snapshot } = req.body;
            if (!folio_anulado || !motivo_sustitucion || !cedula_asambleista || !nombre_completo || !sector || !snapshot) {
                return res.status(400).json({ exito: false, mensaje: 'Faltan campos: folio_anulado, motivo_sustitucion, cedula_asambleista, nombre_completo, sector, snapshot.' });
            }
            const idUsuarioAdmin = req.usuario && req.usuario.id;
            if (!idUsuarioAdmin) {
                return res.status(401).json({ exito: false, mensaje: 'No se pudo identificar al administrador.' });
            }

            const nuevaCert = await Anulacion.emitirSustitucion({
                folio_anulado, motivo_sustitucion, cedula_asambleista, nombre_completo, sector,
                id_usuario_secretaria: idUsuarioAdmin, snapshot
            });
            return res.status(201).json({
                exito: true,
                mensaje: `Certificación de sustitución ${nuevaCert.folio_sustituto} emitida. Sustituye al folio ${nuevaCert.folio_original}.`,
                datos: nuevaCert
            });
        } catch (error) {
            console.error('[AnulacionController.sustituir]', error.message);
            return res.status(500).json({ exito: false, mensaje: error.message || 'Error al emitir la sustitución.' });
        }
    },

    // GET /api/anulaciones/historial
    async historial(_req, res) {
        try {
            const datos = await Anulacion.historial();
            return res.json({ exito: true, total: datos.length, datos });
        } catch (error) {
            console.error('[AnulacionController.historial]', error.message);
            return res.status(500).json({ exito: false, mensaje: 'Error al obtener el historial.' });
        }
    },

    // GET /api/anulaciones/historial/:folio
    async historialPorFolio(req, res) {
        try {
            const datos = await Anulacion.historial(req.params.folio);
            return res.json({ exito: true, total: datos.length, datos });
        } catch (error) {
            console.error('[AnulacionController.historialPorFolio]', error.message);
            return res.status(500).json({ exito: false, mensaje: 'Error al obtener el historial.' });
        }
    },

    // GET /api/anulaciones/estado/:folio
    async estado(req, res) {
        try {
            const r = await Anulacion.verificarEstado(req.params.folio);
            if (!r) return res.status(404).json({ exito: false, mensaje: `El folio ${req.params.folio} no existe.` });
            return res.json({
                exito: true,
                datos: {
                    folio_unico: r.folio_unico, estado: r.estado,
                    motivo_anulacion: r.motivo_anulacion || null, fecha_emision: r.fecha_emision
                },
                mensaje: r.estado === 'ACTIVO' ? 'El documento está vigente.' : `Anulado. Motivo: ${r.motivo_anulacion}`
            });
        } catch (error) {
            console.error('[AnulacionController.estado]', error.message);
            return res.status(500).json({ exito: false, mensaje: 'Error al verificar el estado.' });
        }
    }
};

module.exports = AnulacionController;
