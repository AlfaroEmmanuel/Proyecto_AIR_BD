// =====================================================================
// src/models/Propuesta.js — Issues #11 y #5
// =====================================================================
const pool = require('../config/db');

class Propuesta {

    static async crear({ titulo, descripcion, id_sesion, id_tipo_mayoria, id_tipo_propuesta }) {
        const sql = `
            INSERT INTO propuesta
                (titulo, descripcion, id_sesion, id_estado_propuesta, id_tipo_mayoria, id_tipo_propuesta, estado)
            VALUES ($1, $2, $3,
                    (SELECT id_estado_propuesta FROM estado_propuesta WHERE nombre = 'En trámite'),
                    $4, $5, 'En trámite')
            RETURNING *
        `;
        const { rows } = await pool.query(sql, [
            titulo, descripcion, id_sesion, id_tipo_mayoria, id_tipo_propuesta || null
        ]);
        return rows[0];
    }

    /**
     * Issue #5 — Leyenda legal asociada al tipo de la propuesta.
     * La consume el motor de certificaciones (#17).
     */
    static async obtenerLeyendaLegal(id_propuesta) {
        const sql = `
            SELECT p.id_propuesta,
                   ctp.nombre        AS tipo,
                   ctp.leyenda_legal AS leyenda_legal
              FROM propuesta p
              LEFT JOIN catalogo_tipo_propuesta ctp ON ctp.id_tipo_propuesta = p.id_tipo_propuesta
             WHERE p.id_propuesta = $1
        `;
        const { rows } = await pool.query(sql, [id_propuesta]);
        if (rows.length === 0) return null;
        return {
            id_propuesta: rows[0].id_propuesta,
            tipo: rows[0].tipo,
            leyenda_legal: rows[0].leyenda_legal || ''
        };
    }

    static async obtenerPorId(id_propuesta) {
        const { rows } = await pool.query('SELECT * FROM propuesta WHERE id_propuesta = $1', [id_propuesta]);
        return rows[0] || null;
    }
}

module.exports = Propuesta;
