// =====================================================================
// src/controllers/SesionController.js — Issue #11
// Valida el QUÓRUM antes de permitir registrar una votación.
// =====================================================================
const Sesion = require('../models/Sesion');
const Votacion = require('../models/Votacion');

const crear = async (req, res) => {
    try {
        const sesion = await Sesion.crear(req.body);
        return res.status(201).json({ exito: true, datos: sesion });
    } catch (error) {
        console.error('[SesionController.crear]', error);
        return res.status(500).json({ exito: false, mensaje: 'Error al crear la sesión.' });
    }
};

const obtenerDetalle = async (req, res) => {
    try {
        const sesion = await Sesion.obtenerDetalle(Number(req.params.id));
        if (!sesion) return res.status(404).json({ exito: false, mensaje: 'Sesión no encontrada.' });
        return res.json({ exito: true, datos: sesion });
    } catch (error) {
        console.error('[SesionController.obtenerDetalle]', error);
        return res.status(500).json({ exito: false, mensaje: 'Error en la consulta.' });
    }
};

const listar = async (_req, res) => {
    try {
        return res.json({ exito: true, datos: await Sesion.listar() });
    } catch (error) {
        console.error('[SesionController.listar]', error);
        return res.status(500).json({ exito: false, mensaje: 'Error en la consulta.' });
    }
};

const registrarVotacion = async (req, res) => {
    try {
        const id_sesion = Number(req.params.id);

        const hayQuorum = await Sesion.tieneQuorum(id_sesion);
        if (!hayQuorum) {
            return res.status(409).json({
                exito: false,
                mensaje: 'No se puede votar: la sesión no alcanza el quórum requerido.'
            });
        }

        const { id_propuesta, votos_favor, votos_contra, votos_abstencion, total_presentes } = req.body;
        const resultado = await Votacion.registrar({
            id_propuesta, id_sesion,
            votos_favor: votos_favor || 0,
            votos_contra: votos_contra || 0,
            votos_abstencion: votos_abstencion || 0,
            total_presentes
        });

        return res.status(201).json({
            exito: true,
            mensaje: `Votación registrada. Propuesta: ${resultado.estado_propuesta}.`,
            datos: resultado
        });
    } catch (error) {
        console.error('[SesionController.registrarVotacion]', error);
        return res.status(500).json({ exito: false, mensaje: 'Error al registrar la votación.' });
    }
};

module.exports = { crear, obtenerDetalle, listar, registrarVotacion };
