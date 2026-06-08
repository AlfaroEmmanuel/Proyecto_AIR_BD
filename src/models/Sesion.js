// =====================================================================
// src/models/Sesion.js — Issue #11
// Gestión de sesiones plenarias.
// =====================================================================
const pool = require('../config/db');

class Sesion {

    static async crear({ numero_sesion, fecha_sesion, id_tipo_sesion, id_tipo_modalidad, quorum_requerido }) {
        const sql = `
            INSERT INTO sesion
                (numero_sesion, fecha_sesion, id_tipo_sesion, id_tipo_modalidad, quorum_requerido)
            VALUES ($1, $2, $3, $4, $5)
            RETURNING *
        `;
        const { rows } = await pool.query(sql, [
            numero_sesion, fecha_sesion, id_tipo_sesion, id_tipo_modalidad, quorum_requerido || 0
        ]);
        return rows[0];
    }

    static async obtenerDetalle(id_sesion) {
        const sqlSesion = `
            SELECT s.*, ts.nombre AS tipo_sesion, tm.nombre AS modalidad,
                   (SELECT COUNT(*) FROM asistencia_sesion_plenaria asp
                      JOIN estado_asistencia ea ON ea.id_estado_asistencia = asp.id_estado_asistencia
                     WHERE asp.id_sesion = s.id_sesion AND ea.nombre_estado = 'Presente') AS total_presentes
              FROM sesion s
              JOIN tipo_sesion ts    ON ts.id_tipo_sesion    = s.id_tipo_sesion
              JOIN tipo_modalidad tm ON tm.id_tipo_modalidad = s.id_tipo_modalidad
             WHERE s.id_sesion = $1
        `;
        const { rows } = await pool.query(sqlSesion, [id_sesion]);
        if (rows.length === 0) return null;

        const { rows: propuestas } = await pool.query(
            `SELECT p.id_propuesta, p.titulo, p.estado, ep.nombre AS estado_detalle
               FROM propuesta p
               JOIN estado_propuesta ep ON ep.id_estado_propuesta = p.id_estado_propuesta
              WHERE p.id_sesion = $1`,
            [id_sesion]
        );
        return { ...rows[0], propuestas };
    }

    static async tieneQuorum(id_sesion) {
        const { rows } = await pool.query('SELECT verificar_quorum($1) AS ok', [id_sesion]);
        return rows[0].ok;
    }

    static async listar() {
        const { rows } = await pool.query(
            `SELECT s.id_sesion, s.numero_sesion, s.fecha_sesion, ts.nombre AS tipo, s.cerrada
               FROM sesion s JOIN tipo_sesion ts ON ts.id_tipo_sesion = s.id_tipo_sesion
              ORDER BY s.fecha_sesion DESC`
        );
        return rows;
    }
}

module.exports = Sesion;
