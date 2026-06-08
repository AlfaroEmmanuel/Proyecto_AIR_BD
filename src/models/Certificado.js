// =====================================================================
// src/models/Certificado.js — Issue #14 (reconciliado a la base Sprint 2)
// ÚNICO cambio vs. la versión del equipo: el import del pool.
//   ANTES: const { pool } = require('../config/db')   (db exporta { pool })
//   AHORA: const pool   = require('../config/db')      (db exporta el pool)
// =====================================================================
const crypto = require('crypto');
const pool   = require('../config/db');

class Certificado {

    static generarHash(contenido) {
        return crypto.createHash('sha256').update(contenido, 'utf8').digest('hex');
    }

    static construirContenidoCertificacion(datos) {
        return [
            datos.folio_unico,
            datos.cedula_asambleista,
            datos.nombre_completo,
            datos.sector,
            datos.fecha_emision,
            datos.id_usuario_secretaria
        ].join('|');
    }

    static construirUrlVerificacion(folio) {
        const base = process.env.APP_URL || 'http://localhost:3000';
        return `${base}/verificar/${folio}`;
    }

    static async emitir(datos) {
        const client = await pool.connect();
        try {
            await client.query('BEGIN');

            const folioResult = await client.query('SELECT generar_siguiente_folio() AS folio');
            const folio = folioResult.rows[0].folio;

            const fechaEmision = new Date().toISOString();
            const contenidoCanonico = Certificado.construirContenidoCertificacion({
                folio_unico:           folio,
                cedula_asambleista:    datos.cedula_asambleista,
                nombre_completo:       datos.nombre_completo,
                sector:                datos.sector,
                fecha_emision:         fechaEmision,
                id_usuario_secretaria: datos.id_usuario_secretaria
            });
            const hash = Certificado.generarHash(contenidoCanonico);
            const urlVerificacion = Certificado.construirUrlVerificacion(folio);

            const insertResult = await client.query(
                `INSERT INTO certificacion_emitida
                    (folio_unico, cedula_asambleista, id_usuario_secretaria,
                     hash_sha256, url_verificacion, datos_snapshot)
                 VALUES ($1, $2, $3, $4, $5, $6)
                 RETURNING *`,
                [folio, datos.cedula_asambleista, datos.id_usuario_secretaria,
                 hash, urlVerificacion, JSON.stringify(datos.snapshot)]
            );

            await client.query('COMMIT');
            return { ...insertResult.rows[0], contenido_canonico: contenidoCanonico };
        } catch (error) {
            await client.query('ROLLBACK');
            throw error;
        } finally {
            client.release();
        }
    }

    static async verificarPorFolio(folio) {
        const result = await pool.query('SELECT * FROM verificar_certificacion($1)', [folio]);
        return result.rows[0] || null;
    }

    static async verificarIntegridadHash(folio, hashAVerificar) {
        const result = await pool.query(
            `SELECT hash_sha256, estado FROM certificacion_emitida WHERE folio_unico = $1`, [folio]);
        if (result.rows.length === 0) {
            return { integro: false, mensaje: 'Folio no encontrado en el sistema.' };
        }
        const { hash_sha256, estado } = result.rows[0];
        const integro = hash_sha256 === hashAVerificar && estado === 'ACTIVO';
        return {
            integro, hash_registrado: hash_sha256, hash_recibido: hashAVerificar, estado,
            mensaje: integro
                ? 'El documento es auténtico y no ha sido alterado.'
                : estado === 'ANULADO'
                    ? 'Este documento ha sido anulado.'
                    : 'El hash no coincide. El documento puede haber sido alterado.'
        };
    }

    /** Issue #17 — payload completo del PDF (JSONB) desde la función SQL. */
    static async obtenerDatos(cedula, desde = null, hasta = null) {
        const result = await pool.query(
            'SELECT obtener_datos_certificacion($1, $2, $3) AS datos',
            [cedula, desde, hasta]
        );
        return result.rows[0] && result.rows[0].datos ? result.rows[0].datos : null;
    }

    static async historialPorCedula(cedula) {
        const result = await pool.query(
            `SELECT c.id_certificacion, c.folio_unico, c.estado, c.hash_sha256,
                    c.url_verificacion, c.fecha_emision, u.username AS emitido_por
               FROM certificacion_emitida c
               JOIN sys_usuario u ON u.id_usuario = c.id_usuario_secretaria
              WHERE c.cedula_asambleista = $1
              ORDER BY c.fecha_emision DESC`,
            [cedula]
        );
        return result.rows;
    }
}

module.exports = Certificado;
