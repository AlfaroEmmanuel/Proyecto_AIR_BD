const pool = require('../../config/database');

class Asambleista {
    static async buscarAvanzado(filtros) {
        let query = `
            SELECT a.cedula, a.nombre, s.nombre_sector, n.fecha_inicio, n.fecha_fin,
            CASE 
                WHEN CURRENT_DATE BETWEEN n.fecha_inicio AND n.fecha_fin THEN 'VIGENTE'
                ELSE 'VENCIDO'
            END as estado_nombramiento
            FROM asambleista a
            LEFT JOIN nombramiento n ON a.id_asambleista = n.id_asambleista
            LEFT JOIN sector s ON n.id_sector = s.id_sector
            WHERE 1=1
        `;
        const params = [];
        let index = 1;

        if (filtros.cedula) {
            query += ` AND a.cedula = $${index++}`;
            params.push(filtros.cedula);
        }
        if (filtros.nombre) {
            query += ` AND a.nombre ILIKE $${index++}`;
            params.push(`%${filtros.nombre}%`);
        }
        if (filtros.fecha_inicio && filtros.fecha_fin) {
            query += ` AND n.fecha_inicio >= $${index++} AND n.fecha_fin <= $${index++}`;
            params.push(filtros.fecha_inicio, filtros.fecha_fin);
        }

        const result = await pool.query(query, params);
        return result.rows;
    }
}

module.exports = Asambleista;
