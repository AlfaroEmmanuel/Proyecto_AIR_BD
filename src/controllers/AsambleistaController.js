// =====================================================================
// src/controllers/AsambleistaController.js — Issues #3, #9
// Reglas de negocio: validaciones de entrada y orquestación del modelo
// =====================================================================
const Asambleista = require('../models/Asambleista');

const RE_CEDULA = /^[0-9]-[0-9]{4}-[0-9]{4}$/;            // CR
const RE_EMAIL  = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

const registrar = async (req, res) => {
    try {
        const {
            cedula, nombre, primer_apellido, segundo_apellido, correo,
            id_sector, id_periodo, fecha_inicio, fecha_fin
        } = req.body;

        // Validaciones de entrada
        if (!cedula || !nombre || !primer_apellido || !correo || !id_sector || !id_periodo
            || !fecha_inicio || !fecha_fin) {
            return res.status(400).json({ exito: false, mensaje: 'Faltan campos requeridos.' });
        }
        if (!RE_EMAIL.test(correo)) {
            return res.status(400).json({ exito: false, mensaje: 'Correo institucional inválido.' });
        }
        if (new Date(fecha_fin) <= new Date(fecha_inicio)) {
            return res.status(400).json({ exito: false, mensaje: 'La fecha de fin debe ser posterior al inicio.' });
        }

        await Asambleista.crearConNombramiento({
            cedula, nombre, primer_apellido, segundo_apellido, correo,
            id_sector: Number(id_sector),
            id_periodo: Number(id_periodo),
            fecha_inicio, fecha_fin
        });

        return res.status(201).json({
            exito: true,
            mensaje: 'Asambleísta y nombramiento registrados correctamente.'
        });
    } catch (error) {
        // Si el trigger de traslape disparó RAISE EXCEPTION, lo devolvemos al usuario
        if (error.message && error.message.includes('TRASLAPE DETECTADO')) {
            return res.status(409).json({ exito: false, mensaje: error.message });
        }
        if (error.message && error.message.includes('FECHA INVÁLIDA')) {
            return res.status(400).json({ exito: false, mensaje: error.message });
        }
        console.error('[AsambleistaController.registrar]', error);
        return res.status(500).json({ exito: false, mensaje: 'Error al procesar el registro.' });
    }
};

const buscar = async (req, res) => {
    try {
        const { cedula, nombre, fecha_inicio, fecha_fin } = req.query;
        const datos = await Asambleista.buscarConHistorial({
            cedula, nombre, fecha_inicio, fecha_fin
        });
        return res.json(datos);
    } catch (error) {
        console.error('[AsambleistaController.buscar]', error);
        return res.status(500).json({ exito: false, mensaje: 'Error en la consulta.' });
    }
};

const listar = async (req, res) => {
    try {
        const datos = await Asambleista.listar();
        return res.json(datos);
    } catch (error) {
        console.error('[AsambleistaController.listar]', error);
        return res.status(500).json({ exito: false, mensaje: 'Error en la consulta.' });
    }
};

/**
 * Issue #2: Hoja de vida del asambleísta.
 * GET /api/asambleistas/:cedula/hoja-vida?fecha_inicio=YYYY-MM-DD&fecha_fin=YYYY-MM-DD
 *
 * Sólo Secretaría/Administrador pueden invocarla porque es el insumo
 * directo para generar certificaciones (Issue #17 en Sprint 3).
 */
const hojaDeVida = async (req, res) => {
    try {
        const { cedula } = req.params;
        const { fecha_inicio, fecha_fin } = req.query;

        if (!cedula) {
            return res.status(400).json({ exito: false, mensaje: 'Cédula requerida.' });
        }
        if ((fecha_inicio && !fecha_fin) || (!fecha_inicio && fecha_fin)) {
            return res.status(400).json({ exito: false, mensaje: 'Debe enviar ambas fechas o ninguna.' });
        }
        if (fecha_inicio && fecha_fin && new Date(fecha_fin) < new Date(fecha_inicio)) {
            return res.status(400).json({ exito: false, mensaje: 'fecha_fin debe ser posterior a fecha_inicio.' });
        }

        const datos = await Asambleista.hojaDeVida(cedula, fecha_inicio || null, fecha_fin || null);
        if (!datos) {
            return res.status(404).json({ exito: false, mensaje: 'Asambleísta no encontrado.' });
        }
        return res.json({ exito: true, datos });
    } catch (error) {
        console.error('[AsambleistaController.hojaDeVida]', error);
        return res.status(500).json({ exito: false, mensaje: 'Error en la consulta.' });
    }
};

module.exports = { registrar, buscar, listar, hojaDeVida };
