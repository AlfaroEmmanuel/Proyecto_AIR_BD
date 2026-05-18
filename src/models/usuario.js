const pool = require('../../config/database');

class Usuario {
    static async encontrarPorCredenciales(username, password) {
        const query = `
            SELECT u.*, r.nombre_rol 
            FROM sys_usuario u
            JOIN sys_rol r ON u.id_rol = r.id_rol
            WHERE u.username = $1 AND u.password_hash = $2
        `;
        const result = await pool.query(query, [username, password]);
        return result.rows[0];
    }
}

module.exports = Usuario;
