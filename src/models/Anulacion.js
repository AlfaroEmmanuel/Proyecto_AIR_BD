// =====================================================================
// src/models/Anulacion.js — Issue #15 (reconciliado a la base Sprint 2)
// ÚNICO cambio vs. la versión del equipo: el import del pool.
// =====================================================================
const pool        = require('../config/db');
const Certificado = require('./Certificado');

class Anulacion {

    static async anular(folio, motivo, idUsuarioAdmin, folioSustituto = null) {
        const result = await pool.query(
            'SELECT * FROM anular_certificacion($1, $2, $3, $4)',
            [folio, motivo, idUsuarioAdmin, folioSustituto]
        );
        return result.rows[0];
    }

    static async emitirSustitucion(datos) {
        const client = await pool.connect();
        try {
            await client.query('BEGIN');

            const verificacion = await client.query(
                `SELECT id_certificacion, estado FROM certificacion_emitida WHERE folio_unico = $1`,
                [datos.folio_anulado]
            );
            if (verificacion.rows.length === 0) {
                throw new Error(`El folio ${datos.folio_anulado} no existe en el sistema.`);
            }
            if (verificacion.rows[0].estado !== 'ANULADO') {
                throw new Error(`El folio ${datos.folio_anulado} no está anulado. Solo se puede sustituir un folio anulado.`);
            }

            const snapshotConSustitucion = {
                ...datos.snapshot,
                sustituye_a: datos.folio_anulado,
                motivo_sustitucion: datos.motivo_sustitucion
            };

            const nuevaCert = await Certificado.emitir({
                cedula_asambleista:    datos.cedula_asambleista,
                nombre_completo:       datos.nombre_completo,
                sector:                datos.sector,
                id_usuario_secretaria: datos.id_usuario_secretaria,
                snapshot:              snapshotConSustitucion
            });

            await client.query(
                `UPDATE certificacion_emitida SET id_cert_sustituida = $1 WHERE folio_unico = $2`,
                [verificacion.rows[0].id_certificacion, nuevaCert.folio_unico]
            );
            await client.query(
                `UPDATE anulacion_certificacion SET folio_sustituto = $1 WHERE folio_anulado = $2`,
                [nuevaCert.folio_unico, datos.folio_anulado]
            );

            await client.query('COMMIT');
            return {
                folio_original:   datos.folio_anulado,
                folio_sustituto:  nuevaCert.folio_unico,
                hash_sha256:      nuevaCert.hash_sha256,
                url_verificacion: nuevaCert.url_verificacion,
                fecha_emision:    nuevaCert.fecha_emision
            };
        } catch (error) {
            await client.query('ROLLBACK');
            throw error;
        } finally {
            client.release();
        }
    }

    static async historial(folio = null) {
        const result = await pool.query('SELECT * FROM obtener_historial_anulaciones($1)', [folio]);
        return result.rows;
    }

    static async verificarEstado(folio) {
        const result = await pool.query(
            `SELECT folio_unico, estado, motivo_anulacion, fecha_emision
               FROM certificacion_emitida WHERE folio_unico = $1`,
            [folio]
        );
        return result.rows[0] || null;
    }
}

module.exports = Anulacion;
