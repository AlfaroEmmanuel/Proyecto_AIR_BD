// =====================================================================
// src/models/Folio.js — Acceso a datos para control de folios
// Issue #1: Foliado y Asignación de Consecutivo Legal
// =====================================================================
const pool = require('../config/db');

class Folio {

    /**
     * Llama la función SQL atómica `generar_siguiente_folio()` que ya
     * resuelve la concurrencia mediante INSERT … ON CONFLICT … RETURNING.
     */
    static async generarSiguiente() {
        const { rows } = await pool.query('SELECT generar_siguiente_folio() AS folio');
        return rows[0].folio;
    }

    /**
     * Lista todos los folios emitidos en un año (auditoría).
     */
    static async listarPorAnio(anio) {
        const { rows } = await pool.query(
            'SELECT anio, ultimo_consecutivo, fecha_actualizacion FROM control_folio WHERE anio = $1',
            [anio]
        );
        return rows[0] || null;
    }
}

module.exports = Folio;
