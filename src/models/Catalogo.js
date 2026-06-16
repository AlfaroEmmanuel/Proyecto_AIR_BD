// =====================================================================
// src/models/Catalogo.js
// Devuelve los catálogos que necesitan los formularios de la UI
// (tipos de sesión, modalidad, mayoría, propuesta, comisión, roles).
// =====================================================================
const pool = require('../config/db');

class Catalogo {

    static async listarTodos() {
        const q = (sql) => pool.query(sql).then(r => r.rows);
        const [
            tipo_sesion, tipo_modalidad, tipo_mayoria,
            tipo_propuesta, tipo_comision, rol_comision
        ] = await Promise.all([
            q(`SELECT id_tipo_sesion    AS id, nombre              FROM tipo_sesion             ORDER BY id`),
            q(`SELECT id_tipo_modalidad AS id, nombre              FROM tipo_modalidad          ORDER BY id`),
            q(`SELECT id_tipo_mayoria   AS id, nombre, fraccion    FROM tipo_mayoria_requerida  ORDER BY id`),
            q(`SELECT id_tipo_propuesta AS id, nombre              FROM catalogo_tipo_propuesta WHERE activo = TRUE ORDER BY id`),
            q(`SELECT id_tipo_comision  AS id, nombre              FROM tipo_comision           ORDER BY id`),
            q(`SELECT id_rol_comision   AS id, nombre              FROM rol_comision            ORDER BY id`)
        ]);
        return { tipo_sesion, tipo_modalidad, tipo_mayoria, tipo_propuesta, tipo_comision, rol_comision };
    }
}

module.exports = Catalogo;
