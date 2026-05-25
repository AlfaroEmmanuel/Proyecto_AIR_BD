// =============================================================================
// src/services/CryptoService.js
// Issue #14 — Servicio de QR y Hash
// Proyecto AIR — Sprint 3
// =============================================================================
// RESPONSABILIDAD:
//   Utilidades transversales de seguridad que el Controlador invoca.
//   Vive en /services según la estructura de carpetas del documento (página 58).
//   No contiene lógica legal — solo genera artefactos criptográficos.
//
// INSTALACIÓN REQUERIDA:
//   npm install qrcode
// =============================================================================

const QRCode = require('qrcode');
const crypto = require('crypto');   // Nativo de Node.js

const CryptoService = {

    // -------------------------------------------------------------------------
    // generarQRBase64(contenido)
    // Genera un QR en formato Base64 (PNG embebible en HTML/PDF).
    // El QR contiene la URL de verificación pública.
    //
    // @param {string} contenido — URL de verificación Ej: https://air.itcr.ac.cr/verificar/DAIR-001-2026
    // @returns {string} Imagen QR en Base64 (data:image/png;base64,...)
    // -------------------------------------------------------------------------
    async generarQRBase64(contenido) {
        try {
            const qrBase64 = await QRCode.toDataURL(contenido, {
                errorCorrectionLevel: 'H',   // Alta corrección: resiste daños en el impreso
                margin: 1,
                width: 150,                   // 150px — suficiente para pie de página
                color: {
                    dark:  '#000000',
                    light: '#FFFFFF'
                }
            });
            return qrBase64;
        } catch (error) {
            throw new Error(`Error al generar QR: ${error.message}`);
        }
    },

    // -------------------------------------------------------------------------
    // generarQRSVG(contenido)
    // Alternativa en SVG: mejor calidad en impresión sin pixelación.
    //
    // @param {string} contenido
    // @returns {string} SVG como string
    // -------------------------------------------------------------------------
    async generarQRSVG(contenido) {
        try {
            const qrSVG = await QRCode.toString(contenido, {
                type: 'svg',
                errorCorrectionLevel: 'H',
                margin: 1
            });
            return qrSVG;
        } catch (error) {
            throw new Error(`Error al generar QR SVG: ${error.message}`);
        }
    },

    // -------------------------------------------------------------------------
    // generarHashSHA256(contenido)
    // Hash SHA-256 del contenido. Duplicado aquí para que el servicio sea
    // autocontenido y no dependa del modelo en contextos donde solo se
    // necesita el hash (ej. validación de PDF por terceros).
    //
    // @param {string} contenido
    // @returns {string} Hash hexadecimal de 64 caracteres
    // -------------------------------------------------------------------------
    generarHashSHA256(contenido) {
        return crypto
            .createHash('sha256')
            .update(contenido, 'utf8')
            .digest('hex');
    },

    // -------------------------------------------------------------------------
    // construirPiePaginaVerificacion(folio, hash, urlVerificacion)
    // Arma el objeto con todos los elementos del pie de página del documento.
    // El controlador lo pasa a la plantilla HTML/PDF.
    //
    // @param {string} folio           — "DAIR-001-2026"
    // @param {string} hash            — SHA-256 del documento
    // @param {string} urlVerificacion — URL pública
    // @returns {Object} Datos del pie de página listos para la plantilla
    // -------------------------------------------------------------------------
    async construirPiePaginaVerificacion(folio, hash, urlVerificacion) {
        const qrBase64 = await this.generarQRBase64(urlVerificacion);

        return {
            folio,
            hash_corto:       hash.substring(0, 16) + '...',   // Versión legible en el impreso
            hash_completo:    hash,
            url_verificacion: urlVerificacion,
            qr_base64:        qrBase64,
            // Texto legal del pie de página según el formato oficial
            texto_legal: `Documento emitido digitalmente. Folio: ${folio}. ` +
                         `Verifique su autenticidad en: ${urlVerificacion} ` +
                         `o escanee el código QR.`
        };
    }
};

module.exports = CryptoService;
