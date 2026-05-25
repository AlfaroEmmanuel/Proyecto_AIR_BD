// =============================================================================
// src/controllers/CertificadoController.js
// Issue #14 — Módulo de Validación de Firmas y Verificación Externa
// Proyecto AIR — Sprint 3
// =============================================================================
// RESPONSABILIDAD (MVC - Capa Controlador):
//   - Orquesta el flujo de emisión y verificación de certificaciones
//   - Valida permisos (solo Secretaría puede emitir)
//   - Llama al Modelo para persistir y al Servicio para generar QR
//   - Responde con JSON o con la vista según la ruta
//   - NO hace consultas a BD directamente (eso es el Modelo)
//   - NO genera el PDF directamente (eso es PDFService, Issue #17)
//
// RUTAS que expone este controlador (agregar en routes/certificado.routes.js):
//   POST /certificaciones/emitir          → emitir()        [Secretaría]
//   GET  /verificar/:folio                → verificar()     [Público, sin auth]
//   POST /verificar/hash                  → verificarHash() [Público, sin auth]
//   GET  /certificaciones/historial/:cedula → historial()   [Secretaría]
// =============================================================================

const Certificado    = require('../models/Certificado');
const CryptoService  = require('../services/CryptoService');

const CertificadoController = {

    // -------------------------------------------------------------------------
    // emitir()
    // POST /certificaciones/emitir
    // Solo accesible para rol Secretaría (middleware de auth valida antes).
    //
    // FLUJO COMPLETO:
    //   1. Valida que el body tenga los campos requeridos
    //   2. Llama al Modelo para obtener folio, calcular hash e insertar en BD
    //   3. Llama al Servicio para generar el QR con la URL de verificación
    //   4. Arma el objeto de pie de página y lo retorna al cliente
    //   5. El Issue #17 (PDFService) tomará este objeto y generará el PDF final
    // -------------------------------------------------------------------------
    async emitir(req, res) {
        try {
            const {
                cedula_asambleista,
                nombre_completo,
                sector,
                snapshot           // Objeto JSON con todos los datos del asambleísta
            } = req.body;

            // --- Validación de campos requeridos ---
            if (!cedula_asambleista || !nombre_completo || !sector || !snapshot) {
                return res.status(400).json({
                    ok: false,
                    mensaje: 'Faltan campos requeridos: cedula_asambleista, nombre_completo, sector, snapshot.'
                });
            }

            // El id_usuario viene del token JWT decodificado por el middleware de auth
            const id_usuario_secretaria = req.usuario?.id_usuario;
            if (!id_usuario_secretaria) {
                return res.status(401).json({
                    ok: false,
                    mensaje: 'No se pudo identificar al usuario que emite la certificación.'
                });
            }

            // --- Emitir certificación (Modelo) ---
            // El modelo obtiene el folio atómico, calcula el hash y persiste en BD
            const certificacion = await Certificado.emitir({
                cedula_asambleista,
                nombre_completo,
                sector,
                id_usuario_secretaria,
                snapshot
            });

            // --- Generar QR con la URL de verificación (Servicio) ---
            const piePagina = await CryptoService.construirPiePaginaVerificacion(
                certificacion.folio_unico,
                certificacion.hash_sha256,
                certificacion.url_verificacion
            );

            // --- Respuesta al cliente ---
            // El Issue #17 tomará certificacion + piePagina para armar el PDF
            return res.status(201).json({
                ok: true,
                mensaje: `Certificación ${certificacion.folio_unico} emitida correctamente.`,
                data: {
                    id_certificacion:  certificacion.id_certificacion,
                    folio_unico:       certificacion.folio_unico,
                    hash_sha256:       certificacion.hash_sha256,
                    url_verificacion:  certificacion.url_verificacion,
                    fecha_emision:     certificacion.fecha_emision,
                    pie_pagina:        piePagina   // Incluye QR en Base64
                }
            });

        } catch (error) {
            console.error('[CertificadoController.emitir]', error.message);

            // El trigger tg_no_repudio_cert lanza excepciones con este prefijo
            if (error.message.includes('NO_REPUDIO')) {
                return res.status(403).json({
                    ok: false,
                    mensaje: 'Este documento es inmutable y no puede ser modificado.'
                });
            }

            return res.status(500).json({
                ok: false,
                mensaje: 'Error interno al emitir la certificación.',
                detalle: error.message
            });
        }
    },

    // -------------------------------------------------------------------------
    // verificar()
    // GET /verificar/:folio
    // RUTA PÚBLICA — no requiere autenticación.
    // Terceros (RRHH, otras dependencias) la usan para validar el documento.
    // También es la URL que va dentro del código QR impreso en el PDF.
    // -------------------------------------------------------------------------
    async verificar(req, res) {
        try {
            const { folio } = req.params;

            if (!folio) {
                return res.status(400).json({
                    ok: false,
                    mensaje: 'Debe ingresar un número de folio. Ej: DAIR-001-2026'
                });
            }

            // Llama a la función verificar_certificacion() en BD
            const resultado = await Certificado.verificarPorFolio(folio);

            if (!resultado || !resultado.es_valido && resultado.estado === 'NO_EXISTE') {
                return res.status(404).json({
                    ok: false,
                    es_valido: false,
                    mensaje: `El folio ${folio} no existe en el sistema de la AIR.`
                });
            }

            return res.status(200).json({
                ok: true,
                es_valido:          resultado.es_valido,
                folio_unico:        resultado.folio_unico,
                estado:             resultado.estado,
                nombre_asambleista: resultado.nombre_asambleista,
                cedula:             resultado.cedula,
                fecha_emision:      resultado.fecha_emision,
                hash_sha256:        resultado.hash_sha256,
                mensaje:            resultado.mensaje
            });

        } catch (error) {
            console.error('[CertificadoController.verificar]', error.message);
            return res.status(500).json({
                ok: false,
                mensaje: 'Error al verificar el documento.',
                detalle: error.message
            });
        }
    },

    // -------------------------------------------------------------------------
    // verificarHash()
    // POST /verificar/hash
    // RUTA PÚBLICA — permite que RRHH valide que el PDF impreso no fue alterado.
    // Body: { folio: "DAIR-001-2026", hash: "abc123..." }
    // -------------------------------------------------------------------------
    async verificarHash(req, res) {
        try {
            const { folio, hash } = req.body;

            if (!folio || !hash) {
                return res.status(400).json({
                    ok: false,
                    mensaje: 'Se requieren los campos folio y hash.'
                });
            }

            const resultado = await Certificado.verificarIntegridadHash(folio, hash);

            return res.status(200).json({
                ok: true,
                ...resultado
            });

        } catch (error) {
            console.error('[CertificadoController.verificarHash]', error.message);
            return res.status(500).json({
                ok: false,
                mensaje: 'Error al verificar la integridad del documento.',
                detalle: error.message
            });
        }
    },

    // -------------------------------------------------------------------------
    // historial()
    // GET /certificaciones/historial/:cedula
    // Solo accesible para rol Secretaría.
    // Muestra todas las certificaciones emitidas para un asambleísta.
    // -------------------------------------------------------------------------
    async historial(req, res) {
        try {
            const { cedula } = req.params;

            if (!cedula) {
                return res.status(400).json({
                    ok: false,
                    mensaje: 'Debe ingresar la cédula del asambleísta.'
                });
            }

            const certificaciones = await Certificado.historialPorCedula(cedula);

            return res.status(200).json({
                ok: true,
                total:  certificaciones.length,
                data:   certificaciones
            });

        } catch (error) {
            console.error('[CertificadoController.historial]', error.message);
            return res.status(500).json({
                ok: false,
                mensaje: 'Error al obtener el historial de certificaciones.',
                detalle: error.message
            });
        }
    }
};

module.exports = CertificadoController;
