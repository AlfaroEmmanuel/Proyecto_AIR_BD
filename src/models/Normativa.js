// =====================================================================
// src/models/Normativa.js — Acceso a datos jerárquicos de la normativa
// Issue #10 (Parte I): Estructura recursiva y versionamiento
// =====================================================================
const pool = require('../config/db');

class Normativa {

    /**
     * Devuelve el árbol completo de elementos VIGENTES usando una CTE recursiva.
     * Salida ordenada por jerarquía + orden interno.
     */
    static async obtenerArbolVigente() {
        const sql = `
            WITH RECURSIVE arbol AS (
                SELECT e.id_elemento, e.id_padre, e.tipo, e.numero,
                       e.texto_contenido, e.estado, e.orden,
                       e.id_resolucion_origen, 1 AS nivel,
                       LPAD(e.orden::TEXT, 4, '0') AS ruta_orden
                  FROM elemento_normativo e
                 WHERE e.id_padre IS NULL
                   AND e.estado = 'VIGENTE'
                UNION ALL
                SELECT h.id_elemento, h.id_padre, h.tipo, h.numero,
                       h.texto_contenido, h.estado, h.orden,
                       h.id_resolucion_origen, p.nivel + 1,
                       p.ruta_orden || '.' || LPAD(h.orden::TEXT, 4, '0')
                  FROM elemento_normativo h
                  JOIN arbol p ON h.id_padre = p.id_elemento
                 WHERE h.estado = 'VIGENTE'
            )
            SELECT a.*, r.folio_dair AS resolucion_origen
              FROM arbol a
              JOIN resolucion r ON a.id_resolucion_origen = r.id_resolucion
             ORDER BY a.ruta_orden
        `;
        const { rows } = await pool.query(sql);
        return rows;
    }

    /**
     * Obtiene el historial de versiones de un elemento normativo
     * (identificado por padre, tipo y número).
     */
    static async obtenerHistorial({ id_padre, tipo, numero }) {
        const sql = `
            SELECT e.id_elemento, e.estado, e.texto_contenido,
                   e.fecha_vigencia_inicio, e.fecha_vigencia_fin,
                   r.folio_dair AS resolucion_origen, r.fecha_aprobacion
              FROM elemento_normativo e
              JOIN resolucion r ON e.id_resolucion_origen = r.id_resolucion
             WHERE COALESCE(e.id_padre, -1) = COALESCE($1, -1)
               AND e.tipo   = $2
               AND e.numero = $3
             ORDER BY e.fecha_vigencia_inicio DESC
        `;
        const { rows } = await pool.query(sql, [id_padre, tipo, numero]);
        return rows;
    }

    /**
     * Inserta un nuevo elemento normativo. Si el estado es VIGENTE, el
     * trigger fn_versionar_elemento_normativo se encarga automáticamente
     * de marcar como HISTORICO el anterior con la misma (padre, tipo, número).
     */
    static async insertar({ id_padre, tipo, numero, texto_contenido, orden, id_resolucion_origen }) {
        const sql = `
            INSERT INTO elemento_normativo (
                id_padre, tipo, numero, texto_contenido, orden,
                id_resolucion_origen, estado, fecha_vigencia_inicio
            ) VALUES ($1, $2, $3, $4, $5, $6, 'VIGENTE', CURRENT_DATE)
            RETURNING id_elemento
        `;
        const { rows } = await pool.query(sql, [
            id_padre, tipo, numero, texto_contenido, orden, id_resolucion_origen
        ]);
        return rows[0].id_elemento;
    }
}

module.exports = Normativa;
