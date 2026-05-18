// =====================================================================
// src/models/Usuario.js — Acceso a datos de usuarios del sistema
// Issue #0: Gestión de Seguridad y Roles Institucionales
// =====================================================================
const bcrypt = require('bcrypt');
const pool   = require('../config/db');

class Usuario {

    /**
     * Busca un usuario por username y valida su contraseña con BCrypt.
     * @param {string} username
     * @param {string} passwordPlano
     * @returns {Promise<Object|null>} usuario con su rol, o null si no autenticado
     */
    static async encontrarPorCredenciales(username, passwordPlano) {
        const query = `
            SELECT u.id_usuario, u.username, u.password_hash, u.email, u.activo,
                   u.id_rol, r.nombre_rol
              FROM sys_usuario u
              JOIN sys_rol r ON u.id_rol = r.id_rol
             WHERE u.username = $1
               AND u.activo   = TRUE
        `;
        const { rows } = await pool.query(query, [username]);
        if (rows.length === 0) return null;

        const usuario = rows[0];
        const ok = await bcrypt.compare(passwordPlano, usuario.password_hash);
        if (!ok) return null;

        delete usuario.password_hash; // jamás retornar el hash al controlador
        return usuario;
    }

    /**
     * Registra un nuevo usuario con su contraseña hasheada en BCrypt.
     */
    static async crear({ username, passwordPlano, email, id_rol }) {
        const hash = await bcrypt.hash(passwordPlano, 10);
        const query = `
            INSERT INTO sys_usuario (username, password_hash, email, id_rol)
            VALUES ($1, $2, $3, $4)
            RETURNING id_usuario, username, email, id_rol
        `;
        const { rows } = await pool.query(query, [username, hash, email, id_rol]);
        return rows[0];
    }
}

module.exports = Usuario;
