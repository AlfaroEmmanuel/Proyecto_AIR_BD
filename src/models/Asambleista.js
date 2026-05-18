// =====================================================================
// src/models/Asambleista.js — Acceso a datos de asambleístas
// Issues #9, #3
// =====================================================================
const pool = require('../config/db');

class Asambleista {

    /**
     * Registra un asambleísta y su primer nombramiento en una transacción atómica.
     * Si cualquier paso falla (incluido el trigger de traslape), hace ROLLBACK.
     */
    static async crearConNombramiento({
        cedula, nombre, primer_apellido, segundo_apellido, correo,
        id_sector, id_periodo, fecha_inicio, fecha_fin
    }) {
        const client = await pool.connect();
        try {
            await client.query('BEGIN');

            // Upsert de identidad
            await client.query(`
                INSERT INTO asambleista (cedula, nombre, primer_apellido, segundo_apellido, correo_institucional)
                VALUES ($1, $2, $3, $4, $5)
                ON CONFLICT (cedula) DO UPDATE SET
                    nombre               = EXCLUDED.nombre,
                    primer_apellido      = EXCLUDED.primer_apellido,
                    segundo_apellido     = EXCLUDED.segundo_apellido,
                    correo_institucional = EXCLUDED.correo_institucional
            `, [cedula, nombre, primer_apellido, segundo_apellido, correo]);

            // Nombramiento con rango de fechas (el trigger valida el traslape)
            await client.query(`
                INSERT INTO nombramiento (cedula_asambleista, id_sector, id_periodo,
                                          fecha_inicio, fecha_fin, estado_activo)
                VALUES ($1, $2, $3, $4, $5, TRUE)
            `, [cedula, id_sector, id_periodo, fecha_inicio, fecha_fin]);

            await client.query('COMMIT');
            return { ok: true };
        } catch (err) {
            await client.query('ROLLBACK');
            throw err;
        } finally {
            client.release();
        }
    }

    /**
     * Búsqueda avanzada con filtros opcionales: cédula, nombre y rango de fechas.
     * Retorna hoja de vida del asambleísta con todos sus nombramientos.
     */
    static async buscarConHistorial({ cedula, nombre, fecha_inicio, fecha_fin }) {
        const params = [];
        const where  = [];
        let i = 1;

        if (cedula) {
            where.push(`a.cedula = $${i++}`);
            params.push(cedula);
        }
        if (nombre) {
            where.push(`(a.nombre ILIKE $${i} OR a.primer_apellido ILIKE $${i} OR a.segundo_apellido ILIKE $${i})`);
            params.push(`%${nombre}%`);
            i++;
        }
        if (fecha_inicio && fecha_fin) {
            // Devuelve nombramientos cuyo rango se cruce con el filtro
            where.push(`n.fecha_inicio <= $${i++}`);
            where.push(`n.fecha_fin    >= $${i++}`);
            params.push(fecha_fin, fecha_inicio);
        }

        const sql = `
            SELECT a.cedula,
                   a.nombre,
                   a.primer_apellido,
                   a.segundo_apellido,
                   a.correo_institucional,
                   n.id_nombramiento,
                   n.fecha_inicio,
                   n.fecha_fin,
                   n.estado_activo,
                   s.nombre_sector,
                   p.anio_gestion,
                   CASE
                       WHEN n.estado_activo = TRUE
                            AND CURRENT_DATE BETWEEN n.fecha_inicio AND n.fecha_fin
                       THEN 'VIGENTE'
                       ELSE 'INACTIVO'
                   END AS estado_actual
              FROM asambleista a
              LEFT JOIN nombramiento    n ON a.cedula      = n.cedula_asambleista
              LEFT JOIN sector          s ON n.id_sector   = s.id_sector
              LEFT JOIN periodo_gestion p ON n.id_periodo  = p.id_periodo
             ${where.length ? 'WHERE ' + where.join(' AND ') : ''}
             ORDER BY a.primer_apellido, a.nombre, n.fecha_inicio DESC
        `;
        const { rows } = await pool.query(sql, params);
        return rows;
    }

    /**
     * Issue #2: Hoja de vida consolidada de un asambleísta.
     * Invoca la función SQL `obtener_hoja_vida_asambleista` que vive en la BD.
     *
     * @param {string} cedula
     * @param {string|null} fecha_inicio (opcional)
     * @param {string|null} fecha_fin    (opcional)
     */
    static async hojaDeVida(cedula, fecha_inicio = null, fecha_fin = null) {
        const sql = `SELECT * FROM obtener_hoja_vida_asambleista($1, $2, $3)`;
        const { rows } = await pool.query(sql, [cedula, fecha_inicio, fecha_fin]);

        if (rows.length === 0) return null;

        // Estructura agrupada: 1 sujeto + N nombramientos
        const primer = rows[0];
        return {
            cedula:               primer.cedula,
            nombre_completo:      primer.nombre_completo,
            correo_institucional: primer.correo_institucional,
            nombramientos: rows
                .filter(r => r.id_nombramiento !== null)
                .map(r => ({
                    id_nombramiento:     r.id_nombramiento,
                    sector:              r.nombre_sector,
                    anio_gestion:        r.anio_gestion,
                    fecha_inicio:        r.nombramiento_inicio,
                    fecha_fin:           r.nombramiento_fin,
                    dias_nombramiento:   r.dias_nombramiento,
                    estado:              r.estado_actual,
                })),
        };
    }

    /**
     * Lista todos los asambleístas (versión resumida para tabla principal).
     */
    static async listar() {
        const sql = `
            SELECT a.cedula,
                   a.nombre || ' ' || a.primer_apellido ||
                       COALESCE(' ' || a.segundo_apellido, '') AS nombre_completo,
                   a.correo_institucional,
                   COALESCE(s.nombre_sector, '—') AS sector_actual,
                   CASE
                       WHEN EXISTS (
                           SELECT 1 FROM nombramiento n
                            WHERE n.cedula_asambleista = a.cedula
                              AND n.estado_activo = TRUE
                              AND CURRENT_DATE BETWEEN n.fecha_inicio AND n.fecha_fin
                       ) THEN 'VIGENTE'
                       ELSE 'INACTIVO'
                   END AS estado
              FROM asambleista a
              LEFT JOIN LATERAL (
                   SELECT s.nombre_sector
                     FROM nombramiento n
                     JOIN sector s ON n.id_sector = s.id_sector
                    WHERE n.cedula_asambleista = a.cedula
                      AND n.estado_activo = TRUE
                    ORDER BY n.fecha_inicio DESC
                    LIMIT 1
              ) s ON TRUE
             ORDER BY a.primer_apellido, a.nombre
        `;
        const { rows } = await pool.query(sql);
        return rows;
    }
}

module.exports = Asambleista;
