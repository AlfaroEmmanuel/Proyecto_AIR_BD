// =====================================================================
// src/models/Certificacion.js — Persistencia del registro de certificaciones
// Issues #4 y #14 (base): registro y hash
// =====================================================================
const pool = require('../config/db');

class Certificacion {

    /**
     * Guarda el registro de una certificación emitida con su hash SHA-256.
     */
    static async registrar({ folio, cedula_asambleista, hash_seguridad, id_usuario }) {
        const sql = `
            INSERT INTO certificacion_emitida (
                folio, cedula_asambleista, hash_seguridad,
                fecha_emision, id_usuario_emisor
            ) VALUES ($1, $2, $3, CURRENT_TIMESTAMP, $4)
            RETURNING id_certificacion, folio, fecha_emision
        `;
        const { rows } = await pool.query(sql, [folio, cedula_asambleista, hash_seguridad, id_usuario]);
        return rows[0];
    }

    /**
     * Verifica si un folio corresponde a un documento emitido y devuelve su hash.
     * Útil para el endpoint público de validación (Issue #14).
     */
    static async verificarPorFolio(folio) {
        const sql = `
            SELECT c.folio, c.cedula_asambleista, c.hash_seguridad, c.fecha_emision,
                   a.nombre || ' ' || a.primer_apellido AS nombre_asambleista
              FROM certificacion_emitida c
              JOIN asambleista a ON c.cedula_asambleista = a.cedula
             WHERE c.folio = $1
        `;
        const { rows } = await pool.query(sql, [folio]);
        return rows[0] || null;
    }
}

module.exports = Certificacion;
