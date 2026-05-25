// =============================================================================
// src/models/Certificado.js
// Issue #14 — Módulo de Validación de Firmas y Verificación Externa
// Proyecto AIR — Sprint 3
// =============================================================================
// RESPONSABILIDAD (MVC - Capa Modelo):
//   - Persistencia de certificaciones emitidas en la BD
//   - Cálculo del hash SHA-256 del contenido del documento
//   - Consulta de verificación pública por folio
//   - NO contiene lógica de negocio (eso va en el Controlador)
// =============================================================================

const crypto = require('crypto');   // Nativo de Node.js — no requiere instalación
const { pool } = require('../config/db');

class Certificado {

    // -------------------------------------------------------------------------
    // generarHash(contenido)
    // Genera el SHA-256 del contenido textual del documento.
    // Se llama ANTES de insertar en BD para que el hash quede registrado.
    //
    // El documento (página 51) especifica: "Generación de un Hash de Seguridad
    // (SHA-256) basado en el contenido del documento para validar su integridad."
    // -------------------------------------------------------------------------
    static generarHash(contenido) {
        return crypto
            .createHash('sha256')
            .update(contenido, 'utf8')
            .digest('hex');
    }

    // -------------------------------------------------------------------------
    // construirContenidoCertificacion(datos)
    // Arma el string canónico sobre el que se calcula el hash.
    // Es CRÍTICO que este string sea idéntico cada vez que se reconstruya,
    // por eso usa un formato fijo y sin espacios variables.
    //
    // @param {Object} datos - Datos del asambleísta y la certificación
    // @returns {string} Contenido canónico para hashear
    // -------------------------------------------------------------------------
    static construirContenidoCertificacion(datos) {
        // Formato canónico: cualquier cambio aquí invalida hashes anteriores.
        // Debe mantenerse estable en producción.
        return [
            datos.folio_unico,
            datos.cedula_asambleista,
            datos.nombre_completo,
            datos.sector,
            datos.fecha_emision,           // ISO string: "2026-05-24T10:30:00.000Z"
            datos.id_usuario_secretaria
        ].join('|');
    }

    // -------------------------------------------------------------------------
    // construirUrlVerificacion(folio)
    // Genera la URL pública donde terceros pueden verificar el documento.
    // El controlador la expone en GET /verificar/:folio sin autenticación.
    // -------------------------------------------------------------------------
    static construirUrlVerificacion(folio) {
        const base = process.env.APP_URL || 'http://localhost:3000';
        return `${base}/verificar/${folio}`;
    }

    // -------------------------------------------------------------------------
    // emitir(datos)
    // Inserta una nueva certificación en la BD.
    //
    // FLUJO:
    //   1. Obtiene folio atómico desde BD (generar_siguiente_folio)
    //   2. Calcula el hash SHA-256 del contenido canónico
    //   3. Construye la URL de verificación
    //   4. Inserta el registro con snapshot JSON
    //   5. Retorna el registro completo para que el controlador genere el PDF
    //
    // @param {Object} datos
    //   - cedula_asambleista {string}
    //   - nombre_completo    {string}
    //   - sector             {string}
    //   - id_usuario_secretaria {number}
    //   - snapshot           {Object} — datos completos para el PDF
    // @returns {Object} Certificación emitida con folio y hash
    // -------------------------------------------------------------------------
    static async emitir(datos) {
        const client = await pool.connect();

        try {
            await client.query('BEGIN');

            // Paso 1: Obtener folio único atómico desde BD
            // La función generar_siguiente_folio() hace el LOCK internamente
            const folioResult = await client.query(
                'SELECT generar_siguiente_folio() AS folio'
            );
            const folio = folioResult.rows[0].folio;

            // Paso 2: Calcular hash SHA-256 del contenido canónico
            const fechaEmision = new Date().toISOString();
            const contenidoCanonico = Certificado.construirContenidoCertificacion({
                folio_unico:            folio,
                cedula_asambleista:     datos.cedula_asambleista,
                nombre_completo:        datos.nombre_completo,
                sector:                 datos.sector,
                fecha_emision:          fechaEmision,
                id_usuario_secretaria:  datos.id_usuario_secretaria
            });
            const hash = Certificado.generarHash(contenidoCanonico);

            // Paso 3: URL pública de verificación
            const urlVerificacion = Certificado.construirUrlVerificacion(folio);

            // Paso 4: Insertar en BD
            // El trigger tg_auditoria_certificacion registrará este INSERT automáticamente
            const insertResult = await client.query(
                `INSERT INTO certificacion_emitida
                    (folio_unico, cedula_asambleista, id_usuario_secretaria,
                     hash_sha256, url_verificacion, datos_snapshot)
                 VALUES ($1, $2, $3, $4, $5, $6)
                 RETURNING *`,
                [
                    folio,
                    datos.cedula_asambleista,
                    datos.id_usuario_secretaria,
                    hash,
                    urlVerificacion,
                    JSON.stringify(datos.snapshot)
                ]
            );

            await client.query('COMMIT');

            return {
                ...insertResult.rows[0],
                contenido_canonico: contenidoCanonico   // El controlador lo usa para el PDF
            };

        } catch (error) {
            await client.query('ROLLBACK');
            throw error;
        } finally {
            client.release();
        }
    }

