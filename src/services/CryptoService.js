// =====================================================================
// src/services/CryptoService.js — UNIFICADO
// Junta el sha256 del Sprint 2 (#4) con las utilidades de QR/pie del #14,
// que antes vivían en dos archivos distintos. Una sola fuente de verdad.
// Dependencias: qrcode  (crypto es nativo de Node)
// =====================================================================
const QRCode = require('qrcode');
const crypto = require('crypto');

class CryptoService {

    /** SHA-256 hex (nombre usado por el código del Sprint 2). */
    static sha256(contenido) {
        return crypto.createHash('sha256').update(contenido, 'utf8').digest('hex');
    }

    /** Alias usado por el código del #14. */
    static generarHashSHA256(contenido) {
        return CryptoService.sha256(contenido);
    }

    /** QR en Base64 (PNG) con la URL de verificación. */
    static async generarQRBase64(contenido) {
        return QRCode.toDataURL(contenido, {
            errorCorrectionLevel: 'H', margin: 1, width: 150,
            color: { dark: '#000000', light: '#FFFFFF' }
        });
    }

    /** QR en SVG (mejor para impresión). */
    static async generarQRSVG(contenido) {
        return QRCode.toString(contenido, { type: 'svg', errorCorrectionLevel: 'H', margin: 1 });
    }

    /** Arma el pie de página de verificación (folio + hash + QR + texto legal). */
    static async construirPiePaginaVerificacion(folio, hash, urlVerificacion) {
        const qr_base64 = await CryptoService.generarQRBase64(urlVerificacion);
        return {
            folio,
            hash_corto: hash.substring(0, 16) + '...',
            hash_completo: hash,
            url_verificacion: urlVerificacion,
            qr_base64,
            texto_legal: `Documento emitido digitalmente. Folio: ${folio}. ` +
                         `Verifique su autenticidad en: ${urlVerificacion} o escanee el código QR.`
        };
    }
}

module.exports = CryptoService;
