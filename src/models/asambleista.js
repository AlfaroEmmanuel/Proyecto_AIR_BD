const pool = require('../../config/database');

class Asambleista {
    static async buscarAvanzado(filtros) {
        let query = `
            SELECT a.*, n.id_nombramiento, s.nombre_sector, p.nombre_periodo
            FROM asambleista a
            LEFT JOIN nombramiento n ON a.id_asambleista = n.id_asambleista
            LEFT JOIN sector s ON n.id_sector = s.id_sector
            LEFT JOIN periodo_gestion p ON n.id_periodo = p.id_periodo
            WHERE 1=1
        `;
        const params = [];

        if (filtros.cedula) {
            params.push(filtros.cedula);
            query += ` AND a.cedula = $${params.length}`;
        }
        if (filtros.nombre) {
            params.push(`%${filtros.nombre}%`);
            query += ` AND a.nombre ILIKE $${params.length}`;
        }

        const result = await pool.query(query, params);
        return result.rows;
    }
}

module.exports = Asambleista;