    // -------------------------------------------------------------------------
    // verificarPorFolio(folio)
    // Consulta pública de verificación. Llama a la función de BD que
    // retorna si el documento es válido y sus metadatos.
    // No requiere autenticación (ruta pública para terceros).
    //
    // @param {string} folio — Ej: "DAIR-001-2026"
    // @returns {Object} Resultado de verificación
    // -------------------------------------------------------------------------
    static async verificarPorFolio(folio) {
        const result = await pool.query(
            'SELECT * FROM verificar_certificacion($1)',
            [folio]
        );
        return result.rows[0] || null;
    }

    // -------------------------------------------------------------------------
    // verificarIntegridadHash(folio, hashAVerificar)
    // Compara el hash almacenado en BD contra uno recalculado externamente.
    // Útil para que RRHH valide que el PDF impreso no fue alterado.
    //
    // @param {string} folio
    // @param {string} hashAVerificar — Hash del PDF que tiene el tercero
    // @returns {Object} { integro: boolean, hash_registrado, hash_recibido }
    // -------------------------------------------------------------------------
    static async verificarIntegridadHash(folio, hashAVerificar) {
        const result = await pool.query(
            `SELECT hash_sha256, estado
               FROM certificacion_emitida
              WHERE folio_unico = $1`,
            [folio]
        );

        if (result.rows.length === 0) {
            return {
                integro: false,
                mensaje: 'Folio no encontrado en el sistema.'
            };
        }

        const { hash_sha256, estado } = result.rows[0];
        const integro = hash_sha256 === hashAVerificar && estado === 'ACTIVO';

        return {
            integro,
            hash_registrado: hash_sha256,
            hash_recibido:   hashAVerificar,
            estado,
            mensaje: integro
                ? 'El documento es auténtico y no ha sido alterado.'
                : estado === 'ANULADO'
                    ? 'Este documento ha sido anulado.'
                    : 'El hash no coincide. El documento puede haber sido alterado.'
        };
    }

    // -------------------------------------------------------------------------
    // historialPorCedula(cedula)
    // Retorna todas las certificaciones emitidas para un asambleísta.
    // Usada por el dashboard de la Secretaría (Issue #13).
    //
    // @param {string} cedula
    // @returns {Array} Lista de certificaciones
    // -------------------------------------------------------------------------
    static async historialPorCedula(cedula) {
        const result = await pool.query(
            `SELECT
                c.id_certificacion,
                c.folio_unico,
                c.estado,
                c.hash_sha256,
                c.url_verificacion,
                c.fecha_emision,
                u.username AS emitido_por
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
