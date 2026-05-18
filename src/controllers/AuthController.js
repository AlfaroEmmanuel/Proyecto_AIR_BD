// =====================================================================
// src/controllers/AuthController.js — Issue #0
// Reglas de negocio para autenticación y autorización
// =====================================================================
const jwt     = require('jsonwebtoken');
const Usuario = require('../models/Usuario');

const SECRET = process.env.JWT_SECRET || 'cambiar_en_produccion';

const login = async (req, res) => {
    try {
        const { username, password } = req.body;
        if (!username || !password) {
            return res.status(400).json({ exito: false, mensaje: 'Faltan credenciales.' });
        }

        const usuario = await Usuario.encontrarPorCredenciales(username, password);
        if (!usuario) {
            return res.status(401).json({ exito: false, mensaje: 'Credenciales inválidas.' });
        }

        // Token con el rol del usuario para el middleware de autorización
        const token = jwt.sign(
            { id: usuario.id_usuario, rol: usuario.nombre_rol },
            SECRET,
            { expiresIn: '8h' }
        );

        // Pantalla destino según el rol
        const redireccion = (usuario.nombre_rol === 'Secretaria' || usuario.nombre_rol === 'Administrador')
            ? '/registro_asambleista.html'
            : '/listado_asambleistas.html';

        return res.json({
            exito: true,
            rol: usuario.nombre_rol,
            token,
            redireccion
        });
    } catch (error) {
        console.error('[AuthController.login]', error);
        return res.status(500).json({ exito: false, mensaje: 'Error interno del servidor.' });
    }
};

/**
 * Middleware: verifica el JWT y carga `req.usuario`.
 */
const requireAuth = (req, res, next) => {
    const header = req.headers.authorization;
    if (!header || !header.startsWith('Bearer ')) {
        return res.status(401).json({ exito: false, mensaje: 'Token requerido.' });
    }
    try {
        const token = header.slice(7);
        req.usuario = jwt.verify(token, SECRET);
        next();
    } catch (err) {
        return res.status(401).json({ exito: false, mensaje: 'Token inválido o expirado.' });
    }
};

/**
 * Middleware: limita el acceso a roles específicos.
 * Uso: router.post('/ruta', requireAuth, requireRole('Secretaria','Administrador'), handler)
 */
const requireRole = (...rolesPermitidos) => (req, res, next) => {
    if (!req.usuario || !rolesPermitidos.includes(req.usuario.rol)) {
        return res.status(403).json({ exito: false, mensaje: 'Permisos insuficientes.' });
    }
    next();
};

module.exports = { login, requireAuth, requireRole };
