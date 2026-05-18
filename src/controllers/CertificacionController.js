// =====================================================================
// src/controllers/CertificacionController.js — Issues #4, #14
// Orquesta: validar permisos -> obtener folio -> generar hash -> generar PDF
// La generación del documento delega en /services/PDFService.js
// =====================================================================
const Folio         = require('../models/Folio');
const CryptoService = require('../services/CryptoService');
const PDFService    = require('../services/PDFService');

const generarCertificacionPDF = async (req, res) => {
    try {
        const { nombre, cedula, sector, periodo } = req.body;
        if (!nombre || !cedula) {
            return res.status(400).json({ exito: false, mensaje: 'Faltan datos del asambleísta.' });
        }

        // 1. Obtener folio único atómico (Issue #1)
        const folio = await Folio.generarSiguiente();

        // 2. Generar hash SHA-256 del contenido (Issue #14)
        const contenido = JSON.stringify({ folio, nombre, cedula, sector, periodo, emisionISO: new Date().toISOString() });
        const hash = CryptoService.sha256(contenido);

        // 3. Generar el PDF con la plantilla oficial
        await PDFService.streamCertificacionAIR(res, { folio, hash, nombre, cedula, sector, periodo });

    } catch (error) {
        console.error('[CertificacionController.generarPDF]', error);
        if (!res.headersSent) {
            res.status(500).json({ exito: false, mensaje: 'Error al generar la certificación.' });
        }
    }
};

module.exports = { generarCertificacionPDF };
