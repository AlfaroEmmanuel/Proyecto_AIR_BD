// =====================================================================
// src/models/Votacion.js — Issue #11
// El trigger trg_resolver_propuesta resuelve el estado de la propuesta
// automáticamente tras el INSERT.
// =====================================================================
const pool = require('../config/db');

class Votacion {

    static async registrar({ id_propuesta, id_sesion, votos_favor, votos_contra, votos_abstencion, total_presentes }) {
        const sql = `
            INSERT INTO votacion
                (id_propuesta, id_sesion, votos_favor, votos_contra, votos_abstencion, total_presentes)
            VALUES ($1, $2, $3, $4, $5, $6)
            RETURNING *
        `;
        const { rows } = await pool.query(sql, [
            id_propuesta, id_sesion, votos_favor, votos_contra, votos_abstencion, total_presentes
        ]);
        const { rows: prop } = await pool.query(
            'SELECT estado FROM propuesta WHERE id_propuesta = $1', [id_propuesta]);
        return { votacion: rows[0], estado_propuesta: prop[0] ? prop[0].estado : null };
    }
}

module.exports = Votacion;
