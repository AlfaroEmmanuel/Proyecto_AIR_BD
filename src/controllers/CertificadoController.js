// =====================================================================
// src/controllers/CertificadoController.js — Issues #14 y #17
// Reconciliado a la base Sprint 2: envelope { exito, mensaje, datos },
// usuario req.usuario.id (el JWT trae { id, rol }).
// =====================================================================
const Certificado   = require('../models/Certificado');
const CryptoService = require('../services/CryptoService');
const PDFService    = require('../services/PDFService');

const CertificadoController = {

    // -------------------------------------------------------------------------
    // Issue #14 — emitir (registro + pie de página con QR; NO genera PDF)
    // POST /api/certificaciones/emitir
    // -------------------------------------------------------------------------
    async emitir(req, res) {
        try {
            const { cedula_asambleista, nombre_completo, sector, snapshot } = req.body;
            if (!cedula_asambleista || !nombre_completo || !sector || !snapshot) {
                return res.status(400).json({ exito: false, mensaje: 'Faltan campos: cedula_asambleista, nombre_completo, sector, snapshot.' });
            }
            const id_usuario_secretaria = req.usuario && req.usuario.id;
            if (!id_usuario_secretaria) {
                return res.status(401).json({ exito: false, mensaje: 'No se pudo identificar al usuario emisor.' });
            }

            const cert = await Certificado.emitir({ cedula_asambleista, nombre_completo, sector, id_usuario_secretaria, snapshot });
            const pie  = await CryptoService.construirPiePaginaVerificacion(cert.folio_unico, cert.hash_sha256, cert.url_verificacion);

            return res.status(201).json({
                exito: true,
                mensaje: `Certificación ${cert.folio_unico} emitida correctamente.`,
                datos: {
                    id_certificacion: cert.id_certificacion,
                    folio_unico:      cert.folio_unico,
                    hash_sha256:      cert.hash_sha256,
                    url_verificacion: cert.url_verificacion,
                    fecha_emision:    cert.fecha_emision,
                    pie_pagina:       pie
                }
            });
        } catch (error) {
            console.error('[CertificadoController.emitir]', error.message);
            if (error.message && error.message.includes('NO_REPUDIO')) {
                return res.status(403).json({ exito: false, mensaje: 'Este documento es inmutable y no puede modificarse.' });
            }
            return res.status(500).json({ exito: false, mensaje: 'Error al emitir la certificación.' });
        }
    },

    // -------------------------------------------------------------------------
    // Issue #17 — MOTOR: genera y devuelve el PDF inline
    // POST /api/certificacion/generar   body: { cedula, desde?, hasta? }
    // Orquesta: datos consolidados → emitir (folio+hash+snapshot) → PDF.
    // -------------------------------------------------------------------------
    async generarCertificacionPDF(req, res) {
        try {
            const { cedula, desde, hasta } = req.body;
            if (!cedula) {
                return res.status(400).json({ exito: false, mensaje: 'La cédula es obligatoria.' });
            }

            // 1) Payload consolidado (hoja de vida + asistencia + leyendas + cláusulas)
            const datos = await Certificado.obtenerDatos(cedula, desde || null, hasta || null);
            if (!datos) {
                return res.status(404).json({ exito: false, mensaje: 'Asambleísta no encontrado.' });
            }

            const nombre_completo = datos.identidad ? datos.identidad.nombre : '';
            const sector = (datos.nombramientos && datos.nombramientos[0]) ? datos.nombramientos[0].sector : 'Sin sector';
            const id_usuario_secretaria = req.usuario && req.usuario.id;

            // 2) Emite (folio atómico + hash + snapshot inmutable). Reusa el modelo #14.
            const cert = await Certificado.emitir({
                cedula_asambleista: cedula,
                nombre_completo,
                sector,
                id_usuario_secretaria,
                snapshot: datos
            });

            // 3) Renderiza el PDF inline con todos los bloques + QR + hash.
            await PDFService.streamCertificacionAIR(res, {
                folio: cert.folio_unico,
                hash:  cert.hash_sha256,
                datos
            });
        } catch (error) {
            console.error('[CertificadoController.generarCertificacionPDF]', error.message);
            if (!res.headersSent) {
                res.status(500).json({ exito: false, mensaje: 'Error al generar la certificación.' });
            } else {
                res.end();
            }
        }
    },

    // -------------------------------------------------------------------------
    // Issue #14 — verificar (PÚBLICO, sin auth)
    // GET /api/certificaciones/verificar/:folio
    // -------------------------------------------------------------------------
    async verificar(req, res) {
        try {
            const { folio } = req.params;
            if (!folio) return res.status(400).json({ exito: false, mensaje: 'Ingrese un folio. Ej: DAIR-001-2026' });

            const r = await Certificado.verificarPorFolio(folio);
            if (!r || (!r.es_valido && r.estado === 'NO_EXISTE')) {
                return res.status(404).json({ exito: false, es_valido: false, mensaje: `El folio ${folio} no existe en el sistema.` });
            }
            return res.json({
                exito: true,
                es_valido:          r.es_valido,
                folio_unico:        r.folio_unico,
                estado:             r.estado,
                nombre_asambleista: r.nombre_asambleista,
                cedula:             r.cedula,
                fecha_emision:      r.fecha_emision,
                hash_sha256:        r.hash_sha256,
                mensaje:            r.mensaje
            });
        } catch (error) {
            console.error('[CertificadoController.verificar]', error.message);
            return res.status(500).json({ exito: false, mensaje: 'Error al verificar el documento.' });
        }
    },

    // POST /api/certificaciones/verificar/hash   (PÚBLICO)  body: { folio, hash }
    async verificarHash(req, res) {
        try {
            const { folio, hash } = req.body;
            if (!folio || !hash) return res.status(400).json({ exito: false, mensaje: 'Se requieren folio y hash.' });
            const r = await Certificado.verificarIntegridadHash(folio, hash);
            return res.json({ exito: true, datos: r });
        } catch (error) {
            console.error('[CertificadoController.verificarHash]', error.message);
            return res.status(500).json({ exito: false, mensaje: 'Error al verificar la integridad.' });
        }
    },

    // GET /api/certificaciones/historial/:cedula   (Secretaria/Admin)
    async historial(req, res) {
        try {
            const { cedula } = req.params;
            if (!cedula) return res.status(400).json({ exito: false, mensaje: 'Ingrese la cédula.' });
            const datos = await Certificado.historialPorCedula(cedula);
            return res.json({ exito: true, total: datos.length, datos });
        } catch (error) {
            console.error('[CertificadoController.historial]', error.message);
            return res.status(500).json({ exito: false, mensaje: 'Error al obtener el historial.' });
        }
    }
};

module.exports = CertificadoController;
