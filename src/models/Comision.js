// =====================================================================
// src/models/Comision.js — Issue #6
// Comisiones, integrantes N:M y bulk insert transaccional.
// =====================================================================
const pool = require('../config/db');

class Comision {

    static async listar() {
        const sql = `
            SELECT c.id_comision, c.nombre, c.fecha_creacion, tc.nombre AS tipo,
                   (SELECT COUNT(*) FROM integrante_comision ic
                     WHERE ic.id_comision = c.id_comision AND ic.estado = 'Activo') AS total_integrantes
              FROM comision c
              LEFT JOIN tipo_comision tc ON tc.id_tipo_comision = c.id_tipo_comision
             ORDER BY c.nombre
        `;
        const { rows } = await pool.query(sql);
        return rows;
    }

    static async obtenerDetalle(id_comision) {
        const { rows: com } = await pool.query(
            `SELECT c.*, tc.nombre AS tipo
               FROM comision c LEFT JOIN tipo_comision tc ON tc.id_tipo_comision = c.id_tipo_comision
              WHERE c.id_comision = $1`, [id_comision]);
        if (com.length === 0) return null;

        const { rows: integrantes } = await pool.query(
            `SELECT ic.cedula_asambleista,
                    TRIM(a.nombre || ' ' || a.primer_apellido ||
                         COALESCE(' ' || a.segundo_apellido, '')) AS nombre_completo,
                    rc.nombre AS rol, ic.fecha_ingreso, ic.estado
               FROM integrante_comision ic
               JOIN asambleista a   ON a.cedula = ic.cedula_asambleista
               JOIN rol_comision rc ON rc.id_rol_comision = ic.id_rol_comision
              WHERE ic.id_comision = $1 AND ic.estado = 'Activo'
              ORDER BY rc.id_rol_comision, nombre_completo`,
            [id_comision]);

        return { ...com[0], integrantes };
    }

    static async crear({ nombre, objeto, id_tipo_comision }) {
        const { rows } = await pool.query(
            `INSERT INTO comision (nombre, objeto, id_tipo_comision) VALUES ($1, $2, $3) RETURNING *`,
            [nombre, objeto, id_tipo_comision || null]);
        return rows[0];
    }

    /**
     * Agrega integrantes en bloque (transaccional). El trigger
     * trg_rol_unico_comision rechaza roles activos duplicados.
     * @param {Array<{cedula:string, id_rol:number}>} integrantes
     */
    static async agregarIntegrantes(id_comision, integrantes) {
        const client = await pool.connect();
        try {
            await client.query('BEGIN');
            let total = 0;
            for (const { cedula, id_rol } of integrantes) {
                await client.query(
                    `INSERT INTO integrante_comision (id_comision, cedula_asambleista, id_rol_comision)
                     VALUES ($1, $2, $3)`,
                    [id_comision, cedula, id_rol]);
                total++;
            }
            await client.query('COMMIT');
            return { total_insertados: total };
        } catch (err) {
            await client.query('ROLLBACK');
            throw err; // el trigger pudo lanzar "ROL DUPLICADO"
        } finally {
            client.release();
        }
    }
}

module.exports = Comision;
