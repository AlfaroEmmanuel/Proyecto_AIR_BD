// =====================================================================
// src/services/CryptoService.js — Utilidades criptográficas
// Issue #14: Generación de hash SHA-256 para validación externa
// =====================================================================
const crypto = require('crypto');

class CryptoService {
    /**
     * Devuelve el hash SHA-256 hexadecimal del contenido recibido.
     */
    static sha256(contenido) {
        return crypto.createHash('sha256').update(contenido, 'utf8').digest('hex');
    }
}

module.exports = CryptoService;
