// =====================================================================
// src/models/Asistencia.js — Issue #12
// Pase de lista masivo transaccional + cálculo de porcentajes.
// =====================================================================
const pool = require('../config/db');

class Asistencia {

    /** Padrón vigente: asambleístas con nombramiento activo en la fecha actual. */
    static async obtenerPadronVigente() {
        const sql = `
            SELECT DISTINCT a.cedula,
                   TRIM(a.nombre || ' ' || a.primer_apellido ||
                        COALESCE(' ' || a.segundo_apellido, '')) AS nombre_completo
              FROM nombramiento n
              JOIN asambleista a ON a.cedula = n.cedula_asambleista
             WHERE n.estado_activo = TRUE
               AND CURRENT_DATE BETWEEN n.fecha_inicio AND n.fecha_fin
             ORDER BY nombre_completo
        `;
        const { rows } = await pool.query(sql);
        return rows;
    }

    /**
     * Pase de lista masivo: marca 'Presente' a las cédulas recibidas y
     * 'Ausente' al resto del padrón vigente. Transaccional.
     */
    static async registrarMasivo({ id_sesion, presentes, id_usuario }) {
        const client = await pool.connect();
        try {
            await client.query('BEGIN');
            // Propaga el usuario de la app para el trigger de auditoría (patrón Sprint 2)
            if (id_usuario) {
                await client.query("SELECT set_config('app.id_usuario', $1, true)", [String(id_usuario)]);
            }

            const { rows: padron } = await client.query(
                `SELECT DISTINCT cedula_asambleista AS cedula
                   FROM nombramiento
                  WHERE estado_activo = TRUE
                    AND CURRENT_DATE BETWEEN fecha_inicio AND fecha_fin`
            );

            const setPresentes = new Set(presentes);
            const idPresente = await this._idEstado(client, 'Presente');
            const idAusente  = await this._idEstado(client, 'Ausente');

            for (const { cedula } of padron) {
                const idEstado = setPresentes.has(cedula) ? idPresente : idAusente;
                await client.query(
                    `INSERT INTO asistencia_sesion_plenaria (id_sesion, cedula_asambleista, id_estado_asistencia)
                     VALUES ($1, $2, $3)
                     ON CONFLICT (id_sesion, cedula_asambleista)
                     DO UPDATE SET id_estado_asistencia = EXCLUDED.id_estado_asistencia`,
                    [id_sesion, cedula, idEstado]
                );
            }

            await client.query('COMMIT');
            return { total_padron: padron.length, total_presentes: setPresentes.size };
        } catch (err) {
            await client.query('ROLLBACK');
            throw err;
        } finally {
            client.release();
        }
    }

    static async _idEstado(client, nombre) {
        const { rows } = await client.query(
            'SELECT id_estado_asistencia FROM estado_asistencia WHERE nombre_estado = $1', [nombre]);
        return rows[0].id_estado_asistencia;
    }

    static async obtenerPorAsambleista({ cedula, desde, hasta }) {
        const sql = `
            SELECT s.numero_sesion, s.fecha_sesion, ea.nombre_estado AS estado
              FROM asistencia_sesion_plenaria asp
              JOIN sesion s             ON s.id_sesion = asp.id_sesion
              JOIN estado_asistencia ea ON ea.id_estado_asistencia = asp.id_estado_asistencia
             WHERE asp.cedula_asambleista = $1
               AND ($2::date IS NULL OR s.fecha_sesion >= $2)
               AND ($3::date IS NULL OR s.fecha_sesion <= $3)
             ORDER BY s.fecha_sesion DESC
        `;
        const { rows } = await pool.query(sql, [cedula, desde || null, hasta || null]);
        return rows;
    }

    static async calcularPorcentaje({ cedula, desde, hasta }) {
        const { rows } = await pool.query(
            'SELECT calcular_porcentaje_asistencia_plenaria($1, $2, $3) AS porcentaje',
            [cedula, desde || '1900-01-01', hasta || new Date().toISOString().slice(0, 10)]
        );
        return { cedula, porcentaje_plenaria: rows[0].porcentaje };
    }

    static async calcularPorcentajeComision({ cedula, id_comision }) {
        const { rows } = await pool.query(
            'SELECT calcular_porcentaje_asistencia_comision($1, $2) AS porcentaje',
            [cedula, id_comision]
        );
        return { cedula, id_comision, porcentaje_comision: rows[0].porcentaje };
    }
}

module.exports = Asistencia;
