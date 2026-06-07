// =====================================================================
// src/models/Reporte.js — Issues #7, Ext #8, #16 (y historial global #13)
// =====================================================================
const pool = require('../config/db');

class Reporte {

    // ---- #7 / Ext #8 — Asistencia ----
    static async asistenciaAsambleista(cedula, desde, hasta) {
        const { rows } = await pool.query(
            'SELECT * FROM obtener_asistencia_asambleista($1, $2, $3)',
            [cedula, desde, hasta]
        );
        return rows;
    }

    static async asistenciaConsolidada() {
        const { rows } = await pool.query(
            'SELECT * FROM vw_asistencia_consolidada ORDER BY nombre_completo');
        return rows;
    }

    // ---- #16 — Reportería administrativa ----
    static async certificacionesPorMes(anio) {
        const { rows } = await pool.query(
            'SELECT anio, mes, total FROM vw_certificaciones_por_mes WHERE anio = $1 ORDER BY mes',
            [anio]
        );
        return rows;
    }

    static async asambleistasMasCertificados(limite = 20) {
        const { rows } = await pool.query(
            'SELECT cedula, nombre, total_certificaciones FROM vw_asambleistas_mas_certificados LIMIT $1',
            [limite]
        );
        return rows;
    }

    static async distribucionSectores() {
        const { rows } = await pool.query(
            'SELECT sector, total_asambleistas, porcentaje FROM vw_distribucion_sectores');
        return rows;
    }

    static async kpis(anio) {
        const sql = `
            SELECT
              (SELECT COUNT(*) FROM certificacion_emitida
                 WHERE estado='ACTIVO' AND EXTRACT(YEAR FROM fecha_emision)=$1)  AS total_emitidas_anio,
              (SELECT COUNT(DISTINCT cedula_asambleista) FROM nombramiento
                 WHERE estado_activo = TRUE
                   AND CURRENT_DATE BETWEEN fecha_inicio AND fecha_fin)          AS total_asambleistas_vigentes,
              (SELECT ROUND(AVG(total),2) FROM vw_certificaciones_por_mes WHERE anio=$1) AS promedio_mensual
        `;
        const { rows } = await pool.query(sql, [anio]);
        return rows[0];
    }

    // ---- #13 — Historial global de certificaciones (complementa el por-cédula ya existente) ----
    static async historialCertificaciones({ desde, hasta, idUsuario } = {}) {
        const cond = []; const params = []; let i = 1;
        if (desde)     { cond.push(`ce.fecha_emision >= $${i++}`); params.push(desde); }
        if (hasta)     { cond.push(`ce.fecha_emision <= $${i++}`); params.push(hasta); }
        if (idUsuario) { cond.push(`ce.id_usuario_secretaria = $${i++}`); params.push(idUsuario); }
        const where = cond.length ? 'WHERE ' + cond.join(' AND ') : '';
        const sql = `
            SELECT ce.id_certificacion, ce.folio_unico, ce.cedula_asambleista,
                   TRIM(a.nombre || ' ' || a.primer_apellido ||
                        COALESCE(' ' || a.segundo_apellido, '')) AS nombre_completo,
                   ce.fecha_emision, ce.estado, ce.hash_sha256, u.username AS emisor
              FROM certificacion_emitida ce
              JOIN asambleista a   ON a.cedula = ce.cedula_asambleista
              LEFT JOIN sys_usuario u ON u.id_usuario = ce.id_usuario_secretaria
              ${where}
             ORDER BY ce.fecha_emision DESC
        `;
        const { rows } = await pool.query(sql, params);
        return rows;
    }
}

module.exports = Reporte;
